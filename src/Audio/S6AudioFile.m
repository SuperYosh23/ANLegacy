#import "S6AudioFile.h"
#import "S6HTTPRequest.h"
#import "S6Crypto.h"
#import "S6Tokens.h"
#import "S6Settings.h"
#import "S6Common.h"

static const NSUInteger S6MaxAudioFile = 64 * 1024 * 1024;

@interface S6AudioFile ()
@property (atomic) NSUInteger length;
@property (atomic) NSUInteger available;
@property (atomic) BOOL finished;
@property (atomic, strong) NSError *error;
@end

@implementation S6AudioFile {
    NSArray *_urls;
    NSData *_key;
    uint8_t *_buffer;
    NSCondition *_condition;
    BOOL _cancelled;
    S6HTTPRequest *_request;
}

- (instancetype)initWithURLs:(NSArray *)urls key:(NSData *)key
{
    if ((self = [super init])) {
        _urls = [urls copy];
        _key = [key copy];
        _condition = [[NSCondition alloc] init];
    }
    return self;
}

- (void)dealloc
{
    free(_buffer);
}

- (const uint8_t *)bytes { return _buffer; }

- (void)start
{
    NSThread *t = [[NSThread alloc] initWithTarget:self selector:@selector(download) object:nil];
    t.name = @"S6AudioFile";
    [t start];
}

- (void)cancel
{
    [_condition lock];
    _cancelled = YES;
    S6HTTPRequest *r = _request;
    [_condition broadcast];
    [_condition unlock];
    [r cancel];
}

- (BOOL)waitForBytes:(NSUInteger)end timeout:(NSTimeInterval)timeout
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    [_condition lock];
    while (self.available < end && !self.finished && !_cancelled) {
        if (![_condition waitUntilDate:until]) break;
    }
    BOOL ok = self.available >= end;
    [_condition unlock];
    return ok;
}

- (void)finishWithError:(NSError *)error
{
    [_condition lock];
    self.error = error;
    self.finished = YES;
    [_condition broadcast];
    [_condition unlock];
}

- (void)download
{
    @autoreleasepool {
        NSError *last = nil;
        NSUInteger urlIndex = 0;
        for (int attempt = 0; attempt < 6 && !_cancelled; attempt++) {
            NSString *u = _urls.count ? [_urls objectAtIndex:(urlIndex % _urls.count)] : nil;
            NSURL *url = u ? [NSURL URLWithString:u] : nil;
            if (!url) break;
            NSError *error = nil;
            if ([self fetchFrom:url error:&error]) {
                [self finishWithError:nil];
                return;
            }
            if (_cancelled) break;
            last = error;
            S6Log(@"audio download from %@ broke off at %lu of %lu: %@", url.host, (unsigned long)self.available, (unsigned long)self.length, error.localizedDescription);
            if (attempt % 2 == 1) urlIndex++;   // (each address gets a second chance first)
            usleep(300000);
        }
        [self finishWithError:_cancelled ? S6MakeError(S6ErrorCancelled, L(@"Cancelled")) : (last ?: S6MakeError(S6ErrorPlayback, L(@"The song could not be downloaded.")))];
    }
}

// One request from where the file stands; YES when the file is complete
- (BOOL)fetchFrom:(NSURL *)url error:(NSError **)error
{
    NSUInteger offset = self.available;
    if (self.length && offset >= self.length) return YES;
    S6HTTPRequest *r = [[S6HTTPRequest alloc] initWithMethod:@"GET" URL:url];
    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:@{ @"User-Agent": S6UserAgent }];
    if (offset) [headers setObject:[NSString stringWithFormat:@"bytes=%lu-", (unsigned long)offset] forKey:@"Range"];
    r.headers = headers;
    r.verifyTLS = [S6Settings verifyTLS];
    r.noCompression = YES;
    r.highPriority = YES;
    r.connectTimeout = 15;
    r.readTimeout = 20;
    S6AudioDecrypt *decrypt = [[S6AudioDecrypt alloc] initWithKey:_key offset:offset];
    __block NSInteger status = 0;
    __block BOOL bad = NO;
    __unsafe_unretained S6AudioFile *weakSelf = self;
    __unsafe_unretained S6HTTPRequest *weakRequest = r;
    r.onHeaders = ^(NSInteger s, NSDictionary *h) {
        S6AudioFile *me = weakSelf;
        status = s;
        if (!me || (s != 200 && s != 206)) { bad = YES; [weakRequest cancel]; return; }
        if (s == 200 && offset) { bad = YES; [weakRequest cancel]; return; }   // (the range was ignored)
        NSUInteger total = 0;
        NSString *range = [h objectForKey:@"content-range"];   // "bytes 1000-9999/10000"
        NSRange slash = [range rangeOfString:@"/"];
        if (slash.location != NSNotFound) total = (NSUInteger)[[range substringFromIndex:slash.location + 1] longLongValue];
        if (!total) total = (NSUInteger)[[h objectForKey:@"content-length"] longLongValue] + offset;
        [me prepareForLength:total];
        if (!me->_buffer) { bad = YES; [weakRequest cancel]; }
    };
    r.onData = ^(NSData *chunk) {
        S6AudioFile *me = weakSelf;
        if (!me || bad || me->_cancelled) { [weakRequest cancel]; return; }
        [me appendChunk:chunk decrypt:decrypt];
    };
    __block NSError *failure = nil;
    r.onComplete = ^(NSError *e) { failure = e; };
    [_condition lock];
    if (_cancelled) { [_condition unlock]; return NO; }
    _request = r;
    [_condition unlock];
    [r runSynchronously];
    [_condition lock];
    _request = nil;
    [_condition unlock];
    if (self.length && self.available >= self.length) return YES;
    if (error) *error = failure ?: S6MakeError(status >= 400 ? status : S6ErrorConnectionLost,
                                               status >= 400 ? [NSString stringWithFormat:@"CDN: HTTP %ld", (long)status] : L(@"The download broke off."));
    return NO;
}

- (void)prepareForLength:(NSUInteger)total
{
    [_condition lock];
    if (!_buffer && total > 0 && total <= S6MaxAudioFile) {
        _buffer = malloc(total);
        self.length = total;
    }
    [_condition unlock];
}

- (void)appendChunk:(NSData *)chunk decrypt:(S6AudioDecrypt *)decrypt
{
    NSUInteger at = self.available;
    NSUInteger n = chunk.length;
    if (!_buffer || at + n > self.length) n = self.length > at ? self.length - at : 0;
    if (!n) return;
    memcpy(_buffer + at, chunk.bytes, n);
    [decrypt decrypt:_buffer + at length:n];
    [_condition lock];
    self.available = at + n;
    [_condition broadcast];
    [_condition unlock];
}

@end
