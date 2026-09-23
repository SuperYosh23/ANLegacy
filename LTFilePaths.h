#import <Foundation/Foundation.h>

// The app historically stored its data in /var/mobile/Documents/LegacyMusic and
// staged temporary files in /tmp. Both are outside the app sandbox and are denied
// on modern iOS (>= 10). Prefer the legacy locations when they are actually
// writable (older jailbroken devices) and otherwise fall back to the app
// container, so a single build keeps working everywhere.

static inline BOOL LTDirectoryIsWritable(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) return NO;
    NSString *probe = [path stringByAppendingPathComponent:@".lt_write_probe"];
    if ([fm createFileAtPath:probe contents:[NSData data] attributes:nil]) {
        [fm removeItemAtPath:probe error:NULL];
        return YES;
    }
    return NO;
}

// Directory that holds playlists/library/downloads/artwork.
static inline NSString *LTDataDirectory(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *legacy = @"/var/mobile/Documents/LegacyMusic";
        if (LTDirectoryIsWritable(legacy)) {
            dir = legacy;
        } else {
            [fm createDirectoryAtPath:legacy withIntermediateDirectories:YES attributes:nil error:NULL];
            if (LTDirectoryIsWritable(legacy)) {
                dir = legacy;
            } else {
                NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                dir = [docs stringByAppendingPathComponent:@"LegacyMusic"];
                [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
            }
        }
    });
    return dir;
}

// Directory for short-lived files (log, stream cache, crash log).
static inline NSString *LTTempDirectory(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (LTDirectoryIsWritable(@"/tmp")) {
            dir = @"/tmp";
        } else {
            dir = NSTemporaryDirectory();
        }
    });
    return dir;
}
