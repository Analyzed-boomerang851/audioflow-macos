import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Darwin
import Foundation
import ServiceManagement

struct CoreAudioError: LocalizedError {
    let status: OSStatus
    let operation: String
    var errorDescription: String? {
        let chars: [CChar] = [CChar((status >> 24) & 0xff), CChar((status >> 16) & 0xff), CChar((status >> 8) & 0xff), CChar(status & 0xff), 0]
        let code = String(decoding: chars.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return L10n.format("%@失败（%@）", L10n.tr(operation), code.allSatisfy(\.isASCII) ? code : String(status))
    }
}

private enum CustomThemeBackgroundError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        L10n.tr("无法读取所选图片，请选择有效的 PNG、JPEG、HEIC 或 TIFF 图片。")
    }
}

enum CoreAudioBridge {
    private struct ProcessIdentity {
        var bundleID: String
        var name: String
        var icon: NSImage?
        var category: AudioApplicationCategory
    }

    static let system = AudioObjectID(kAudioObjectSystemObject)
    private static var processIdentityCache: [pid_t: ProcessIdentity] = [:]
    private static var processExposureCache: [pid_t: Bool] = [:]

    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func objectIDs(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &values) == noErr else { return [] }
        return values
    }

    static func uint32(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32? {
        var addr = address(selector, scope: scope, element: element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func pid(object: AudioObjectID) -> pid_t? {
        var addr = address(kAudioProcessPropertyPID)
        var value = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func double(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Double? {
        var addr = address(selector, scope: scope, element: element)
        var value = Double(0)
        var size = UInt32(MemoryLayout<Double>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func float32(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Float32? {
        var addr = address(selector, scope: scope, element: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func isSettable(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var addr = address(selector, scope: scope, element: element)
        var result = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(object, &addr, &result) == noErr && result.boolValue
    }

    static func string(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var addr = address(selector, scope: scope)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func channelCount(device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, pointer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func defaultDevice(selector: AudioObjectPropertySelector) -> AudioObjectID {
        var addr = address(selector)
        var value = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &value)
        return value
    }

    static func devices() -> [AudioDeviceModel] {
        let defaultInput = defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutput = defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
        return objectIDs(object: system, selector: kAudioHardwarePropertyDevices).compactMap { id in
            guard let name = string(object: id, selector: kAudioObjectPropertyName) else { return nil }
            let uid = string(object: id, selector: kAudioDevicePropertyDeviceUID) ?? "device-\(id)"
            let device = AudioDeviceModel(
                id: id,
                uid: uid,
                name: name,
                inputChannels: channelCount(device: id, scope: kAudioDevicePropertyScopeInput),
                outputChannels: channelCount(device: id, scope: kAudioDevicePropertyScopeOutput),
                sampleRate: double(object: id, selector: kAudioDevicePropertyNominalSampleRate) ?? 0,
                transportType: uint32(object: id, selector: kAudioDevicePropertyTransportType) ?? 0,
                manufacturer: string(object: id, selector: kAudioObjectPropertyManufacturer) ?? "未知厂商",
                isDefaultInput: id == defaultInput,
                isDefaultOutput: id == defaultOutput
            )
            return isPresentableDevice(device) ? device : nil
        }.sorted { lhs, rhs in
            if lhs.isDefaultOutput != rhs.isDefaultOutput { return lhs.isDefaultOutput }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func isPresentableDevice(_ device: AudioDeviceModel) -> Bool {
        guard device.isInput || device.isOutput else { return false }
        guard uint32(object: device.id, selector: kAudioDevicePropertyDeviceIsAlive) == 1 else { return false }

        let normalizedName = device.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let privateDevicePrefixes = ["音合流 ·", "音合流音量 ·", "声澜 ·", "声澜音量 ·"]
        if privateDevicePrefixes.contains(where: normalizedName.hasPrefix)
            || normalizedName == "音合流"
            || normalizedName == "声澜" {
            return false
        }

        if device.isDefaultInput || device.isDefaultOutput { return true }
        switch device.transportType {
        case kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE,
             kAudioDeviceTransportTypeAirPlay,
             kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeAVB:
            return true
        default:
            return false
        }
    }

    static func processes() -> [AudioProcessModel] {
        guard #available(macOS 14.2, *) else { return [] }
        var livePIDs = Set<pid_t>()
        let result: [AudioProcessModel] = objectIDs(object: system, selector: kAudioHardwarePropertyProcessObjectList).compactMap { objectID in
            guard let pid = pid(object: objectID), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
            let runningOutput = uint32(object: objectID, selector: kAudioProcessPropertyIsRunningOutput) == 1
            livePIDs.insert(pid)
            let reportedBundleID = string(object: objectID, selector: kAudioProcessPropertyBundleID) ?? ""
            let app = NSRunningApplication(processIdentifier: pid)
            let shouldExpose: Bool
            if let cached = processExposureCache[pid] {
                shouldExpose = cached
            } else {
                shouldExpose = shouldExposeProcess(pid: pid, app: app, reportedBundleID: reportedBundleID)
                processExposureCache[pid] = shouldExpose
            }
            guard shouldExpose else { return nil }
            let identity: ProcessIdentity
            if let cached = processIdentityCache[pid] {
                identity = cached
            } else {
                identity = resolvedProcessIdentity(pid: pid, app: app, reportedBundleID: reportedBundleID)
                processIdentityCache[pid] = identity
            }
            return AudioProcessModel(
                id: objectID,
                pid: pid,
                bundleID: identity.bundleID,
                name: identity.name,
                icon: identity.icon,
                category: identity.category,
                isRunningOutput: runningOutput
            )
        }.sorted { lhs, rhs in
            if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        processIdentityCache = processIdentityCache.filter { livePIDs.contains($0.key) }
        processExposureCache = processExposureCache.filter { livePIDs.contains($0.key) }
        return result
    }

    private static func shouldExposeProcess(
        pid: pid_t,
        app: NSRunningApplication?,
        reportedBundleID: String
    ) -> Bool {
        let executablePath = (app?.executableURL ?? executableURL(for: pid))?.path.lowercased() ?? ""
        let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
        let executable = app?.executableURL ?? executableURL(for: pid)
        let ownerURL = executable.flatMap(outermostApplicationBundleURL)
        let normalizedBundleID = reportedBundleID.lowercased()
        if executablePath.contains(".driver/contents/macos/") { return false }
        if executablePath.contains("/coreaudiod") || executableName == "coreaudiod" { return false }
        if executableName == "arkaudiod" || executableName == "bluetoothaudiod" { return false }
        if normalizedBundleID.hasPrefix("com.apple.audio.") || normalizedBundleID.hasPrefix("com.apple.coreaudio.") { return false }
        // A real user-facing .app (including Electron/Chromium helpers nested in
        // that bundle) is eligible. Bare daemons and command-line audio clients
        // are deliberately omitted from the application mixer.
        if ownerURL == nil && app?.activationPolicy == .prohibited { return false }
        if ownerURL == nil && app == nil { return false }
        return true
    }

    private static func resolvedProcessIdentity(
        pid: pid_t,
        app: NSRunningApplication?,
        reportedBundleID: String
    ) -> ProcessIdentity {
        let executable = app?.executableURL ?? executableURL(for: pid)
        let ownerURL = executable.flatMap(outermostApplicationBundleURL)
        let ownerBundle = ownerURL.flatMap(Bundle.init(url:))
        let ownerName = ownerBundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? ownerBundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? ownerBundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? ownerBundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let rawName = app?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? reportedBundleID.components(separatedBy: ".").last
            ?? ""
        let generic = rawName.isEmpty
            || rawName.localizedCaseInsensitiveContains("helper")
            || rawName.localizedCaseInsensitiveContains("renderer")
            || rawName.localizedCaseInsensitiveContains("audio service")
        let nestedProcess = ownerName.map { $0.localizedCaseInsensitiveCompare(rawName) != .orderedSame } ?? false
        let displayName: String
        if let ownerName, generic || nestedProcess {
            displayName = "\(ownerName)（音频进程）"
        } else if generic {
            displayName = "系统音频进程（PID \(pid)）"
        } else if !rawName.isEmpty {
            displayName = rawName
        } else {
            displayName = "未知音频进程（PID \(pid)）"
        }
        let ownerBundleID = ownerBundle?.bundleIdentifier ?? reportedBundleID
        let ownerIcon = ownerURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? app?.icon
        let category = audioApplicationCategory(
            bundle: ownerBundle,
            bundleID: ownerBundleID,
            displayName: displayName
        )
        return ProcessIdentity(bundleID: ownerBundleID, name: displayName, icon: ownerIcon, category: category)
    }

    private static func audioApplicationCategory(
        bundle: Bundle?,
        bundleID: String,
        displayName: String
    ) -> AudioApplicationCategory {
        let declaredCategory = (bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String)?.lowercased() ?? ""
        if declaredCategory.contains("music") || declaredCategory.contains("audio") {
            return .music
        }
        if declaredCategory.contains("video") {
            return .video
        }

        let identifier = bundleID.lowercased()
        let name = displayName.lowercased()
        let searchable = "\(identifier) \(name)"

        let musicIdentifiers = [
            "com.apple.music", "com.tencent.qqmusic", "com.netease.163music",
            "com.spotify.client", "com.kugou", "com.kuwo", "com.tidal",
            "com.audirvana", "com.deezer", "foobar", "vox"
        ]
        let musicNames = [
            "音乐", "music", "spotify", "网易云", "酷狗", "酷我",
            "tidal", "audirvana", "deezer", "foobar", "vox"
        ]
        if musicIdentifiers.contains(where: identifier.contains)
            || musicNames.contains(where: name.contains) {
            return .music
        }

        let videoIdentifiers = [
            "quicktime", "vlc", "iina", "bilibili", "iqiyi", "youku",
            "tencent.video", "douyin", "zoom", "tencentmeeting", "facetime",
            "webex", "obsproject", "plex", "infuse"
        ]
        let videoNames = [
            "视频", "播放器", "video", "player", "quicktime", "vlc", "iina",
            "哔哩哔哩", "bilibili", "爱奇艺", "优酷", "腾讯视频", "抖音",
            "zoom", "会议", "meeting", "facetime", "webex", "obs", "plex", "infuse"
        ]
        if videoIdentifiers.contains(where: searchable.contains)
            || videoNames.contains(where: name.contains) {
            return .video
        }
        return .other
    }

    private static func executableURL(for pid: pid_t) -> URL? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    private static func outermostApplicationBundleURL(for executableURL: URL) -> URL? {
        var cursor = executableURL.deletingLastPathComponent()
        var owner: URL?
        while cursor.path != "/" && !cursor.path.isEmpty {
            if cursor.pathExtension.lowercased() == "app" { owner = cursor }
            cursor.deleteLastPathComponent()
        }
        return owner
    }

    static func volume(device: AudioObjectID, scope: AudioObjectPropertyScope) -> Double {
        if scope == kAudioDevicePropertyScopeOutput,
           let value = float32(object: device, selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope) {
            return Double(value)
        }
        if let value = float32(object: device, selector: kAudioDevicePropertyVolumeScalar, scope: scope) {
            return Double(value)
        }
        let channels = max(channelCount(device: device, scope: scope), 1)
        let values = (1...channels).compactMap {
            float32(object: device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: AudioObjectPropertyElement($0))
        }
        return values.isEmpty ? 1 : Double(values.reduce(0, +) / Float32(values.count))
    }

    static func setVolume(_ value: Double, device: AudioObjectID, scope: AudioObjectPropertyScope, operation: String) throws {
        var scalar = Float32(max(0, min(1, value)))
        let candidates: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = scope == kAudioDevicePropertyScopeOutput
            ? [(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain), (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)]
            : [(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)]

        for candidate in candidates where isSettable(object: device, selector: candidate.0, scope: scope, element: candidate.1) {
            var addr = address(candidate.0, scope: scope, element: candidate.1)
            let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
            if status == noErr { return }
        }

        let channels = channelCount(device: device, scope: scope)
        var successfulChannels = 0
        var lastStatus = OSStatus(kAudioHardwareUnsupportedOperationError)
        if channels > 0 {
            for channel in 1...channels {
                let element = AudioObjectPropertyElement(channel)
                guard isSettable(object: device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: element) else { continue }
                var addr = address(kAudioDevicePropertyVolumeScalar, scope: scope, element: element)
                lastStatus = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
                if lastStatus == noErr { successfulChannels += 1 }
            }
        }
        guard successfulChannels > 0 else { throw CoreAudioError(status: lastStatus, operation: operation) }
    }

    static func supportsVolume(device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        let candidates: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = scope == kAudioDevicePropertyScopeOutput
            ? [(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain), (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)]
            : [(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)]
        if candidates.contains(where: { isSettable(object: device, selector: $0.0, scope: scope, element: $0.1) }) {
            return true
        }
        let channels = channelCount(device: device, scope: scope)
        guard channels > 0 else { return false }
        return (1...channels).contains {
            isSettable(object: device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: AudioObjectPropertyElement($0))
        }
    }

    static func masterVolume(device: AudioObjectID) -> Double { volume(device: device, scope: kAudioDevicePropertyScopeOutput) }
    static func setMasterVolume(_ value: Double, device: AudioObjectID) throws { try setVolume(value, device: device, scope: kAudioDevicePropertyScopeOutput, operation: "设置系统主音量") }
    static func inputVolume(device: AudioObjectID) -> Double { volume(device: device, scope: kAudioDevicePropertyScopeInput) }
    static func setInputVolume(_ value: Double, device: AudioObjectID) throws { try setVolume(value, device: device, scope: kAudioDevicePropertyScopeInput, operation: "设置麦克风输入增益") }

    static func mute(device: AudioObjectID, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> Bool {
        if let explicitMute = uint32(object: device, selector: kAudioDevicePropertyMute, scope: scope) {
            return explicitMute == 1
        }
        return supportsVolume(device: device, scope: scope) && volume(device: device, scope: scope) <= 0.001
    }

    static func setMute(_ muted: Bool, device: AudioObjectID, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) throws {
        var value: UInt32 = muted ? 1 : 0
        var addr = address(kAudioDevicePropertyMute, scope: scope)
        guard isSettable(object: device, selector: kAudioDevicePropertyMute, scope: scope) else {
            try setVolume(
                muted ? 0 : 1,
                device: device,
                scope: scope,
                operation: scope == kAudioDevicePropertyScopeInput ? (muted ? "静音麦克风" : "取消麦克风静音") : (muted ? "静音系统输出" : "取消系统静音")
            )
            return
        }
        let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else { throw CoreAudioError(status: status, operation: muted ? "静音设备" : "取消设备静音") }
    }

    static func setDefaultOutput(_ device: AudioObjectID) throws {
        var value = device
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var status = AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
        guard status == noErr else { throw CoreAudioError(status: status, operation: "切换默认输出设备") }
        addr = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        status = AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
        if status != noErr { throw CoreAudioError(status: status, operation: "切换系统提示音设备") }
    }

    static func setDefaultInput(_ device: AudioObjectID) throws {
        var value = device
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
        guard status == noErr else { throw CoreAudioError(status: status, operation: "切换默认输入设备") }
    }

    static func setSampleRate(_ sampleRate: Double, device: AudioObjectID) throws {
        var value = sampleRate
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        guard isSettable(object: device, selector: kAudioDevicePropertyNominalSampleRate, scope: kAudioObjectPropertyScopeGlobal) else {
            throw CoreAudioError(status: kAudioHardwareUnsupportedOperationError, operation: "设置采样率")
        }
        let status = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Double>.size), &value)
        guard status == noErr else { throw CoreAudioError(status: status, operation: "设置采样率") }
    }

    static func availableSampleRates(device: AudioObjectID) -> [Double] {
        var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else {
            return [double(object: device, selector: kAudioDevicePropertyNominalSampleRate)].compactMap { $0 }
        }
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
        let commonRates: [Double] = [8000, 16000, 22050, 24000, 32000, 44100, 48000, 88200, 96000, 176400, 192000]
        var values = Set<Double>()
        for range in ranges {
            if abs(range.mMaximum - range.mMinimum) < 0.5 {
                values.insert(range.mMinimum)
            } else {
                for rate in commonRates where rate >= range.mMinimum && rate <= range.mMaximum { values.insert(rate) }
            }
        }
        if let current = double(object: device, selector: kAudioDevicePropertyNominalSampleRate) { values.insert(current) }
        return values.sorted()
    }

    static func outputLatencyMilliseconds(device: AudioObjectID) -> Double {
        let sampleRate = double(object: device, selector: kAudioDevicePropertyNominalSampleRate) ?? 0
        let frames = uint32(object: device, selector: kAudioDevicePropertyBufferFrameSize) ?? 0
        guard sampleRate > 0 else { return 0 }
        return Double(frames) / sampleRate * 1000
    }
}

private struct RuntimeRefreshRequest {
    let force: Bool
    let topologyDue: Bool
    let devices: [AudioDeviceModel]
    let connectedUIDs: Set<String>
    let preferredOutputUID: String?
    let preferredInputUID: String?
    let selectedOutputID: AudioObjectID
    let selectedInputID: AudioObjectID
    let masterWriteSequence: UInt64
    let inputWriteSequence: UInt64
}

private struct RuntimeRefreshSnapshot {
    let force: Bool
    let topologyRefreshed: Bool
    let devices: [AudioDeviceModel]
    let connectedUIDs: Set<String>
    let newlyAvailableUIDs: Set<String>
    let outputID: AudioObjectID
    let inputID: AudioObjectID
    let outputVolume: Double?
    let outputMuted: Bool?
    let inputVolume: Double?
    let inputMuted: Bool?
    let outputSupportsVolume: Bool?
    let inputSupportsVolume: Bool?
    let outputLatencyMilliseconds: Double?
    let loginItemStatus: SMAppService.Status?
    let masterWriteSequence: UInt64
    let inputWriteSequence: UInt64
}

@MainActor
final class AudioController: ObservableObject {
    @Published var devices: [AudioDeviceModel] = []
    @Published var applications: [ApplicationMixState] = []
    @Published var masterVolume = 1.0
    @Published var masterMuted = false
    @Published var inputVolume = 1.0
    @Published var inputMuted = false
    @Published var selectedOutputID = AudioObjectID(kAudioObjectUnknown)
    @Published var selectedInputID = AudioObjectID(kAudioObjectUnknown)
    @Published private(set) var selectedOutputSupportsVolume = false
    @Published private(set) var selectedInputSupportsVolume = false
    @Published private(set) var outputLatencyMilliseconds = 0.0
    @Published private(set) var deviceRuntimeStates: [AudioObjectID: AudioDeviceRuntimeState] = [:]
    @Published var theme: ThemeChoice = .system {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
            if theme == .system { synchronizeSystemAppearance() }
        }
    }
    @Published var language: AppLanguage = .simplifiedChinese {
        didSet {
            L10n.setLanguage(language)
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            statusMessage = L10n.tr("Core Audio 已连接")
        }
    }
    @Published private(set) var systemUsesDarkAppearance = false
    @Published var selectedSection: ControllerSection = .mixer
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var loginItemEnabled = false
    @Published private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    @Published var menuBarIcon: MenuBarIconChoice = .waveform {
        didSet { UserDefaults.standard.set(menuBarIcon.rawValue, forKey: Self.menuBarIconKey) }
    }
    @Published var showMenuBarVolume = true {
        didSet { UserDefaults.standard.set(showMenuBarVolume, forKey: Self.showMenuBarVolumeKey) }
    }
    @Published var menuBarVolumeStyle: MenuBarVolumeStyle = .percentage {
        didSet { UserDefaults.standard.set(menuBarVolumeStyle.rawValue, forKey: Self.menuBarVolumeStyleKey) }
    }
    @Published var menuBarPopoverStyle: MenuBarPopoverStyle = .minimal {
        didSet { UserDefaults.standard.set(menuBarPopoverStyle.rawValue, forKey: Self.menuBarPopoverStyleKey) }
    }
    @Published var useLiquidGlass = true {
        didSet { UserDefaults.standard.set(useLiquidGlass, forKey: Self.useLiquidGlassKey) }
    }
    /// Controls only the material surface behind cards and controls. Text,
    /// symbols and interactive content deliberately remain fully opaque.
    @Published var glassPanelOpacity = 0.78 {
        didSet { UserDefaults.standard.set(glassPanelOpacity, forKey: Self.glassPanelOpacityKey) }
    }
    @Published var customThemeBackgroundEnabled = false {
        didSet {
            UserDefaults.standard.set(customThemeBackgroundEnabled, forKey: Self.customThemeBackgroundEnabledKey)
        }
    }
    @Published var customThemeBackgroundOpacity = 0.82 {
        didSet {
            UserDefaults.standard.set(
                customThemeBackgroundOpacity,
                forKey: Self.customThemeBackgroundOpacityKey
            )
        }
    }
    @Published var customThemeBackgroundBlur = 12.0 {
        didSet {
            UserDefaults.standard.set(
                customThemeBackgroundBlur,
                forKey: Self.customThemeBackgroundBlurKey
            )
        }
    }
    @Published private(set) var customThemeBackgroundImage: NSImage?
    @Published private(set) var customThemeBackgroundName: String?
    @Published var systemAudioPermissionGranted: Bool?
    @Published var rememberedDevices: [RememberedAudioDevice] = []
    @Published private(set) var favoriteApplicationKeys = Set<String>()
    @Published private(set) var applicationOrders: [String: [String]] = [:]
    @Published private(set) var minimalApplicationOrder: [String] = []
    @Published private(set) var collapsedApplicationGroups = Set<String>()
    @Published private(set) var masterEqualizer = EqualizerSettings()
    @Published private(set) var applicationEqualizers: [String: EqualizerSettings] = [:]

    var hasAnyEqualizerEnabled: Bool {
        EqualizerBatchState.hasEnabled(
            master: masterEqualizer,
            applications: applicationEqualizers
        )
    }

    var shouldShowDisableAllEqualizersAction: Bool {
        EqualizerBatchState.shouldShowDisableAllAction(
            master: masterEqualizer,
            currentApplications: runningApplications.map(applicationEqualizer(for:))
        )
    }

    private let processAudioManager = ProcessAudioGainManager()
    private let processScanQueue = DispatchQueue(label: "com.starry.shenglan.process-scan", qos: .utility)
    private let runtimeReadQueue = DispatchQueue(label: "com.starry.shenglan.runtime-read", qos: .userInitiated)
    private let deviceWriteQueue = DispatchQueue(label: "com.starry.shenglan.device-volume", qos: .userInteractive)
    private var refreshTimer: Timer?
    private var processByID: [AudioObjectID: AudioProcessModel] = [:]
    private var pendingProcessingWork: [AudioObjectID: DispatchWorkItem] = [:]
    private var lastProcessingApply: [AudioObjectID: CFAbsoluteTime] = [:]
    private var timedMuteWork: [AudioObjectID: DispatchWorkItem] = [:]
    private var equalizerPersistenceWork: DispatchWorkItem?
    private var activeUserInteractions = 0
    private var connectedUIDs = Set<String>()
    private var preferredOutputUID: String?
    private var preferredInputUID: String?
    private var lastTopologyRefresh = -Double.infinity
    private var lastProcessRefresh = -Double.infinity
    private var processRefreshInFlight = false
    private var processRefreshPendingForce = false
    private var runtimeRefreshInFlight = false
    private var runtimeRefreshPendingForce = false
    private var deviceRuntimeRefreshesInFlight = Set<AudioObjectID>()
    private var audioOperationsInFlight = 0
    private var masterVolumeWriteSequence: UInt64 = 0
    private var inputVolumeWriteSequence: UInt64 = 0
    private var outputSelectionSequence: UInt64 = 0
    private var inputSelectionSequence: UInt64 = 0
    private var systemThemeObserver: NSObjectProtocol?
    private var applicationActivationObserver: NSObjectProtocol?

    private static let rememberedDevicesKey = "rememberedAudioDevices.v1"
    private static let preferredOutputUIDKey = "preferredOutputDeviceUID.v1"
    private static let preferredInputUIDKey = "preferredInputDeviceUID.v1"
    private static let themeKey = "themeChoice.v1"
    private static let languageKey = "appLanguage.v1"
    private static let menuBarIconKey = "menuBarIconChoice.v1"
    private static let showMenuBarVolumeKey = "showMenuBarVolume.v1"
    private static let menuBarVolumeStyleKey = "menuBarVolumeStyle.v1"
    private static let menuBarPopoverStyleKey = "menuBarPopoverStyle.v1"
    private static let useLiquidGlassKey = "useLiquidGlass.v1"
    private static let glassPanelOpacityKey = "glassPanelOpacity.v1"
    private static let customThemeBackgroundEnabledKey = "customThemeBackgroundEnabled.v1"
    private static let customThemeBackgroundNameKey = "customThemeBackgroundName.v1"
    private static let customThemeBackgroundOpacityKey = "customThemeBackgroundOpacity.v1"
    private static let customThemeBackgroundBlurKey = "customThemeBackgroundBlur.v1"
    private static let systemAudioPermissionKey = "systemAudioPermissionGranted.v1"
    private static let favoriteApplicationKeysKey = "favoriteApplicationKeys.v1"
    private static let applicationOrdersKey = "applicationOrders.v1"
    private static let minimalApplicationOrderKey = "minimalApplicationOrder.v1"
    private static let collapsedApplicationGroupsKey = "collapsedApplicationGroups.v1"
    private static let masterEqualizerKey = "masterEqualizer.v1"
    private static let applicationEqualizersKey = "applicationEqualizers.v1"

    init() {
        loginItemStatus = SMAppService.mainApp.status
        loginItemEnabled = loginItemStatus == .enabled
        if let value = UserDefaults.standard.string(forKey: Self.languageKey),
           let savedLanguage = AppLanguage(rawValue: value) {
            language = savedLanguage
        }
        L10n.setLanguage(language)
        statusMessage = L10n.tr("Core Audio 已连接")
        if let value = UserDefaults.standard.string(forKey: Self.themeKey), let choice = ThemeChoice(rawValue: value) { theme = choice }
        if let value = UserDefaults.standard.string(forKey: Self.menuBarIconKey), let choice = MenuBarIconChoice(rawValue: value) { menuBarIcon = choice }
        if UserDefaults.standard.object(forKey: Self.showMenuBarVolumeKey) != nil {
            showMenuBarVolume = UserDefaults.standard.bool(forKey: Self.showMenuBarVolumeKey)
        }
        if let value = UserDefaults.standard.string(forKey: Self.menuBarVolumeStyleKey),
           let style = MenuBarVolumeStyle(rawValue: value) {
            menuBarVolumeStyle = style
        }
        if let value = UserDefaults.standard.string(forKey: Self.menuBarPopoverStyleKey),
           let style = MenuBarPopoverStyle(rawValue: value) {
            menuBarPopoverStyle = style
        }
        if UserDefaults.standard.object(forKey: Self.useLiquidGlassKey) != nil {
            useLiquidGlass = UserDefaults.standard.bool(forKey: Self.useLiquidGlassKey)
        }
        if UserDefaults.standard.object(forKey: Self.glassPanelOpacityKey) != nil {
            glassPanelOpacity = min(
                max(UserDefaults.standard.double(forKey: Self.glassPanelOpacityKey), 0.18),
                1
            )
        }
        customThemeBackgroundName = UserDefaults.standard.string(forKey: Self.customThemeBackgroundNameKey)
        customThemeBackgroundImage = NSImage(contentsOf: Self.customThemeBackgroundURL)
        if customThemeBackgroundImage != nil,
           UserDefaults.standard.object(forKey: Self.customThemeBackgroundEnabledKey) != nil {
            customThemeBackgroundEnabled = UserDefaults.standard.bool(forKey: Self.customThemeBackgroundEnabledKey)
        }
        if UserDefaults.standard.object(forKey: Self.customThemeBackgroundOpacityKey) != nil {
            customThemeBackgroundOpacity = min(
                max(UserDefaults.standard.double(forKey: Self.customThemeBackgroundOpacityKey), 0),
                1
            )
        }
        if UserDefaults.standard.object(forKey: Self.customThemeBackgroundBlurKey) != nil {
            customThemeBackgroundBlur = min(
                max(UserDefaults.standard.double(forKey: Self.customThemeBackgroundBlurKey), 0),
                36
            )
        }
        if UserDefaults.standard.object(forKey: Self.systemAudioPermissionKey) != nil {
            systemAudioPermissionGranted = UserDefaults.standard.bool(forKey: Self.systemAudioPermissionKey)
        }
        favoriteApplicationKeys = Set(UserDefaults.standard.stringArray(forKey: Self.favoriteApplicationKeysKey) ?? [])
        minimalApplicationOrder = UserDefaults.standard.stringArray(forKey: Self.minimalApplicationOrderKey) ?? []
        collapsedApplicationGroups = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedApplicationGroupsKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: Self.applicationOrdersKey),
           let saved = try? JSONDecoder().decode([String: [String]].self, from: data) {
            applicationOrders = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.masterEqualizerKey),
           var saved = try? JSONDecoder().decode(EqualizerSettings.self, from: data) {
            saved.normalize()
            masterEqualizer = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.applicationEqualizersKey),
           let saved = try? JSONDecoder().decode([String: EqualizerSettings].self, from: data) {
            applicationEqualizers = saved.mapValues { value in
                var normalized = value
                normalized.normalize()
                return normalized
            }
        }
        // Older builds allowed both layers to remain active. On first launch
        // after the exclusivity change, preserve the visible master choice and
        // turn off app stages. Future user actions persist whichever layer was
        // activated most recently through the centralized update methods.
        if masterEqualizer.isEnabled,
           applicationEqualizers.values.contains(where: \.isEnabled) {
            applicationEqualizers = applicationEqualizers.mapValues { value in
                var disabled = value
                disabled.isEnabled = false
                return disabled
            }
            if let data = try? JSONEncoder().encode(applicationEqualizers) {
                UserDefaults.standard.set(data, forKey: Self.applicationEqualizersKey)
            }
        }
        preferredOutputUID = UserDefaults.standard.string(forKey: Self.preferredOutputUIDKey)
        preferredInputUID = UserDefaults.standard.string(forKey: Self.preferredInputUIDKey)
        if let data = UserDefaults.standard.data(forKey: Self.rememberedDevicesKey),
           let saved = try? JSONDecoder().decode([RememberedAudioDevice].self, from: data) {
            rememberedDevices = saved
        }
        // Resolve the real macOS preference directly. Observing
        // `NSApp.effectiveAppearance` here is both too early in the App
        // lifecycle and circular once individual windows have an explicit
        // appearance, which caused the follow-system choice to flip after a
        // focus/click change.
        systemUsesDarkAppearance = Self.systemAppearanceIsDark
        startObservingSystemAppearance()
        refresh()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncRuntimeState() }
        }
        // Do not fire while AppKit is tracking a click or drag. The old common-mode
        // timer could enumerate devices/processes in the middle of a gesture and
        // visibly steal frames from sliders and glass controls.
        RunLoop.main.add(timer, forMode: .default)
        refreshTimer = timer
        // Do not recreate a global permission-check tap during launch. Some
        // Bluetooth devices serialize that HAL operation with volume/device
        // queries for several seconds. The persisted permission state is
        // revalidated by the first real per-application processing request;
        // success/failure updates it immediately.
    }

    deinit {
        equalizerPersistenceWork?.cancel()
        refreshTimer?.invalidate()
        if let systemThemeObserver {
            DistributedNotificationCenter.default().removeObserver(systemThemeObserver)
        }
        if let applicationActivationObserver {
            NotificationCenter.default.removeObserver(applicationActivationObserver)
        }
        processAudioManager.stopAll()
    }

    /// Resolve “跟随系统” once and publish the concrete result. SwiftUI's nil
    /// preferred scheme can be recalculated independently by different AppKit
    /// windows; a shared resolved value keeps the controller and status popover
    /// in lockstep while still updating immediately when macOS changes theme.
    func synchronizeSystemAppearance() {
        let usesDarkAppearance = Self.systemAppearanceIsDark
        if systemUsesDarkAppearance != usesDarkAppearance {
            systemUsesDarkAppearance = usesDarkAppearance
        }
    }

    private static var systemAppearanceIsDark: Bool {
        // Query NSGlobalDomain directly. Reading only the app defaults domain
        // can temporarily return a stale inherited value after macOS changes
        // appearance, which made Follow System flip again on focus.
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let style = (global?["AppleInterfaceStyle"] as? String)
            ?? UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        return style?
            .caseInsensitiveCompare("Dark") == .orderedSame
    }

    private static var customThemeBackgroundDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.starry.audioflow", isDirectory: true)
    }

    private static var customThemeBackgroundURL: URL {
        customThemeBackgroundDirectory.appendingPathComponent("theme-background.png")
    }

    func setCustomThemeBackgroundEnabled(_ enabled: Bool) {
        customThemeBackgroundEnabled = enabled && customThemeBackgroundImage != nil
    }

    func importCustomThemeBackground(from sourceURL: URL) throws {
        let accessingSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessingSecurityScope { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard let sourceImage = NSImage(contentsOf: sourceURL),
              let tiffData = sourceImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CustomThemeBackgroundError.unreadableImage
        }

        try FileManager.default.createDirectory(
            at: Self.customThemeBackgroundDirectory,
            withIntermediateDirectories: true
        )
        try pngData.write(to: Self.customThemeBackgroundURL, options: .atomic)
        guard let storedImage = NSImage(data: pngData) else {
            throw CustomThemeBackgroundError.unreadableImage
        }

        customThemeBackgroundImage = storedImage
        customThemeBackgroundName = sourceURL.lastPathComponent
        UserDefaults.standard.set(sourceURL.lastPathComponent, forKey: Self.customThemeBackgroundNameKey)
        customThemeBackgroundEnabled = true
        statusMessage = L10n.tr("自定义主题背景已更新")
    }

    func removeCustomThemeBackground() {
        try? FileManager.default.removeItem(at: Self.customThemeBackgroundURL)
        customThemeBackgroundImage = nil
        customThemeBackgroundName = nil
        customThemeBackgroundEnabled = false
        UserDefaults.standard.removeObject(forKey: Self.customThemeBackgroundNameKey)
        statusMessage = L10n.tr("已移除自定义主题背景")
    }

    private func startObservingSystemAppearance() {
        systemThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.synchronizeSystemAppearance() }
        }

        applicationActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.synchronizeSystemAppearance() }
        }

        synchronizeSystemAppearance()
    }

    var outputDevices: [AudioDeviceModel] { devices.filter(\.isOutput) }
    var inputDevices: [AudioDeviceModel] { devices.filter(\.isInput) }
    var selectedOutput: AudioDeviceModel? { devices.first { $0.id == selectedOutputID } }
    var selectedInput: AudioDeviceModel? { devices.first { $0.id == selectedInputID } }
    // Applications remain visible after pausing and leave only when their host
    // process exits. `isRunningOutput` now represents row status, not visibility.
    var runningApplications: [ApplicationMixState] { applications }
    var activeProcessingCount: Int { applications.filter(\.processingActive).count }
    var visibleApplications: [ApplicationMixState] { applications }
    var unavailableRememberedDevices: [RememberedAudioDevice] {
        let liveKeys = Set(devices.map {
            rememberedDeviceKey(name: $0.name, transportType: $0.transportType, manufacturer: $0.manufacturer)
        })
        var grouped: [String: RememberedAudioDevice] = [:]
        for device in rememberedDevices {
            let key = rememberedDeviceKey(
                name: device.name,
                transportType: device.transportType,
                manufacturer: device.manufacturer
            )
            guard !liveKeys.contains(key) else { continue }
            if var existing = grouped[key] {
                existing.inputChannels = max(existing.inputChannels, device.inputChannels)
                existing.outputChannels = max(existing.outputChannels, device.outputChannels)
                existing.usedAsInput = existing.usedAsInput || device.usedAsInput
                existing.usedAsOutput = existing.usedAsOutput || device.usedAsOutput
                existing.lastSeen = max(existing.lastSeen, device.lastSeen)
                grouped[key] = existing
            } else {
                grouped[key] = device
            }
        }
        return grouped.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func rememberedDeviceKey(name: String, transportType: UInt32, manufacturer: String) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(transportType)|\(manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    func applicationState(id: AudioObjectID) -> ApplicationMixState? {
        applications.first { $0.id == id }
    }

    func applicationPreferenceKey(for app: ApplicationMixState) -> String {
        let bundleID = app.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !bundleID.isEmpty { return "bundle:\(bundleID)" }
        return "name:\(app.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    func applicationEqualizer(for app: ApplicationMixState) -> EqualizerSettings {
        applicationEqualizer(forKey: applicationPreferenceKey(for: app))
    }

    func applicationEqualizer(forKey key: String) -> EqualizerSettings {
        applicationEqualizers[key] ?? EqualizerSettings()
    }

    func disableAllEqualizers() {
        guard hasAnyEqualizerEnabled else { return }

        EqualizerBatchState.disableAll(
            master: &masterEqualizer,
            applications: &applicationEqualizers
        )
        equalizerPersistenceWork?.cancel()
        equalizerPersistenceWork = nil
        persistEqualizers()

        for app in applications {
            scheduleApplicationProcessing(id: app.id, immediate: true)
        }
        statusMessage = L10n.tr("已关闭所有EQ")
    }

    func setMasterEqualizerEnabled(_ enabled: Bool) {
        updateMasterEqualizer(immediate: true) { $0.isEnabled = enabled }
        statusMessage = L10n.tr(enabled ? "总均衡器已开启" : "总均衡器已关闭")
    }

    func setMasterEqualizerPreset(_ preset: EqualizerPreset) {
        updateMasterEqualizer(immediate: true) { $0.apply(preset) }
        statusMessage = L10n.format("总均衡器已切换为 %@", preset.title)
    }

    func resetMasterEqualizer() {
        let presetTitle = masterEqualizer.preset.title
        updateMasterEqualizer(immediate: true) { $0.resetCurrentPreset() }
        statusMessage = L10n.format("总均衡器的%@已重置", presetTitle)
    }

    func setMasterEqualizerBandGain(index: Int, gainDB: Double) {
        guard EqualizerSettings.bandFrequencies.indices.contains(index) else { return }
        updateMasterEqualizer { settings in
            settings.prepareCurrentPresetForEditing()
            settings.bandGainsDB[index] = min(max(gainDB, EqualizerSettings.gainRange.lowerBound), EqualizerSettings.gainRange.upperBound)
            settings.saveCurrentPresetProfile()
        }
    }

    func setMasterEqualizerPreamp(_ preampDB: Double) {
        updateMasterEqualizer { settings in
            settings.prepareCurrentPresetForEditing()
            settings.preampDB = min(max(preampDB, EqualizerSettings.preampRange.lowerBound), EqualizerSettings.preampRange.upperBound)
            settings.saveCurrentPresetProfile()
        }
    }

    func setMasterEqualizerReverbMix(_ wetMix: Double) {
        updateMasterEqualizer { settings in
            applyReverbMix(wetMix, to: &settings)
        }
    }

    func setMasterEqualizerStereoBalance(_ balance: Double) {
        updateMasterEqualizer { settings in
            settings.prepareCurrentPresetForEditing()
            settings.stereoBalance = min(max(balance, -1), 1)
            settings.saveCurrentPresetProfile()
        }
    }

    func setApplicationEqualizerEnabled(key: String, enabled: Bool) {
        updateApplicationEqualizer(key: key, immediate: true) { $0.isEnabled = enabled }
        statusMessage = L10n.tr(enabled ? "应用均衡器已开启" : "应用均衡器已关闭")
    }

    func setApplicationEqualizerPreset(key: String, preset: EqualizerPreset) {
        updateApplicationEqualizer(key: key, immediate: true) { $0.apply(preset) }
        statusMessage = L10n.format("应用均衡器已切换为 %@", preset.title)
    }

    func resetApplicationEqualizer(key: String) {
        let presetTitle = applicationEqualizer(forKey: key).preset.title
        updateApplicationEqualizer(key: key, immediate: true) { $0.resetCurrentPreset() }
        statusMessage = L10n.format("应用均衡器的%@已重置", presetTitle)
    }

    func setApplicationEqualizerBandGain(key: String, index: Int, gainDB: Double) {
        guard EqualizerSettings.bandFrequencies.indices.contains(index) else { return }
        updateApplicationEqualizer(key: key) { settings in
            settings.prepareCurrentPresetForEditing()
            settings.bandGainsDB[index] = min(max(gainDB, EqualizerSettings.gainRange.lowerBound), EqualizerSettings.gainRange.upperBound)
            settings.saveCurrentPresetProfile()
        }
    }

    func setApplicationEqualizerPreamp(key: String, preampDB: Double) {
        updateApplicationEqualizer(key: key) { settings in
            settings.prepareCurrentPresetForEditing()
            settings.preampDB = min(max(preampDB, EqualizerSettings.preampRange.lowerBound), EqualizerSettings.preampRange.upperBound)
            settings.saveCurrentPresetProfile()
        }
    }

    func setApplicationEqualizerReverbMix(key: String, wetMix: Double) {
        updateApplicationEqualizer(key: key) { settings in
            applyReverbMix(wetMix, to: &settings)
        }
    }

    func setApplicationEqualizerStereoBalance(key: String, balance: Double) {
        updateApplicationEqualizer(key: key) { settings in
            settings.prepareCurrentPresetForEditing()
            settings.stereoBalance = min(max(balance, -1), 1)
            settings.saveCurrentPresetProfile()
        }
    }

    private func applyReverbMix(_ wetMix: Double, to settings: inout EqualizerSettings) {
        settings.prepareCurrentPresetForEditing()
        let clampedMix = min(max(wetMix, 0), 0.60)
        if settings.reverb.wetMix <= 0.001, clampedMix > 0.001 {
            settings.reverb = EqualizerReverbSettings(
                wetMix: clampedMix,
                roomSize: 0.55,
                damping: 0.50,
                preDelayMS: 18,
                stereoWidth: 0.72
            )
        } else {
            settings.reverb.wetMix = clampedMix
        }
        settings.saveCurrentPresetProfile()
    }

    private func updateMasterEqualizer(
        immediate: Bool = false,
        _ edit: (inout EqualizerSettings) -> Void
    ) {
        var settings = masterEqualizer
        edit(&settings)
        settings.normalize()
        if settings.isEnabled {
            applicationEqualizers = applicationEqualizers.mapValues { value in
                var disabled = value
                disabled.isEnabled = false
                return disabled
            }
        }
        masterEqualizer = settings
        if immediate {
            equalizerPersistenceWork?.cancel()
            equalizerPersistenceWork = nil
            persistEqualizers()
        } else {
            scheduleEqualizerPersistence()
        }
        for app in applications {
            scheduleApplicationProcessing(id: app.id, immediate: immediate)
        }
    }

    private func updateApplicationEqualizer(
        key: String,
        immediate: Bool = false,
        _ edit: (inout EqualizerSettings) -> Void
    ) {
        var settings = applicationEqualizers[key] ?? EqualizerSettings()
        edit(&settings)
        settings.normalize()
        let disabledMaster = settings.isEnabled && masterEqualizer.isEnabled
        if disabledMaster {
            masterEqualizer.isEnabled = false
        }
        applicationEqualizers[key] = settings
        if immediate {
            equalizerPersistenceWork?.cancel()
            equalizerPersistenceWork = nil
            persistEqualizers()
        } else {
            scheduleEqualizerPersistence()
        }
        for app in applications {
            if disabledMaster || applicationPreferenceKey(for: app) == key {
                scheduleApplicationProcessing(id: app.id, immediate: immediate)
            }
        }
    }

    private func scheduleEqualizerPersistence() {
        equalizerPersistenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistEqualizers()
            self?.equalizerPersistenceWork = nil
        }
        equalizerPersistenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func persistEqualizers() {
        if let data = try? JSONEncoder().encode(masterEqualizer) {
            UserDefaults.standard.set(data, forKey: Self.masterEqualizerKey)
        }
        if let data = try? JSONEncoder().encode(applicationEqualizers) {
            UserDefaults.standard.set(data, forKey: Self.applicationEqualizersKey)
        }
    }

    func minimalApplicationOrderKey(for app: ApplicationMixState) -> String {
        let name = app.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(applicationPreferenceKey(for: app))|name:\(name)"
    }

    func isApplicationFavorite(_ app: ApplicationMixState) -> Bool {
        favoriteApplicationKeys.contains(applicationPreferenceKey(for: app))
    }

    func toggleApplicationFavorite(_ app: ApplicationMixState) {
        let key = applicationPreferenceKey(for: app)
        if favoriteApplicationKeys.contains(key) {
            favoriteApplicationKeys.remove(key)
            applicationOrders[ApplicationOrderGroup.favorites.rawValue]?.removeAll { $0 == key }
            statusMessage = L10n.format("已取消收藏 %@", L10n.tr(app.name))
        } else {
            favoriteApplicationKeys.insert(key)
            var order = applicationOrders[ApplicationOrderGroup.favorites.rawValue] ?? []
            if !order.contains(key) { order.append(key) }
            applicationOrders[ApplicationOrderGroup.favorites.rawValue] = order
            statusMessage = L10n.format("已收藏 %@", L10n.tr(app.name))
        }
        persistApplicationOrganization()
    }

    func applicationCount(for tab: ApplicationListTab) -> Int {
        switch tab {
        case .all:
            applications.count
        case .favorites:
            applications.filter(isApplicationFavorite).count
        case .music:
            applications.filter { $0.category == .music }.count
        case .video:
            applications.filter { $0.category == .video }.count
        case .other:
            applications.filter { $0.category == .other }.count
        }
    }

    func orderedApplications(for group: ApplicationOrderGroup) -> [ApplicationMixState] {
        let candidates: [ApplicationMixState]
        if let category = group.category {
            candidates = applications.filter { $0.category == category }
        } else {
            candidates = applications.filter(isApplicationFavorite)
        }

        let savedOrder = applicationOrders[group.rawValue] ?? []
        let savedPositions = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($0.element, $0.offset) })
        let livePositions = Dictionary(
            applications.enumerated().map { (applicationPreferenceKey(for: $0.element), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return candidates.sorted { lhs, rhs in
            let lhsKey = applicationPreferenceKey(for: lhs)
            let rhsKey = applicationPreferenceKey(for: rhs)
            let lhsSaved = savedPositions[lhsKey]
            let rhsSaved = savedPositions[rhsKey]
            if let lhsSaved, let rhsSaved, lhsSaved != rhsSaved { return lhsSaved < rhsSaved }
            if lhsSaved != nil, rhsSaved == nil { return true }
            if lhsSaved == nil, rhsSaved != nil { return false }
            let lhsLive = livePositions[lhsKey] ?? .max
            let rhsLive = livePositions[rhsKey] ?? .max
            if lhsLive != rhsLive { return lhsLive < rhsLive }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var orderedMinimalApplications: [ApplicationMixState] {
        let savedPositions = Dictionary(
            uniqueKeysWithValues: minimalApplicationOrder.enumerated().map { ($0.element, $0.offset) }
        )
        let livePositions = Dictionary(
            applications.enumerated().map { (minimalApplicationOrderKey(for: $0.element), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return applications.sorted { lhs, rhs in
            let lhsKey = minimalApplicationOrderKey(for: lhs)
            let rhsKey = minimalApplicationOrderKey(for: rhs)
            let lhsSaved = savedPositions[lhsKey]
            let rhsSaved = savedPositions[rhsKey]
            if let lhsSaved, let rhsSaved, lhsSaved != rhsSaved { return lhsSaved < rhsSaved }
            if lhsSaved != nil, rhsSaved == nil { return true }
            if lhsSaved == nil, rhsSaved != nil { return false }
            return (livePositions[lhsKey] ?? .max) < (livePositions[rhsKey] ?? .max)
        }
    }

    @discardableResult
    func moveMinimalApplication(preferenceKey sourceKey: String, by rowOffset: Int) -> Bool {
        guard rowOffset != 0 else { return false }

        var orderedKeys: [String] = []
        var namesByKey: [String: String] = [:]
        for item in orderedMinimalApplications {
            let key = minimalApplicationOrderKey(for: item)
            namesByKey[key] = item.name
            if !orderedKeys.contains(key) { orderedKeys.append(key) }
        }

        guard let sourceIndex = orderedKeys.firstIndex(of: sourceKey), orderedKeys.count > 1 else {
            return false
        }
        let destination = min(max(0, sourceIndex + rowOffset), orderedKeys.count - 1)
        guard destination != sourceIndex else { return false }

        orderedKeys.remove(at: sourceIndex)
        orderedKeys.insert(sourceKey, at: destination)
        minimalApplicationOrder = orderedKeys
        UserDefaults.standard.set(orderedKeys, forKey: Self.minimalApplicationOrderKey)
        statusMessage = L10n.format(
            "已调整 %@ 的极简列表顺序",
            L10n.tr(namesByKey[sourceKey] ?? "应用")
        )
        return true
    }

    func isApplicationGroupCollapsed(_ group: ApplicationOrderGroup) -> Bool {
        collapsedApplicationGroups.contains(group.rawValue)
    }

    func toggleApplicationGroupCollapsed(_ group: ApplicationOrderGroup) {
        if collapsedApplicationGroups.contains(group.rawValue) {
            collapsedApplicationGroups.remove(group.rawValue)
        } else {
            collapsedApplicationGroups.insert(group.rawValue)
        }
        UserDefaults.standard.set(collapsedApplicationGroups.sorted(), forKey: Self.collapsedApplicationGroupsKey)
    }

    func canMoveApplication(_ app: ApplicationMixState, in group: ApplicationOrderGroup, move: ApplicationOrderMove) -> Bool {
        let ordered = orderedApplications(for: group)
        guard let index = ordered.firstIndex(where: { $0.id == app.id }), ordered.count > 1 else { return false }
        switch move {
        case .up, .first: return index > 0
        case .down, .last: return index < ordered.count - 1
        }
    }

    func moveApplication(_ app: ApplicationMixState, in group: ApplicationOrderGroup, move: ApplicationOrderMove) {
        var orderedKeys: [String] = []
        for item in orderedApplications(for: group) {
            let key = applicationPreferenceKey(for: item)
            if !orderedKeys.contains(key) { orderedKeys.append(key) }
        }
        let key = applicationPreferenceKey(for: app)
        guard let index = orderedKeys.firstIndex(of: key), orderedKeys.count > 1 else { return }
        let destination: Int
        switch move {
        case .up: destination = max(0, index - 1)
        case .down: destination = min(orderedKeys.count - 1, index + 1)
        case .first: destination = 0
        case .last: destination = orderedKeys.count - 1
        }
        guard destination != index else { return }
        orderedKeys.remove(at: index)
        orderedKeys.insert(key, at: destination)
        applicationOrders[group.rawValue] = orderedKeys
        persistApplicationOrganization()
        statusMessage = L10n.format("已调整 %@ 在%@中的顺序", L10n.tr(app.name), group.title)
    }

    @discardableResult
    func moveApplication(
        preferenceKey sourceKey: String,
        by rowOffset: Int,
        in group: ApplicationOrderGroup
    ) -> Bool {
        guard rowOffset != 0 else { return false }

        var orderedKeys: [String] = []
        var namesByKey: [String: String] = [:]
        for item in orderedApplications(for: group) {
            let key = applicationPreferenceKey(for: item)
            namesByKey[key] = item.name
            if !orderedKeys.contains(key) { orderedKeys.append(key) }
        }

        guard let sourceIndex = orderedKeys.firstIndex(of: sourceKey), orderedKeys.count > 1 else {
            return false
        }
        let destination = min(max(0, sourceIndex + rowOffset), orderedKeys.count - 1)
        guard destination != sourceIndex else { return false }

        orderedKeys.remove(at: sourceIndex)
        orderedKeys.insert(sourceKey, at: destination)
        applicationOrders[group.rawValue] = orderedKeys
        persistApplicationOrganization()
        statusMessage = L10n.format(
            "已拖动调整 %@ 在%@中的顺序",
            L10n.tr(namesByKey[sourceKey] ?? "应用"),
            group.title
        )
        return true
    }

    @discardableResult
    func moveApplication(
        preferenceKey sourceKey: String,
        to target: ApplicationMixState,
        in group: ApplicationOrderGroup
    ) -> Bool {
        var orderedKeys: [String] = []
        for item in orderedApplications(for: group) {
            let key = applicationPreferenceKey(for: item)
            if !orderedKeys.contains(key) { orderedKeys.append(key) }
        }

        let targetKey = applicationPreferenceKey(for: target)
        guard sourceKey != targetKey,
              let sourceIndex = orderedKeys.firstIndex(of: sourceKey),
              let targetIndex = orderedKeys.firstIndex(of: targetKey) else {
            return false
        }

        orderedKeys.remove(at: sourceIndex)
        orderedKeys.insert(sourceKey, at: min(targetIndex, orderedKeys.count))
        applicationOrders[group.rawValue] = orderedKeys
        persistApplicationOrganization()
        statusMessage = L10n.format("已拖动调整 %@ 所在%@列表的顺序", L10n.tr(target.name), group.title)
        return true
    }

    private func persistApplicationOrganization() {
        UserDefaults.standard.set(favoriteApplicationKeys.sorted(), forKey: Self.favoriteApplicationKeysKey)
        if let data = try? JSONEncoder().encode(applicationOrders) {
            UserDefaults.standard.set(data, forKey: Self.applicationOrdersKey)
        }
    }

    func refresh() {
        syncRuntimeState(force: true)
    }

    func syncRuntimeState(force: Bool = false) {
        guard force || (activeUserInteractions == 0 && audioOperationsInFlight == 0) else { return }
        // The distributed appearance notification is occasionally coalesced
        // while the app is inactive. The existing low-cost runtime tick keeps
        // Follow System correct even when no notification was delivered.
        if theme == .system { synchronizeSystemAppearance() }
        let now = CFAbsoluteTimeGetCurrent()
        let topologyDue = force || now - lastTopologyRefresh >= 2.0
        let processesDue = force || now - lastProcessRefresh >= 0.9
        if processesDue {
            lastProcessRefresh = now
            refreshProcesses(force: force)
        }
        scheduleRuntimeRefresh(force: force, topologyDue: topologyDue, now: now)
    }

    private func scheduleRuntimeRefresh(force: Bool, topologyDue: Bool, now: CFAbsoluteTime) {
        if runtimeRefreshInFlight {
            if force || topologyDue { runtimeRefreshPendingForce = true }
            return
        }

        runtimeRefreshInFlight = true
        if topologyDue { lastTopologyRefresh = now }
        let request = RuntimeRefreshRequest(
            force: force,
            topologyDue: topologyDue,
            devices: devices,
            connectedUIDs: connectedUIDs,
            preferredOutputUID: preferredOutputUID,
            preferredInputUID: preferredInputUID,
            selectedOutputID: selectedOutputID,
            selectedInputID: selectedInputID,
            masterWriteSequence: masterVolumeWriteSequence,
            inputWriteSequence: inputVolumeWriteSequence
        )

        runtimeReadQueue.async { [weak self] in
            var refreshedDevices = request.devices
            var newlyAvailableUIDs = Set<String>()

            if request.topologyDue {
                refreshedDevices = CoreAudioBridge.devices()
                let refreshedUIDs = Set(refreshedDevices.map(\.uid))
                newlyAvailableUIDs = refreshedUIDs.subtracting(request.connectedUIDs)
                let isInitialScan = request.connectedUIDs.isEmpty

                if let preferredOutputUID = request.preferredOutputUID,
                   let preferred = refreshedDevices.first(where: { $0.uid == preferredOutputUID && $0.isOutput }),
                   !preferred.isDefaultOutput,
                   isInitialScan || newlyAvailableUIDs.contains(preferredOutputUID) {
                    try? CoreAudioBridge.setDefaultOutput(preferred.id)
                    refreshedDevices = CoreAudioBridge.devices()
                }
                if let preferredInputUID = request.preferredInputUID,
                   let preferred = refreshedDevices.first(where: { $0.uid == preferredInputUID && $0.isInput }),
                   !preferred.isDefaultInput,
                   isInitialScan || newlyAvailableUIDs.contains(preferredInputUID) {
                    try? CoreAudioBridge.setDefaultInput(preferred.id)
                    refreshedDevices = CoreAudioBridge.devices()
                }
            }

            let outputID = request.topologyDue
                ? refreshedDevices.first(where: \.isDefaultOutput)?.id
                    ?? refreshedDevices.first(where: \.isOutput)?.id
                    ?? kAudioObjectUnknown
                : request.selectedOutputID
            let inputID = request.topologyDue
                ? refreshedDevices.first(where: \.isDefaultInput)?.id
                    ?? refreshedDevices.first(where: \.isInput)?.id
                    ?? kAudioObjectUnknown
                : request.selectedInputID

            let snapshot = RuntimeRefreshSnapshot(
                force: request.force,
                topologyRefreshed: request.topologyDue,
                devices: refreshedDevices,
                connectedUIDs: request.topologyDue ? Set(refreshedDevices.map(\.uid)) : request.connectedUIDs,
                newlyAvailableUIDs: newlyAvailableUIDs,
                outputID: outputID,
                inputID: inputID,
                outputVolume: outputID == kAudioObjectUnknown ? nil : CoreAudioBridge.masterVolume(device: outputID),
                outputMuted: outputID == kAudioObjectUnknown ? nil : CoreAudioBridge.mute(device: outputID),
                inputVolume: inputID == kAudioObjectUnknown ? nil : CoreAudioBridge.inputVolume(device: inputID),
                inputMuted: inputID == kAudioObjectUnknown ? nil : CoreAudioBridge.mute(device: inputID, scope: kAudioDevicePropertyScopeInput),
                outputSupportsVolume: request.topologyDue && outputID != kAudioObjectUnknown
                    ? CoreAudioBridge.supportsVolume(device: outputID, scope: kAudioDevicePropertyScopeOutput)
                    : nil,
                inputSupportsVolume: request.topologyDue && inputID != kAudioObjectUnknown
                    ? CoreAudioBridge.supportsVolume(device: inputID, scope: kAudioDevicePropertyScopeInput)
                    : nil,
                outputLatencyMilliseconds: request.topologyDue && outputID != kAudioObjectUnknown
                    ? CoreAudioBridge.outputLatencyMilliseconds(device: outputID)
                    : nil,
                loginItemStatus: request.topologyDue ? SMAppService.mainApp.status : nil,
                masterWriteSequence: request.masterWriteSequence,
                inputWriteSequence: request.inputWriteSequence
            )
            DispatchQueue.main.async { [weak self] in
                self?.applyRuntimeSnapshot(snapshot)
            }
        }
    }

    private func applyRuntimeSnapshot(_ snapshot: RuntimeRefreshSnapshot) {
        runtimeRefreshInFlight = false
        guard activeUserInteractions == 0 && audioOperationsInFlight == 0 else {
            if snapshot.topologyRefreshed { lastTopologyRefresh = -Double.infinity }
            runtimeRefreshPendingForce = runtimeRefreshPendingForce || snapshot.force
            return
        }

        if snapshot.topologyRefreshed {
            let previousOutput = selectedOutputID
            connectedUIDs = snapshot.connectedUIDs
            if snapshot.force || snapshot.devices != devices { devices = snapshot.devices }
            let liveDeviceIDs = Set(snapshot.devices.map(\.id))
            if deviceRuntimeStates.keys.contains(where: { !liveDeviceIDs.contains($0) }) {
                deviceRuntimeStates = deviceRuntimeStates.filter { liveDeviceIDs.contains($0.key) }
            }
            if selectedOutputID != snapshot.outputID { selectedOutputID = snapshot.outputID }
            if selectedInputID != snapshot.inputID { selectedInputID = snapshot.inputID }
            if let supported = snapshot.outputSupportsVolume,
               selectedOutputSupportsVolume != supported {
                selectedOutputSupportsVolume = supported
            }
            if let supported = snapshot.inputSupportsVolume,
               selectedInputSupportsVolume != supported {
                selectedInputSupportsVolume = supported
            }
            if let latency = snapshot.outputLatencyMilliseconds,
               abs(outputLatencyMilliseconds - latency) > 0.01 {
                outputLatencyMilliseconds = latency
            }
            if let status = snapshot.loginItemStatus {
                if loginItemStatus != status { loginItemStatus = status }
                let enabled = status == .enabled
                if loginItemEnabled != enabled { loginItemEnabled = enabled }
            }
            if previousOutput != kAudioObjectUnknown, previousOutput != snapshot.outputID {
                for app in applications where app.processingActive && app.routeDeviceUID == nil {
                    scheduleApplicationProcessing(id: app.id, immediate: true)
                }
            }
            if snapshot.force || !snapshot.newlyAvailableUIDs.isEmpty {
                if let output = snapshot.devices.first(where: \.isDefaultOutput) {
                    remember(output, usedAsOutput: true, usedAsInput: false)
                }
                if let input = snapshot.devices.first(where: \.isDefaultInput) {
                    remember(input, usedAsOutput: false, usedAsInput: true)
                }
            }
        }

        if snapshot.masterWriteSequence == masterVolumeWriteSequence,
           snapshot.outputID == selectedOutputID {
            if let value = snapshot.outputVolume, abs(value - masterVolume) > 0.002 { masterVolume = value }
            if let muted = snapshot.outputMuted, muted != masterMuted { masterMuted = muted }
        }
        if snapshot.inputWriteSequence == inputVolumeWriteSequence,
           snapshot.inputID == selectedInputID {
            if let value = snapshot.inputVolume, abs(value - inputVolume) > 0.002 { inputVolume = value }
            if let muted = snapshot.inputMuted, muted != inputMuted { inputMuted = muted }
        }
        mergeSelectedDeviceRuntimeState(snapshot)

        if runtimeRefreshPendingForce {
            runtimeRefreshPendingForce = false
            syncRuntimeState(force: true)
        }
    }

    private func mergeSelectedDeviceRuntimeState(_ snapshot: RuntimeRefreshSnapshot) {
        var nextStates = deviceRuntimeStates
        var changed = false
        if snapshot.outputID != kAudioObjectUnknown,
           let device = devices.first(where: { $0.id == snapshot.outputID }) {
            var state = nextStates[snapshot.outputID] ?? AudioDeviceRuntimeState(
                availableSampleRates: device.sampleRate > 0 ? [device.sampleRate] : []
            )
            let original = state
            if let value = snapshot.outputVolume { state.outputVolume = value }
            if let muted = snapshot.outputMuted { state.outputMuted = muted }
            if let supported = snapshot.outputSupportsVolume { state.outputSupportsVolume = supported }
            if state != original { nextStates[snapshot.outputID] = state; changed = true }
        }
        if snapshot.inputID != kAudioObjectUnknown,
           let device = devices.first(where: { $0.id == snapshot.inputID }) {
            var state = nextStates[snapshot.inputID] ?? AudioDeviceRuntimeState(
                availableSampleRates: device.sampleRate > 0 ? [device.sampleRate] : []
            )
            let original = state
            if let value = snapshot.inputVolume { state.inputVolume = value }
            if let muted = snapshot.inputMuted { state.inputMuted = muted }
            if let supported = snapshot.inputSupportsVolume { state.inputSupportsVolume = supported }
            if state != original { nextStates[snapshot.inputID] = state; changed = true }
        }
        if changed { deviceRuntimeStates = nextStates }
    }

    func setUserInteractionActive(_ active: Bool) {
        if active {
            activeUserInteractions += 1
            return
        }

        activeUserInteractions = max(0, activeUserInteractions - 1)
        guard activeUserInteractions == 0 else { return }
        if equalizerPersistenceWork != nil {
            equalizerPersistenceWork?.cancel()
            equalizerPersistenceWork = nil
            persistEqualizers()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.activeUserInteractions == 0 else { return }
            self.syncRuntimeState()
        }
    }

    func refreshProcesses(force: Bool = false) {
        guard !processRefreshInFlight else {
            processRefreshPendingForce = processRefreshPendingForce || force
            return
        }
        processRefreshInFlight = true
        processScanQueue.async { [weak self] in
            let processes = CoreAudioBridge.processes()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.processRefreshInFlight = false
                guard self.activeUserInteractions == 0 else {
                    // Do not publish a process snapshot into a view hierarchy
                    // while a native slider owns pointer tracking.
                    self.lastProcessRefresh = -Double.infinity
                    return
                }
                self.applyProcessSnapshot(processes, force: force)
                if self.processRefreshPendingForce {
                    self.processRefreshPendingForce = false
                    self.refreshProcesses(force: true)
                }
            }
        }
    }

    private func applyProcessSnapshot(_ processes: [AudioProcessModel], force: Bool) {
        processByID = Dictionary(uniqueKeysWithValues: processes.map { ($0.id, $0) })
        let old = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        let oldByPID = Dictionary(applications.map { ($0.pid, $0) }, uniquingKeysWith: { existing, _ in existing })
        var retainedPIDs = Set<pid_t>()
        var next: [ApplicationMixState] = []

        // New rows are created only after real output has been observed. Once
        // observed, the same host process remains in the list while paused.
        for process in processes {
            let previous = old[process.id] ?? oldByPID[process.pid]
            guard process.isRunningOutput || previous != nil else { continue }
            var state = previous ?? ApplicationMixState(
                id: process.id,
                pid: process.pid,
                bundleID: process.bundleID,
                name: process.name,
                icon: process.icon,
                category: process.category,
                volume: 1,
                isRunningOutput: process.isRunningOutput
            )
            state.id = process.id
            state.pid = process.pid
            state.bundleID = process.bundleID
            state.name = process.name
            state.category = process.category
            if state.icon == nil { state.icon = process.icon }
            state.isRunningOutput = process.isRunningOutput
            retainedPIDs.insert(process.pid)
            next.append(state)
        }

        // Some apps temporarily remove their Core Audio process object when
        // playback stops. Retain their last session until the actual host PID
        // terminates, then restore it if Core Audio publishes a new object.
        for var saved in applications where !retainedPIDs.contains(saved.pid) && isHostProcessAlive(saved.pid) {
            saved.isRunningOutput = false
            retainedPIDs.insert(saved.pid)
            next.append(saved)
        }

        next.sort {
            if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
            if $0.isRunningOutput != $1.isRunningOutput { return $0.isRunningOutput }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if next.count > 32 { next.removeSubrange(32...) }
        let oldSignature = applications.map { "\($0.id):\($0.name):\($0.category.rawValue):\($0.isRunningOutput)" }
        let newSignature = next.map { "\($0.id):\($0.name):\($0.category.rawValue):\($0.isRunningOutput)" }
        if force || oldSignature != newSignature { applications = next }

        // A total EQ must automatically pick up every newly audible process;
        // per-app EQ profiles also follow the stable bundle/name key across a
        // Core Audio object-ID replacement.
        for app in next {
            let equalizerActive = masterEqualizer.isEnabled || applicationEqualizer(for: app).isEnabled
            let ordinaryProcessingActive = app.isMuted || abs(app.volume - 1) > 0.001 || app.overdriveEnabled || app.routeDeviceUID != nil
            let objectChanged = oldByPID[app.pid]?.id != app.id
            if (equalizerActive || ordinaryProcessingActive) && (!app.processingActive || objectChanged) {
                scheduleApplicationProcessing(id: app.id, immediate: true)
            }
        }

        let livePIDs = Set(next.map(\.pid))
        for removed in old.values where !livePIDs.contains(removed.pid) {
            processAudioManager.stop(processID: removed.pid)
        }
    }

    private func isHostProcessAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    func deviceRuntimeState(for device: AudioDeviceModel) -> AudioDeviceRuntimeState {
        var state = deviceRuntimeStates[device.id] ?? AudioDeviceRuntimeState(
            availableSampleRates: device.sampleRate > 0 ? [device.sampleRate] : []
        )
        if device.id == selectedOutputID {
            state.outputVolume = masterVolume
            state.outputMuted = masterMuted
            state.outputSupportsVolume = selectedOutputSupportsVolume
        }
        if device.id == selectedInputID {
            state.inputVolume = inputVolume
            state.inputMuted = inputMuted
            state.inputSupportsVolume = selectedInputSupportsVolume
        }
        return state
    }

    func refreshDeviceRuntimeState(_ deviceID: AudioObjectID) {
        guard let device = devices.first(where: { $0.id == deviceID }),
              !deviceRuntimeRefreshesInFlight.contains(deviceID) else { return }
        deviceRuntimeRefreshesInFlight.insert(deviceID)
        runtimeReadQueue.async { [weak self] in
            let state = AudioDeviceRuntimeState(
                outputVolume: device.isOutput ? CoreAudioBridge.masterVolume(device: deviceID) : 0,
                outputMuted: device.isOutput ? CoreAudioBridge.mute(device: deviceID) : false,
                outputSupportsVolume: device.isOutput
                    ? CoreAudioBridge.supportsVolume(device: deviceID, scope: kAudioDevicePropertyScopeOutput)
                    : false,
                inputVolume: device.isInput ? CoreAudioBridge.inputVolume(device: deviceID) : 0,
                inputMuted: device.isInput
                    ? CoreAudioBridge.mute(device: deviceID, scope: kAudioDevicePropertyScopeInput)
                    : false,
                inputSupportsVolume: device.isInput
                    ? CoreAudioBridge.supportsVolume(device: deviceID, scope: kAudioDevicePropertyScopeInput)
                    : false,
                availableSampleRates: CoreAudioBridge.availableSampleRates(device: deviceID)
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.deviceRuntimeRefreshesInFlight.remove(deviceID)
                guard self.devices.contains(where: { $0.id == deviceID }) else { return }
                if self.deviceRuntimeStates[deviceID] != state {
                    self.deviceRuntimeStates[deviceID] = state
                }
                if deviceID == self.selectedOutputID {
                    if self.selectedOutputSupportsVolume != state.outputSupportsVolume {
                        self.selectedOutputSupportsVolume = state.outputSupportsVolume
                    }
                }
                if deviceID == self.selectedInputID {
                    if self.selectedInputSupportsVolume != state.inputSupportsVolume {
                        self.selectedInputSupportsVolume = state.inputSupportsVolume
                    }
                }
            }
        }
    }

    func setOutputVolume(_ value: Double, for deviceID: AudioObjectID) {
        if deviceID == selectedOutputID {
            setMasterVolume(value)
            return
        }
        let requested = min(max(value, 0), 1)
        if var state = deviceRuntimeStates[deviceID] {
            state.outputVolume = requested
            if requested > 0.001 { state.outputMuted = false }
            deviceRuntimeStates[deviceID] = state
        }
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setMasterVolume(requested, device: deviceID)
                DispatchQueue.main.async { [weak self] in self?.refreshDeviceRuntimeState(deviceID) }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.refreshDeviceRuntimeState(deviceID)
                }
            }
        }
    }

    func setInputVolume(_ value: Double, for deviceID: AudioObjectID) {
        if deviceID == selectedInputID {
            setInputVolume(value)
            return
        }
        let requested = min(max(value, 0), 1)
        if var state = deviceRuntimeStates[deviceID] {
            state.inputVolume = requested
            deviceRuntimeStates[deviceID] = state
        }
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setInputVolume(requested, device: deviceID)
                DispatchQueue.main.async { [weak self] in self?.refreshDeviceRuntimeState(deviceID) }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.refreshDeviceRuntimeState(deviceID)
                }
            }
        }
    }

    func setOutputMuted(_ muted: Bool, for deviceID: AudioObjectID) {
        if deviceID == selectedOutputID {
            setMasterMuted(muted)
            return
        }
        if var state = deviceRuntimeStates[deviceID] {
            state.outputMuted = muted
            deviceRuntimeStates[deviceID] = state
        }
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setMute(muted, device: deviceID)
                DispatchQueue.main.async { [weak self] in self?.refreshDeviceRuntimeState(deviceID) }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.refreshDeviceRuntimeState(deviceID)
                }
            }
        }
    }

    func setInputMuted(_ muted: Bool, for deviceID: AudioObjectID) {
        if deviceID == selectedInputID {
            setInputMuted(muted)
            return
        }
        if var state = deviceRuntimeStates[deviceID] {
            state.inputMuted = muted
            deviceRuntimeStates[deviceID] = state
        }
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setMute(muted, device: deviceID, scope: kAudioDevicePropertyScopeInput)
                DispatchQueue.main.async { [weak self] in self?.refreshDeviceRuntimeState(deviceID) }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = error.localizedDescription
                    self?.refreshDeviceRuntimeState(deviceID)
                }
            }
        }
    }

    func setMasterVolume(_ value: Double) {
        guard selectedOutputID != kAudioObjectUnknown else { return }
        let requested = min(max(value, 0), 1)
        let deviceID = selectedOutputID
        let shouldUnmute = requested > 0.001 && masterMuted
        masterVolumeWriteSequence &+= 1
        let sequence = masterVolumeWriteSequence

        // Publish the user's intent immediately so every slider and percentage
        // stays under the pointer. Potentially blocking HAL writes run on a
        // dedicated serial queue and therefore cannot steal AppKit tracking
        // frames from the main run loop.
        if abs(masterVolume - requested) > 0.0005 { masterVolume = requested }
        if requested > 0.001 { masterMuted = false }
        deviceWriteQueue.async { [weak self] in
            do {
                if shouldUnmute { try CoreAudioBridge.setMute(false, device: deviceID) }
                try CoreAudioBridge.setMasterVolume(requested, device: deviceID)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.masterVolumeWriteSequence == sequence else { return }
                    if self.activeUserInteractions == 0 {
                        self.statusMessage = L10n.format("系统主音量已同步为 %@%%", String(Int(requested * 100)))
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.masterVolumeWriteSequence == sequence else { return }
                    self.errorMessage = error.localizedDescription
                    self.syncRuntimeState(force: true)
                }
            }
        }
    }

    func setMasterMuted(_ muted: Bool) {
        guard selectedOutputID != kAudioObjectUnknown else { return }
        let deviceID = selectedOutputID
        masterVolumeWriteSequence &+= 1
        let sequence = masterVolumeWriteSequence

        // Muting is a visual state transition too: publish it before touching
        // HAL so the master and application sliders collapse to zero in the
        // same frame as the click. The real device write remains serialized
        // with volume changes off the main run loop.
        masterMuted = muted
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setMute(muted, device: deviceID)
                let confirmedMute = CoreAudioBridge.mute(device: deviceID)
                let confirmedVolume = CoreAudioBridge.masterVolume(device: deviceID)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.masterVolumeWriteSequence == sequence else { return }
                    self.masterMuted = confirmedMute
                    self.masterVolume = confirmedVolume
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.masterVolumeWriteSequence == sequence else { return }
                    self.errorMessage = error.localizedDescription
                    self.syncRuntimeState(force: true)
                }
            }
        }
    }

    func setInputVolume(_ value: Double) {
        guard selectedInputID != kAudioObjectUnknown else { return }
        let requested = min(max(value, 0), 1)
        let deviceID = selectedInputID
        inputVolumeWriteSequence &+= 1
        let sequence = inputVolumeWriteSequence
        if abs(inputVolume - requested) > 0.0005 { inputVolume = requested }
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setInputVolume(requested, device: deviceID)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputVolumeWriteSequence == sequence else { return }
                    if self.activeUserInteractions == 0 { self.statusMessage = L10n.tr("输入增益已同步") }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputVolumeWriteSequence == sequence else { return }
                    self.errorMessage = "\(L10n.tr("当前输入设备不支持软件增益。"))\n\(error.localizedDescription)"
                    self.syncRuntimeState(force: true)
                }
            }
        }
    }

    func setInputMuted(_ muted: Bool) {
        guard selectedInputID != kAudioObjectUnknown else { return }
        let deviceID = selectedInputID
        inputVolumeWriteSequence &+= 1
        let sequence = inputVolumeWriteSequence
        inputMuted = muted
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setMute(muted, device: deviceID, scope: kAudioDevicePropertyScopeInput)
                let confirmed = CoreAudioBridge.mute(device: deviceID, scope: kAudioDevicePropertyScopeInput)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputVolumeWriteSequence == sequence else { return }
                    self.inputMuted = confirmed
                    self.refreshDeviceRuntimeState(deviceID)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputVolumeWriteSequence == sequence else { return }
                    self.errorMessage = error.localizedDescription
                    self.syncRuntimeState(force: true)
                }
            }
        }
    }

    func selectOutput(_ id: AudioObjectID) {
        guard id != kAudioObjectUnknown, let device = devices.first(where: { $0.id == id }) else { return }
        let previousID = selectedOutputID
        outputSelectionSequence &+= 1
        let sequence = outputSelectionSequence
        selectedOutputID = id
        let cached = deviceRuntimeState(for: device)
        selectedOutputSupportsVolume = cached.outputSupportsVolume
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setDefaultOutput(id)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.outputSelectionSequence == sequence else { return }
                    self.preferredOutputUID = device.uid
                    UserDefaults.standard.set(device.uid, forKey: Self.preferredOutputUIDKey)
                    self.remember(device, usedAsOutput: true, usedAsInput: false)
                    self.syncRuntimeState(force: true)
                    for app in self.applications where app.processingActive {
                        self.scheduleApplicationProcessing(id: app.id, immediate: true)
                    }
                    self.statusMessage = L10n.format("已切换系统输出设备：%@", device.name)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.outputSelectionSequence == sequence else { return }
                    self.selectedOutputID = previousID
                    self.errorMessage = error.localizedDescription
                    self.syncRuntimeState(force: true)
                }
            }
        }
    }

    func selectInput(_ id: AudioObjectID) {
        guard id != kAudioObjectUnknown, let device = devices.first(where: { $0.id == id }) else { return }
        let previousID = selectedInputID
        inputSelectionSequence &+= 1
        let sequence = inputSelectionSequence
        selectedInputID = id
        let cached = deviceRuntimeState(for: device)
        selectedInputSupportsVolume = cached.inputSupportsVolume
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setDefaultInput(id)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputSelectionSequence == sequence else { return }
                    self.preferredInputUID = device.uid
                    UserDefaults.standard.set(device.uid, forKey: Self.preferredInputUIDKey)
                    self.remember(device, usedAsOutput: false, usedAsInput: true)
                    self.syncRuntimeState(force: true)
                    self.statusMessage = L10n.format("已切换系统输入设备：%@", device.name)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.inputSelectionSequence == sequence else { return }
                    self.selectedInputID = previousID
                    self.errorMessage = error.localizedDescription
                    self.syncRuntimeState(force: true)
                }
            }
        }
    }

    func setSampleRate(_ sampleRate: Double, for deviceID: AudioObjectID) {
        deviceWriteQueue.async { [weak self] in
            do {
                try CoreAudioBridge.setSampleRate(sampleRate, device: deviceID)
                DispatchQueue.main.async { [weak self] in
                    self?.refreshDeviceRuntimeState(deviceID)
                    self?.syncRuntimeState(force: true)
                    self?.statusMessage = L10n.format("采样率已设置为 %@ Hz", String(Int(sampleRate)))
                }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            loginItemStatus = SMAppService.mainApp.status
            switch SMAppService.mainApp.status {
            case .enabled: statusMessage = L10n.tr("已允许登录时启动")
            case .requiresApproval: statusMessage = L10n.tr("登录启动项已申请，等待在系统设置中批准")
            case .notRegistered: statusMessage = L10n.tr("已关闭登录时启动")
            case .notFound: statusMessage = L10n.tr("登录启动服务不可用")
            @unknown default: statusMessage = L10n.tr("登录启动状态已更新")
            }
        } catch {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            errorMessage = "\(L10n.tr("无法修改登录启动项。"))\n\(error.localizedDescription)"
        }
    }

    func updateApplication(id: AudioObjectID, _ edit: (inout ApplicationMixState) -> Void) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        edit(&applications[index])
    }

    func setApplicationMuted(id: AudioObjectID, muted: Bool) {
        updateApplication(id: id) { $0.isMuted = muted }
        scheduleApplicationProcessing(id: id, immediate: true)
    }

    func setApplicationVolume(id: AudioObjectID, volume: Double) {
        let requested = min(max(volume, 0), 1)
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        let needsVolumeUpdate = abs(applications[index].volume - requested) > 0.0005
        let needsUnmute = requested > 0.001 && applications[index].isMuted
        guard needsVolumeUpdate || needsUnmute else { return }
        applications[index].volume = requested
        if needsUnmute { applications[index].isMuted = false }
        scheduleApplicationProcessing(id: id)
    }

    func setApplicationBoost(id: AudioObjectID, boost: Int) {
        updateApplication(id: id) { app in
            app.boost = min(max(boost, 1), 4)
            app.overdriveEnabled = app.boost > 1
        }
        scheduleApplicationProcessing(id: id, immediate: true)
    }

    func setApplicationRoute(id: AudioObjectID, deviceID: AudioObjectID?) {
        if let deviceID, let device = outputDevices.first(where: { $0.id == deviceID }) {
            updateApplication(id: id) {
                $0.route = device.name
                $0.routeDeviceUID = device.uid
            }
        } else {
            updateApplication(id: id) {
                $0.route = "跟随系统输出"
                $0.routeDeviceUID = nil
            }
        }
        scheduleApplicationProcessing(id: id, immediate: true)
    }

    func resetApplicationControls(id: AudioObjectID) {
        let equalizerKey = applications.first(where: { $0.id == id }).map(applicationPreferenceKey)
        updateApplication(id: id) { app in
            app.volume = 1
            app.isMuted = false
            app.boost = 1
            app.overdriveEnabled = false
            app.route = "跟随系统输出"
            app.routeDeviceUID = nil
        }
        if let equalizerKey {
            applicationEqualizers.removeValue(forKey: equalizerKey)
            scheduleEqualizerPersistence()
        }
        cancelTimedMute(id: id)
        scheduleApplicationProcessing(id: id, immediate: true)
        statusMessage = L10n.tr("已恢复应用的默认声音设置")
    }

    /// Resolves the output endpoint that an application's audio reaches right
    /// now. A nil route UID means "follow the system", not an unknown device,
    /// so the UI should surface the current Core Audio default endpoint.
    func resolvedOutputDevice(for app: ApplicationMixState) -> AudioDeviceModel? {
        if let routeUID = app.routeDeviceUID {
            return outputDevices.first { $0.uid == routeUID }
        }
        return outputDevices.first { $0.id == selectedOutputID }
    }

    func setAllActiveMuted(_ muted: Bool) {
        for app in runningApplications { setApplicationMuted(id: app.id, muted: muted) }
        statusMessage = L10n.tr(muted ? "已静音全部正在发声的应用" : "已取消全部应用静音")
    }

    func scheduleTimedMute(id: AudioObjectID, seconds: TimeInterval) {
        timedMuteWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.setApplicationMuted(id: id, muted: true) }
        }
        timedMuteWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        statusMessage = L10n.format("已设置 %@ 分钟后静音", String(Int(seconds / 60)))
    }

    func cancelTimedMute(id: AudioObjectID) {
        timedMuteWork.removeValue(forKey: id)?.cancel()
        statusMessage = L10n.tr("已取消定时静音")
    }

    func requestSystemAudioPermission() {
        // Never recreate the capture preflight after this stable bundle ID has
        // already completed a real tap operation. Creating another temporary
        // tap is itself an authorization request on macOS and can make a user
        // think the permission was forgotten.
        if systemAudioPermissionGranted == true {
            statusMessage = L10n.tr("系统音频录制权限已可用")
            return
        }
        statusMessage = L10n.tr("正在向 macOS 申请系统音频录制权限…")
        processAudioManager.requestSystemAudioPermission { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.updateSystemAudioPermission(true)
                self.statusMessage = L10n.tr("系统音频录制权限已可用")
            case .failure(let error):
                self.updateSystemAudioPermission(false)
                self.errorMessage = "\(L10n.tr("系统音频权限未获得。"))\n\(error.localizedDescription)"
            }
        }
    }

    private func updateSystemAudioPermission(_ granted: Bool) {
        guard systemAudioPermissionGranted != granted else { return }
        systemAudioPermissionGranted = granted
        UserDefaults.standard.set(granted, forKey: Self.systemAudioPermissionKey)
    }

    private func scheduleApplicationProcessing(id: AudioObjectID, immediate: Bool = false) {
        pendingProcessingWork[id]?.cancel()
        let now = CFAbsoluteTimeGetCurrent()
        let minimumInterval = 1.0 / 60.0
        let elapsed = now - (lastProcessingApply[id] ?? 0)
        if immediate || elapsed >= minimumInterval {
            pendingProcessingWork[id] = nil
            lastProcessingApply[id] = now
            applyApplicationProcessing(id: id)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.lastProcessingApply[id] = CFAbsoluteTimeGetCurrent()
                self?.pendingProcessingWork[id] = nil
                self?.applyApplicationProcessing(id: id)
            }
        }
        pendingProcessingWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, minimumInterval - elapsed), execute: work)
    }

    private func remember(_ device: AudioDeviceModel, usedAsOutput: Bool, usedAsInput: Bool) {
        if let index = rememberedDevices.firstIndex(where: { $0.uid == device.uid }) {
            rememberedDevices[index].name = device.name
            rememberedDevices[index].inputChannels = device.inputChannels
            rememberedDevices[index].outputChannels = device.outputChannels
            rememberedDevices[index].transportType = device.transportType
            rememberedDevices[index].manufacturer = device.manufacturer
            rememberedDevices[index].lastSeen = Date()
            rememberedDevices[index].usedAsOutput = rememberedDevices[index].usedAsOutput || usedAsOutput
            rememberedDevices[index].usedAsInput = rememberedDevices[index].usedAsInput || usedAsInput
        } else {
            rememberedDevices.append(
                RememberedAudioDevice(
                    uid: device.uid,
                    name: device.name,
                    inputChannels: device.inputChannels,
                    outputChannels: device.outputChannels,
                    transportType: device.transportType,
                    manufacturer: device.manufacturer,
                    lastSeen: Date(),
                    usedAsInput: usedAsInput,
                    usedAsOutput: usedAsOutput
                )
            )
        }
        rememberedDevices.sort { $0.lastSeen > $1.lastSeen }
        if rememberedDevices.count > 20 { rememberedDevices.removeSubrange(20...) }
        if let data = try? JSONEncoder().encode(rememberedDevices) {
            UserDefaults.standard.set(data, forKey: Self.rememberedDevicesKey)
        }
    }

    private func applyApplicationProcessing(id: AudioObjectID) {
        guard let process = processByID[id], let app = applications.first(where: { $0.id == id }) else { return }
        let routeDevice: AudioDeviceModel
        if let routeUID = app.routeDeviceUID {
            guard let explicitDevice = outputDevices.first(where: { $0.uid == routeUID }) else {
                errorMessage = L10n.format("%@ 当前未连接，请重新选择输出设备", L10n.tr(app.route))
                return
            }
            routeDevice = explicitDevice
        } else {
            guard let systemDevice = selectedOutput else {
                errorMessage = L10n.tr("系统输出设备当前不可用")
                return
            }
            routeDevice = systemDevice
        }
        let gain = app.isMuted ? 0 : app.volume * (app.overdriveEnabled ? Double(app.boost) : 1)
        let applicationEqualizer = applicationEqualizer(for: app)
        let forceProcessing = app.isMuted ||
            abs(app.volume - 1) > 0.001 ||
            app.overdriveEnabled ||
            app.routeDeviceUID != nil ||
            masterEqualizer.isEnabled ||
            applicationEqualizer.isEnabled
        audioOperationsInFlight += 1
        processAudioManager.apply(
            process: process,
            outputDeviceUID: routeDevice.uid,
            gain: Float(gain),
            masterEqualizer: masterEqualizer,
            applicationEqualizer: applicationEqualizer,
            forceProcessing: forceProcessing
        ) { [weak self] result in
            guard let self else { return }
            self.audioOperationsInFlight = max(0, self.audioOperationsInFlight - 1)
            switch result {
            case .success(let active):
                if self.applicationState(id: id)?.processingActive != active {
                    self.updateApplication(id: id) { $0.processingActive = active }
                }
                if active { self.updateSystemAudioPermission(true) }
                if self.activeUserInteractions == 0 {
                    self.statusMessage = active
                        ? L10n.format("正在实时处理 %@", L10n.tr(process.name))
                        : L10n.format("%@ 已恢复系统直通", L10n.tr(process.name))
                }
            case .failure(let error):
                self.updateApplication(id: id) { $0.processingActive = false }
                // A HAL route/start failure is not evidence that macOS revoked
                // Audio Capture permission. Keep the persisted authorization
                // state and report the actual audio-path failure instead of
                // making the permission UI flip back to “未授权” every launch.
                self.errorMessage = "\(L10n.format("无法控制 %@。", L10n.tr(process.name)))\n\(error.localizedDescription)"
            }
            if self.audioOperationsInFlight == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self, self.activeUserInteractions == 0 else { return }
                    self.syncRuntimeState()
                }
            }
        }
    }

}
