#import <Foundation/Foundation.h>

// One encrypted audio file from Spotify's CDN, downloaded into memory and decrypted as it arrives (AES-CTR from the
// start of the file). The decoder reads from it while the rest still comes; a broken connection carries on where it
// stopped (Range), the next CDN address is tried when one fails.
@interface S6AudioFile : NSObject

- (instancetype)initWithURLs:(NSArray *)urls key:(NSData *)key;
- (void)start;        // downloads on a thread of its own
- (void)cancel;

@property (atomic, readonly) NSUInteger length;       // the whole file (0 until the first answer)
@property (atomic, readonly) NSUInteger available;    // bytes from the start that are here and decrypted
@property (atomic, readonly) BOOL finished;           // all here (or given up: see error)
@property (atomic, readonly, strong) NSError *error;

// The file's bytes; valid while this object lives, from the moment `length` is known
- (const uint8_t *)bytes;
// Waits until `end` bytes are here, the download finished or failed, or `timeout` passed; YES when they are here
- (BOOL)waitForBytes:(NSUInteger)end timeout:(NSTimeInterval)timeout;

@end
