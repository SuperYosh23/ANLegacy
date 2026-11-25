#import "LTPlayerController.h"
#import "LTYouTubeClient.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"
// For LTTempDirectory(), where the downloaded track is staged before playback.
#import "LTFilePaths.h"
// For isfinite(), used to keep NaN out of the now-playing dictionary.
#import <math.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>

NSString *const LTPlayerTrackDidChangeNotification = @"LTPlayerTrackDidChangeNotification";
NSString *const LTPlayerStateDidChangeNotification = @"LTPlayerStateDidChangeNotification";
NSString *const LTPlayerDidFinishQueueNotification = @"LTPlayerDidFinishQueueNotification";
NSString *const LTPlayerQueueDidChangeNotification = @"LTPlayerQueueDidChangeNotification";

// These keys were added with MPNowPlayingInfoCenter in iOS 5. Using the literal
// strings keeps iOS 4 from resolving weak-imported constant symbols at all.
static NSString * const LTNowPlayingElapsedKey = @"MPNowPlayingInfoPropertyElapsedPlaybackTime";
static NSString * const LTNowPlayingRateKey = @"MPNowPlayingInfoPropertyPlaybackRate";
static NSString * const LTNowPlayingQueueIndexKey = @"MPNowPlayingInfoPropertyPlaybackQueueIndex";
static NSString * const LTNowPlayingQueueCountKey = @"MPNowPlayingInfoPropertyPlaybackQueueCount";

@interface LTPlayerController () <NSURLConnectionDataDelegate, AVAudioPlayerDelegate>
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) AVPlayer *moviePlayer;
@property (nonatomic, assign) BOOL pendingMuxed;
@property (nonatomic, copy) NSArray *queue;
@property (nonatomic, copy) NSArray *sourceQueue;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, assign) BOOL shuffleEnabled;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL userPaused;
@property (nonatomic, assign) BOOL resumeAfterInterruption;
@property (nonatomic, strong) MPMediaItemArtwork *nowPlayingArtwork;
@property (nonatomic, copy) NSString *pendingVideoId;
@property (nonatomic, strong) NSURLConnection *streamConnection;
@property (nonatomic, strong) NSMutableData *streamData;
@property (nonatomic, copy) NSString *streamVideoId;
@property (nonatomic, assign) NSInteger streamHTTPStatus;
@property (nonatomic, assign) NSInteger audioBitrateKbps;
@property (nonatomic, strong) NSTimer *statsTimer;
@property (nonatomic, strong) NSTimer *nowPlayingTimer;
@property (nonatomic, assign) NSTimeInterval statsBaseTime;
// Keeps the process alive while a track ends and the next stream is being
// resolved. Without this iOS suspends the app in the gap between songs (there
// is no audio playing for a moment), the stream callback never arrives, and
// playback stays dead until the userforegrounds the app or taps play.
@property (nonatomic, assign) UIBackgroundTaskIdentifier transitionTask;
// Belt-and-braces recovery for a missed AVPlayerItemDidPlayToEndTime on old
// iOS: if the player is stopped at the end of an item while the user never
// paused, advance the queue ourselves.
@property (nonatomic, strong) NSTimer *watchdogTimer;
@property (nonatomic, assign) NSInteger stalledTicks;
// A task held for the whole time audio is active in the background, not just
// during the gap between songs. Expiry renews it while playback continues.
@property (nonatomic, assign) UIBackgroundTaskIdentifier sessionTask;
// Used by the watchdog to tell "the item ended and rewound to 0" from "this
// item just started loading".
@property (nonatomic, assign) NSTimeInterval trackStartTime;
@property (nonatomic, assign) NSTimeInterval lastProgressTime;
@property (nonatomic, assign) NSTimeInterval lastObservedPosition;
@end

@implementation LTPlayerController

+ (instancetype)sharedController {
    static LTPlayerController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LTPlayerController alloc] init];
    });
    return shared;
}

- (float)volume {
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"LTPlaybackVolume"];
    return saved ? [saved floatValue] : 1.0f;
}

- (void)setVolume:(float)volume {
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    [[NSUserDefaults standardUserDefaults] setObject:@(volume) forKey:@"LTPlaybackVolume"];
    self.audioPlayer.volume = volume;
    // AVPlayer only gained -volume in iOS 7; guard for older devices (3GS/iOS 6).
    if ([self.moviePlayer respondsToSelector:@selector(setVolume:)]) {
        if ([self.moviePlayer respondsToSelector:@selector(setVolume:)]) [self.moviePlayer setValue:@(volume) forKey:@"volume"];
    }
}

- (id)init {
    self = [super init];
    if (self) {
        _currentIndex = -1;
        _repeatMode = LTRepeatModeOff;
        _sessionTask = UIBackgroundTaskInvalid;
        _trackStartTime = 0.0;
        _lastProgressTime = 0.0;
        _lastObservedPosition = 0.0;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        // AVAudioSessionInterruptionNotification only exists on iOS 6+. On older
        // systems it is a weak import whose value is NULL, so *reading* it (as
        // opposed to taking its address) dereferences NULL and crashes with
        // SIGBUS/KERN_PROTECTION_FAILURE. Resolve it through dlsym, which simply
        // fails on systems whose AVFoundation doesn't export it.
        NSString *interruptionName = nil;
        void *interruptionSymbol = dlsym(RTLD_DEFAULT, "AVAudioSessionInterruptionNotification");
        if (interruptionSymbol) {
            interruptionName = *(NSString *__unsafe_unretained *)interruptionSymbol;
        }
        if (interruptionName) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(audioInterrupted:)
                                                         name:interruptionName
                                                       object:nil];
        }
        [self configureAudioSession];
        self.statsTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                           target:self
                                                         selector:@selector(statsTick:)
                                                         userInfo:nil
                                                          repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.statsTimer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)hasActivePlayer {
    return self.audioPlayer != nil || self.moviePlayer != nil;
}

- (BOOL)playerIsPlaying {
    if (self.moviePlayer) return self.moviePlayer.rate != 0.0;
    return self.audioPlayer.isPlaying;
}

- (NSTimeInterval)playerDuration {
    if (self.moviePlayer) {
        CMTime t = kCMTimeInvalid;
        AVPlayerItem *item = self.moviePlayer.currentItem;
        AVAsset *asset = nil;
        if ([item respondsToSelector:@selector(asset)]) {
            asset = [item performSelector:@selector(asset)];
        }
        // Prefer asset.duration: on iOS 4.1 AVPlayerItem may not implement -duration.
        if (asset && [asset respondsToSelector:@selector(duration)]) {
            t = [asset duration];
        } else if ([item respondsToSelector:@selector(duration)]) {
            t = [item duration];
        }
        if (!CMTIME_IS_NUMERIC(t)) return 0.0;
        NSTimeInterval seconds = CMTimeGetSeconds(t);
        return isfinite(seconds) ? seconds : 0.0;
    }
    NSTimeInterval duration = self.audioPlayer.duration;
    return isfinite(duration) ? duration : 0.0;
}

// NOTE: unlike -playerDuration this used to call CMTimeGetSeconds unguarded.
// Before an AVPlayerItem is ready, -currentTime is kCMTimeInvalid, and
// CMTimeGetSeconds on an invalid time returns NaN rather than 0. That NaN then
// flowed straight into MPNowPlayingInfoPropertyElapsedPlaybackTime (and into
// statsBaseTime), and a non-finite value handed to the now-playing daemon
// destabilises the lock screen -- which showed up as Springboard dying on the
// first track of a session, depending purely on whether the player had finished
// setting up yet.
- (NSTimeInterval)playerCurrentTime {
    if (self.moviePlayer) {
        CMTime t = kCMTimeInvalid;
        if ([self.moviePlayer respondsToSelector:@selector(currentTime)]) {
            t = [self.moviePlayer currentTime];
        }
        if (!CMTIME_IS_NUMERIC(t)) return 0.0;
        NSTimeInterval seconds = CMTimeGetSeconds(t);
        return isfinite(seconds) ? seconds : 0.0;
    }
    NSTimeInterval current = self.audioPlayer.currentTime;
    return isfinite(current) ? current : 0.0;
}

- (void)playerSeekToTime:(NSTimeInterval)time {
    if (self.moviePlayer) {
        [self.moviePlayer seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
        self.statsBaseTime = time;
        return;
    }
    self.audioPlayer.currentTime = time;
    self.statsBaseTime = time;
}

#pragma mark - Listening stats

- (void)statsTick:(NSTimer *)timer {
    [self commitStatsDelta];
}

- (void)commitStatsDelta {
    LTTrack *track = [self currentTrack];
    if (!track || !track.videoId.length) return;
    NSTimeInterval now = [self playerCurrentTime];
    if (now <= self.statsBaseTime) {
        self.statsBaseTime = now;
        return;
    }
    NSTimeInterval delta = now - self.statsBaseTime;
    self.statsBaseTime = now;
    if (delta > 0) {
        [[LTPlaylistStore sharedStore] recordListenedSeconds:delta forTrack:track];
    }
}

- (void)startActivePlayer {
    if (self.moviePlayer) {
        [self.audioPlayer pause];
        [self.moviePlayer play];
    } else {
        [self.moviePlayer pause];
        [self.audioPlayer play];
    }
}

- (void)pauseActivePlayer {
    [self.audioPlayer pause];
    [self.moviePlayer pause];
}

- (void)stopAudioPlayer {
    [self.audioPlayer stop];
    self.audioPlayer = nil;
}

- (void)stopMoviePlayer {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:nil];
    [self.moviePlayer pause];
    self.moviePlayer = nil;
}

- (void)configureAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    BOOL ok = [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (!ok) LTLog(@"AUDIO setCategory error: %@", error);
    error = nil;
    ok = [session setActive:YES error:&error];
    if (!ok) LTLog(@"AUDIO setActive error: %@", error);
    else LTLog(@"AUDIO session active");
}

// iOS 4 routes lock-screen and headphone buttons as UIEvent remote-control
// events. Ask for them again when playback starts so a player created after
// launch is covered even if the app delegate's early registration was lost.
- (void)beginRemoteControlListening {
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(beginReceivingRemoteControlEvents)]) {
        [app performSelector:@selector(beginReceivingRemoteControlEvents)];
    }
    // iOS 4.3 private MediaRemote hint: makes SpringBoard treat us as the
    // active now-playing app. Runtime lookup only; no weak symbol on 4.3.
    static BOOL checked = NO;
    static void (*setCanBeNowPlaying)(BOOL) = NULL;
    if (!checked) {
        checked = YES;
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (mr) {
            setCanBeNowPlaying = (void (*)(BOOL))dlsym(mr, "MRMediaRemoteSetCanBeNowPlayingApplication");
        }
    }
    if (setCanBeNowPlaying) setCanBeNowPlaying(YES);
}

// One implementation for the app delegate, the tab-bar root and any other
// responder in the chain. Logging subtype makes a "dead" lock screen easy to
// diagnose: no REMOTE line means iOS never delivered the event at all.
- (void)handleRemoteControlEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    // iOS 7.1+ uses MPRemoteCommandCenter (handled by the app delegate). Taking
    // the legacy UIEvent here too would fire each button twice.
    if (NSClassFromString(@"MPRemoteCommandCenter")) return;
    LTLog(@"REMOTE subtype=%d", (int)event.subtype);
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlPlay:
        case UIEventSubtypeRemoteControlStop:
            [self playMovie];
            break;
        case UIEventSubtypeRemoteControlPause:
            [self pausePlayback];
            break;
        case UIEventSubtypeRemoteControlTogglePlayPause:
            [self togglePlayPause];
            break;
        case UIEventSubtypeRemoteControlNextTrack:
            [self nextTrack];
            break;
        case UIEventSubtypeRemoteControlPreviousTrack:
            [self previousTrack];
            break;
        default:
            break;
    }
}

#pragma mark - Background transition support

// Audio apps keep running in the background only while sound is actually being
// produced. Between two tracks the AVPlayer has ended and the next stream has
// not started yet, so iOS can suspend the app mid-fetch. A background task
// covers that whole window.
- (void)beginTransitionTask {
    UIApplication *app = [UIApplication sharedApplication];
    if (self.transitionTask != UIBackgroundTaskInvalid) return;
    if (![app respondsToSelector:@selector(beginBackgroundTaskWithExpirationHandler:)]) return;
    __unsafe_unretained LTPlayerController *weakSelf = self;
    self.transitionTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [weakSelf endTransitionTask];
    }];
    LTLog(@"BG task begin %d", (int)self.transitionTask);
}

- (void)endTransitionTask {
    if (self.transitionTask == UIBackgroundTaskInvalid) return;
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(endBackgroundTask:)]) {
        [app endBackgroundTask:self.transitionTask];
    }
    LTLog(@"BG task end %d", (int)self.transitionTask);
    self.transitionTask = UIBackgroundTaskInvalid;
}

// Background audio keeps the process alive only while samples are actually
// coming out. A stream that is still buffering, or the silent instant after an
// item ends, can let iOS suspend us before the next item starts. Hold a second,
// renewable task for the whole active playback session to close that window.
- (BOOL)shouldKeepSessionTask {
    return [self hasActivePlayer] && !self.userPaused;
}

- (void)beginSessionTask {
    if (self.sessionTask != UIBackgroundTaskInvalid) return;
    if (![self shouldKeepSessionTask]) return;
    UIApplication *app = [UIApplication sharedApplication];
    if (![app respondsToSelector:@selector(beginBackgroundTaskWithExpirationHandler:)]) return;
    __unsafe_unretained LTPlayerController *weakSelf = self;
    self.sessionTask = [app beginBackgroundTaskWithExpirationHandler:^{
        LTPlayerController *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf endSessionTask];
        // Renew while there is still something to play; otherwise we would keep
        // a dead app alive in the background for no reason.
        if ([strongSelf shouldKeepSessionTask]) [strongSelf beginSessionTask];
    }];
    LTLog(@"BG session begin %d", (int)self.sessionTask);
}

- (void)endSessionTask {
    if (self.sessionTask == UIBackgroundTaskInvalid) return;
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(endBackgroundTask:)]) {
        [app endBackgroundTask:self.sessionTask];
    }
    LTLog(@"BG session end %d", (int)self.sessionTask);
    self.sessionTask = UIBackgroundTaskInvalid;
}

- (void)startWatchdog {
    if (self.watchdogTimer) return;
    self.watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                          target:self
                                                        selector:@selector(watchdogTick:)
                                                        userInfo:nil
                                                         repeats:YES];
    // Default-mode timers do not fire while the app is backgrounded; common
    // modes do, which matters because that is exactly when this is needed.
    [[NSRunLoop mainRunLoop] addTimer:self.watchdogTimer forMode:NSRunLoopCommonModes];
}

- (void)stopWatchdog {
    [self.watchdogTimer invalidate];
    self.watchdogTimer = nil;
    self.stalledTicks = 0;
}

// AVPlayerItemDidPlayToEndTimeNotification is not always delivered on old iOS
// (and some items rewind -currentTime to 0 instead of leaving it at the end).
// Recover both forms without waiting for the user to open the app or tap play.
- (void)watchdogTick:(NSTimer *)timer {
    if (self.userPaused || self.isLoading) {
        self.stalledTicks = 0;
        return;
    }
    if (![self hasActivePlayer]) {
        self.stalledTicks = 0;
        return;
    }

    NSTimeInterval duration = [self playerDuration];
    NSTimeInterval position = [self playerCurrentTime];
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();

    if ([self playerIsPlaying]) {
        if (position > self.lastObservedPosition + 0.05) {
            self.lastObservedPosition = position;
            self.lastProgressTime = now;
        }
        self.stalledTicks = 0;
        return;
    }

    BOOL endedByPosition = duration > 0.0 && position >= duration - 1.0;
    BOOL endedByRewind = duration > 0.0 && position < 1.0
        && (now - self.lastProgressTime) > 3.0
        && (now - self.trackStartTime) > 8.0;
    if (endedByPosition || endedByRewind) {
        LTLog(@"WATCHDOG item ended at %.1f/%.1f rewind=%d - advancing",
              position, duration, (int)endedByRewind);
        self.stalledTicks = 0;
        [self beginTransitionTask];
        [self nextTrack];
        return;
    }

    self.stalledTicks++;
    if (self.stalledTicks >= 2) {
        // Stopped in the middle without the user pausing: the player quietly
        // lost its rate in the background. Restart it rather than waiting for
        // a manual play tap.
        LTLog(@"WATCHDOG stalled at %.1f/%.1f - resuming", position, duration);
        self.stalledTicks = 0;
        [self beginTransitionTask];
        [self playMovie];
    }
}

- (void)appWillEnterForeground:(NSNotification *)notification {
    [self configureAudioSession];
    [self endSessionTask];
}

- (void)appDidEnterBackground:(NSNotification *)notification {
    [self beginRemoteControlListening];
    [self beginSessionTask];
    if ([self hasActivePlayer] && !self.userPaused && ![self playerIsPlaying]) {
        LTLog(@"PLAYER auto-resume in background");
        [self playMovie];
    }
}

- (void)audioInterrupted:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    if (!info) return;
    NSNumber *type = [info objectForKey:AVAudioSessionInterruptionTypeKey];
    if (!type) return;
    LTLog(@"AUDIO interruption type=%d", [type intValue]);
    if ([type intValue] == AVAudioSessionInterruptionTypeBegan) {
        self.resumeAfterInterruption = [self playerIsPlaying];
        [self pauseActivePlayer];
    } else if ([type intValue] == AVAudioSessionInterruptionTypeEnded) {
        [self configureAudioSession];
        if (self.resumeAfterInterruption) {
            self.resumeAfterInterruption = NO;
            [self playMovie];
        }
    }
}

- (void)playMovie {
    [self configureAudioSession];
    [self beginRemoteControlListening];
    self.isLoading = NO;
    if (self.userPaused) {
        // User tapped pause while the track was loading/starting.
        [self pauseActivePlayer];
        [self stopNowPlayingTimer];
        [self updateNowPlayingInfo];
        [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
        return;
    }
    self.userPaused = NO;
    self.statsBaseTime = [self playerCurrentTime];
    [self startActivePlayer];
    [self beginSessionTask];
    [self endTransitionTask];
    [self startWatchdog];
    [self updateNowPlayingInfo];
    [self startNowPlayingTimer];
    BOOL keepAwake = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTKeepAwake"];
    [[UIApplication sharedApplication] setIdleTimerDisabled:keepAwake];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
}

- (void)pausePlayback {
    [self pauseActivePlayer];
    [self stopNowPlayingTimer];
    [self stopWatchdog];
    [self endTransitionTask];
    [self endSessionTask];
    self.userPaused = YES;
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
    [self updateNowPlayingInfo];
    // Stats persistence can be slow on older devices/storage; don't block pause UI.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self commitStatsDelta];
    });
}

// The lock screen and Control Center only advance the scrubber while the app
// keeps pushing elapsed time; without this the progress bar sits still and can
// stay hidden until something else (a pause) triggers a fresh update.
- (void)startNowPlayingTimer {
    if (self.nowPlayingTimer) return;
    self.nowPlayingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(nowPlayingTick:)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)stopNowPlayingTimer {
    [self.nowPlayingTimer invalidate];
    self.nowPlayingTimer = nil;
}

- (void)nowPlayingTick:(NSTimer *)timer {
    if (![self playerIsPlaying]) {
        [self stopNowPlayingTimer];
        return;
    }
    [self updateNowPlayingInfo];
}

- (void)updateNowPlayingInfo {
    Class centerCls = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!centerCls) {
        // MPNowPlayingInfoCenter is iOS 5+. iOS 4.3 can still receive remote
        // control events, but the system has no public API for lock-screen
        // title/artwork, so do not keep retrying or touching iOS 5+ constants.
        static BOOL loggedUnsupported = NO;
        if (!loggedUnsupported) {
            loggedUnsupported = YES;
            LTLog(@"NOWPLAYING metadata unavailable on this OS");
        }
        return;
    }
    id center = [centerCls performSelector:@selector(defaultCenter)];
    if (!center) return;

    LTTrack *track = [self currentTrack];
    if (!track) {
        if ([center respondsToSelector:@selector(setNowPlayingInfo:)]) {
            [center performSelector:@selector(setNowPlayingInfo:) withObject:nil];
        }
        return;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (track.title.length) [info setObject:track.title forKey:MPMediaItemPropertyTitle];
    if (track.artist.length) [info setObject:track.artist forKey:MPMediaItemPropertyArtist];
    if (track.album.length) [info setObject:track.album forKey:MPMediaItemPropertyAlbumTitle];
    NSTimeInterval dur = [self playerDuration];
    if (dur > 0) {
        [info setObject:@(dur) forKey:MPMediaItemPropertyPlaybackDuration];
    }
    // Defence in depth: whatever the getters return, nothing non-finite and
    // nothing past the duration reaches the now-playing daemon. A NaN or an
    // elapsed time beyond the track length is the input that makes Springboard's
    // lock screen misbehave, and this dictionary is read by another process.
    NSTimeInterval elapsed = [self playerCurrentTime];
    if (isfinite(elapsed) && elapsed >= 0) {
        if (dur > 0 && elapsed > dur) elapsed = dur;
        [info setObject:@(elapsed) forKey:LTNowPlayingElapsedKey];
    }
    [info setObject:@([self playerIsPlaying] ? 1.0 : 0.0) forKey:LTNowPlayingRateKey];
    if (self.currentIndex >= 0) {
        [info setObject:@(self.currentIndex) forKey:LTNowPlayingQueueIndexKey];
    }
    [info setObject:@((NSInteger)self.queue.count) forKey:LTNowPlayingQueueCountKey];
    if (self.nowPlayingArtwork) {
        [info setObject:self.nowPlayingArtwork forKey:MPMediaItemPropertyArtwork];
    }
    if ([center respondsToSelector:@selector(setNowPlayingInfo:)]) {
        [center performSelector:@selector(setNowPlayingInfo:) withObject:info];
    }
}

#pragma mark - Playback

- (LTTrack *)currentTrack {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.queue.count) return nil;
    return [self.queue objectAtIndex:(NSUInteger)self.currentIndex];
}

- (LTTrack *)peekTrackOffset:(NSInteger)offset {
    if (offset == 0) return [self currentTrack];
    if (self.repeatMode == LTRepeatModeOff) {
        NSInteger idx = self.currentIndex + offset;
        if (idx < 0) return nil;
        if (idx >= (NSInteger)self.queue.count) return nil;
        return [self.queue objectAtIndex:(NSUInteger)idx];
    }
    NSInteger n = (NSInteger)self.queue.count;
    if (n <= 0) return nil;
    NSInteger idx = self.currentIndex + offset;
    while (idx < 0) idx += n;
    while (idx >= n) idx -= n;
    return [self.queue objectAtIndex:(NSUInteger)idx];
}

- (BOOL)isPlaying {
    return [self playerIsPlaying];
}

- (NSTimeInterval)duration {
    return [self playerDuration];
}

- (NSTimeInterval)currentTime {
    return [self playerCurrentTime];
}

- (void)playQueue:(NSArray *)tracks atIndex:(NSInteger)index {
    if (!tracks.count) return;
    [self commitStatsDelta];
    self.sourceQueue = [tracks copy];
    self.queue = [tracks copy];
    self.radioEnabled = NO;
    self.radioSeedVideoId = nil;
    if (index < 0) index = 0;
    if (index >= (NSInteger)tracks.count) index = 0;
    self.currentIndex = index;
    [self postQueueChanged];
    [self loadCurrentTrack];
}

- (void)playQueue:(NSArray *)tracks shuffle:(BOOL)shuffle {
    if (!tracks.count) return;
    [self commitStatsDelta];
    self.sourceQueue = [tracks copy];
    self.queue = [tracks copy];
    self.radioEnabled = NO;
    self.radioSeedVideoId = nil;
    self.shuffleEnabled = shuffle;
    if (shuffle) {
        self.queue = [self shuffledArray:self.queue];
        self.currentIndex = 0;
    } else {
        self.currentIndex = 0;
    }
    [self postQueueChanged];
    [self loadCurrentTrack];
}

- (void)enqueueTracks:(NSArray *)tracks {
    if (!tracks.count) return;
    NSMutableArray *q = [self.queue mutableCopy] ?: [NSMutableArray array];
    NSMutableArray *src = [self.sourceQueue mutableCopy] ?: [NSMutableArray array];
    [q addObjectsFromArray:tracks];
    [src addObjectsFromArray:tracks];
    self.queue = q;
    self.sourceQueue = src;
    if (self.currentIndex < 0) {
        self.currentIndex = 0;
        [self postQueueChanged];
        [self loadCurrentTrack];
    } else {
        [self postQueueChanged];
    }
}

- (void)jumpToIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.queue.count) return;
    [self commitStatsDelta];
    self.currentIndex = index;
    [self postQueueChanged];
    [self loadCurrentTrack];
    [self maybeExtendRadio];
}

- (void)moveTrackAtIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
    NSInteger count = (NSInteger)self.queue.count;
    if (fromIndex < 0 || fromIndex >= count) return;
    if (toIndex < 0 || toIndex >= count) return;
    if (fromIndex == toIndex) return;
    [self commitStatsDelta];

    NSMutableArray *q = [self.queue mutableCopy];
    id track = [q objectAtIndex:(NSUInteger)fromIndex];
    [q removeObjectAtIndex:(NSUInteger)fromIndex];
    [q insertObject:track atIndex:(NSUInteger)toIndex];
    self.queue = q;

    NSInteger idx = self.currentIndex;
    if (fromIndex == idx) {
        idx = toIndex;
    } else if (fromIndex < idx && toIndex >= idx) {
        idx -= 1;
    } else if (fromIndex > idx && toIndex <= idx) {
        idx += 1;
    }
    self.currentIndex = idx;

    if (self.shuffleEnabled) {
        // Manual reordering beats shuffle: cancel shuffle and adopt the new
        // order as the source order, Apple Music style.
        self.shuffleEnabled = NO;
        self.sourceQueue = [q copy];
    } else if (self.sourceQueue.count == self.queue.count) {
        // Keep the source (unshuffled) order in sync; when shuffle is off the
        // two arrays are identical copies.
        NSMutableArray *src = [self.sourceQueue mutableCopy];
        id srcTrack = [src objectAtIndex:(NSUInteger)fromIndex];
        [src removeObjectAtIndex:(NSUInteger)fromIndex];
        [src insertObject:srcTrack atIndex:(NSUInteger)toIndex];
        self.sourceQueue = src;
    }

    [self postQueueChanged];
}

- (void)removeTrackAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.queue.count) return;
    NSMutableArray *q = [self.queue mutableCopy];
    [q removeObjectAtIndex:(NSUInteger)index];
    NSMutableArray *src = [self.sourceQueue mutableCopy];
    if (index < (NSInteger)src.count) {
        [src removeObjectAtIndex:(NSUInteger)index];
    }
    self.queue = q;
    self.sourceQueue = src;
    if (self.queue.count == 0) {
        self.currentIndex = -1;
        [self pausePlayback];
        [self postQueueChanged];
        return;
    }
    if (index < self.currentIndex) {
        self.currentIndex -= 1;
    } else if (index == self.currentIndex) {
        if (self.currentIndex >= (NSInteger)self.queue.count) {
            self.currentIndex = (NSInteger)self.queue.count - 1;
        }
        [self postQueueChanged];
        [self loadCurrentTrack];
        return;
    }
    [self postQueueChanged];
}

- (void)loadNowPlayingArtworkForTrack:(LTTrack *)track {
    if (!track.thumbnailURL.length) return;
    __unsafe_unretained LTPlayerController *weakSelf = self;
    // Ask for the sharpest available artwork, falling back automatically when
    // YouTube has no maxres thumbnail. The previous code passed the URL through
    // highResThumbnailURL: which left i.ytimg.com untouched, so the lock screen
    // got the 640x480 sddefault and looked soft on a retina screen.
    NSArray *candidates = [[LTYouTubeClient sharedClient] artworkURLsForTrack:track];
    if (!candidates.count) return;
    [[LTYouTubeClient sharedClient] loadArtworkFromCandidates:candidates
                                                         index:0
                                                   completion:^(UIImage *image) {
        LTPlayerController *strongSelf = weakSelf;
        if (!strongSelf || !image) return;
        // Ignore a late arrival for a track we have already moved off.
        if (![[strongSelf currentTrack].videoId isEqualToString:track.videoId] &&
            track.videoId.length) {
            return;
        }
        // Shrink before handing it to MediaPlayer. This dictionary is consumed
        // by the now-playing daemon and rendered by the lock screen, i.e. by
        // SpringBoard in another process, so the image is no longer ours to
        // budget. The cap is 1024 rather than the 256 this used to use: 256px
        // is visibly soft on any retina lock screen, which is where the
        // "blurry album art" report came from, while 1024 is still smaller than
        // the source and keeps the decoded bitmap to a few MB instead of the
        // ~8MB a full 1280x1280 image would cost the rendering process.
        UIImage *sized = [[LTPlayerController class] downscaledArtwork:image];
        Class artCls = NSClassFromString(@"MPMediaItemArtwork");
        if (artCls && [artCls instancesRespondToSelector:@selector(initWithImage:)]) {
            strongSelf.nowPlayingArtwork = (MPMediaItemArtwork *)((id (*)(id, SEL, id))objc_msgSend)([artCls alloc], @selector(initWithImage:), sized);
        } else {
            strongSelf.nowPlayingArtwork = nil;
        }
        [strongSelf updateNowPlayingInfo];
    }];
}

// Cap the artwork we publish to the system. See the comment at the call site
// for why this is not merely the full image, and why the cap is 1024.
+ (UIImage *)downscaledArtwork:(UIImage *)image {
    CGImageRef cg = image.CGImage;
    if (!cg) return image;
    const CGFloat kMaxArtworkEdge = 1024.0f;
    CGFloat longest = (CGFloat)MAX(CGImageGetWidth(cg), CGImageGetHeight(cg));
    if (longest <= kMaxArtworkEdge) return image;
    CGFloat scale = kMaxArtworkEdge / longest;
    size_t w = (size_t)MAX(1.0f, roundf((CGFloat)CGImageGetWidth(cg) * scale));
    size_t h = (size_t)MAX(1.0f, roundf((CGFloat)CGImageGetHeight(cg) * scale));
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (!cs) return image;
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);
    if (!ctx) return image;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg);
    CGImageRef scaled = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!scaled) return image;
    UIImage *out = [UIImage imageWithCGImage:scaled];
    CGImageRelease(scaled);
    return out;
}

// Warm the artwork cache for the next couple of queue entries. Purely a
// latency optimisation: the result is only useful to a later
// loadNowPlayingArtworkForTrack:, which will then hit the memory or disk cache.
- (void)prefetchArtworkForUpcomingTrack {
    if ((NSInteger)self.currentIndex < 0) return;
    NSUInteger warmCount = MIN((NSUInteger)3, self.queue.count - (NSUInteger)self.currentIndex - 1);
    for (NSUInteger i = 1; i <= warmCount; i++) {
        NSUInteger idx = (NSUInteger)self.currentIndex + i;
        if (idx >= self.queue.count) break;
        LTTrack *next = [self.queue objectAtIndex:idx];
        if (![next isKindOfClass:[LTTrack class]] || !next.thumbnailURL.length) continue;
        NSArray *candidates = [[LTYouTubeClient sharedClient] artworkURLsForTrack:next];
        if (!candidates.count) continue;
        // Result intentionally discarded -- we only want it in the cache.
        [[LTYouTubeClient sharedClient] loadArtworkFromCandidates:candidates
                                                             index:0
                                                       completion:^(UIImage *image) {}];
    }
}

- (void)loadCurrentTrack {
    LTTrack *track = [self currentTrack];
    if (!track) return;
    // Cover the whole load - local decode or stream resolution - so iOS cannot
    // suspend us in the gap before the next item produces audio. playMovie ends
    // this task as soon as playback actually starts.
    [self beginTransitionTask];
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    self.trackStartTime = now;
    self.lastProgressTime = now;
    self.lastObservedPosition = 0.0;
    [[LTPlaylistStore sharedStore] recordRecentTrack:track];
    [[LTPlaylistStore sharedStore] recordTrackPlay:track];
    self.statsBaseTime = 0;
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerTrackDidChangeNotification object:self];

    self.nowPlayingArtwork = nil;
    if (track.thumbnailURL.length) {
        [self loadNowPlayingArtworkForTrack:track];
    } else {
        __unsafe_unretained LTPlayerController *weakSelf = self;
        [[LTPlaylistStore sharedStore] resolveThumbnailForTrack:track completion:^(NSString *thumbnailURL) {
            if (thumbnailURL.length) {
                [weakSelf loadNowPlayingArtworkForTrack:track];
            }
        }];
    }

    // Start fetching the NEXT track's artwork now, while this one is still
    // playing. Without this the lock screen has nothing to show for a moment
    // after every track change, because the sharp image we now request is a
    // network fetch rather than the small thumbnail that list browsing already
    // cached. By the time the user gets to the next track it is usually warm.
    [self prefetchArtworkForUpcomingTrack];

    NSString *localPath = [[LTPlaylistStore sharedStore] existingLocalFilePathForVideoId:track.videoId];
    if (localPath.length) {
        LTLog(@"OFFLINE playing videoId=%@ title=%@", track.videoId, track.title);
        self.isLoading = NO;
        self.audioBitrateKbps = [[LTPlaylistStore sharedStore] bitrateKbpsForVideoId:track.videoId];
        [self loadLocalFileAtPath:localPath];
        return;
    }

    self.pendingVideoId = track.videoId;
    self.isLoading = YES;
    self.userPaused = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
    LTLog(@"LOAD videoId=%@ title=%@", track.videoId, track.title);
    __unsafe_unretained LTPlayerController *weakSelf = self;
    [[LTYouTubeClient sharedClient] streamURLForVideo:track.videoId completion:^(NSString *streamURL, BOOL muxedStream, NSInteger audioBitrateKbps, NSError *error) {
        LTPlayerController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (![strongSelf.pendingVideoId isEqualToString:track.videoId]) return;
        if (error) {
            LTLog(@"ERROR fetch stream: %@", error);
            strongSelf.isLoading = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
            [strongSelf showError:error];
            return;
        }
        strongSelf.pendingMuxed = muxedStream;
        strongSelf.audioBitrateKbps = audioBitrateKbps;
        [[LTPlaylistStore sharedStore] recordBitrateKbps:audioBitrateKbps forVideoId:track.videoId];
        LTLog(@"FETCH_OK downloading stream for %@ muxed=%d", track.videoId, muxedStream);
        [strongSelf streamAndPlayURL:streamURL videoId:track.videoId muxed:muxedStream];
    }];
}

- (void)loadLocalFileAtPath:(NSString *)path {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    if ([[path pathExtension] caseInsensitiveCompare:@"mp4"] == NSOrderedSame) {
        LTLog(@"MUXED playing via AVPlayer %@", path);
        [self loadMuxedFileAtURL:fileURL];
        return;
    }
    [self stopMoviePlayer];
    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&error];
    if (!player) {
        LTLog(@"AUDIOPLAYER init error: %@", error);
        self.isLoading = NO;
        [self showError:error];
        return;
    }
    self.audioPlayer = player;
    self.audioPlayer.delegate = self;
    self.audioPlayer.volume = self.volume;
    self.audioPlayer.meteringEnabled = YES;
    [self.audioPlayer prepareToPlay];
    [self updateNowPlayingInfo];
    [self playMovie];
}

- (void)loadMuxedFileAtURL:(NSURL *)fileURL {
    [self stopAudioPlayer];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:fileURL];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
    self.moviePlayer = [[AVPlayer alloc] initWithPlayerItem:item];
    if ([self.moviePlayer respondsToSelector:@selector(setVolume:)]) {
        if ([self.moviePlayer respondsToSelector:@selector(setVolume:)]) [self.moviePlayer setValue:@(self.volume) forKey:@"volume"];
    }
    [self updateNowPlayingInfo];
    [self playMovie];
}

- (void)playerItemDidEnd:(NSNotification *)notification {
    LTLog(@"FINISH avplayer item end");
    [self beginTransitionTask];
    [self nextTrack];
}

- (void)streamAndPlayURL:(NSString *)urlString videoId:(NSString *)videoId muxed:(BOOL)muxed {
    if (!urlString.length) {
        self.isLoading = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
        return;
    }
    [self stopAudioPlayer];
    [self stopMoviePlayer];
    NSURL *url = [NSURL URLWithString:urlString];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
    self.moviePlayer = [[AVPlayer alloc] initWithPlayerItem:item];
    if ([self.moviePlayer respondsToSelector:@selector(setVolume:)]) {
        if ([self.moviePlayer respondsToSelector:@selector(setVolume:)]) [self.moviePlayer setValue:@(self.volume) forKey:@"volume"];
    }
    self.pendingMuxed = muxed;
    [self updateNowPlayingInfo];
    [self playMovie];
    LTLog(@"STREAM started videoId=%@", videoId);
}

- (void)downloadAndPlayURL:(NSString *)urlString videoId:(NSString *)videoId {
    self.streamVideoId = self.pendingVideoId;
    self.streamHTTPStatus = 0;
    [self.streamConnection cancel];
    self.streamConnection = nil;
    self.streamData = [NSMutableData data];
    NSString *path = [LTTempDirectory() stringByAppendingPathComponent:(self.pendingMuxed ? @"lt_track.mp4" : @"lt_track.m4a")];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:120.0];
    [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
    BOOL hasN = ([urlString rangeOfString:@"&n="].location != NSNotFound || [urlString rangeOfString:@"?n="].location != NSNotFound);
    LTLog(@"START_DOWNLOAD videoId=%@ host=%@ hasN=%d fullurl=%@", self.streamVideoId, [request.URL host], hasN, urlString);
    self.streamConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    LTLog(@"DL_RESPONSE status=%d expected=%lld", (int)[http statusCode], [response expectedContentLength]);
    self.streamHTTPStatus = [http statusCode];
    [self.streamData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.streamData appendData:data];
    if ((self.streamData.length / 262144) != ((self.streamData.length - data.length) / 262144)) {
        LTLog(@"DL_PROGRESS bytes=%d", (int)self.streamData.length);
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    LTLog(@"DL_ERROR %@", error);
    self.streamConnection = nil;
    self.isLoading = NO;
    if (![self.streamVideoId isEqualToString:self.pendingVideoId]) return;
    [self showError:error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LTLog(@"DL_FINISH bytes=%d status=%d", (int)self.streamData.length, (int)self.streamHTTPStatus);
    self.streamConnection = nil;
    if (![self.streamVideoId isEqualToString:self.pendingVideoId]) {
        LTLog(@"DL_STALE ignoring");
        return;
    }
    if (self.streamHTTPStatus >= 400 || !self.streamData.length) {
        self.isLoading = NO;
        NSString *reason = self.streamHTTPStatus
            ? [NSString stringWithFormat:@"Stream download failed (HTTP %d).\nThis usually clears after a few minutes.", (int)self.streamHTTPStatus]
            : @"Stream download failed.\nThis usually clears after a few minutes.";
        [self showError:[NSError errorWithDomain:NSURLErrorDomain code:self.streamHTTPStatus
                                        userInfo:@{NSLocalizedDescriptionKey: reason}]];
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
        return;
    }
    NSString *path = [LTTempDirectory() stringByAppendingPathComponent:(self.pendingMuxed ? @"lt_track.mp4" : @"lt_track.m4a")];
    [self.streamData writeToFile:path atomically:YES];
    LTLog(@"WROTE file, playing %@", self.streamVideoId);
    [self loadLocalFileAtPath:path];
}

- (void)maybeExtendRadio {
    LTLog(@"EXTEND radioEnabled=%d seed=%@ idx=%ld qcount=%lu", (int)self.radioEnabled, self.radioSeedVideoId, (long)self.currentIndex, (unsigned long)self.queue.count);
    if (!self.radioEnabled || !self.radioSeedVideoId.length) return;
    if (self.currentIndex < 0) return;
    // Extend proactively when the queue is short, not only when playback is
    // about to run out, so freshly started stations fill up instead of staying
    // at their initial handful of songs.
    if ((NSInteger)self.currentIndex + 2 < (NSInteger)self.queue.count && (NSInteger)self.queue.count >= 15) return;
    LTTrack *current = [self currentTrack];
    if (!current) return;
    __unsafe_unretained LTPlayerController *weakSelf = self;
    [[LTYouTubeClient sharedClient] fetchRadioForTrack:current completion:^(NSArray *tracks, NSError *error) {
        LTPlayerController *strongSelf = weakSelf;
        LTLog(@"EXTEND fetch returned %lu tracks", (unsigned long)tracks.count);
        if (!strongSelf || !tracks.count) return;
        NSMutableArray *toAdd = [NSMutableArray array];
        for (LTTrack *t in tracks) {
            if ([strongSelf isStationBlacklistedVideoId:t.videoId]) continue;
            BOOL exists = NO;
            for (LTTrack *q in strongSelf.queue) {
                if ([q.videoId isEqualToString:t.videoId]) { exists = YES; break; }
            }
            if (!exists) [toAdd addObject:t];
            if (toAdd.count >= 15) break;
        }
        if (toAdd.count) {
            NSMutableArray *q = [strongSelf.queue mutableCopy] ?: [NSMutableArray array];
            NSMutableArray *src = [strongSelf.sourceQueue mutableCopy] ?: [NSMutableArray array];
            [q addObjectsFromArray:toAdd];
            [src addObjectsFromArray:toAdd];
            strongSelf.queue = q;
            strongSelf.sourceQueue = src;
            [strongSelf postQueueChanged];
        }
    }];
    // Blend in remembered "recommend more" seeds
    NSArray *liked = [self likedVideoIdsForCurrentStation];
    if (liked.count) {
        NSString *vid = [liked objectAtIndex:0];
        LTTrack *lt = [[LTTrack alloc] init];
        lt.videoId = vid;
        [[LTYouTubeClient sharedClient] fetchRadioForTrack:lt completion:^(NSArray *tracks, NSError *error) {
            LTPlayerController *strongSelf = weakSelf;
            if (!strongSelf || !tracks.count) {
                return;
            }
            NSMutableArray *toAdd = [NSMutableArray array];
            for (LTTrack *t in tracks) {
                if ([strongSelf isStationBlacklistedVideoId:t.videoId]) continue;
                BOOL exists = NO;
                for (LTTrack *q in strongSelf.queue) {
                    if ([q.videoId isEqualToString:t.videoId]) { exists = YES; break; }
                }
                if (!exists) [toAdd addObject:t];
                if (toAdd.count >= 10) break;
            }
            if (toAdd.count) {
                NSMutableArray *q = [strongSelf.queue mutableCopy] ?: [NSMutableArray array];
                NSMutableArray *src = [strongSelf.sourceQueue mutableCopy] ?: [NSMutableArray array];
                [q addObjectsFromArray:toAdd];
                [src addObjectsFromArray:toAdd];
                strongSelf.queue = q;
                strongSelf.sourceQueue = src;
                [strongSelf postQueueChanged];
            }
        }];
#if !__has_feature(objc_arc)
        [lt release];
#endif
    }
}

- (void)nextTrack {
    [self commitStatsDelta];
    if (self.repeatMode == LTRepeatModeOne && self.currentIndex >= 0) {
        [self loadCurrentTrack];
        return;
    }
    if (self.currentIndex + 1 < (NSInteger)self.queue.count) {
        self.currentIndex += 1;
        [self postQueueChanged];
        [self loadCurrentTrack];
        [self maybeExtendRadio];
    } else if (self.repeatMode == LTRepeatModeAll && self.queue.count) {
        self.currentIndex = 0;
        [self postQueueChanged];
        [self loadCurrentTrack];
        [self maybeExtendRadio];
    } else if (self.radioEnabled && self.radioSeedVideoId.length) {
        [self maybeExtendRadio];
        if (self.currentIndex + 1 < (NSInteger)self.queue.count) {
            self.currentIndex += 1;
            [self postQueueChanged];
            [self loadCurrentTrack];
            [self maybeExtendRadio];
            return;
        }
        [self pausePlayback];
        self.currentIndex = -1;
        [self postQueueChanged];
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerDidFinishQueueNotification object:self];
    } else {
        [self pausePlayback];
        self.currentIndex = -1;
        [self postQueueChanged];
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerDidFinishQueueNotification object:self];
    }
}

- (void)previousTrack {
    [self commitStatsDelta];
    if (self.currentIndex > 0) {
        self.currentIndex -= 1;
        [self postQueueChanged];
        [self loadCurrentTrack];
    } else if ([self playerCurrentTime] > 3.0) {
        [self playerSeekToTime:0];
    } else {
        [self loadCurrentTrack];
    }
}

- (void)toggleShuffle {
    self.shuffleEnabled = !self.shuffleEnabled;
    if (self.shuffleEnabled) {
        LTTrack *current = [self currentTrack];
        NSMutableArray *rest = [NSMutableArray array];
        for (NSInteger i = self.currentIndex + 1; i < (NSInteger)self.queue.count; i++) {
            [rest addObject:[self.queue objectAtIndex:(NSUInteger)i]];
        }
        rest = [[self shuffledArray:rest] mutableCopy];
        NSMutableArray *newQueue = [NSMutableArray array];
        if (current) [newQueue addObject:current];
        [newQueue addObjectsFromArray:rest];
        self.queue = newQueue;
        self.currentIndex = 0;
        LTLog(@"SHUFFLE on");
    } else {
        NSInteger target = 0;
        LTTrack *current = [self currentTrack];
        self.queue = [self.sourceQueue copy];
        if (current) {
            for (NSInteger i = 0; i < (NSInteger)self.queue.count; i++) {
                if ([[self.queue objectAtIndex:(NSUInteger)i] isEqual:current]) { target = i; break; }
            }
        }
        self.currentIndex = target;
        LTLog(@"SHUFFLE off");
    }
    [self postQueueChanged];
}

- (NSArray *)shuffledArray:(NSArray *)array {
    NSMutableArray *m = [array mutableCopy];
    for (NSInteger i = (NSInteger)m.count - 1; i > 0; i--) {
        NSUInteger j = (NSUInteger)arc4random_uniform((uint32_t)(i + 1));
        [m exchangeObjectAtIndex:(NSUInteger)i withObjectAtIndex:j];
    }
    return m;
}

- (void)extendRadio {
    [self maybeExtendRadio];
}

- (void)cycleRepeatMode {
    self.repeatMode = (LTRepeatMode)((self.repeatMode + 1) % 3);
    LTLog(@"REPEAT mode=%d", (int)self.repeatMode);
    [self postQueueChanged];
}

- (void)setRepeatMode:(LTRepeatMode)repeatMode {
    _repeatMode = repeatMode;
    LTLog(@"REPEAT mode=%d", (int)repeatMode);
    [self postQueueChanged];
}

- (void)postQueueChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerQueueDidChangeNotification object:self];
}

- (void)togglePlayPause {
    if ([self hasActivePlayer]) {
        if ([self playerIsPlaying]) {
            [self pausePlayback];
        } else {
            self.userPaused = NO;
            [self playMovie];
        }
        return;
    }
    // No player yet (e.g. still resolving/loading stream): honor tap intent so
    // repeated taps during load don't appear ignored on slow devices/networks.
    if (self.isLoading || [self currentTrack]) {
        self.userPaused = !self.userPaused;
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
    }
}

- (void)seekToTime:(NSTimeInterval)time {
    [self playerSeekToTime:time];
    [self updateNowPlayingInfo];
}

- (BOOL)isStationBlacklistedVideoId:(NSString *)videoId {
    if (!self.queueSourceName.length || !videoId.length) return NO;
    NSString *key = [NSString stringWithFormat:@"LTStationBlacklist_%@", self.queueSourceName];
    NSArray *list = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [list containsObject:videoId];
}

- (void)blacklistVideoIdForCurrentStation:(NSString *)videoId {
    if (!self.queueSourceName.length || !videoId.length) return;
    NSString *key = [NSString stringWithFormat:@"LTStationBlacklist_%@", self.queueSourceName];
    NSMutableArray *list = [[[NSUserDefaults standardUserDefaults] objectForKey:key] mutableCopy];
    if (!list) list = [NSMutableArray array];
    if (![list containsObject:videoId]) [list addObject:videoId];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:key];
}

- (NSArray *)likedVideoIdsForCurrentStation {
    if (!self.queueSourceName.length) return [NSArray array];
    NSString *key = [NSString stringWithFormat:@"LTStationLiked_%@", self.queueSourceName];
    NSArray *list = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [list isKindOfClass:[NSArray class]] ? list : [NSArray array];
}

- (void)addLikedVideoIdForCurrentStation:(NSString *)videoId {
    if (!self.queueSourceName.length || !videoId.length) return;
    NSString *key = [NSString stringWithFormat:@"LTStationLiked_%@", self.queueSourceName];
    NSMutableArray *list = [[[NSUserDefaults standardUserDefaults] objectForKey:key] mutableCopy];
    if (!list) list = [NSMutableArray array];
    if (![list containsObject:videoId]) [list addObject:videoId];
    [[NSUserDefaults standardUserDefaults] setObject:list forKey:key];
}

- (BOOL)isStationLikedVideoId:(NSString *)videoId {
    return [[self likedVideoIdsForCurrentStation] containsObject:videoId];
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    LTLog(@"FINISH success=%d", flag);
    if (flag) {
        [self beginTransitionTask];
        [self nextTrack];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
    }
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    LTLog(@"AUDIOPLAYER decode error: %@", error);
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
}

#pragma mark - Errors

- (void)showError:(NSError *)error {
    [self endTransitionTask];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Playback Failed"
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    });
}

@end
