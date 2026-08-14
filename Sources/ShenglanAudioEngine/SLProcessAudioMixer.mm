#import "SLProcessAudioMixer.h"
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
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

namespace {

constexpr size_t SLEqualizerBandCount = 10;
constexpr size_t SLEqualizerStageCount = 2;
constexpr size_t SLMaximumChannelCount = 16;
constexpr size_t SLReverbChannelCount = 2;
constexpr size_t SLReverbCombCount = 4;
constexpr size_t SLReverbAllpassCount = 2;
constexpr size_t SLReverbMaximumDelaySamples = 16'384;
constexpr size_t SLMasterEqualizerStage = 0;
constexpr size_t SLApplicationEqualizerStage = 1;

constexpr std::array<double, SLEqualizerBandCount> SLEqualizerFrequencies = {
    31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
};

// Prime-ish delay lengths from the classic Schroeder/Freeverb topology at
// 44.1 kHz. They are sample-rate scaled and decorrelated per stereo channel.
constexpr std::array<size_t, SLReverbCombCount> SLReverbCombTunings = {
    1116, 1188, 1277, 1356
};
constexpr std::array<size_t, SLReverbAllpassCount> SLReverbAllpassTunings = {
    556, 441
};

struct SLBiquadCoefficients {
    float b0 = 1.0f;
    float b1 = 0.0f;
    float b2 = 0.0f;
    float a1 = 0.0f;
    float a2 = 0.0f;
};

struct SLAtomicBiquadCoefficients {
    std::atomic<float> b0 {1.0f};
    std::atomic<float> b1 {0.0f};
    std::atomic<float> b2 {0.0f};
    std::atomic<float> a1 {0.0f};
    std::atomic<float> a2 {0.0f};

    void store(const SLBiquadCoefficients &value) noexcept {
        b0.store(value.b0, std::memory_order_relaxed);
        b1.store(value.b1, std::memory_order_relaxed);
        b2.store(value.b2, std::memory_order_relaxed);
        a1.store(value.a1, std::memory_order_relaxed);
        a2.store(value.a2, std::memory_order_relaxed);
    }

    SLBiquadCoefficients load() const noexcept {
        return {
            b0.load(std::memory_order_relaxed),
            b1.load(std::memory_order_relaxed),
            b2.load(std::memory_order_relaxed),
            a1.load(std::memory_order_relaxed),
            a2.load(std::memory_order_relaxed)
        };
    }
};

struct SLBiquadState {
    float z1 = 0.0f;
    float z2 = 0.0f;
};

struct SLDelayLine {
    std::array<float, SLReverbMaximumDelaySamples> buffer {};
    size_t index = 0;

    float process(float input, size_t requestedLength) noexcept {
        if (requestedLength == 0) { return input; }
        const size_t length = std::min(requestedLength, SLReverbMaximumDelaySamples);
        if (index >= length) { index = 0; }
        const float output = buffer[index];
        buffer[index] = input;
        index += 1;
        if (index >= length) { index = 0; }
        return output;
    }
};

struct SLCombFilter {
    SLDelayLine delay;
    float dampedOutput = 0.0f;

    float process(float input,
                  size_t delaySamples,
                  float feedback,
                  float damping) noexcept {
        const size_t length = std::max<size_t>(1, std::min(delaySamples, SLReverbMaximumDelaySamples));
        if (delay.index >= length) { delay.index = 0; }
        const float output = delay.buffer[delay.index];
        dampedOutput = output * (1.0f - damping) + dampedOutput * damping;
        delay.buffer[delay.index] = input + dampedOutput * feedback;
        delay.index += 1;
        if (delay.index >= length) { delay.index = 0; }
        return output;
    }
};

struct SLAllpassFilter {
    SLDelayLine delay;

    float process(float input, size_t delaySamples) noexcept {
        constexpr float feedback = 0.50f;
        const size_t length = std::max<size_t>(1, std::min(delaySamples, SLReverbMaximumDelaySamples));
        if (delay.index >= length) { delay.index = 0; }
        const float delayed = delay.buffer[delay.index];
        const float output = delayed - input;
        delay.buffer[delay.index] = input + delayed * feedback;
        delay.index += 1;
        if (delay.index >= length) { delay.index = 0; }
        return output;
    }
};

struct SLReverbState {
    SLDelayLine preDelay;
    std::array<SLCombFilter, SLReverbCombCount> combs;
    std::array<SLAllpassFilter, SLReverbAllpassCount> allpasses;
};

struct SLEqualizerSnapshot {
    bool enabled[SLEqualizerStageCount] = {false, false};
    float preamp[SLEqualizerStageCount] = {1.0f, 1.0f};
    float stereoBalance[SLEqualizerStageCount] = {0.0f, 0.0f};
    float reverbWetMix[SLEqualizerStageCount] = {0.0f, 0.0f};
    float reverbRoomSize[SLEqualizerStageCount] = {0.5f, 0.5f};
    float reverbDamping[SLEqualizerStageCount] = {0.5f, 0.5f};
    float reverbPreDelayMS[SLEqualizerStageCount] = {0.0f, 0.0f};
    float reverbStereoWidth[SLEqualizerStageCount] = {0.5f, 0.5f};
    SLBiquadCoefficients coefficients[SLEqualizerStageCount][SLEqualizerBandCount];
};

static SLBiquadCoefficients SLPeakingEqualizerCoefficients(double frequency,
                                                            double gainDB,
                                                            double sampleRate) noexcept {
    if (std::abs(gainDB) < 0.001 || sampleRate <= 0 || frequency >= sampleRate * 0.475) {
        return {};
    }

    // One-octave graphic bands use a broad constant-Q filter so adjacent
    // settings combine into an audible musical curve rather than isolated pins.
    // The formula is the normalized Audio EQ Cookbook peaking-EQ biquad.
    constexpr double q = 1.00;
    const double amplitude = std::pow(10.0, gainDB / 40.0);
    const double omega = 2.0 * M_PI * frequency / sampleRate;
    const double alpha = std::sin(omega) / (2.0 * q);
    const double cosine = std::cos(omega);
    const double a0 = 1.0 + alpha / amplitude;
    return {
        static_cast<float>((1.0 + alpha * amplitude) / a0),
        static_cast<float>((-2.0 * cosine) / a0),
        static_cast<float>((1.0 - alpha * amplitude) / a0),
        static_cast<float>((-2.0 * cosine) / a0),
        static_cast<float>((1.0 - alpha / amplitude) / a0)
    };
}

class SLRealtimeDSP final {
public:
    std::atomic<float> gain {1.0f};

    void setSampleRate(double sampleRate) noexcept {
        sampleRate_ = sampleRate > 0 ? sampleRate : 48'000.0;
        publishCoefficients();
        clearState();
    }

    void configure(size_t stage,
                   bool enabled,
                   float preampDB,
                   NSArray<NSNumber *> *bandGains) noexcept {
        if (stage >= SLEqualizerStageCount) { return; }
        const bool enabledChanged = stageEnabled_[stage] != enabled;
        stageEnabled_[stage] = enabled;
        preampDB_[stage] = std::min(std::max(preampDB, -12.0f), 0.0f);
        for (size_t index = 0; index < SLEqualizerBandCount; ++index) {
            const float value = index < bandGains.count ? bandGains[index].floatValue : 0.0f;
            bandGainsDB_[stage][index] = std::min(std::max(value, -12.0f), 12.0f);
        }
        publishCoefficients();
        if (enabledChanged) { resetStateRequested_.store(true, std::memory_order_release); }
    }

    void configureReverb(size_t stage,
                         float wetMix,
                         float roomSize,
                         float damping,
                         float preDelayMS,
                         float stereoWidth) noexcept {
        if (stage >= SLEqualizerStageCount) { return; }
        const float nextWetMix = std::min(std::max(wetMix, 0.0f), 0.60f);
        const float nextRoomSize = std::min(std::max(roomSize, 0.0f), 1.0f);
        const float nextDamping = std::min(std::max(damping, 0.0f), 1.0f);
        const float nextPreDelayMS = std::min(std::max(preDelayMS, 0.0f), 80.0f);
        const float nextStereoWidth = std::min(std::max(stereoWidth, 0.0f), 1.0f);
        const bool activeChanged = (reverbWetMixValue_[stage] > 0.001f) != (nextWetMix > 0.001f);
        const bool topologyChanged =
            std::abs(reverbRoomSizeValue_[stage] - nextRoomSize) > 0.001f ||
            std::abs(reverbDampingValue_[stage] - nextDamping) > 0.001f ||
            std::abs(reverbPreDelayMSValue_[stage] - nextPreDelayMS) > 0.01f ||
            std::abs(reverbStereoWidthValue_[stage] - nextStereoWidth) > 0.001f;
        reverbWetMixValue_[stage] = nextWetMix;
        reverbRoomSizeValue_[stage] = nextRoomSize;
        reverbDampingValue_[stage] = nextDamping;
        reverbPreDelayMSValue_[stage] = nextPreDelayMS;
        reverbStereoWidthValue_[stage] = nextStereoWidth;
        publishCoefficients();
        if (activeChanged || topologyChanged) {
            resetStateRequested_.store(true, std::memory_order_release);
        }
    }

    void configureStereoBalance(size_t stage, float balance) noexcept {
        if (stage >= SLEqualizerStageCount) { return; }
        stereoBalanceValue_[stage] = std::min(std::max(balance, -1.0f), 1.0f);
        publishCoefficients();
    }

    void beginRender() noexcept {
        if (resetStateRequested_.exchange(false, std::memory_order_acq_rel)) {
            clearState();
        }
    }

    void snapshot(SLEqualizerSnapshot &result) const noexcept {
        uint64_t before = 0;
        uint64_t after = 0;
        do {
            before = parameterVersion_.load(std::memory_order_acquire);
            if ((before & 1U) != 0) { continue; }
            for (size_t stage = 0; stage < SLEqualizerStageCount; ++stage) {
                result.enabled[stage] = enabled_[stage].load(std::memory_order_relaxed);
                result.preamp[stage] = preamp_[stage].load(std::memory_order_relaxed);
                result.stereoBalance[stage] = stereoBalance_[stage].load(std::memory_order_relaxed);
                result.reverbWetMix[stage] = reverbWetMix_[stage].load(std::memory_order_relaxed);
                result.reverbRoomSize[stage] = reverbRoomSize_[stage].load(std::memory_order_relaxed);
                result.reverbDamping[stage] = reverbDamping_[stage].load(std::memory_order_relaxed);
                result.reverbPreDelayMS[stage] = reverbPreDelayMS_[stage].load(std::memory_order_relaxed);
                result.reverbStereoWidth[stage] = reverbStereoWidth_[stage].load(std::memory_order_relaxed);
                for (size_t band = 0; band < SLEqualizerBandCount; ++band) {
                    result.coefficients[stage][band] = coefficients_[stage][band].load();
                }
            }
            after = parameterVersion_.load(std::memory_order_acquire);
        } while (before != after || (after & 1U) != 0);
    }

    float process(float input,
                  size_t channel,
                  const SLEqualizerSnapshot &parameters) noexcept {
        const size_t safeChannel = std::min(channel, SLMaximumChannelCount - 1);
        float sample = input * gain.load(std::memory_order_relaxed);
        // Each stage runs tone shaping followed by its own room model. The
        // application stage remains first, then the shared master stage.
        sample = processStage(sample, safeChannel, SLApplicationEqualizerStage, parameters);
        sample = processStage(sample, safeChannel, SLMasterEqualizerStage, parameters);
        return softPeakLimit(sample);
    }

private:
    double sampleRate_ = 48'000.0;
    bool stageEnabled_[SLEqualizerStageCount] = {false, false};
    float preampDB_[SLEqualizerStageCount] = {0.0f, 0.0f};
    float bandGainsDB_[SLEqualizerStageCount][SLEqualizerBandCount] = {};
    float reverbWetMixValue_[SLEqualizerStageCount] = {0.0f, 0.0f};
    float reverbRoomSizeValue_[SLEqualizerStageCount] = {0.5f, 0.5f};
    float reverbDampingValue_[SLEqualizerStageCount] = {0.5f, 0.5f};
    float reverbPreDelayMSValue_[SLEqualizerStageCount] = {0.0f, 0.0f};
    float reverbStereoWidthValue_[SLEqualizerStageCount] = {0.5f, 0.5f};
    float stereoBalanceValue_[SLEqualizerStageCount] = {0.0f, 0.0f};
    std::atomic<uint64_t> parameterVersion_ {0};
    std::atomic<bool> resetStateRequested_ {false};
    std::atomic<bool> enabled_[SLEqualizerStageCount];
    std::atomic<float> preamp_[SLEqualizerStageCount];
    std::atomic<float> stereoBalance_[SLEqualizerStageCount];
    std::atomic<float> reverbWetMix_[SLEqualizerStageCount];
    std::atomic<float> reverbRoomSize_[SLEqualizerStageCount];
    std::atomic<float> reverbDamping_[SLEqualizerStageCount];
    std::atomic<float> reverbPreDelayMS_[SLEqualizerStageCount];
    std::atomic<float> reverbStereoWidth_[SLEqualizerStageCount];
    SLAtomicBiquadCoefficients coefficients_[SLEqualizerStageCount][SLEqualizerBandCount];
    SLBiquadState state_[SLMaximumChannelCount][SLEqualizerStageCount][SLEqualizerBandCount];
    SLReverbState reverbState_[SLEqualizerStageCount][SLReverbChannelCount];

    void publishCoefficients() noexcept {
        parameterVersion_.fetch_add(1, std::memory_order_acq_rel);
        for (size_t stage = 0; stage < SLEqualizerStageCount; ++stage) {
            enabled_[stage].store(stageEnabled_[stage], std::memory_order_relaxed);
            const float linearPreamp = stageEnabled_[stage]
                ? std::pow(10.0f, preampDB_[stage] / 20.0f)
                : 1.0f;
            preamp_[stage].store(linearPreamp, std::memory_order_relaxed);
            stereoBalance_[stage].store(
                stageEnabled_[stage] ? stereoBalanceValue_[stage] : 0.0f,
                std::memory_order_relaxed
            );
            reverbWetMix_[stage].store(
                stageEnabled_[stage] ? reverbWetMixValue_[stage] : 0.0f,
                std::memory_order_relaxed
            );
            reverbRoomSize_[stage].store(reverbRoomSizeValue_[stage], std::memory_order_relaxed);
            reverbDamping_[stage].store(reverbDampingValue_[stage], std::memory_order_relaxed);
            reverbPreDelayMS_[stage].store(reverbPreDelayMSValue_[stage], std::memory_order_relaxed);
            reverbStereoWidth_[stage].store(reverbStereoWidthValue_[stage], std::memory_order_relaxed);
            for (size_t band = 0; band < SLEqualizerBandCount; ++band) {
                const SLBiquadCoefficients value = stageEnabled_[stage]
                    ? SLPeakingEqualizerCoefficients(
                        SLEqualizerFrequencies[band],
                        bandGainsDB_[stage][band],
                        sampleRate_
                    )
                    : SLBiquadCoefficients {};
                coefficients_[stage][band].store(value);
            }
        }
        parameterVersion_.fetch_add(1, std::memory_order_release);
    }

    void clearState() noexcept {
        std::memset(state_, 0, sizeof(state_));
        std::memset(reverbState_, 0, sizeof(reverbState_));
    }

    float processStage(float sample,
                       size_t channel,
                       size_t stage,
                       const SLEqualizerSnapshot &parameters) noexcept {
        if (!parameters.enabled[stage]) { return sample; }
        float value = sample * parameters.preamp[stage];
        for (size_t band = 0; band < SLEqualizerBandCount; ++band) {
            const SLBiquadCoefficients &coefficient = parameters.coefficients[stage][band];
            SLBiquadState &filterState = state_[channel][stage][band];
            const float output = coefficient.b0 * value + filterState.z1;
            filterState.z1 = coefficient.b1 * value - coefficient.a1 * output + filterState.z2;
            filterState.z2 = coefficient.b2 * value - coefficient.a2 * output;
            value = output;
        }
        value = processReverb(value, channel, stage, parameters);
        const float balance = parameters.stereoBalance[stage];
        if (channel == 0 && balance > 0.0f) {
            value *= 1.0f - balance;
        } else if (channel == 1 && balance < 0.0f) {
            value *= 1.0f + balance;
        }
        return value;
    }

    float processReverb(float input,
                        size_t channel,
                        size_t stage,
                        const SLEqualizerSnapshot &parameters) noexcept {
        const float wetMix = parameters.reverbWetMix[stage];
        if (wetMix <= 0.001f) { return input; }

        const size_t reverbChannel = std::min(channel, SLReverbChannelCount - 1);
        SLReverbState &reverb = reverbState_[stage][reverbChannel];
        const float sampleRateScale = static_cast<float>(sampleRate_ / 44'100.0);
        const size_t preDelaySamples = static_cast<size_t>(std::lround(
            parameters.reverbPreDelayMS[stage] * static_cast<float>(sampleRate_) / 1'000.0f
        ));
        const float preDelayed = reverb.preDelay.process(input, preDelaySamples);
        const float feedback = std::min(
            0.93f,
            0.68f + parameters.reverbRoomSize[stage] * 0.25f
        );
        const float damping = std::min(
            0.86f,
            0.08f + parameters.reverbDamping[stage] * 0.78f
        );
        const float width = parameters.reverbStereoWidth[stage];
        const size_t stereoOffset = reverbChannel == 0
            ? 0
            : static_cast<size_t>(std::lround((12.0f + width * 23.0f) * sampleRateScale));

        float wetSignal = 0.0f;
        constexpr float reverbInputGain = 0.45f;
        for (size_t index = 0; index < SLReverbCombCount; ++index) {
            const size_t delaySamples = static_cast<size_t>(std::lround(
                static_cast<float>(SLReverbCombTunings[index]) * sampleRateScale
            )) + stereoOffset;
            wetSignal += reverb.combs[index].process(
                preDelayed * reverbInputGain,
                delaySamples,
                feedback,
                damping
            );
        }
        wetSignal /= static_cast<float>(SLReverbCombCount);

        for (size_t index = 0; index < SLReverbAllpassCount; ++index) {
            const size_t delaySamples = static_cast<size_t>(std::lround(
                static_cast<float>(SLReverbAllpassTunings[index]) * sampleRateScale
            )) + stereoOffset / 2;
            wetSignal = reverb.allpasses[index].process(wetSignal, delaySamples);
        }

        // Keep dry audio present while making the room tail immediately
        // audible. Preset-specific preamp headroom and the final soft limiter
        // protect against the extra correlated energy.
        const float dryGain = 1.0f - wetMix * 0.35f;
        const float wetGain = wetMix * 1.55f;
        return input * dryGain + wetSignal * wetGain;
    }

    static float softPeakLimit(float sample) noexcept {
        constexpr float knee = 0.98f;
        constexpr float ceiling = 0.999f;
        const float magnitude = std::abs(sample);
        if (magnitude <= knee) { return sample; }
        const float normalized = (magnitude - knee) / (ceiling - knee);
        const float limited = knee + (ceiling - knee) * std::tanh(normalized);
        return std::copysign(std::min(limited, ceiling), sample);
    }
};

} // namespace

@interface SLProcessAudioMixer () {
    SLRealtimeDSP *_realtimeDSP;
    AudioObjectID _tapID;
    AudioObjectID _aggregateID;
    AudioDeviceIOProcID _ioProcID;
    BOOL _running;
    AudioObjectID _processObjectID;
    NSString *_outputDeviceUID;
}
- (SLRealtimeDSP *)realtimeDSP;
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

    SLRealtimeDSP *dsp = mixer.realtimeDSP;
    if (dsp == nullptr) { return noErr; }
    dsp->beginRender();
    SLEqualizerSnapshot parameters;
    dsp->snapshot(parameters);
    size_t channelBase = 0;
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
        const size_t bufferChannels = std::max<size_t>(1, output.mNumberChannels);
        for (UInt32 sample = 0; sample < sampleCount; ++sample) {
            const size_t channel = channelBase + (sample % bufferChannels);
            destination[sample] = dsp->process(source[sample], channel, parameters);
        }
        channelBase += bufferChannels;
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
        _realtimeDSP = new SLRealtimeDSP();
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
    delete _realtimeDSP;
    _realtimeDSP = nullptr;
}

- (SLRealtimeDSP *)realtimeDSP { return _realtimeDSP; }
- (float)gain { return _realtimeDSP != nullptr ? _realtimeDSP->gain.load(std::memory_order_relaxed) : 1.0f; }
- (void)setGain:(float)gain {
    if (_realtimeDSP != nullptr) {
        _realtimeDSP->gain.store(fminf(fmaxf(gain, 0.0f), 4.0f), std::memory_order_relaxed);
    }
}
- (BOOL)isRunning { return _running; }
- (AudioObjectID)processObjectID { return _processObjectID; }
- (NSString *)outputDeviceUID { return _outputDeviceUID; }

- (void)setMasterEqualizerEnabled:(BOOL)enabled
                        preampDB:(float)preampDB
                       bandGains:(NSArray<NSNumber *> *)bandGains {
    if (_realtimeDSP != nullptr) {
        _realtimeDSP->configure(SLMasterEqualizerStage, enabled, preampDB, bandGains);
    }
}

- (void)setMasterReverbWetMix:(float)wetMix
                     roomSize:(float)roomSize
                      damping:(float)damping
                   preDelayMS:(float)preDelayMS
                  stereoWidth:(float)stereoWidth {
    if (_realtimeDSP != nullptr) {
        _realtimeDSP->configureReverb(
            SLMasterEqualizerStage,
            wetMix,
            roomSize,
            damping,
            preDelayMS,
            stereoWidth
        );
    }
}

- (void)setMasterStereoBalance:(float)balance {
    if (_realtimeDSP != nullptr) {
        _realtimeDSP->configureStereoBalance(SLMasterEqualizerStage, balance);
    }
}

- (void)setApplicationEqualizerEnabled:(BOOL)enabled
                             preampDB:(float)preampDB
                            bandGains:(NSArray<NSNumber *> *)bandGains {
    if (_realtimeDSP != nullptr) {
        _realtimeDSP->configure(SLApplicationEqualizerStage, enabled, preampDB, bandGains);
    }
}

- (void)setApplicationReverbWetMix:(float)wetMix
                          roomSize:(float)roomSize
                           damping:(float)damping
                        preDelayMS:(float)preDelayMS
                       stereoWidth:(float)stereoWidth {
    if (_realtimeDSP != nullptr) {
        _realtimeDSP->configureReverb(
            SLApplicationEqualizerStage,
            wetMix,
            roomSize,
            damping,
            preDelayMS,
            stereoWidth
        );
    }
}

- (void)setApplicationStereoBalance:(float)balance {
    if (_realtimeDSP != nullptr) {
        _realtimeDSP->configureStereoBalance(SLApplicationEqualizerStage, balance);
    }
}

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

    AudioObjectPropertyAddress sampleRateAddress = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    Float64 sampleRate = 48'000.0;
    UInt32 sampleRateSize = sizeof(sampleRate);
    if (AudioObjectGetPropertyData(
            _aggregateID,
            &sampleRateAddress,
            0,
            nullptr,
            &sampleRateSize,
            &sampleRate
        ) != noErr || sampleRate <= 0) {
        sampleRate = 48'000.0;
    }
    if (_realtimeDSP != nullptr) { _realtimeDSP->setSampleRate(sampleRate); }

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
