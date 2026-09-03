#import <Foundation/Foundation.h>

// Minimal embedded HTTP server used for wireless playlist sync.
// Advertises itself over Bonjour as _anlegacy-sync._tcp.<name> so the
// desktop app can discover it without any manual IP entry.
@interface LTSyncServer : NSObject

// Return a response body (may be nil) and fill *status (defaults handled by server).
@property (nonatomic, copy) NSData *(^requestHandler)(NSString *method, NSString *path, NSData *body, NSInteger *status);

// Called once after a client connection finishes being served.
@property (nonatomic, copy) void (^onConnectionFinished)(NSString *method, NSString *path);

// Bonjour service type to publish (e.g. @"_anlegacy-sync._tcp."). Set before start.
@property (nonatomic, copy) NSString *serviceType;

@property (nonatomic, readonly) NSUInteger port;

- (BOOL)start:(NSError **)error;
- (void)stop;

@end
