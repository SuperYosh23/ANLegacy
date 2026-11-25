#import <Foundation/Foundation.h>
#import "S6TLSSocket.h"

// A small WebSocket client (RFC 6455) on top of the app's own TLS socket - iOS 6 has none of its own.
// Blocking, for one worker thread; -cancel may be called from any thread. Text messages only (what Spotify's dealer
// sends).
@interface S6WebSocket : NSObject

@property (nonatomic, readonly) S6TLSSocket *socket;

// The TCP/TLS connection (wss:// or ws://) and the HTTP upgrade; YES once the server switched protocols
- (BOOL)connectToURL:(NSURL *)url origin:(NSString *)origin userAgent:(NSString *)userAgent verify:(BOOL)verify error:(NSError **)error;
- (BOOL)sendText:(NSString *)text error:(NSError **)error;

// The text messages completed by what has arrived. Takes frames already received first; only when there are none it
// reads the socket once (waiting up to the socket's read timeout). Pings are answered here. `closed` turns YES when
// the server ended the connection.
- (NSArray *)readMessages:(BOOL *)closed error:(NSError **)error;

- (void)cancel;
- (void)close;

@end
