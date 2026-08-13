#import "SLProcessAudioMixer.h"
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <unistd.h>

static NSString * const SLAudioErrorDomain = @"com.starry.shenglan.audio";

static NSError *SLMakeAudioError(OSStatus status, NSString *operation) {
    UInt32 big = CFSwapInt32HostToBig((UInt32)status);
    char code[5] = {0};
    memcpy(code, &big, 4);
    NSString *statusText = nil;
    BOOL printable = true;
    for (int i = 0; i < 4; ++i) {
        if (code[i] < 32 || code[i] > 126) { printable = false; break; }
    }
    if (status == kAudioHardwareIllegalOperationError) {
        statusText = @"音频设备正忙或尚未就绪";
    } else if (status == kAudioHardwareNotReadyError) {
        statusText = @"音频设备尚未就绪";
    } else {
        statusText = printable ? [NSString stringWithUTF8String:code] : [NSString stringWithFormat:@"%d", status];
    }
    return [NSError errorWithDomain:SLAudioErrorDomain
                               code:status
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@失败（%@）", operation, statusText]}];
}

static OSStatus SLStartAudioDeviceWithRetry(AudioObjectID deviceID,
                                             AudioDeviceIOProcID ioProcID) {
    OSStatus status = noErr;
    for (int attempt = 0; attempt < 10; ++attempt) {
        status = AudioDeviceStart(deviceID, ioProcID);
        if (status == noErr) { return noErr; }
        if (status != kAudioHardwareIllegalOperationError &&
            status != kAudioHardwareNotReadyError) {
            return status;
        }
        // Core Audio publishes aggregate membership asynchronously. Retrying
        // here is safe because this work runs on the dedicated mixer queue and
        // prevents the transient four-character `nope` status from escaping to
        // the UI while Bluetooth or process-tap endpoints settle.
        usleep((useconds_t)(40000 + attempt * 15000));
    }
    return status;
}

// Apple’s Core Audio tap sample creates the aggregate first, then adds the
// physical output and tap through aggregate-device properties. Doing this in
// one composition dictionary can leave Bluetooth-backed aggregates waiting in
// AudioDeviceCreateIOProcID. Keep the playback device live first, then attach
// the tap as the aggregate input.
static OSStatus SLSetAggregateUIDList(AudioObjectID aggregateID,
                                      AudioObjectPropertySelector selector,
                                      NSString *uid) {
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    CFArrayRef list = (__bridge CFArrayRef)@[uid];
    UInt32 size = sizeof(list);
    return AudioObjectSetPropertyData(aggregateID, &address, 0, nullptr, size, &list);
}

static OSStatus SLSetAggregateMainDevice(AudioObjectID aggregateID, NSString *uid) {
    AudioObjectPropertyAddress address = {
        kAudioAggregateDevicePropertyMainSubDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    CFStringRef mainUID = (__bridge CFStringRef)uid;
    UInt32 size = sizeof(mainUID);
    return AudioObjectSetPropertyData(aggregateID, &address, 0, nullptr, size, &mainUID);
}

static UInt32 SLAggregateObjectCount(AudioObjectID aggregateID,
                                     AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nullptr, &size) != noErr) {
        return 0;
    }
    return size / sizeof(AudioObjectID);
}

static OSStatus SLWaitForPlaybackAggregate(AudioObjectID aggregateID) {
    // Aggregate composition is applied by coreaudiod asynchronously. Starting
    // IO in the same turn can fail with kAudioHardwareIllegalOperationError,
    // especially when the physical endpoint is Bluetooth. This queue is not
    // the main thread, so wait briefly for both the output device and subtap.
    for (int attempt = 0; attempt < 100; ++attempt) {
        const UInt32 activeDevices = SLAggregateObjectCount(
            aggregateID,
            kAudioAggregateDevicePropertyActiveSubDeviceList
        );
        const UInt32 activeTaps = SLAggregateObjectCount(
            aggregateID,
            kAudioAggregateDevicePropertySubTapList
        );
        if (activeDevices > 0 && activeTaps > 0) { return noErr; }
        usleep(10000);
    }
    return kAudioHardwareNotReadyError;
}

static OSStatus SLWaitForTapAggregate(AudioObjectID aggregateID) {
    for (int attempt = 0; attempt < 100; ++attempt) {
        if (SLAggregateObjectCount(
                aggregateID,
                kAudioAggregateDevicePropertySubTapList
            ) > 0) {
            return noErr;
        }
        usleep(10000);
    }
    return kAudioHardwareNotReadyError;
}

static OSStatus SLCreateTapAggregate(NSString *name,
                                     NSString *tapUID,
                                     AudioObjectID *aggregateID) {
    NSDictionary *description = @{
        @kAudioAggregateDeviceNameKey: name,
        @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceIsPrivateKey: @YES
    };
    OSStatus status = AudioHardwareCreateAggregateDevice(
        (__bridge CFDictionaryRef)description,
        aggregateID
    );
    if (status != noErr) { return status; }
    status = SLSetAggregateUIDList(
        *aggregateID,
        kAudioAggregateDevicePropertyTapList,
        tapUID
    );
    if (status != noErr) { return status; }
    return SLWaitForTapAggregate(*aggregateID);
}

static OSStatus SLCreatePlaybackAggregate(NSString *name,
                                          NSString *outputDeviceUID,
                                          NSString *tapUID,
                                          AudioObjectID *aggregateID) {
    NSDictionary *description = @{
        @kAudioAggregateDeviceNameKey: name,
        @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceIsPrivateKey: @YES
    };
    OSStatus status = AudioHardwareCreateAggregateDevice(
        (__bridge CFDictionaryRef)description,
        aggregateID
    );
    if (status != noErr) { return status; }

    status = SLSetAggregateUIDList(
        *aggregateID,
        kAudioAggregateDevicePropertyFullSubDeviceList,
        outputDeviceUID
    );
    if (status != noErr) { return status; }

    status = SLSetAggregateMainDevice(*aggregateID, outputDeviceUID);
    if (status != noErr) { return status; }

    status = SLSetAggregateUIDList(
        *aggregateID,
        kAudioAggregateDevicePropertyTapList,
        tapUID
    );
    if (status != noErr) { return status; }
    return SLWaitForPlaybackAggregate(*aggregateID);
}

@interface SLProcessAudioMixer () {
    std::atomic<float> _realtimeGain;
    AudioObjectID _tapID;
    AudioObjectID _aggregateID;
    AudioDeviceIOProcID _ioProcID;
    BOOL _running;
    AudioObjectID _processObjectID;
    NSString *_outputDeviceUID;
}
@end

static OSStatus SLMixerIOProc(AudioObjectID,
                              const AudioTimeStamp *,
                              const AudioBufferList *inputData,
                              const AudioTimeStamp *,
                              AudioBufferList *outputData,
                              const AudioTimeStamp *,
                              void *clientData) noexcept {
    SLProcessAudioMixer *mixer = (__bridge SLProcessAudioMixer *)clientData;
    if (mixer == nil || outputData == nullptr) { return noErr; }

    const float gain = mixer.gain;
    for (UInt32 outputIndex = 0; outputIndex < outputData->mNumberBuffers; ++outputIndex) {
        AudioBuffer &output = outputData->mBuffers[outputIndex];
        if (output.mData == nullptr || output.mDataByteSize == 0) { continue; }
        memset(output.mData, 0, output.mDataByteSize);

        if (inputData == nullptr || inputData->mNumberBuffers == 0) { continue; }
        const UInt32 inputIndex = std::min(outputIndex, inputData->mNumberBuffers - 1);
        const AudioBuffer &input = inputData->mBuffers[inputIndex];
        if (input.mData == nullptr || input.mDataByteSize == 0) { continue; }

        const UInt32 byteCount = std::min(input.mDataByteSize, output.mDataByteSize);
        const UInt32 sampleCount = byteCount / sizeof(Float32);
        const Float32 *source = static_cast<const Float32 *>(input.mData);
        Float32 *destination = static_cast<Float32 *>(output.mData);
        for (UInt32 sample = 0; sample < sampleCount; ++sample) {
            // 1x is strict unity gain. Higher boosts are peak-limited so the
            // processing path never writes invalid samples or adds clipping
            // overshoot on top of the device's own master volume.
            const Float32 processed = source[sample] * gain;
            destination[sample] = fminf(fmaxf(processed, -1.0f), 1.0f);
        }
    }
    return noErr;
}

static OSStatus SLPermissionIOProc(AudioObjectID,
                                   const AudioTimeStamp *,
                                   const AudioBufferList *,
                                   const AudioTimeStamp *,
                                   AudioBufferList *outputData,
                                   const AudioTimeStamp *,
                                   void *) noexcept {
    if (outputData != nullptr) {
        for (UInt32 index = 0; index < outputData->mNumberBuffers; ++index) {
            AudioBuffer &buffer = outputData->mBuffers[index];
            if (buffer.mData != nullptr && buffer.mDataByteSize > 0) {
                memset(buffer.mData, 0, buffer.mDataByteSize);
            }
        }
    }
    return noErr;
}

@implementation SLProcessAudioMixer

+ (OSStatus)requestSystemAudioPermission {
    if (@available(macOS 14.2, *)) {
        AudioObjectID tapID = kAudioObjectUnknown;
        AudioObjectID aggregateID = kAudioObjectUnknown;
        AudioDeviceIOProcID ioProcID = nullptr;
        CFStringRef tapUID = nullptr;

        auto cleanup = [&]() {
            if (aggregateID != kAudioObjectUnknown && ioProcID != nullptr) {
                AudioDeviceStop(aggregateID, ioProcID);
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID);
            }
            ioProcID = nullptr;
            if (aggregateID != kAudioObjectUnknown) {
                AudioHardwareDestroyAggregateDevice(aggregateID);
            }
            aggregateID = kAudioObjectUnknown;
            if (tapID != kAudioObjectUnknown) {
                AudioHardwareDestroyProcessTap(tapID);
            }
            tapID = kAudioObjectUnknown;
            if (tapUID != nullptr) { CFRelease(tapUID); tapUID = nullptr; }
        };

        CATapDescription *tapDescription =
            [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];
        tapDescription.name = @"音合流 · 系统音频权限检查";
        tapDescription.privateTap = YES;
        tapDescription.muteBehavior = CATapUnmuted;

        OSStatus status = AudioHardwareCreateProcessTap(tapDescription, &tapID);
        if (status != noErr) { cleanup(); return status; }

        AudioObjectPropertyAddress tapUIDAddress = {
            kAudioTapPropertyUID,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        UInt32 tapUIDSize = sizeof(CFStringRef);
        status = AudioObjectGetPropertyData(tapID, &tapUIDAddress, 0, nullptr, &tapUIDSize, &tapUID);
        if (status != noErr || tapUID == nullptr) { cleanup(); return status; }

        // Permission preflight follows Apple's sample exactly: a tap-only
        // aggregate is enough to start capture and avoids touching the user's
        // current Bluetooth output device.
        status = SLCreateTapAggregate(
            @"音合流 · 系统音频权限检查",
            (__bridge NSString *)tapUID,
            &aggregateID
        );
        if (status != noErr) { cleanup(); return status; }

        status = AudioDeviceCreateIOProcID(aggregateID, SLPermissionIOProc, nullptr, &ioProcID);
        if (status != noErr) { cleanup(); return status; }

        // Apple's Core Audio tap authorization is evaluated when the aggregate
        // actually starts recording, not when the tap object is created.
        status = SLStartAudioDeviceWithRetry(aggregateID, ioProcID);
        if (status == noErr) {
            usleep(120000);
        }
        cleanup();
        return status;
    }
    return kAudioHardwareUnsupportedOperationError;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _realtimeGain.store(1.0f);
        _tapID = kAudioObjectUnknown;
        _aggregateID = kAudioObjectUnknown;
        _ioProcID = nullptr;
        _running = NO;
        _processObjectID = kAudioObjectUnknown;
        _outputDeviceUID = @"";
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (float)gain { return _realtimeGain.load(std::memory_order_relaxed); }
- (void)setGain:(float)gain { _realtimeGain.store(fminf(fmaxf(gain, 0.0f), 4.0f), std::memory_order_relaxed); }
- (BOOL)isRunning { return _running; }
- (AudioObjectID)processObjectID { return _processObjectID; }
- (NSString *)outputDeviceUID { return _outputDeviceUID; }

- (BOOL)startWithProcessObjectID:(AudioObjectID)processObjectID
                     processName:(NSString *)processName
                 outputDeviceUID:(NSString *)outputDeviceUID
                            gain:(float)gain
                           error:(NSError * _Nullable * _Nullable)error {
    [self stop];
    self.gain = gain;
    _processObjectID = processObjectID;
    _outputDeviceUID = [outputDeviceUID copy];

    CATapDescription *tapDescription = [[CATapDescription alloc] initStereoMixdownOfProcesses:@[@(processObjectID)]];
    tapDescription.name = [NSString stringWithFormat:@"音合流音量 · %@", processName];
    tapDescription.privateTap = YES;
    // The processed signal must be the only copy reaching the output while the
    // aggregate is reading. mutedWhenTapped leaves normal playback untouched
    // before IO starts, then suppresses the original copy during tap reads.
    tapDescription.muteBehavior = CATapMutedWhenTapped;

    OSStatus status = noErr;
    if (@available(macOS 14.2, *)) {
        status = AudioHardwareCreateProcessTap(tapDescription, &_tapID);
    } else {
        status = kAudioHardwareUnsupportedOperationError;
    }
    if (status != noErr) {
        if (error) { *error = SLMakeAudioError(status, @"创建应用音频通道"); }
        [self stop];
        return NO;
    }

    AudioObjectPropertyAddress tapUIDAddress = {kAudioTapPropertyUID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 tapUIDSize = sizeof(CFStringRef);
    CFStringRef tapUID = nullptr;
    status = AudioObjectGetPropertyData(_tapID, &tapUIDAddress, 0, nullptr, &tapUIDSize, &tapUID);
    if (status != noErr || tapUID == nullptr) {
        if (error) { *error = SLMakeAudioError(status, @"读取应用音频通道"); }
        [self stop];
        return NO;
    }

    status = SLCreatePlaybackAggregate(
        [NSString stringWithFormat:@"音合流 · %@", processName],
        outputDeviceUID,
        (__bridge NSString *)tapUID,
        &_aggregateID
    );
    CFRelease(tapUID);
    if (status != noErr) {
        if (error) { *error = SLMakeAudioError(status, @"创建应用混音设备"); }
        [self stop];
        return NO;
    }

    status = AudioDeviceCreateIOProcID(_aggregateID, SLMixerIOProc, (__bridge void *)self, &_ioProcID);
    if (status != noErr) {
        if (error) { *error = SLMakeAudioError(status, @"建立应用音频回送"); }
        [self stop];
        return NO;
    }

    status = SLStartAudioDeviceWithRetry(_aggregateID, _ioProcID);
    if (status != noErr) {
        if (error) { *error = SLMakeAudioError(status, @"启动应用音频处理"); }
        [self stop];
        return NO;
    }
    _running = YES;
    return YES;
}

- (void)stop {
    if (_aggregateID != kAudioObjectUnknown && _ioProcID != nullptr) {
        AudioDeviceStop(_aggregateID, _ioProcID);
        AudioDeviceDestroyIOProcID(_aggregateID, _ioProcID);
    }
    _ioProcID = nullptr;
    if (_aggregateID != kAudioObjectUnknown) {
        AudioHardwareDestroyAggregateDevice(_aggregateID);
    }
    _aggregateID = kAudioObjectUnknown;
    if (_tapID != kAudioObjectUnknown) {
        if (@available(macOS 14.2, *)) {
            AudioHardwareDestroyProcessTap(_tapID);
        }
    }
    _tapID = kAudioObjectUnknown;
    _running = NO;
    _processObjectID = kAudioObjectUnknown;
    _outputDeviceUID = @"";
}

@end
