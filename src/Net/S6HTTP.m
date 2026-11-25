#import "S6HTTP.h"
#import "S6HTTPRequest.h"
#import "S6Settings.h"
#import "S6Utils.h"
#import "S6Common.h"

static const NSInteger S6MaxRedirects = 5;

@interface S6HTTPTask ()
@property (atomic, strong) S6HTTPRequest *request;
@property (atomic) BOOL isCancelled;
@end

@implementation S6HTTPTask

- (void)cancel
{
    if (self.isCancelled) return;
    self.isCancelled = YES;
    [self.request cancel];
    dispatch_block_t block = self.cancelBlock;
    self.cancelBlock = nil;
    if (block) block();
}

@end

@implementation S6HTTP

+ (void)run:(S6HTTPTask *)task method:(NSString *)method url:(NSURL *)url headers:(NSDictionary *)headers body:(NSData *)body
       hops:(NSInteger)hops retries:(NSInteger)retries completion:(S6HTTPCompletion)completion
{
    S6HTTPRequest *r = [[S6HTTPRequest alloc] initWithMethod:method URL:url];
    r.headers = headers;
    r.body = body;
    r.connectTimeout = 15;
    r.readTimeout = 30;
    r.verifyTLS = [S6Settings verifyTLS];
    __unsafe_unretained S6HTTPRequest *weakRequest = r;
    r.onComplete = ^(NSError *error) {
        S6HTTPRequest *request = weakRequest;
        if (task.isCancelled) return;
        NSInteger status = request.statusCode;
        NSDictionary *responseHeaders = request.responseHeaders;
        if (!error && status >= 300 && status < 400 && status != 304 && hops < S6MaxRedirects) {
            NSString *location = [responseHeaders objectForKey:@"location"];
            NSURL *next = location.length ? [[NSURL URLWithString:location relativeToURL:url] absoluteURL] : nil;
            if (next.host.length) {
                BOOL safe = [method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"];
                BOOL toGet = status == 303 || ((status == 301 || status == 302) && !safe);
                NSDictionary *nextHeaders = headers;
                if (![[next.host lowercaseString] isEqualToString:[url.host lowercaseString]]) {
                    // credentials stay with the host they were meant for
                    NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
                    for (NSString *key in headers) {
                        NSString *lower = [key lowercaseString];
                        if ([lower isEqualToString:@"authorization"] || [lower isEqualToString:@"client-id"]) continue;
                        [trimmed setObject:[headers objectForKey:key] forKey:key];
                    }
                    nextHeaders = trimmed;
                }
                [self run:task method:toGet ? @"GET" : method url:next headers:nextHeaders body:toGet ? nil : body
                     hops:hops + 1 retries:retries completion:completion];
                return;
            }
        }
        if (error && retries > 0 && error.code != S6ErrorCancelled && error.code != S6ErrorCertificate) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (task.isCancelled) return;
                [self run:task method:method url:url headers:headers body:body hops:hops retries:retries - 1 completion:completion];
            });
            return;
        }
        NSData *responseBody = request.responseBody;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(error ? 0 : status, responseBody, responseHeaders, error);
        });
    };
    task.request = r;
    if (task.isCancelled) return;
    [r start];
}

+ (S6HTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(S6HTTPCompletion)completion
{
    S6HTTPTask *task = [[S6HTTPTask alloc] init];
    NSURL *u = url.length ? [NSURL URLWithString:url] : nil;
    if (!u.host.length) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(0, nil, nil, S6MakeError(S6ErrorNetwork, [NSString stringWithFormat:L(@"Bad address: %@"), url ?: @""]));
        });
        return task;
    }
    [self run:task method:method.length ? [method uppercaseString] : @"GET" url:u headers:headers body:body hops:0 retries:retries completion:completion];
    return task;
}

+ (S6HTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(S6HTTPCompletion)completion
{
    return [self request:@"GET" url:url headers:headers body:nil retries:1 completion:completion];
}

// What an error body says: {"message": ...}, {"error": ..., "message": ...}, {"error_description": ...}, {"errors": [{"message": ...}]}
+ (NSString *)messageFromErrorJSON:(id)json
{
    NSDictionary *d = S6Dict(json);
    if (!d) {
        NSDictionary *first = S6Dict(([S6Arr(json) count] ? [S6Arr(json) objectAtIndex:0] : nil));
        return S6Str([first objectForKey:@"error"]) ?: S6Str([first objectForKey:@"message"]);
    }
    NSString *message = S6Str([d objectForKey:@"message"]);
    if (!message.length) message = S6Str([d objectForKey:@"error_description"]);
    if (!message.length) message = S6Str([S6Dict(([S6Arr([d objectForKey:@"errors"]) count] ? [S6Arr([d objectForKey:@"errors"]) objectAtIndex:0] : nil)) objectForKey:@"message"]);
    if (!message.length && [[d objectForKey:@"error"] isKindOfClass:[NSString class]]) message = [d objectForKey:@"error"];
    return message.length ? message : nil;
}

+ (S6HTTPCompletion)jsonHandler:(S6JSONCompletion)completion
{
    return ^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        if (!completion) return;
        if (error) { completion(nil, 0, error); return; }
        id json = [S6Utils JSONObjectFromData:body];
        if (status >= 400) {
            NSString *message = [self messageFromErrorJSON:json] ?: [NSString stringWithFormat:L(@"Request failed (HTTP %ld)."), (long)status];
            completion(json, status, S6MakeError(status, message));
            return;
        }
        if (!json && body.length) {
            completion(nil, status, S6MakeError(S6ErrorBadResponse, L(@"Unexpected response format.")));
            return;
        }
        completion(json, status, nil);
    };
}

+ (S6HTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(S6JSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: [NSDictionary dictionary]];
    if (![h objectForKey:@"Accept"]) [h setObject:@"application/json" forKey:@"Accept"];
    return [self request:@"GET" url:url headers:h body:nil retries:1 completion:[self jsonHandler:completion]];
}

+ (S6HTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(S6JSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: [NSDictionary dictionary]];
    if (![h objectForKey:@"Accept"]) [h setObject:@"application/json" forKey:@"Accept"];
    if (![h objectForKey:@"Content-Type"]) [h setObject:@"application/json" forKey:@"Content-Type"];
    NSData *body = [S6Utils JSONDataFromObject:object] ?: [NSData data];
    return [self request:@"POST" url:url headers:h body:body retries:retries completion:[self jsonHandler:completion]];
}

+ (S6HTTPTask *)postForm:(NSString *)url headers:(NSDictionary *)headers fields:(NSDictionary *)fields completion:(S6JSONCompletion)completion
{
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in fields) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", [S6Utils urlEncode:key], [S6Utils urlEncode:[[fields objectForKey:key] description]]]];
    }
    NSData *body = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: [NSDictionary dictionary]];
    if (![h objectForKey:@"Content-Type"]) [h setObject:@"application/x-www-form-urlencoded" forKey:@"Content-Type"];
    if (![h objectForKey:@"Accept"]) [h setObject:@"application/json" forKey:@"Accept"];
    return [self request:@"POST" url:url headers:h body:body retries:0 completion:[self jsonHandler:completion]];
}

+ (S6HTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(S6JSONCompletion)completion
{
    return [self postForm:url headers:nil fields:fields completion:completion];
}

@end
