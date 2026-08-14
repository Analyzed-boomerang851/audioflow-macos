#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Real-time-safe Core Audio process tap loopback with per-process gain.
/// The tapped process is muted only while the aggregate device is actively reading the tap.
@interface SLProcessAudioMixer : NSObject

@property (atomic) float gain;
@property (atomic, readonly, getter=isRunning) BOOL running;
@property (atomic, readonly) AudioObjectID processObjectID;
@property (atomic, copy, readonly) NSString *outputDeviceUID;

/// Configures the shared "all applications" equalizer stage. Values are ten
/// fixed graphic-EQ bands from 31 Hz through 16 kHz, expressed in decibels.
- (void)setMasterEqualizerEnabled:(BOOL)enabled
                        preampDB:(float)preampDB
                       bandGains:(NSArray<NSNumber *> *)bandGains;

/// Configures the algorithmic room stage that follows the master equalizer.
/// Mix is 0...0.6, room/damping/width are normalized 0...1, and pre-delay is ms.
- (void)setMasterReverbWetMix:(float)wetMix
                     roomSize:(float)roomSize
                      damping:(float)damping
                   preDelayMS:(float)preDelayMS
                  stereoWidth:(float)stereoWidth;

/// Sets master stereo balance from -1 (left) through 0 (center) to +1 (right).
/// The favored channel remains at unity while the opposite channel is attenuated.
- (void)setMasterStereoBalance:(float)balance;

/// Configures the equalizer stage owned by the tapped application. The master
/// stage runs after this stage, so both curves remain independently editable.
- (void)setApplicationEqualizerEnabled:(BOOL)enabled
                             preampDB:(float)preampDB
                            bandGains:(NSArray<NSNumber *> *)bandGains;

/// Configures the per-application room stage. It runs before the shared master
/// equalizer/reverb so application and total scenes remain independently real.
- (void)setApplicationReverbWetMix:(float)wetMix
                          roomSize:(float)roomSize
                           damping:(float)damping
                        preDelayMS:(float)preDelayMS
                       stereoWidth:(float)stereoWidth;

/// Sets per-application stereo balance without adding gain to either channel.
- (void)setApplicationStereoBalance:(float)balance;

/// Starts a short-lived private global process-tap aggregate and immediately
/// tears it down. macOS requests/validates System Audio Recording access when
/// recording actually starts; merely creating a tap is not an authorization
/// check. No application needs to be playing and no samples are retained.
+ (OSStatus)requestSystemAudioPermission;

- (BOOL)startWithProcessObjectID:(AudioObjectID)processObjectID
                     processName:(NSString *)processName
                 outputDeviceUID:(NSString *)outputDeviceUID
                            gain:(float)gain
                           error:(NSError * _Nullable * _Nullable)error;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
