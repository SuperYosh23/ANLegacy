#import "S6AudioOutput.h"
#import "S6Common.h"
#import <AudioToolbox/AudioToolbox.h>
#include <pthread.h>

static const UInt32 S6BufferFrames = 4096;     // ~93 ms per queue buffer at 44.1 kHz
#define S6QueueBufferCount 3
static const NSUInteger S6RingSeconds = 2;

@interface S6AudioOutput ()
@property (atomic) uint64_t framesPlayed;
@property (atomic) BOOL running;
@property (atomic) double sampleRate;
@end

@implementation S6AudioOutput {
    AudioQueueRef _queue;
    AudioQueueBufferRef _buffers[S6QueueBufferCount];
    int16_t *_ring;
    NSUInteger _capacity;          // frames
    uint64_t _read, _write;        // frame counters (the ring index is the counter modulo the capacity)
    uint64_t _generation;          // bumps on every flush: a waiting writer gives up
    BOOL _primed;                  // the queue's buffers are enqueued (a paused queue keeps them)
    pthread_mutex_t _mutex;
    pthread_cond_t _space;
}

+ (instancetype)shared
{
    static S6AudioOutput *output;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ output = [[S6AudioOutput alloc] init]; });
    return output;
}

- (instancetype)init
{
    if ((self = [super init])) {
        pthread_mutex_init(&_mutex, NULL);
        pthread_cond_init(&_space, NULL);
        _volume = 1;
    }
    return self;
}

- (void)setVolume:(float)volume
{
    _volume = MAX(0.f, MIN(1.f, volume));
    if (_queue) AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, _volume);
}

- (NSUInteger)framesBuffered
{
    pthread_mutex_lock(&_mutex);
    NSUInteger n = (NSUInteger)(_write - _read);
    pthread_mutex_unlock(&_mutex);
    return n;
}

static void S6OutputCallback(void *user, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
    S6AudioOutput *me = (__bridge S6AudioOutput *)user;
    [me fill:buffer];
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

- (void)fill:(AudioQueueBufferRef)buffer
{
    int16_t *out = buffer->mAudioData;
    UInt32 frames = buffer->mAudioDataBytesCapacity / 4;
    pthread_mutex_lock(&_mutex);
    NSUInteger avail = (NSUInteger)(_write - _read);
    NSUInteger n = MIN(avail, (NSUInteger)frames);
    NSUInteger done = 0;
    while (done < n && _ring) {
        NSUInteger index = (NSUInteger)((_read + done) % _capacity);
        NSUInteger chunk = MIN(n - done, _capacity - index);
        memcpy(out + done * 2, _ring + index * 2, chunk * 4);
        done += chunk;
    }
    _read += n;
    if (n < frames) {
        memset(out + n * 2, 0, (frames - n) * 4);
        if (self.running) self.underrun = YES;
    }
    self.framesPlayed += n;
    pthread_cond_broadcast(&_space);
    pthread_mutex_unlock(&_mutex);
    buffer->mAudioDataByteSize = frames * 4;
}

- (BOOL)prepareForSampleRate:(double)rate
{
    if (rate <= 0) rate = 44100;
    if (_queue && rate == self.sampleRate) return YES;
    if (_queue) {
        AudioQueueStop(_queue, true);
        AudioQueueDispose(_queue, true);
        _queue = NULL;
        self.running = NO;
    }
    _primed = NO;
    pthread_mutex_lock(&_mutex);
    free(_ring);
    _capacity = (NSUInteger)(rate * S6RingSeconds);
    _ring = calloc(_capacity, 4);
    _read = _write = 0;
    _generation++;
    pthread_cond_broadcast(&_space);
    pthread_mutex_unlock(&_mutex);

    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;
    OSStatus status = AudioQueueNewOutput(&format, S6OutputCallback, (__bridge void *)self, NULL, kCFRunLoopCommonModes, 0, &_queue);
    if (status != noErr) {
        S6Log(@"audio: AudioQueueNewOutput failed (%d)", (int)status);
        _queue = NULL;
        return NO;
    }
    for (int i = 0; i < S6QueueBufferCount; i++) AudioQueueAllocateBuffer(_queue, S6BufferFrames * 4, &_buffers[i]);
    AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, _volume);
    self.sampleRate = rate;
    return YES;
}

- (void)play
{
    if (!_queue && ![self prepareForSampleRate:self.sampleRate ?: 44100]) return;
    if (self.running) return;
    self.running = YES;
    if (!_primed) {
        for (int i = 0; i < S6QueueBufferCount; i++) {
            [self fill:_buffers[i]];
            AudioQueueEnqueueBuffer(_queue, _buffers[i], 0, NULL);
        }
        _primed = YES;
    }
    OSStatus status = AudioQueueStart(_queue, NULL);
    if (status != noErr) {
        S6Log(@"audio: AudioQueueStart failed (%d)", (int)status);
        self.running = NO;
    }
}

- (void)pause
{
    if (!_queue || !self.running) return;
    AudioQueuePause(_queue);   // (the buffers stay enqueued; the next start plays them first)
    self.running = NO;
}

- (void)stop
{
    if (_queue) AudioQueueStop(_queue, true);
    _primed = NO;
    self.running = NO;
    [self flush];
}

- (void)flush
{
    pthread_mutex_lock(&_mutex);
    _read = _write = 0;
    _generation++;
    self.framesPlayed = 0;
    pthread_cond_broadcast(&_space);
    pthread_mutex_unlock(&_mutex);
}

- (uint64_t)generation
{
    pthread_mutex_lock(&_mutex);
    uint64_t g = _generation;
    pthread_mutex_unlock(&_mutex);
    return g;
}

- (NSUInteger)write:(const int16_t *)frames count:(NSUInteger)count generation:(uint64_t)generation
{
    NSUInteger written = 0;
    pthread_mutex_lock(&_mutex);
    while (written < count && _ring) {
        if (generation != _generation) break;
        NSUInteger space = _capacity - (NSUInteger)(_write - _read);
        if (space == 0) {
            pthread_cond_wait(&_space, &_mutex);
            continue;
        }
        NSUInteger n = MIN(space, count - written);
        NSUInteger index = (NSUInteger)(_write % _capacity);
        NSUInteger first = MIN(n, _capacity - index);
        memcpy(_ring + index * 2, frames + written * 2, first * 4);
        if (n > first) memcpy(_ring, frames + (written + first) * 2, (n - first) * 4);
        _write += n;
        written += n;
    }
    pthread_mutex_unlock(&_mutex);
    return written;
}

@end
