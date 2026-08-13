import CoreAudio
import Foundation
import ShenglanAudioEngine

final class ProcessAudioGainManager {
    private let queue = DispatchQueue(label: "com.starry.shenglan.process-audio", qos: .userInitiated)
    private let permissionQueue = DispatchQueue(label: "com.starry.shenglan.audio-permission", qos: .userInitiated)
    private var mixers: [pid_t: SLProcessAudioMixer] = [:]

    func requestSystemAudioPermission(completion: @escaping (Result<Void, Error>) -> Void) {
        // Permission prompting can wait for macOS (for example while the Mac
        // is locked). Keep it off the serial mixer queue so an outstanding
        // prompt never freezes later volume updates.
        permissionQueue.async {
            let status = SLProcessAudioMixer.requestSystemAudioPermission()
            DispatchQueue.main.async {
                if status == noErr {
                    completion(.success(()))
                } else {
                    completion(.failure(CoreAudioError(status: status, operation: L10n.tr("申请系统音频录制权限"))))
                }
            }
        }
    }

    func apply(
        process: AudioProcessModel,
        outputDeviceUID: String,
        gain: Float,
        forceProcessing: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let clampedGain = min(max(gain, 0), 4)
            let needsProcessing = forceProcessing || abs(clampedGain - 1) > 0.001

            if !needsProcessing {
                self.mixers.removeValue(forKey: process.pid)?.stop()
                DispatchQueue.main.async { completion(.success(false)) }
                return
            }

            if let mixer = self.mixers[process.pid],
               mixer.isRunning,
               mixer.processObjectID == process.id,
               mixer.outputDeviceUID == outputDeviceUID {
                mixer.gain = clampedGain
                // Atomic gain updates do not change controller state. Avoid a
                // controller rebuild; the completion only closes the short HAL
                // operation guard used by runtime polling.
                DispatchQueue.main.async { completion(.success(true)) }
                return
            }

            let replacedMixer = self.mixers.removeValue(forKey: process.pid)
            replacedMixer?.stop()
            if replacedMixer != nil {
                // HAL teardown is asynchronous even after stop returns. Give a
                // replaced private aggregate a short release window before the
                // same process/output pair is rebuilt.
                usleep(80_000)
            }

            var lastError: Error?
            for attempt in 0..<2 {
                let mixer = SLProcessAudioMixer()
                do {
                    try mixer.start(
                        withProcessObjectID: process.id,
                        processName: process.name,
                        outputDeviceUID: outputDeviceUID,
                        gain: clampedGain
                    )
                    self.mixers[process.pid] = mixer
                    DispatchQueue.main.async { completion(.success(true)) }
                    return
                } catch {
                    mixer.stop()
                    lastError = error
                    let code = (error as NSError).code
                    let retryable = code == Int(kAudioHardwareIllegalOperationError) ||
                        code == Int(kAudioHardwareNotReadyError)
                    guard retryable && attempt == 0 else { break }
                    usleep(140_000)
                }
            }
            DispatchQueue.main.async {
                completion(.failure(lastError ?? CoreAudioError(
                    status: kAudioHardwareUnspecifiedError,
                    operation: L10n.tr("启动应用音频处理")
                )))
            }
        }
    }

    func stop(processID: pid_t, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?.mixers.removeValue(forKey: processID)?.stop()
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func stopAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for mixer in self.mixers.values { mixer.stop() }
            self.mixers.removeAll()
        }
    }
}
