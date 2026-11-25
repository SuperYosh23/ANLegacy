#import "S6Player.h"
#import <objc/message.h>
#import "S6PlaybackEngine.h"
#import "S6Models.h"
#import "S6SpClient.h"
#import "S6Catalog.h"
#import "S6ImageLoader.h"
#import "S6Settings.h"
#import "S6Reachability.h"
#import "S6Utils.h"
#import "S6Common.h"
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

NSString * const S6PlayerDidChangeNotification = @"S6PlayerDidChangeNotification";
NSString * const S6PlayerDidFailNotification = @"S6PlayerDidFailNotification";

static const NSInteger S6RestartThresholdMs = 3000;    // "previous" after this restarts the song instead
static const NSInteger S6MaxSkipsOnError = 5;

@interface S6Player () <S6PlaybackEngineDelegate>
@property (nonatomic, strong) S6Track *currentTrack;
@property (nonatomic) BOOL playing;
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *contextURI;
@property (nonatomic, copy) NSString *contextName;
@property (nonatomic, strong) NSMutableArray *queue;          // user queue
@property (nonatomic, strong) NSDate *sleepAt;
@property (nonatomic) BOOL sleepAtEndOfSong;
@end

@implementation S6Player {
    NSArray *_contextTracks;
    NSMutableArray *_order;           // indices into _contextTracks, in play order
    NSInteger _orderPos;              // where the current context song is in _order (-1 none)
    BOOL _currentFromQueue;           // the current song came from the user queue
    NSUInteger _loadToken;            // bumps with every load: late answers are dropped
    S6Track *_preparedTrack;          // the next song the engine got ready (gapless)
    NSUInteger _prepareToken;
    NSInteger _failures;
    S6PlaybackEngine *_engine;
    dispatch_queue_t _loadQueue;
    id _artworkToken;
    NSString *_artworkURL;
    UIImage *_artwork;
    BOOL _fetchingRadio;
    NSTimer *_sleepTimer;
    NSInteger _resumeMs;              // a restored song starts here (the place it was left at)
    BOOL _saveScheduled;
}

+ (instancetype)shared
{
    static S6Player *player;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ player = [[S6Player alloc] init]; });
    return player;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _queue = [NSMutableArray array];
        _order = [NSMutableArray array];
        _orderPos = -1;
        _loadQueue = dispatch_queue_create("com.samcejko.sixify.load", NULL /* was DISPATCH_QUEUE_CONCURRENT */);
        _engine = [S6PlaybackEngine shared];
        _engine.delegate = self;
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateNowPlaying) userInfo:nil repeats:YES];
        // (the place in the song, every so often: iOS ends a background app without a word)
        [NSTimer scheduledTimerWithTimeInterval:20.0 target:self selector:@selector(saveWhilePlaying) userInfo:nil repeats:YES];
    }
    return self;
}

- (NSArray *)userQueue { return [self.queue copy]; }
- (BOOL)buffering { return self.loading || _engine.buffering; }
- (NSInteger)positionMs { return _engine.currentItem ? _engine.positionMs : _resumeMs; }
- (NSInteger)durationMs { return _engine.currentItem.durationMs ?: self.currentTrack.durationMs; }
- (NSString *)formatName { return _engine.currentItem.formatName; }

- (void)changed
{
    [[NSNotificationCenter defaultCenter] postNotificationName:S6PlayerDidChangeNotification object:self];
    [self updateNowPlaying];
    [self scheduleSave];
}

// The quality to load: Normal (96 kbit/s) on mobile data with the data saver on, else the chosen one
- (S6Quality)quality
{
    return [S6Settings dataSaver] && [S6Reachability onCellular] ? S6QualityNormal : [S6Settings quality];
}

#pragma mark - Context

static void S6Shuffle(NSMutableArray *a)
{
    for (NSUInteger i = a.count; i > 1; i--) [a exchangeObjectAtIndex:i - 1 withObjectAtIndex:(arc4random() % (u_int32_t)(i ? i : 1))];
}

- (void)buildOrderStartingWith:(NSInteger)first
{
    [_order removeAllObjects];
    for (NSUInteger i = 0; i < _contextTracks.count; i++) [_order addObject:@(i)];
    if (self.shuffle) {
        S6Shuffle(_order);
        if (first >= 0) {
            [_order removeObject:@(first)];
            [_order insertObject:@(first) atIndex:0];
        }
        _orderPos = first >= 0 ? 0 : -1;
    } else {
        _orderPos = first;
    }
}

- (void)playTracks:(NSArray *)tracks startingAt:(NSUInteger)index contextURI:(NSString *)uri contextName:(NSString *)name
{
    [self playTracks:tracks startingAt:index positionMs:0 paused:NO contextURI:uri contextName:name];
}

- (void)playTracks:(NSArray *)tracks startingAt:(NSUInteger)index positionMs:(NSInteger)positionMs paused:(BOOL)paused
        contextURI:(NSString *)uri contextName:(NSString *)name
{
    if (!tracks.count) return;
    _contextTracks = [tracks copy];
    self.contextURI = uri;
    self.contextName = name;
    NSInteger start = (NSInteger)MIN(index, tracks.count - 1);
    // (a song that cannot play is passed over)
    if (![[tracks objectAtIndex:(NSUInteger)start] playable]) positionMs = 0;
    while (start < (NSInteger)tracks.count && ![[tracks objectAtIndex:(NSUInteger)start] playable]) start++;
    if (start >= (NSInteger)tracks.count) return;
    [self buildOrderStartingWith:start];
    _currentFromQueue = NO;
    _failures = 0;
    _resumeMs = 0;
    [self loadAndPlay:[tracks objectAtIndex:(NSUInteger)start] fromMs:positionMs paused:paused];
}

- (NSArray *)contextTracks { return _contextTracks ?: [NSArray array]; }

- (NSInteger)contextIndex
{
    return (_orderPos >= 0 && _orderPos < (NSInteger)_order.count && !_currentFromQueue) ? [[_order objectAtIndex:(NSUInteger)_orderPos] integerValue] : -1;
}

- (NSArray *)previousTracks:(NSUInteger)max
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger p = MAX(0, _orderPos - (NSInteger)max); p < _orderPos && p < (NSInteger)_order.count; p++) {
        [out addObject:[_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]]];
    }
    return out;
}

- (void)replaceQueue:(NSArray *)tracks
{
    [self.queue removeAllObjects];
    [self.queue addObjectsFromArray:tracks ?: [NSArray array]];
    [self dropPrepared];
    [self changed];
}

- (void)playTracksShuffled:(NSArray *)tracks contextURI:(NSString *)uri contextName:(NSString *)name
{
    if (!tracks.count) return;
    self.shuffle = YES;
    [self playTracks:tracks startingAt:(arc4random() % (u_int32_t)(tracks.count ? tracks.count : 1)) contextURI:uri contextName:name];
}

- (void)setShuffle:(BOOL)shuffle
{
    if (_shuffle == shuffle) return;
    _shuffle = shuffle;
    // the order changes, the current song stays where it is
    NSInteger current = (_orderPos >= 0 && _orderPos < (NSInteger)_order.count) ? [[_order objectAtIndex:(NSUInteger)_orderPos] integerValue] : -1;
    [self buildOrderStartingWith:current];
    [self dropPrepared];
    [self changed];
}

- (void)setRepeat:(S6RepeatMode)repeat
{
    _repeat = repeat;
    [self dropPrepared];
    [self changed];
}

- (void)addToQueue:(S6Track *)track
{
    if (!track) return;
    [self.queue addObject:track];
    [self dropPrepared];
    [self changed];
}

- (void)playNext:(S6Track *)track
{
    if (!track) return;
    [self.queue insertObject:track atIndex:0];
    [self dropPrepared];
    [self changed];
}

- (void)removeFromQueueAtIndex:(NSUInteger)index
{
    if (index < self.queue.count) [self.queue removeObjectAtIndex:index];
    [self dropPrepared];
    [self changed];
}

- (void)clearQueue
{
    [self.queue removeAllObjects];
    [self dropPrepared];
    [self changed];
}

- (NSArray *)upcomingTracks:(NSUInteger)max
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger p = _orderPos + 1; p < (NSInteger)_order.count && out.count < max; p++) {
        [out addObject:[_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]]];
    }
    return out;
}

// What comes after the current song, without moving there: (track, from queue?, order position)
- (S6Track *)peekNext:(BOOL *)fromQueue position:(NSInteger *)position
{
    if (self.queue.count) { *fromQueue = YES; *position = _orderPos; return [self.queue objectAtIndex:0]; }
    *fromQueue = NO;
    if (self.repeat == S6RepeatOne && self.currentTrack) { *position = _orderPos; return self.currentTrack; }
    for (NSInteger p = _orderPos + 1; p < (NSInteger)_order.count; p++) {
        S6Track *t = [_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]];
        if (t.playable) { *position = p; return t; }
    }
    if (self.repeat == S6RepeatAll && _order.count) {
        for (NSInteger p = 0; p < (NSInteger)_order.count; p++) {
            S6Track *t = [_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]];
            if (t.playable) { *position = p; return t; }
        }
    }
    return nil;
}

#pragma mark - Loading

- (void)loadAndPlay:(S6Track *)track { [self loadAndPlay:track fromMs:0 paused:NO]; }

- (void)loadAndPlay:(S6Track *)track fromMs:(NSInteger)startMs paused:(BOOL)paused
{
    NSUInteger token = ++_loadToken;
    [self dropPrepared];
    self.currentTrack = track;
    self.loading = YES;
    self.playing = !paused;
    [_engine stop];
    [self changed];
    S6Quality quality = [self quality];
    dispatch_async(_loadQueue, ^{
        NSError *error = nil;
        S6PlaybackItem *item = [S6PlaybackItem loadTrack:track quality:quality error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != self->_loadToken) { [item cancel]; return; }
            self.loading = NO;
            if (!item) {
                [self failed:track error:error];
                return;
            }
            self->_failures = 0;
            NSInteger from = item.durationMs > 0 && startMs >= item.durationMs ? 0 : MAX(0, startMs);
            [self->_engine playItem:item fromMs:from paused:!self.playing];
        });
    });
}

- (void)failed:(S6Track *)track error:(NSError *)error
{
    S6Log(@"cannot play %@: %@", track.name, error.localizedDescription);
    [[NSNotificationCenter defaultCenter] postNotificationName:S6PlayerDidFailNotification object:self
                                                      userInfo:@{ @"error": error ?: S6MakeError(S6ErrorPlayback, L(@"This song cannot be played.")) }];
    if (++_failures >= S6MaxSkipsOnError) {
        self.playing = NO;
        [self changed];
        return;
    }
    [self advanceAutomatically:NO];
}

- (void)dropPrepared
{
    _prepareToken++;
    _preparedTrack = nil;
    [_engine queueNextItem:nil];
}

- (void)engineNeedsNextItem
{
    if (self.sleepAtEndOfSong) return;   // (the sleep timer ends with this song: nothing is prepared)
    BOOL fromQueue = NO;
    NSInteger position = -1;
    S6Track *next = [self peekNext:&fromQueue position:&position];
    if (!next || next == _preparedTrack) return;
    NSUInteger token = ++_prepareToken;
    _preparedTrack = next;
    S6Quality quality = [self quality];
    dispatch_async(_loadQueue, ^{
        S6PlaybackItem *item = [S6PlaybackItem loadTrack:next quality:quality error:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != self->_prepareToken || !item) { [item cancel]; return; }
            [self->_engine queueNextItem:item];
        });
    });
}

#pragma mark - Engine events

- (void)engineDidStartItem:(S6PlaybackItem *)item
{
    if (item.track != self.currentTrack) {
        // the prepared next song went on without a gap: the queue moves along
        [self moveToTrack:item.track];
        self.currentTrack = item.track;
        _preparedTrack = nil;
    }
    self.loading = NO;
    [self changed];
}

- (void)engineDidFinishItem:(S6PlaybackItem *)item
{
    if (self.sleepAtEndOfSong) {
        [self setSleepTimerMinutes:0];
        self.playing = NO;
        [_engine stop];
        _resumeMs = 0;
        [self changed];
        return;
    }
    [self advanceAutomatically:YES];
}

- (void)engineDidFailItem:(S6PlaybackItem *)item error:(NSError *)error
{
    [self failed:item.track error:error];
}

// The queue position follows a song that started by itself (gapless)
- (void)moveToTrack:(S6Track *)track
{
    if (self.queue.count && [self.queue objectAtIndex:0] == track) {
        [self.queue removeObjectAtIndex:0];
        _currentFromQueue = YES;
        return;
    }
    _currentFromQueue = NO;
    if (self.repeat == S6RepeatOne) return;
    for (NSInteger p = _orderPos + 1; p < (NSInteger)_order.count; p++) {
        if ([_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]] == track) { _orderPos = p; return; }
    }
    for (NSInteger p = 0; p < (NSInteger)_order.count; p++) {
        if ([_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]] == track) { _orderPos = p; return; }
    }
}

- (void)advanceAutomatically:(BOOL)automatic
{
    if (automatic && self.repeat == S6RepeatOne && self.currentTrack) {
        [self loadAndPlay:self.currentTrack];
        return;
    }
    if (self.queue.count) {
        S6Track *t = [self.queue objectAtIndex:0];
        [self.queue removeObjectAtIndex:0];
        _currentFromQueue = YES;
        [self loadAndPlay:t];
        return;
    }
    for (NSInteger p = _orderPos + 1; p < (NSInteger)_order.count; p++) {
        S6Track *t = [_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]];
        if (!t.playable) continue;
        _orderPos = p;
        _currentFromQueue = NO;
        [self loadAndPlay:t];
        return;
    }
    if (self.repeat == S6RepeatAll && _order.count) {
        if (self.shuffle) S6Shuffle(_order);
        _orderPos = -1;
        [self advanceAutomatically:NO];
        return;
    }
    if ([S6Settings autoplay] && self.currentTrack.uri.length && !_fetchingRadio) {
        // the end of the context: similar songs follow (Spotify's autoplay)
        _fetchingRadio = YES;
        S6Track *seed = self.currentTrack;
        [S6SpClient radioForURI:seed.uri completion:^(NSArray *uris, NSError *error) {
            self->_fetchingRadio = NO;
            if (!uris.count) { self.playing = NO; [self changed]; return; }
            NSMutableArray *list = [NSMutableArray array];
            for (NSString *u in uris) if (list.count < 50 && ![u isEqualToString:seed.uri]) [list addObject:u];
            [S6Catalog tracksForURIs:list completion:^(NSArray *found, NSError *e) {
                NSMutableArray *tracks = [NSMutableArray array];
                for (S6Track *track in found) if (track.uri.length && track.playable) [tracks addObject:track];
                if (!tracks.count) { self.playing = NO; [self changed]; return; }
                [self playTracks:tracks startingAt:0 contextURI:[@"spotify:station:track:" stringByAppendingString:seed.trackId ?: @""]
                     contextName:[NSString stringWithFormat:L(@"%@ Radio"), seed.name]];
            }];
        }];
        return;
    }
    self.playing = NO;
    [_engine stop];
    [self changed];
}

#pragma mark - Controls

- (void)play
{
    if (!self.currentTrack) return;
    self.playing = YES;
    if (_engine.currentItem) [_engine resume];
    else if (!self.loading) {
        NSInteger from = _resumeMs;
        _resumeMs = 0;
        [self loadAndPlay:self.currentTrack fromMs:from paused:NO];
    }
    [self changed];
}

- (void)pause
{
    self.playing = NO;
    [_engine pause];
    [self changed];
}

- (void)togglePlay
{
    if (self.playing) [self pause];
    else [self play];
}

- (void)next
{
    if (!self.currentTrack) return;
    self.playing = YES;
    [self advanceAutomatically:NO];
}

- (void)previous
{
    if (!self.currentTrack) return;
    if (self.positionMs > S6RestartThresholdMs || _orderPos <= 0 || _currentFromQueue) {
        [self seekToMs:0];
        if (!self.playing) [self play];
        return;
    }
    for (NSInteger p = _orderPos - 1; p >= 0; p--) {
        S6Track *t = [_contextTracks objectAtIndex:[[_order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]];
        if (!t.playable) continue;
        _orderPos = p;
        self.playing = YES;
        [self loadAndPlay:t];
        return;
    }
    [self seekToMs:0];
}

- (void)seekToMs:(NSInteger)ms
{
    if (!_engine.currentItem && self.currentTrack) _resumeMs = MAX(0, ms);   // (a restored song not started yet)
    [_engine seekToMs:ms];
    [self changed];
}

#pragma mark - Lock screen, remote controls

- (void)handleRemoteEvent:(UIEvent *)event
{
    if (event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlPlay: [self play]; break;
        case UIEventSubtypeRemoteControlPause: [self pause]; break;
        case UIEventSubtypeRemoteControlStop: [self pause]; break;
        case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlay]; break;
        case UIEventSubtypeRemoteControlNextTrack: [self next]; break;
        case UIEventSubtypeRemoteControlPreviousTrack: [self previous]; break;
        default: break;
    }
}

- (void)updateNowPlaying
{
    if (!NSClassFromString(@"MPNowPlayingInfoCenter")) return;
    S6Track *t = self.currentTrack;
    if (!t) {
        if (NSClassFromString(@"MPNowPlayingInfoCenter")) if (NSClassFromString(@"MPNowPlayingInfoCenter")) { Class _c=NSClassFromString(@"MPNowPlayingInfoCenter"); id _ctr=((id(*)(id,SEL))objc_msgSend)(_c,@selector(defaultCenter)); [_ctr setValue:nil forKey:@"nowPlayingInfo"]; }
        return;
    }
    NSString *art = [t imageURLForSize:300];
    if (art.length && ![art isEqualToString:_artworkURL]) {
        _artworkURL = art;
        _artwork = nil;
        __unsafe_unretained S6Player *weakSelf = self;
        _artworkToken = [[S6ImageLoader shared] loadImage:art maxPixels:600 completion:^(UIImage *image) {
            S6Player *me = weakSelf;
            if (!me || ![me->_artworkURL isEqualToString:art]) return;
            me->_artwork = image;
            [me updateNowPlaying];
        }];
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    [info setObject:(t.name ?: @"") forKey:MPMediaItemPropertyTitle];
    [info setObject:([t artistNames] ?: @"") forKey:MPMediaItemPropertyArtist];
    if (t.album.name.length) [info setObject:t.album.name forKey:MPMediaItemPropertyAlbumTitle];
    [info setObject:@((double)self.durationMs / 1000.0) forKey:MPMediaItemPropertyPlaybackDuration];
    [info setObject:@((double)self.positionMs / 1000.0) forKey:@"MPNowPlayingInfoPropertyElapsedPlaybackTime"];
    [info setObject:@(self.playing && !self.buffering ? 1.0 : 0.0) forKey:@"MPNowPlayingInfoPropertyPlaybackRate"];
    if (_artwork && NSClassFromString(@"MPMediaItemArtwork")) [info setObject:((id(*)(id,SEL,id))objc_msgSend)([NSClassFromString(@"MPMediaItemArtwork") alloc], @selector(initWithImage:), _artwork) forKey:MPMediaItemPropertyArtwork];
    if (NSClassFromString(@"MPNowPlayingInfoCenter")) if (NSClassFromString(@"MPNowPlayingInfoCenter")) { Class _c=NSClassFromString(@"MPNowPlayingInfoCenter"); id _ctr=((id(*)(id,SEL))objc_msgSend)(_c,@selector(defaultCenter)); [_ctr setValue:info forKey:@"nowPlayingInfo"]; }
}

- (void)saveWhilePlaying { if (self.playing && _engine.currentItem) [self saveState]; }

#pragma mark - Sleep timer

- (void)setSleepTimerMinutes:(NSInteger)minutes
{
    [_sleepTimer invalidate];
    _sleepTimer = nil;
    self.sleepAt = nil;
    self.sleepAtEndOfSong = minutes < 0;
    if (minutes > 0) {
        self.sleepAt = [NSDate dateWithTimeIntervalSinceNow:minutes * 60];
        _sleepTimer = [NSTimer scheduledTimerWithTimeInterval:minutes * 60 target:self selector:@selector(sleepNow) userInfo:nil repeats:NO];
    }
    if (minutes < 0) [self dropPrepared];
    [self changed];
}

- (void)sleepNow
{
    _sleepTimer = nil;
    self.sleepAt = nil;
    [self pause];
}

#pragma mark - Editing the queue

- (void)moveQueueItemFrom:(NSUInteger)from to:(NSUInteger)to
{
    if (from >= self.queue.count || to >= self.queue.count || from == to) return;
    id t = [self.queue objectAtIndex:from];
    [self.queue removeObjectAtIndex:from];
    [self.queue insertObject:t atIndex:to];
    [self dropPrepared];
    [self changed];
}

- (void)moveUpcomingFrom:(NSUInteger)from to:(NSUInteger)to
{
    NSInteger a = _orderPos + 1 + (NSInteger)from, b = _orderPos + 1 + (NSInteger)to;
    if (a < 0 || b < 0 || a >= (NSInteger)_order.count || b >= (NSInteger)_order.count || a == b) return;
    id x = [_order objectAtIndex:(NSUInteger)a];
    [_order removeObjectAtIndex:(NSUInteger)a];
    [_order insertObject:x atIndex:(NSUInteger)b];
    [self dropPrepared];
    [self changed];
}

- (void)removeUpcomingAtIndex:(NSUInteger)index
{
    NSInteger a = _orderPos + 1 + (NSInteger)index;
    if (a < 0 || a >= (NSInteger)_order.count) return;
    [_order removeObjectAtIndex:(NSUInteger)a];
    [self dropPrepared];
    [self changed];
}

#pragma mark - Where it was left (kept between launches)

+ (NSString *)statePath
{
    NSString *base = ({ NSArray *_p=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES); _p.count?[_p objectAtIndex:0]:nil; });
    NSString *dir = [base stringByAppendingPathComponent:@"Sixify"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:@"queue.json"];
}

static NSArray *S6JSONTracks(NSArray *tracks)
{
    NSMutableArray *out = [NSMutableArray array];
    for (S6Track *t in tracks) { NSDictionary *j = [t toJSON]; if (j) [out addObject:j]; }
    return out;
}

- (void)scheduleSave
{
    if (_saveScheduled) return;
    _saveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_saveScheduled = NO;
        [self saveState];
    });
}

- (void)saveState
{
    S6Track *current = self.currentTrack;
    if (!current) { [[NSFileManager defaultManager] removeItemAtPath:[S6Player statePath] error:NULL]; return; }
    NSArray *context = _contextTracks ?: [NSArray array];
    NSArray *order = _order ?: [NSArray array];
    NSInteger pos = _orderPos;
    if (context.count > 1500) {
        // (a huge context: the song and what follows in play order are enough)
        NSMutableArray *window = [NSMutableArray array];
        for (NSInteger p = MAX(0, pos); p < (NSInteger)order.count && window.count < 500; p++) [window addObject:[context objectAtIndex:[[order objectAtIndex:(NSUInteger)p] unsignedIntegerValue]]];
        context = window;
        NSMutableArray *o = [NSMutableArray array];
        for (NSUInteger i = 0; i < window.count; i++) [o addObject:@(i)];
        order = o;
        pos = pos >= 0 ? 0 : -1;
    }
    NSInteger position = _engine.currentItem ? self.positionMs : _resumeMs;
    NSDictionary *state = @{ @"context": S6JSONTracks(context), @"order": [order copy], @"pos": @(pos), @"queue": S6JSONTracks(self.queue),
                             @"current": [current toJSON] ?: [NSDictionary dictionary], @"fromQueue": @(_currentFromQueue), @"ms": @(position),
                             @"uri": self.contextURI ?: @"", @"name": self.contextName ?: @"", @"shuffle": @(self.shuffle), @"repeat": @(self.repeat) };
    NSString *path = [S6Player statePath];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [[S6Utils JSONDataFromObject:state] writeToFile:path atomically:YES];
    });
}

- (void)restoreState
{
    if (self.currentTrack) return;   // (something plays already, handed over by Spotify Connect say)
    NSDictionary *s = S6Dict([S6Utils JSONObjectFromData:[NSData dataWithContentsOfFile:[S6Player statePath]]]);
    S6Track *current = [S6Track trackFromJSON:S6Dict([s objectForKey:@"current"])];
    if (!current) return;
    NSMutableArray *context = [NSMutableArray array];
    for (id j in S6Arr([s objectForKey:@"context"]) ?: [NSArray array]) { S6Track *t = [S6Track trackFromJSON:S6Dict(j)]; if (t) [context addObject:t]; }
    NSMutableArray *order = [NSMutableArray array];
    for (id n in S6Arr([s objectForKey:@"order"]) ?: [NSArray array]) if ([n integerValue] >= 0 && [n unsignedIntegerValue] < context.count) [order addObject:@([n unsignedIntegerValue])];
    if (order.count != context.count) { [order removeAllObjects]; for (NSUInteger i = 0; i < context.count; i++) [order addObject:@(i)]; }
    _contextTracks = context;
    _order = order;
    _orderPos = MIN((NSInteger)order.count - 1, S6Int([s objectForKey:@"pos"]));
    // (the current song is the same object as its place in the context, so the list shows it as playing)
    if (_orderPos >= 0 && !S6Bool([s objectForKey:@"fromQueue"])) {
        S6Track *atPos = [context objectAtIndex:[[order objectAtIndex:(NSUInteger)_orderPos] unsignedIntegerValue]];
        if ([atPos.uri isEqualToString:current.uri]) current = atPos;
    }
    for (id j in S6Arr([s objectForKey:@"queue"]) ?: [NSArray array]) { S6Track *t = [S6Track trackFromJSON:S6Dict(j)]; if (t) [self.queue addObject:t]; }
    _currentFromQueue = S6Bool([s objectForKey:@"fromQueue"]);
    _shuffle = S6Bool([s objectForKey:@"shuffle"]);
    _repeat = (S6RepeatMode)S6Int([s objectForKey:@"repeat"]);
    self.contextURI = S6Str([s objectForKey:@"uri"]);
    self.contextName = S6Str([s objectForKey:@"name"]);
    self.currentTrack = current;
    _resumeMs = S6Int([s objectForKey:@"ms"]);
    self.playing = NO;
    S6Log(@"restored %@ at %.0f s, %lu songs around it", current.name, _resumeMs / 1000.0, (unsigned long)context.count);
    [[NSNotificationCenter defaultCenter] postNotificationName:S6PlayerDidChangeNotification object:self];
    [self updateNowPlaying];
}
- (NSString *)debugState
{
    return [NSString stringWithFormat:@"player: %@ (%@), %@, context %@ (%ld/%lu), queue %lu, shuffle %d, repeat %ld | %@",
            self.currentTrack.name ?: @"-", self.currentTrack.uri ?: @"-", self.playing ? (self.loading ? @"loading" : @"playing") : @"paused",
            self.contextName ?: @"-", (long)_orderPos, (unsigned long)_order.count, (unsigned long)self.queue.count, self.shuffle, (long)self.repeat,
            [_engine debugState]];
}

@end
