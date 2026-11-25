#import <Foundation/Foundation.h>

// Blocking TLS 1.2 client socket on top of mbedTLS. One instance per connection, used from a
// single worker thread; -cancel may be called from any thread to abort a blocking read.
// Successful handshakes are remembered per host so later connections can resume the session.
@interface S6TLSSocket : NSObject

+ (void)warmUp;                 // parses the CA bundle on a background queue
+ (BOOL)caBundleAvailable;
+ (NSInteger)caCertificateCount;

@property (nonatomic) BOOL plain;   // YES = no TLS, raw TCP (http://)

- (BOOL)connectToHost:(NSString *)host port:(int)port verify:(BOOL)verify
     connectTimeoutMs:(int)connectMs readTimeoutMs:(int)readMs error:(NSError **)error;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;
// Returns > 0 bytes read, 0 on EOF, -1 on error (error set).
- (NSInteger)readIntoBuffer:(void *)buffer maxLength:(NSUInteger)maxLength error:(NSError **)error;
- (void)cancel;
- (void)close;

// Keep-alive support
@property (nonatomic, readonly) BOOL isConnected;
- (BOOL)isLikelyAlive;                       // idle socket still open and nothing pending from the peer
- (void)setReadTimeoutMs:(uint32_t)ms;       // applies to subsequent reads

// For a relay that waits on several sockets at once (poll): the TCP descriptor, and whether bytes the TLS layer
// already took from it wait to be read (poll does not see those)
@property (nonatomic, readonly) int fileDescriptor;
- (BOOL)hasBufferedData;

@property (nonatomic, readonly) NSString *cipherSuite;
@property (nonatomic, readonly) NSString *tlsVersion;

@end
