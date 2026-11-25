#import <Foundation/Foundation.h>

typedef void (^S6HTTPHeadersBlock)(NSInteger status, NSDictionary *headers);
typedef void (^S6HTTPDataBlock)(NSData *chunk);
typedef void (^S6HTTPCompleteBlock)(NSError *error);

// Minimal HTTP/1.1 client over S6TLSSocket: keep-alive connections from S6ConnectionPool, chunked transfer
// decoding, gzip/deflate content decoding. Redirects are NOT followed (the caller decides; S6HTTP does).
// All callbacks run synchronously on the worker thread that performs the request.
@interface S6HTTPRequest : NSObject

- (instancetype)initWithMethod:(NSString *)method URL:(NSURL *)url;

@property (nonatomic, readonly, copy) NSString *method;
@property (nonatomic, readonly, strong) NSURL *url;
@property (nonatomic, strong) NSDictionary *headers;        // request headers; Host, Content-Length, Connection and Accept-Encoding are managed here
@property (nonatomic, strong) NSData *body;
@property (nonatomic) NSTimeInterval connectTimeout;        // seconds, default 20
@property (nonatomic) NSTimeInterval readTimeout;           // seconds, default 60
@property (nonatomic) BOOL verifyTLS;                       // default YES
@property (nonatomic) BOOL highPriority;                    // video segments and playlists: never queue behind image downloads
@property (nonatomic) BOOL noCompression;                   // asks for the body as it is stored (media relayed to the player)

@property (nonatomic, copy) S6HTTPHeadersBlock onHeaders;   // final status and headers (1xx responses are skipped)
@property (nonatomic, copy) S6HTTPDataBlock onData;         // decoded body bytes; when nil the body is collected in responseBody
@property (nonatomic, copy) S6HTTPCompleteBlock onComplete; // error is nil on success

@property (nonatomic, readonly) NSInteger statusCode;
@property (nonatomic, readonly) NSDictionary *responseHeaders;    // lowercase names, duplicates joined with ", ", Set-Cookie excluded
@property (nonatomic, readonly) NSArray *responseHeaderPairs;     // @[@[name, value], ...] in wire order, original case
@property (nonatomic, readonly) NSArray *setCookieHeaders;        // every Set-Cookie value separately
@property (nonatomic, readonly) NSData *responseBody;             // only when onData is nil
@property (nonatomic, readonly) BOOL decodedContentEncoding;      // YES when gzip/deflate was removed by this client
@property (nonatomic, readonly) NSString *tlsInfo;                // "TLSv1.2 TLS-ECDHE-..." once connected
@property (nonatomic, readonly) BOOL isCancelled;
@property (nonatomic, readonly) BOOL isFinished;

+ (NSString *)defaultUserAgent;

- (void)start;                // on a global queue
- (void)runSynchronously;     // on the calling thread (the media proxy and the chat have threads of their own)
- (void)cancel;

@end
