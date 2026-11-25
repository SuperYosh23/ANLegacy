#import <Foundation/Foundation.h>

@class S6AudioFile;

// Ogg Vorbis from one of Spotify's audio files (stb_vorbis, push mode) while it is still downloading. Spotify puts
// its own packet with the loudness values in front (0xa7 bytes); the Vorbis stream starts after it.
@interface S6VorbisDecoder : NSObject

- (instancetype)initWithFile:(S6AudioFile *)file;
- (BOOL)open:(NSError **)error;                        // waits for the headers (blocking)

@property (nonatomic, readonly) int sampleRate;
@property (nonatomic, readonly) int channels;
@property (nonatomic, readonly) float trackGainDb;     // Spotify's ReplayGain values
@property (nonatomic, readonly) float trackPeak;
@property (nonatomic) uint64_t totalFrames;            // from the metadata (for seeking by bytes)

@property (nonatomic, readonly) uint64_t frame;        // where the next frames come from
@property (nonatomic, readonly) BOOL atEnd;            // everything decoded
@property (nonatomic, readonly) BOOL starved;          // the last read ran out of downloaded bytes

// Up to `maxFrames` frames as interleaved 16-bit stereo, multiplied by `gain`; fewer (even 0) when the download is
// behind (`starved`) or at the end (`atEnd`); -1 when the stream is broken
- (NSInteger)readFrames:(int16_t *)out max:(NSUInteger)maxFrames gain:(float)gain;
- (BOOL)seekToFrame:(uint64_t)target;                   // blocking while the bytes there download

@end
