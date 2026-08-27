#import "LTPlayerController.h"
#import "LTYouTubeClient.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"
#import <MediaPlayer/MediaPlayer.h>

NSString *const LTPlayerTrackDidChangeNotification = @"LTPlayerTrackDidChangeNotification";
NSString *const LTPlayerStateDidChangeNotification = @"LTPlayerStateDidChangeNotification";
NSString *const LTPlayerDidFinishQueueNotification = @"LTPlayerDidFinishQueueNotification";
NSString *const LTPlayerQueueDidChangeNotification = @"LTPlayerQueueDidChangeNotification";

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

- (id)init {
    self = [super init];
    if (self) {
        _currentIndex = -1;
        _repeatMode = LTRepeatModeOff;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(audioInterrupted:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:nil];
        [self configureAudioSession];
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
        CMTime t = self.moviePlayer.currentItem.duration;
        return CMTIME_IS_NUMERIC(t) ? CMTimeGetSeconds(t) : 0.0;
    }
    return self.audioPlayer.duration;
}

- (NSTimeInterval)playerCurrentTime {
    if (self.moviePlayer) return CMTimeGetSeconds(self.moviePlayer.currentTime);
    return self.audioPlayer.currentTime;
}

- (void)playerSeekToTime:(NSTimeInterval)time {
    if (self.moviePlayer) {
        [self.moviePlayer seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)];
        return;
    }
    self.audioPlayer.currentTime = time;
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

- (void)appWillEnterForeground:(NSNotification *)notification {
    [self configureAudioSession];
}

- (void)appDidEnterBackground:(NSNotification *)notification {
    if ([self hasActivePlayer] && !self.userPaused && ![self playerIsPlaying]) {
        LTLog(@"PLAYER auto-resume in background");
        [self playMovie];
    }
}

- (void)audioInterrupted:(NSNotification *)notification {
    NSNumber *type = [[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey];
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
    self.isLoading = NO;
    self.userPaused = NO;
    [self startActivePlayer];
    [self updateNowPlayingInfo];
    BOOL keepAwake = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTKeepAwake"];
    [[UIApplication sharedApplication] setIdleTimerDisabled:keepAwake];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
}

- (void)pausePlayback {
    [self pauseActivePlayer];
    [self updateNowPlayingInfo];
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:self];
}

- (void)updateNowPlayingInfo {
    LTTrack *track = [self currentTrack];
    if (!track) {
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
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
    [info setObject:@([self playerCurrentTime]) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [info setObject:@([self playerIsPlaying] ? 1.0 : 0.0) forKey:MPNowPlayingInfoPropertyPlaybackRate];
    [info setObject:@(self.currentIndex) forKey:MPNowPlayingInfoPropertyPlaybackQueueIndex];
    [info setObject:@((NSInteger)self.queue.count) forKey:MPNowPlayingInfoPropertyPlaybackQueueCount];
    if (self.nowPlayingArtwork) {
        [info setObject:self.nowPlayingArtwork forKey:MPMediaItemPropertyArtwork];
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}

#pragma mark - Playback

- (LTTrack *)currentTrack {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.queue.count) return nil;
    return [self.queue objectAtIndex:(NSUInteger)self.currentIndex];
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
    self.sourceQueue = [tracks copy];
    self.queue = [tracks copy];
    if (index < 0) index = 0;
    if (index >= (NSInteger)tracks.count) index = 0;
    self.currentIndex = index;
    [self postQueueChanged];
    [self loadCurrentTrack];
}

- (void)playQueue:(NSArray *)tracks shuffle:(BOOL)shuffle {
    if (!tracks.count) return;
    self.sourceQueue = [tracks copy];
    self.queue = [tracks copy];
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
    self.currentIndex = index;
    [self postQueueChanged];
    [self loadCurrentTrack];
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

- (void)loadCurrentTrack {
    LTTrack *track = [self currentTrack];
    if (!track) return;
    [[LTPlaylistStore sharedStore] recordRecentTrack:track];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerTrackDidChangeNotification object:self];

    self.nowPlayingArtwork = nil;
    if (track.thumbnailURL.length) {
        __weak LTPlayerController *weakSelf = self;
        NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:track.thumbnailURL];
        [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
            LTPlayerController *strongSelf = weakSelf;
            if (!strongSelf || !image) return;
            strongSelf.nowPlayingArtwork = [[MPMediaItemArtwork alloc] initWithImage:image];
            [strongSelf updateNowPlayingInfo];
        }];
    }

    NSString *localPath = [[LTPlaylistStore sharedStore] existingLocalFilePathForVideoId:track.videoId];
    if (localPath.length) {
        LTLog(@"OFFLINE playing videoId=%@ title=%@", track.videoId, track.title);
        self.isLoading = NO;
        [self loadLocalFileAtPath:localPath];
        return;
    }

    self.pendingVideoId = track.videoId;
    self.isLoading = YES;
    LTLog(@"LOAD videoId=%@ title=%@", track.videoId, track.title);
    __weak LTPlayerController *weakSelf = self;
    [[LTYouTubeClient sharedClient] streamURLForVideo:track.videoId completion:^(NSString *streamURL, BOOL muxedStream, NSError *error) {
        LTPlayerController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (![strongSelf.pendingVideoId isEqualToString:track.videoId]) return;
        if (error) {
            LTLog(@"ERROR fetch stream: %@", error);
            strongSelf.isLoading = NO;
            [strongSelf showError:error];
            return;
        }
        strongSelf.pendingMuxed = muxedStream;
        LTLog(@"FETCH_OK downloading stream for %@ muxed=%d", track.videoId, muxedStream);
        [strongSelf downloadAndPlayURL:streamURL videoId:track.videoId];
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
    [self updateNowPlayingInfo];
    [self playMovie];
}

- (void)playerItemDidEnd:(NSNotification *)notification {
    LTLog(@"FINISH avplayer item end");
    [self nextTrack];
}

- (void)downloadAndPlayURL:(NSString *)urlString videoId:(NSString *)videoId {
    self.streamVideoId = self.pendingVideoId;
    self.streamHTTPStatus = 0;
    [self.streamConnection cancel];
    self.streamConnection = nil;
    self.streamData = [NSMutableData data];
    NSString *path = self.pendingMuxed ? @"/tmp/lt_track.mp4" : @"/tmp/lt_track.m4a";
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
    NSString *path = self.pendingMuxed ? @"/tmp/lt_track.mp4" : @"/tmp/lt_track.m4a";
    [self.streamData writeToFile:path atomically:YES];
    LTLog(@"WROTE file, playing %@", self.streamVideoId);
    [self loadLocalFileAtPath:path];
}

- (void)nextTrack {
    if (self.repeatMode == LTRepeatModeOne && self.currentIndex >= 0) {
        [self loadCurrentTrack];
        return;
    }
    if (self.currentIndex + 1 < (NSInteger)self.queue.count) {
        self.currentIndex += 1;
        [self postQueueChanged];
        [self loadCurrentTrack];
    } else if (self.repeatMode == LTRepeatModeAll && self.queue.count) {
        self.currentIndex = 0;
        [self postQueueChanged];
        [self loadCurrentTrack];
    } else {
        [self pausePlayback];
        self.currentIndex = -1;
        [self postQueueChanged];
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerDidFinishQueueNotification object:self];
    }
}

- (void)previousTrack {
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
    if (![self hasActivePlayer]) return;
    if ([self playerIsPlaying]) {
        self.userPaused = YES;
        [self pausePlayback];
    } else {
        [self playMovie];
    }
}

- (void)seekToTime:(NSTimeInterval)time {
    [self playerSeekToTime:time];
    [self updateNowPlayingInfo];
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    LTLog(@"FINISH success=%d", flag);
    if (flag) {
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
