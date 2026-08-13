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
