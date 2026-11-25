#import "S6PlaybackEngine.h"
#import "S6AudioFile.h"
#import "S6VorbisDecoder.h"
#import "S6AudioOutput.h"
#import "S6Session.h"
#import "S6SpClient.h"
#import "S6Models.h"
#import "S6Proto.h"
#import "S6Crypto.h"
#import "S6Common.h"

static const NSUInteger S6ChunkFrames = 4096;

@interface S6PlaybackItem ()
@property (nonatomic) uint64_t outputStart;     // frames written to the output (since its last flush) before this item's first one
@property (nonatomic) uint64_t baseFrame;       // the decoder frame at outputStart
@property (nonatomic) BOOL askedForNext;
@end

@implementation S6PlaybackItem

// format numbers of metadata.proto, in order of preference for each quality
static NSArray *S6FormatsFor(S6Quality q)
{
    switch (q) {
        case S6QualityNormal: return @[ @0, @1, @2 ];
        case S6QualityHigh: return @[ @1, @2, @0 ];
        default: return @[ @2, @1, @0 ];
    }
}

static NSString *S6FormatName(uint64_t format)
{
    switch (format) {
        case 0: return @"Ogg Vorbis 96";
        case 1: return @"Ogg Vorbis 160";
        case 2: return @"Ogg Vorbis 320";
        default: return [NSString stringWithFormat:@"format %llu", format];
    }
}

// The Vorbis file of a Track/Episode message in the preferred format: @[gid, fileId, format]
static NSArray *S6PickFile(NSData *message, uint32_t filesField, S6Quality quality)
{
    NSMutableDictionary *byFormat = [NSMutableDictionary dictionary];
    for (NSData *f in S6ProtoAllBytes(message, filesField)) {
        NSData *fileId = S6ProtoBytes(f, 1);
        uint64_t format = S6ProtoVarint(f, 2, 99);
        if (fileId.length == 20 && ![byFormat objectForKey:@(format)]) [byFormat setObject:fileId forKey:@(format)];
    }
    for (NSNumber *format in S6FormatsFor(quality)) {
        NSData *fileId = [byFormat objectForKey:format];
        if (fileId) return @[ S6ProtoBytes(message, 1) ?: [NSData data], fileId, format ];
    }
    return nil;
}

+ (S6PlaybackItem *)loadTrack:(S6Track *)track quality:(S6Quality)quality error:(NSError **)error
{
    NSData *gid = S6GidFromBase62(track.trackId);
    if (!gid) { if (error) *error = S6MakeError(S6ErrorPlayback, L(@"This song cannot be played.")); return nil; }
    NSData *meta = track.isEpisode ? [S6SpClient episodeMetadata:gid error:error] : [S6SpClient trackMetadata:gid error:error];
    if (!meta) return nil;
    NSArray *pick = S6PickFile(meta, 12, quality);
    if (!pick && !track.isEpisode) {
        // relinked: another release of the same song plays in this country
        for (NSData *alternative in S6ProtoAllBytes(meta, 13)) {
            pick = S6PickFile(alternative, 12, quality);
            if (pick) break;
        }
    }
    if (!pick) {
        if (error) *error = S6MakeError(S6ErrorRestricted, track.isEpisode ? L(@"This episode is not hosted on Spotify, it cannot be played here yet.")
                                                                           : L(@"This song is not available."));
        return nil;
    }
    NSData *keyGid = [[pick objectAtIndex:0] length] == 16 ? [pick objectAtIndex:0] : gid;
    NSData *fileId = [pick objectAtIndex:1];
    S6PlaybackItem *item = [[S6PlaybackItem alloc] init];
    item.track = track;
    item.durationMs = (NSInteger)S6ProtoZigzag(S6ProtoVarint(meta, 7, 0)) ?: track.durationMs;
    item.formatName = S6FormatName([[pick objectAtIndex:2] unsignedLongLongValue]);

    NSData *key = [[S6Session shared] audioKeyForTrack:keyGid file:fileId error:error];
    if (!key) return nil;
    NSArray *urls = [S6SpClient cdnURLsForFile:fileId error:error];
    if (!urls) return nil;
    item.file = [[S6AudioFile alloc] initWithURLs:urls key:key];
    [item.file start];
    item.decoder = [[S6VorbisDecoder alloc] initWithFile:item.file];
    if (![item.decoder open:error]) {
        [item.file cancel];
        return nil;
    }
    int rate = item.decoder.sampleRate ?: 44100;
    item.decoder.totalFrames = (uint64_t)item.durationMs * (uint64_t)rate / 1000;
    float gain = 1;
    if ([S6Settings normalize]) {
        gain = powf(10.f, item.decoder.trackGainDb / 20.f);
        if (gain * item.decoder.trackPeak > 1.f) gain = 1.f / item.decoder.trackPeak;
    }
    item.gain = gain;
    S6Log(@"loaded %@: %@, %d Hz, gain %.1f dB (peak %.2f)", track.name, item.formatName, rate, item.decoder.trackGainDb, item.decoder.trackPeak);
    return item;
}

- (void)cancel { [self.file cancel]; }

@end

@interface S6PlaybackEngine ()
@property (atomic, strong) S6PlaybackItem *currentItem;
@property (atomic, strong) S6PlaybackItem *nextItem;
@property (atomic) BOOL paused;
@property (atomic) BOOL buffering;
@end

@implementation S6PlaybackEngine {
    NSCondition *_cond;
    S6PlaybackItem *_decodingItem;      // what the thread decodes (the current item, or the next one once it started)
    NSInteger _pendingSeekMs;           // -1 = none
    uint64_t _generation;               // a new play request: the thread starts over
    uint64_t _framesWritten;            // into the output since its last flush
    BOOL _drained;                      // the last item is all decoded; finished once played
    S6AudioOutput *_output;
    S6PlaybackItem *_fadeNext;          // crossfading: the next song coming in under the end of this one
    uint64_t _fadeLength, _fadeDone;    // frames
}

+ (instancetype)shared
{
    static S6PlaybackEngine *engine;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ engine = [[S6PlaybackEngine alloc] init]; });
    return engine;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _cond = [[NSCondition alloc] init];
        _pendingSeekMs = -1;
        _output = [S6AudioOutput shared];
        NSThread *t = [[NSThread alloc] initWithTarget:self selector:@selector(decodeLoop) object:nil];
        t.name = @"S6PlaybackEngine";
        t.threadPriority = 0.9;
        [t start];
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        });
    }
    return self;
}

#pragma mark - Commands (main thread)

- (void)playItem:(S6PlaybackItem *)item fromMs:(NSInteger)startMs paused:(BOOL)paused
{
    S6PlaybackItem *old;
    [_cond lock];
    old = self.currentItem;
    _generation++;
    _decodingItem = item;
    self.currentItem = item;
    S6PlaybackItem *oldNext = self.nextItem;
    self.nextItem = nil;
    S6PlaybackItem *oldFade = _fadeNext;
    _fadeNext = nil;
    _drained = NO;
    _framesWritten = 0;
    _pendingSeekMs = startMs > 0 ? startMs : -1;
    self.paused = paused;
    item.outputStart = 0;
    item.baseFrame = 0;
    [_output stop];            // (inside the lock: the thread cannot write old audio after this)
    [_output prepareForSampleRate:item.decoder.sampleRate ?: 44100];
    [_cond broadcast];
    [_cond unlock];
    if (old != item) [old cancel];
    if (oldNext != item) [oldNext cancel];
    if (oldFade && oldFade != item) [oldFade cancel];
    if (!paused) [_output play];
    [self.delegate engineDidStartItem:item];
}

- (void)queueNextItem:(S6PlaybackItem *)item
{
    [_cond lock];
    S6PlaybackItem *old = self.nextItem;
    self.nextItem = item;
    [_cond broadcast];
    [_cond unlock];
    if (old && old != item) [old cancel];
}

- (void)pause
{
    [_cond lock];
    self.paused = YES;
    [_cond unlock];
    [_output pause];
}

- (void)resume
{
    if (!self.currentItem) return;
    [_cond lock];
    self.paused = NO;
    [_cond broadcast];
    [_cond unlock];
    [_output play];
}

- (void)seekToMs:(NSInteger)ms
{
    S6PlaybackItem *dropped = nil;
    [_cond lock];
    if (!self.currentItem) { [_cond unlock]; return; }
    _pendingSeekMs = MAX(0, ms);
    if (_decodingItem && _decodingItem != self.currentItem) {
        // the next song had begun decoding behind this one: it is loaded again when its time comes
        dropped = _decodingItem;
        self.currentItem.askedForNext = NO;
    }
    if (_fadeNext) {
        // (a seek in the middle of a crossfade: the next song is loaded again when its time comes)
        dropped = _fadeNext;
        _fadeNext = nil;
        self.currentItem.askedForNext = NO;
    }
    _decodingItem = self.currentItem;
    _drained = NO;
    [_output flush];                      // wakes a writer waiting for room
    [_cond broadcast];
    [_cond unlock];
    [dropped cancel];
}

- (void)stop
{
    S6PlaybackItem *old, *oldNext;
    [_cond lock];
    _generation++;
    old = self.currentItem;
    oldNext = self.nextItem;
    S6PlaybackItem *oldFade = _fadeNext;
    _fadeNext = nil;
    _decodingItem = nil;
    self.currentItem = nil;
    self.nextItem = nil;
    _drained = NO;
    [_output stop];
    [_cond unlock];
    [old cancel];
    [oldNext cancel];
    [oldFade cancel];
}

- (NSInteger)positionMs
{
    S6PlaybackItem *item = self.currentItem;
    if (!item) return 0;
    double rate = item.decoder.sampleRate ?: 44100;
    uint64_t played = _output.framesPlayed;
    uint64_t intoItem = played > item.outputStart ? played - item.outputStart : 0;
    // (what is queued in the AudioQueue but not heard yet: about one buffer)
    uint64_t latency = (uint64_t)(0.09 * rate);
    intoItem = intoItem > latency ? intoItem - latency : 0;
    NSInteger ms = (NSInteger)((double)(item.baseFrame + intoItem) * 1000.0 / rate);
    return item.durationMs > 0 ? MIN(ms, item.durationMs) : ms;
}

#pragma mark - Main-thread bookkeeping

- (void)tick
{
    S6PlaybackItem *current = self.currentItem;
    if (!current) return;
    uint64_t played = _output.framesPlayed;
    S6PlaybackItem *decoding;
    BOOL drained;
    uint64_t written;
    [_cond lock];
    decoding = _decodingItem;
    drained = _drained;
    written = _framesWritten;
    [_cond unlock];
    // the gapless next item became audible
    if (decoding && decoding != current && played >= decoding.outputStart) {
        self.currentItem = decoding;
        [current cancel];
        [self.delegate engineDidStartItem:decoding];
        return;
    }
    if (drained && played >= written && !self.paused) {
        [_cond lock];
        _drained = NO;
        _decodingItem = nil;
        [_cond unlock];
        [_output stop];
        [self.delegate engineDidFinishItem:current];
        return;
    }
    BOOL buffering = !self.paused && _output.underrun && current.decoder.starved;
    if (buffering != self.buffering) self.buffering = buffering;
    if (!current.decoder.starved) _output.underrun = NO;
}

#pragma mark - The decoding thread

- (void)decodeLoop
{
    int16_t *buffer = malloc(S6ChunkFrames * 4);
    int16_t *mix = malloc(S6ChunkFrames * 4);
    while (YES) {
        @autoreleasepool {
            [_cond lock];
            while (!_decodingItem || ((self.paused || _drained) && _pendingSeekMs < 0)) [_cond wait];
            S6PlaybackItem *item = _decodingItem;
            NSInteger seekMs = _pendingSeekMs;
            _pendingSeekMs = -1;
            uint64_t generation = _generation;
            uint64_t outputGeneration = _output.generation;
            [_cond unlock];

            if (seekMs >= 0) {
                double rate = item.decoder.sampleRate ?: 44100;
                [_output stop];
                [item.decoder seekToFrame:(uint64_t)((double)seekMs * rate / 1000.0)];
                [_cond lock];
                BOOL current = generation == _generation;
                if (current) {
                    _framesWritten = 0;
                    item.outputStart = 0;
                    item.baseFrame = item.decoder.frame;
                }
                BOOL play = current && !self.paused;
                [_cond unlock];
                if (play) [_output play];
                continue;
            }

            if ([self crossfadeStep:item buffer:buffer mix:mix generation:generation outputGeneration:outputGeneration]) continue;

            NSInteger n = [item.decoder readFrames:buffer max:S6ChunkFrames gain:item.gain];
            if (n > 0) {
                NSUInteger written = [_output write:buffer count:(NSUInteger)n generation:outputGeneration];
                [_cond lock];
                if (generation == _generation && outputGeneration == _output.generation) _framesWritten += written;
                [_cond unlock];
            }
            if (!item.askedForNext && (item.file.finished || item.decoder.atEnd)) {
                item.askedForNext = YES;
                dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate engineNeedsNextItem]; });
            }
            if (n < 0) {
                NSError *error = item.file.error ?: S6MakeError(S6ErrorPlayback, L(@"The song could not be decoded."));
                [_cond lock];
                BOOL current = generation == _generation && _decodingItem == item;
                if (current) _decodingItem = nil;
                [_cond unlock];
                if (current) dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate engineDidFailItem:item error:error]; });
                continue;
            }
            if (item.decoder.atEnd) {
                [_cond lock];
                if (generation == _generation && _decodingItem == item) {
                    S6PlaybackItem *next = self.nextItem;
                    if (next && next.decoder.sampleRate == item.decoder.sampleRate) {
                        // gapless: the next song's frames follow right behind
                        self.nextItem = nil;
                        next.outputStart = _framesWritten;
                        next.baseFrame = next.decoder.frame;
                        _decodingItem = next;
                    } else {
                        _drained = YES;
                    }
                }
                [_cond unlock];
                continue;
            }
            if (n == 0 && item.decoder.starved) usleep(20000);
        }
    }
}

// Crossfading (Settings): once the song is within the fade's length of its end and the next one is ready, both are
// decoded and mixed (equal power) until this one ends; the next one then simply goes on. YES when this step was a fade.
- (BOOL)crossfadeStep:(S6PlaybackItem *)item buffer:(int16_t *)buffer mix:(int16_t *)mix generation:(uint64_t)generation outputGeneration:(uint64_t)outputGeneration
{
    NSInteger seconds = [S6Settings crossfadeSeconds];
    S6PlaybackItem *fade;
    [_cond lock];
    if (!_fadeNext && seconds > 0 && generation == _generation && _decodingItem == item) {
        S6PlaybackItem *next = self.nextItem;
        uint64_t rate = (uint64_t)(item.decoder.sampleRate ?: 44100);
        uint64_t total = item.decoder.totalFrames, length = (uint64_t)seconds * rate;
        if (next && next.decoder.sampleRate == item.decoder.sampleRate && total > length * 3 && item.decoder.frame + length >= total) {
            self.nextItem = nil;
            _fadeNext = next;
            _fadeLength = MAX((uint64_t)1, total - item.decoder.frame);
            _fadeDone = 0;
            next.outputStart = _framesWritten;
            next.baseFrame = next.decoder.frame;
        }
    }
    fade = _fadeNext;
    [_cond unlock];
    if (!fade) return NO;
    NSInteger n = [item.decoder readFrames:buffer max:S6ChunkFrames gain:item.gain];
    if (n > 0) {
        NSInteger m = [fade.decoder readFrames:mix max:(NSUInteger)n gain:fade.gain];
        if (m < 0) m = 0;
        if (m < n) memset(mix + m * 2, 0, (size_t)(n - m) * 4);
        for (NSInteger i = 0; i < n; i++) {
            float p = (float)(_fadeDone + (uint64_t)i) / (float)_fadeLength;
            if (p > 1.f) p = 1.f;
            float a = sqrtf(1.f - p), b = sqrtf(p);
            for (int c = 0; c < 2; c++) {
                float v = (float)buffer[i * 2 + c] * a + (float)mix[i * 2 + c] * b;
                buffer[i * 2 + c] = (int16_t)(v > 32767.f ? 32767.f : (v < -32768.f ? -32768.f : v));
            }
        }
        _fadeDone += (uint64_t)n;
        NSUInteger written = [_output write:buffer count:(NSUInteger)n generation:outputGeneration];
        [_cond lock];
        if (generation == _generation && outputGeneration == _output.generation) _framesWritten += written;
        [_cond unlock];
    }
    if (n < 0 || item.decoder.atEnd || _fadeDone >= _fadeLength) {
        // this song is over: the next one goes on by itself
        [_cond lock];
        if (generation == _generation && _decodingItem == item && _fadeNext == fade) {
            _decodingItem = fade;
            _fadeNext = nil;
        }
        [_cond unlock];
    } else if (n == 0 && item.decoder.starved) {
        usleep(20000);
    }
    return YES;
}

- (NSString *)debugState
{
    S6PlaybackItem *item = self.currentItem;
    return [NSString stringWithFormat:@"engine: %@ %@, %ld/%ld ms, %@, buffered %lu frames, file %lu/%lu%@%@",
            item ? item.track.name : @"idle", item.formatName ?: @"", (long)self.positionMs, (long)item.durationMs,
            self.paused ? @"paused" : (self.buffering ? @"buffering" : @"playing"), (unsigned long)_output.framesBuffered,
            (unsigned long)item.file.available, (unsigned long)item.file.length, self.nextItem ? @", next ready" : @"",
            item.file.error ? [NSString stringWithFormat:@", download error %@", item.file.error.localizedDescription] : @""];
}

@end
