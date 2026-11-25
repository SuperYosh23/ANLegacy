#import <Foundation/Foundation.h>

typedef void (^S6HTTPCompletion)(NSInteger status, NSData *body, NSDictionary *headers, NSError *error);
typedef void (^S6JSONCompletion)(id json, NSInteger status, NSError *error);

// A running request of S6HTTP. After -cancel the completion block is never called.
@interface S6HTTPTask : NSObject
@property (atomic, readonly) BOOL isCancelled;
@property (atomic, copy) dispatch_block_t cancelBlock;   // for chained requests: called by -cancel (once)
- (void)cancel;
@end

// Convenience layer over S6HTTPRequest for API calls: redirects are followed, GET requests are tried a second
// time after a network error, completion blocks run on the main thread.
@interface S6HTTP : NSObject

+ (S6HTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(S6HTTPCompletion)completion;

+ (S6HTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(S6HTTPCompletion)completion;

// JSON answers. `error` is set for network errors, for statuses >= 400 (code = the status, message from the body
// when it has one) and for bodies that are not JSON; `json` is passed even with an error when the body parsed.
+ (S6HTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(S6JSONCompletion)completion;
+ (S6HTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(S6JSONCompletion)completion;
+ (S6HTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(S6JSONCompletion)completion;
+ (S6HTTPTask *)postForm:(NSString *)url headers:(NSDictionary *)headers fields:(NSDictionary *)fields completion:(S6JSONCompletion)completion;

@end
