#import <Foundation/Foundation.h>
#import "S6Settings.h"

@class S6Track, S6AudioFile, S6VorbisDecoder;

// One song made ready to play: its file downloading, the decoder past the headers, the loudness factor
@interface S6PlaybackItem : NSObject
@property (nonatomic, strong) S6Track *track;
@property (nonatomic, strong) S6AudioFile *file;
@property (nonatomic, strong) S6VorbisDecoder *decoder;
@property (nonatomic) float gain;
@property (nonatomic) NSInteger durationMs;
@property (nonatomic, copy) NSString *formatName;        // "Ogg Vorbis 320"
// Loads a song (blocking, worker threads): metadata, the best file for the quality, its key, the CDN, the headers
+ (S6PlaybackItem *)loadTrack:(S6Track *)track quality:(S6Quality)quality error:(NSError **)error;
- (void)cancel;
@end

@protocol S6PlaybackEngineDelegate <NSObject>
- (void)engineDidStartItem:(S6PlaybackItem *)item;       // it is audible now (also the gapless next one)
- (void)engineDidFinishItem:(S6PlaybackItem *)item;      // played to the end and nothing followed
- (void)engineDidFailItem:(S6PlaybackItem *)item error:(NSError *)error;
- (void)engineNeedsNextItem;                             // the current song is almost all decoded: a good time to load the next
@end

// The decoding thread between the items and the speaker. Delegate calls come on the main thread.
@interface S6PlaybackEngine : NSObject

+ (instancetype)shared;
@property (nonatomic, unsafe_unretained) id<S6PlaybackEngineDelegate> delegate;

- (void)playItem:(S6PlaybackItem *)item fromMs:(NSInteger)startMs paused:(BOOL)paused;   // replaces whatever played
- (void)queueNextItem:(S6PlaybackItem *)item;            // follows without a gap
- (void)pause;
- (void)resume;
- (void)seekToMs:(NSInteger)ms;
- (void)stop;

@property (atomic, readonly, strong) S6PlaybackItem *currentItem;
@property (atomic, readonly, strong) S6PlaybackItem *nextItem;
@property (atomic, readonly) BOOL paused;
@property (atomic, readonly) BOOL buffering;
@property (nonatomic, readonly) NSInteger positionMs;    // of the current item
- (NSString *)debugState;

@end
