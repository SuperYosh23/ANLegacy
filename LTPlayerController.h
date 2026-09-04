#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "LTModel.h"

extern NSString *const LTPlayerTrackDidChangeNotification;
extern NSString *const LTPlayerStateDidChangeNotification;
extern NSString *const LTPlayerDidFinishQueueNotification;
extern NSString *const LTPlayerQueueDidChangeNotification;

typedef NS_ENUM(NSInteger, LTRepeatMode) {
    LTRepeatModeOff = 0,
    LTRepeatModeAll,
    LTRepeatModeOne,
};

@interface LTPlayerController : NSObject

+ (instancetype)sharedController;

@property (nonatomic, readonly) NSArray *queue;
@property (nonatomic, readonly) NSInteger currentIndex;
@property (nonatomic, readonly) BOOL shuffleEnabled;
@property (nonatomic, assign) LTRepeatMode repeatMode;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSInteger audioBitrateKbps;
@property (nonatomic, strong) NSString *queueSourceName;

- (void)playQueue:(NSArray *)tracks atIndex:(NSInteger)index;
- (void)playQueue:(NSArray *)tracks shuffle:(BOOL)shuffle;
- (void)enqueueTracks:(NSArray *)tracks;
- (void)jumpToIndex:(NSInteger)index;
- (void)removeTrackAtIndex:(NSInteger)index;
- (LTTrack *)currentTrack;
- (LTTrack *)peekTrackOffset:(NSInteger)offset;
- (void)nextTrack;
- (void)previousTrack;
- (void)togglePlayPause;
- (void)playMovie;
- (void)pausePlayback;
- (void)seekToTime:(NSTimeInterval)time;
- (void)toggleShuffle;
- (void)cycleRepeatMode;

@end
