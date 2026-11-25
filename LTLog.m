#import <Foundation/Foundation.h>
#import "LTFilePaths.h"

// Appends a timestamped line to /tmp/legacymusic.log and mirrors it to the
// system log.
//
// COST: this sits in ~150 call sites, several of which fire on every touch-move
// or timer tick. The original opened, seeked, wrote and closed the file on every
// call: four syscalls plus an NSDate plus two string formats per event, which
// was measurable jank on a 3GS. The handle is now opened once and shared.
//
// This is a real function in a .m rather than a static inline in the header
// because a static inline gives every translation unit its own copy of the
// handle and its own "already enabled" flag, so ~20 files would each hold an
// open descriptor and race to append to the same file.
//
// The write is deliberately synchronous and unbuffered: this log is the app's
// primary crash-diagnosis artifact (see CLAUDE.md), so a line emitted right
// before a crash has to already be on disk. Buffering would buy a little speed
// at the cost of the thing the log exists for.
//
// Set the "LTLogDisabled" user default to YES to silence it entirely. It is
// read once at first use, so it has to be set before the app logs anything.
void LTLog(NSString *format, ...) {
    static int enabled = -1;
    static NSFileHandle *handle = nil;
    static NSObject *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTLogDisabled"] ? 0 : 1;
        lock = [[NSObject alloc] init];
    });
    if (!enabled) return;

    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@", msg);

    @synchronized (lock) {
        if (!handle) {
            NSString *path = [LTTempDirectory() stringByAppendingPathComponent:@"legacymusic.log"];
            handle = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!handle) {
                [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
                handle = [NSFileHandle fileHandleForWritingAtPath:path];
            }
            // Nothing to write to (read-only volume). Stop retrying the open.
            if (!handle) enabled = 0;
        }
        if (!handle) return;
        [handle seekToEndOfFile];
        [handle writeData:[[NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg]
                          dataUsingEncoding:NSUTF8StringEncoding]];
    }
}
