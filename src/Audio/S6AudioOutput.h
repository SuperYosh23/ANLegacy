#import <Foundation/Foundation.h>

// 16-bit stereo PCM to the speaker through an AudioQueue, fed from a ring buffer of about two seconds: one thread
// writes (the decoder), the queue's own thread plays. Counts the frames really played (for the position).
@interface S6AudioOutput : NSObject

+ (instancetype)shared;

- (BOOL)prepareForSampleRate:(double)rate;       // (re)creates the queue when the rate changes
- (void)play;
- (void)pause;
- (void)stop;                                   // empties everything

// Writes up to `count` frames, waiting while the ring is full; returns how many were taken. Writes for an older
// `generation` (a flush came in between) are refused.
- (NSUInteger)write:(const int16_t *)frames count:(NSUInteger)count generation:(uint64_t)generation;
- (void)flush;                                  // drops what is buffered (seeking, skipping)
@property (atomic, readonly) uint64_t generation;  // bumps with every flush

@property (atomic, readonly) uint64_t framesPlayed;    // since the last flush
@property (atomic, readonly) NSUInteger framesBuffered;
@property (atomic, readonly) BOOL running;
@property (atomic, readonly) double sampleRate;
@property (atomic) BOOL underrun;                       // the queue ran dry since this was last cleared
@property (nonatomic) float volume;                     // 0...1, the app's own (Spotify Connect's volume); default 1

@end
