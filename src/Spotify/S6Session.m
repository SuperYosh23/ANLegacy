#import "S6Session.h"
#import "S6AccessPoint.h"
#import "S6Proto.h"
#import "S6Crypto.h"
#import "S6Settings.h"
#import "S6Tokens.h"
#import "S6HTTPRequest.h"
#import "S6Utils.h"
#import "S6Common.h"

NSString * const S6SessionStateDidChangeNotification = @"S6SessionStateDidChangeNotification";

static const NSTimeInterval S6PongDelay = 60;          // librespot answers a Ping a minute later, as Spotify's own clients do
static const NSTimeInterval S6ReadTimeout = 150;      // no Ping for this long: the connection is gone
static const NSTimeInterval S6MaxRetryDelay = 60;

@interface S6PendingKey : NSObject
@property (nonatomic, assign) dispatch_semaphore_t done;
@property (nonatomic, strong) NSData *key;
@property (nonatomic, strong) NSError *error;
@end
@implementation S6PendingKey
@end

@interface S6PendingMercury : NSObject
@property (nonatomic, assign) dispatch_semaphore_t done;
@property (nonatomic, strong) NSMutableArray *parts;
@property (nonatomic, strong) NSData *partial;
@property (nonatomic) NSInteger status;
@property (nonatomic, strong) NSArray *result;
@property (nonatomic, strong) NSError *error;
@end
@implementation S6PendingMercury
@end

@interface S6Session ()
@property (atomic) S6SessionState state;
@property (atomic, strong) NSError *lastError;
@property (atomic, copy) NSString *username;
@property (atomic, copy) NSString *country;
@property (atomic, copy) NSDictionary *attributes;
@property (atomic, copy) NSString *spclientHost;
@property (atomic, copy) NSString *dealerHost;
@end

@implementation S6Session {
    dispatch_queue_t _queue;               // connecting and logging in, one thing at a time
    S6AccessPoint *_ap;
    NSUInteger _generation;                // a new number for every connection; old readers and timers stop
    NSMutableDictionary *_pendingKeys;     // @(seq) -> S6PendingKey
    NSMutableDictionary *_pendingMercury;  // 8-byte seq -> S6PendingMercury
    uint32_t _keySeq;
    uint64_t _mercurySeq;
    NSArray *_accessPoints;                // "host:port", in Spotify's order of preference
    NSUInteger _apIndex;
    NSTimeInterval _retryDelay;
    BOOL _retryScheduled;
    NSCondition *_stateCondition;
}

+ (instancetype)shared
{
    static S6Session *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ session = [[S6Session alloc] init]; });
    return session;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.samcejko.sixify.session", DISPATCH_QUEUE_SERIAL);
        _pendingKeys = [NSMutableDictionary dictionary];
        _pendingMercury = [NSMutableDictionary dictionary];
        _stateCondition = [[NSCondition alloc] init];
        _retryDelay = 2;
        self.username = [S6Settings username];
        // (with an account the app starts as connecting: "logged out" would flash the login screen at every launch)
        self.state = [S6Settings hasAccount] ? S6SessionStateConnecting : S6SessionStateLoggedOut;
    }
    return self;
}

- (BOOL)premium { return [[[self.attributes objectForKey:@"type"] description] isEqualToString:@"premium"]; }

- (void)setStateAndNotify:(S6SessionState)state error:(NSError *)error
{
    [_stateCondition lock];
    self.state = state;
    if (error || state == S6SessionStateReady) self.lastError = error;
    [_stateCondition broadcast];
    [_stateCondition unlock];
    S6Log(@"session: %@%@", [self stateName:state], error ? [NSString stringWithFormat:@" (%@)", error.localizedDescription] : @"");
    S6Main(^{ [[NSNotificationCenter defaultCenter] postNotificationName:S6SessionStateDidChangeNotification object:self]; });
}

- (NSString *)stateName:(S6SessionState)s
{
    switch (s) {
        case S6SessionStateLoggedOut: return @"logged out";
        case S6SessionStateConnecting: return @"connecting";
        case S6SessionStateReady: return @"ready";
        case S6SessionStateOffline: return @"offline";
        case S6SessionStateFailed: return @"login refused";
    }
    return @"?";
}

#pragma mark - Connecting

- (void)start
{
    dispatch_async(_queue, ^{ [self connectIfNeeded]; });
}

- (void)reconnectSoon
{
    dispatch_async(_queue, ^{
        if (self.state != S6SessionStateReady || !self->_ap.connected) [self connectIfNeeded];
    });
}

- (void)loginWithUsername:(NSString *)username authType:(NSInteger)authType authData:(NSData *)authData
{
    dispatch_async(_queue, ^{
        [self dropConnection];
        [[S6Tokens shared] reset];   // (the tokens belong to the account that was logged in)
        self.username = username;
        [self setStateAndNotify:S6SessionStateConnecting error:nil];
        NSError *error = nil;
        if (![self connectWithUsername:username authType:authType authData:authData error:&error]) {
            [self setStateAndNotify:[S6Settings hasAccount] ? S6SessionStateOffline : S6SessionStateFailed error:error];
            if ([S6Settings hasAccount]) [self scheduleRetry];
        }
    });
}

- (void)logout
{
    dispatch_async(_queue, ^{
        [self dropConnection];
        [S6Settings forgetAccount];
        [[S6Tokens shared] reset];
        self.username = nil;
        self.attributes = nil;
        [self setStateAndNotify:S6SessionStateLoggedOut error:nil];
    });
}

// (on the queue)
- (void)connectIfNeeded
{
    if (![S6Settings hasAccount]) {
        if (self.state != S6SessionStateLoggedOut) [self setStateAndNotify:S6SessionStateLoggedOut error:nil];
        return;
    }
    if (self.state == S6SessionStateReady && _ap.connected) return;
    if (self.state == S6SessionStateFailed) return;   // (a refused login waits for a new one)
    [self setStateAndNotify:S6SessionStateConnecting error:nil];
    NSError *error = nil;
    if ([self connectWithUsername:[S6Settings username] authType:[S6Settings authType] authData:[S6Settings authData] error:&error]) return;
    if (error.code == S6ErrorAuth) {
        [self setStateAndNotify:S6SessionStateFailed error:error];
        return;
    }
    [self setStateAndNotify:S6SessionStateOffline error:error];
    [self scheduleRetry];
}

- (void)scheduleRetry
{
    if (_retryScheduled) return;
    _retryScheduled = YES;
    NSTimeInterval delay = _retryDelay;
    _retryDelay = MIN(S6MaxRetryDelay, _retryDelay * 2);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _queue, ^{
        self->_retryScheduled = NO;
        [self connectIfNeeded];
    });
}

// apresolve: the access points, dealers and spclients Spotify wants this client to use (on the queue)
- (void)resolveAccessPoints
{
    NSURL *url = [NSURL URLWithString:@"https://apresolve.spotify.com/?type=accesspoint&type=dealer&type=spclient"];
    S6HTTPRequest *r = [[S6HTTPRequest alloc] initWithMethod:@"GET" URL:url];
    r.verifyTLS = [S6Settings verifyTLS];
    r.connectTimeout = 10;
    r.readTimeout = 15;
    __block NSError *failure = nil;
    r.onComplete = ^(NSError *e) { failure = e; };
    [r runSynchronously];
    NSDictionary *json = failure ? nil : S6Dict([S6Utils JSONObjectFromData:r.responseBody]);
    NSArray *aps = S6Arr([json objectForKey:@"accesspoint"]);
    NSArray *spclients = S6Arr([json objectForKey:@"spclient"]);
    _accessPoints = aps.count ? aps : @[ @"ap.spotify.com:443", @"ap.spotify.com:80" ];
    _apIndex = 0;
    NSString *sp = S6Str([spclients count] ? [spclients objectAtIndex:0] : nil);
    self.spclientHost = sp.length ? sp : @"spclient.wg.spotify.com:443";
    NSArray *_dealers = S6Arr([json objectForKey:@"dealer"]); NSString *dealer = S6Str([_dealers count] ? [_dealers objectAtIndex:0] : nil);
    self.dealerHost = dealer.length ? dealer : @"dealer.spotify.com:443";
    S6Log(@"apresolve: %lu access points (%@ first), spclient %@%@", (unsigned long)_accessPoints.count, ([_accessPoints count] ? [_accessPoints objectAtIndex:0] : nil),
          self.spclientHost, failure ? [NSString stringWithFormat:@" (fallback: %@)", failure.localizedDescription] : @"");
}

- (void)dropConnection
{
    @synchronized (self) {
        _generation++;
        [_ap close];
        _ap = nil;
    }
    [self failPending:S6MakeError(S6ErrorConnectionLost, L(@"The connection to Spotify was closed."))];
}

- (void)failPending:(NSError *)error
{
    NSArray *keys, *mercury;
    @synchronized (self) {
        keys = [_pendingKeys allValues];
        mercury = [_pendingMercury allValues];
        [_pendingKeys removeAllObjects];
        [_pendingMercury removeAllObjects];
    }
    for (S6PendingKey *p in keys) { p.error = error; dispatch_semaphore_signal(p.done); }
    for (S6PendingMercury *p in mercury) { p.error = error; dispatch_semaphore_signal(p.done); }
}

// One login: an access point, the credentials, the welcome (on the queue)
- (BOOL)connectWithUsername:(NSString *)username authType:(NSInteger)authType authData:(NSData *)authData error:(NSError **)error
{
    if (!_accessPoints.count) [self resolveAccessPoints];
    NSError *lastError = nil;
    NSUInteger tries = MIN((NSUInteger)4, _accessPoints.count);
    for (NSUInteger attempt = 0; attempt < tries; attempt++) {
        NSString *hostPort = S6Str([_accessPoints objectAtIndex:((_apIndex + attempt) % _accessPoints.count)]) ?: @"";
        NSRange colon = [hostPort rangeOfString:@":" options:NSBackwardsSearch];
        NSString *host = colon.location == NSNotFound ? hostPort : [hostPort substringToIndex:colon.location];
        int port = colon.location == NSNotFound ? 443 : [[hostPort substringFromIndex:colon.location + 1] intValue];
        S6AccessPoint *ap = [[S6AccessPoint alloc] init];
        NSError *e = nil;
        if (![ap connectToHost:host port:port error:&e]) {
            S6Log(@"access point %@: %@", hostPort, e.localizedDescription);
            lastError = e;
            [ap close];
            continue;
        }
        NSInteger refusal = 0;
        if ([self loginOn:ap username:username authType:authType authData:authData refusal:&refusal error:&e]) {
            _apIndex = (_apIndex + attempt) % _accessPoints.count;
            _retryDelay = 2;
            return YES;
        }
        [ap close];
        lastError = e;
        S6Log(@"login on %@ failed: %@", hostPort, e.localizedDescription);
        if (refusal && refusal != 0x02) break;   // a real refusal (not "try another access point")
    }
    if (error) *error = lastError ?: S6MakeError(S6ErrorConnect, L(@"Spotify cannot be reached."));
    return NO;
}

- (BOOL)loginOn:(S6AccessPoint *)ap username:(NSString *)username authType:(NSInteger)authType authData:(NSData *)authData
        refusal:(NSInteger *)refusal error:(NSError **)error
{
    S6ProtoWriter *credentials = [S6ProtoWriter writer];
    [credentials string:username field:10];
    [credentials varint:(uint64_t)authType field:20];
    [credentials bytes:authData field:30];
    S6ProtoWriter *system = [S6ProtoWriter writer];
    [system varint:5 field:10];                                // cpu_family: CPU_ARM
    [system varint:5 field:60];                                // os: OS_LINUX
    [system string:@"librespot-sixify-1" field:90];             // system_information_string
    [system string:[S6Settings deviceId] field:100];           // device_id
    S6ProtoWriter *login = [S6ProtoWriter writer];
    [login message:credentials field:10];
    [login message:system field:50];
    [login string:@"librespot 0.8.0" field:70];                // version_string
    if (![ap sendPacket:S6PacketLogin payload:login.data error:error]) return NO;

    uint8_t cmd = 0;
    NSData *payload = nil;
    if (![ap receivePacket:&cmd payload:&payload error:error]) return NO;
    if (cmd == S6PacketAuthFailure) {
        uint64_t code = S6ProtoVarint(payload, 10, 0);
        if (refusal) *refusal = (NSInteger)code;
        NSString *text = code == 0x0b ? L(@"Spotify Premium is required.") :
                         code == 0x0c ? L(@"Spotify did not accept the login. Log in again from the Spotify app.") :
                         code == 0x02 ? L(@"Spotify asked to try another server.") :
                         [NSString stringWithFormat:L(@"Spotify refused the login (error %llu)."), code];
        if (error) *error = S6MakeError(code == 0x02 ? S6ErrorConnect : S6ErrorAuth, text);
        return NO;
    }
    if (cmd != S6PacketAPWelcome) {
        if (error) *error = S6MakeError(S6ErrorBadResponse, [NSString stringWithFormat:L(@"Spotify answered the login unexpectedly (0x%02x)."), cmd]);
        return NO;
    }
    NSString *canonical = S6ProtoString(payload, 10) ?: username;
    NSInteger reusableType = (NSInteger)S6ProtoVarint(payload, 30, 1);
    NSData *reusable = S6ProtoBytes(payload, 40);
    if (reusable.length) [S6Settings setUsername:canonical authType:reusableType authData:reusable];
    self.username = canonical;
    S6Log(@"logged in as %@ (on %@)", canonical, ap.host);

    [ap setReadTimeout:S6ReadTimeout];
    NSUInteger generation;
    @synchronized (self) {
        generation = ++_generation;
        _ap = ap;
    }
    NSThread *reader = [[NSThread alloc] initWithTarget:self selector:@selector(readLoop:) object:@[ @(generation), ap ]];
    reader.name = @"S6Session reader";
    [reader start];
    [self setStateAndNotify:S6SessionStateReady error:nil];
    return YES;
}

#pragma mark - Reading

- (void)readLoop:(NSArray *)args
{
    @autoreleasepool {
        NSUInteger generation = [[args objectAtIndex:0] unsignedIntegerValue];
        S6AccessPoint *ap = [args objectAtIndex:1];
        NSError *error = nil;
        while (YES) {
            @autoreleasepool {
                uint8_t cmd = 0;
                NSData *payload = nil;
                if (![ap receivePacket:&cmd payload:&payload error:&error]) break;
                @synchronized (self) { if (generation != _generation) break; }
                [self dispatchPacket:cmd payload:payload generation:generation];
            }
        }
        BOOL current;
        @synchronized (self) { current = generation == _generation; }
        if (!current) return;
        S6Log(@"session: connection lost (%@)", error.localizedDescription);
        dispatch_async(_queue, ^{
            BOOL stillCurrent;
            @synchronized (self) { stillCurrent = generation == self->_generation; }
            if (!stillCurrent) return;
            [self dropConnection];
            [self setStateAndNotify:S6SessionStateOffline error:error];
            [self connectIfNeeded];
        });
    }
}

- (void)dispatchPacket:(uint8_t)cmd payload:(NSData *)payload generation:(NSUInteger)generation
{
    switch (cmd) {
        case S6PacketPing: {
            __unsafe_unretained S6Session *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(S6PongDelay * NSEC_PER_SEC)), _queue, ^{
                S6Session *me = weakSelf;
                S6AccessPoint *ap;
                @synchronized (me) { ap = generation == me->_generation ? me->_ap : nil; }
                uint8_t zero[4] = { 0, 0, 0, 0 };
                [ap sendPacket:S6PacketPong payload:[NSData dataWithBytes:zero length:4] error:NULL];
            });
            break;
        }
        case S6PacketCountryCode:
            self.country = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
            S6Log(@"country %@", self.country);
            break;
        case S6PacketProductInfo:
            [self parseProductInfo:payload];
            break;
        case S6PacketAesKey:
        case S6PacketAesKeyError:
            [self dispatchKey:cmd payload:payload];
            break;
        case S6PacketMercuryReq:
        case S6PacketMercurySub:
        case S6PacketMercuryUnsub:
        case S6PacketMercuryEvent:
            [self dispatchMercury:cmd payload:payload];
            break;
        default:
            break;   // (Pong acks, legacy welcome, license version, secret blocks...)
    }
}

- (void)parseProductInfo:(NSData *)payload
{
    NSString *xml = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding] ?: @"";
    static NSRegularExpression *element;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ element = [NSRegularExpression regularExpressionWithPattern:@"<([A-Za-z0-9_-]+)>([^<]*)</\\1>" options:0 error:NULL]; });
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    for (NSTextCheckingResult *m in [element matchesInString:xml options:0 range:NSMakeRange(0, xml.length)]) {
        NSString *value = [[[xml substringWithRange:[m rangeAtIndex:2]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"]
                           stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
        [attributes setObject:value forKey:[xml substringWithRange:[m rangeAtIndex:1]]];
    }
    self.attributes = attributes;
    S6Log(@"product: %@, catalogue %@", [attributes objectForKey:@"type"], [attributes objectForKey:@"catalogue"]);
    S6Main(^{ [[NSNotificationCenter defaultCenter] postNotificationName:S6SessionStateDidChangeNotification object:self]; });
}

#pragma mark - Waiting

- (BOOL)waitUntilReady:(NSTimeInterval)timeout error:(NSError **)error
{
    if (self.state == S6SessionStateReady) return YES;
    if (self.state == S6SessionStateOffline) [self reconnectSoon];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    [_stateCondition lock];
    while (self.state != S6SessionStateReady && self.state != S6SessionStateLoggedOut && self.state != S6SessionStateFailed) {
        if (![_stateCondition waitUntilDate:until]) break;
    }
    S6SessionState s = self.state;
    [_stateCondition unlock];
    if (s == S6SessionStateReady) return YES;
    if (error) {
        if (s == S6SessionStateLoggedOut) *error = S6MakeError(S6ErrorNotLoggedIn, L(@"You are not logged in."));
        else *error = self.lastError ?: S6MakeError(S6ErrorConnect, L(@"Spotify cannot be reached."));
    }
    return NO;
}

#pragma mark - Audio keys

- (NSData *)audioKeyForTrack:(NSData *)gid file:(NSData *)fileId error:(NSError **)error
{
    NSError *last = nil;
    for (int attempt = 0; attempt < 3; attempt++) {
        if (![self waitUntilReady:20 error:error]) return nil;
        S6PendingKey *pending = [[S6PendingKey alloc] init];
        pending.done = dispatch_semaphore_create(0);
        uint32_t seq;
        S6AccessPoint *ap;
        @synchronized (self) {
            seq = _keySeq++;
            [_pendingKeys setObject:pending forKey:@(seq)];
            ap = _ap;
        }
        NSMutableData *request = [NSMutableData dataWithData:fileId];
        [request appendData:gid];
        uint8_t tail[6] = { (uint8_t)(seq >> 24), (uint8_t)(seq >> 16), (uint8_t)(seq >> 8), (uint8_t)seq, 0, 0 };
        [request appendBytes:tail length:6];
        NSError *sendError = nil;
        if (![ap sendPacket:S6PacketRequestKey payload:request error:&sendError]) {
            @synchronized (self) { [_pendingKeys removeObjectForKey:@(seq)]; }
            last = sendError;
            continue;
        }
        long timedOut = dispatch_semaphore_wait(pending.done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
        @synchronized (self) { [_pendingKeys removeObjectForKey:@(seq)]; }
        if (!timedOut && pending.key) return pending.key;
        last = timedOut ? S6MakeError(S6ErrorTimeout, L(@"Spotify did not hand over the song's key in time.")) : pending.error;
        S6Log(@"audio key attempt %d failed: %@", attempt + 1, last.localizedDescription);
        usleep(400000);
    }
    if (error) *error = last;
    return nil;
}

- (void)dispatchKey:(uint8_t)cmd payload:(NSData *)payload
{
    if (payload.length < 4) return;
    const uint8_t *p = payload.bytes;
    uint32_t seq = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
    S6PendingKey *pending;
    @synchronized (self) { pending = [_pendingKeys objectForKey:@(seq)]; }
    if (!pending) return;
    if (cmd == S6PacketAesKey && payload.length >= 20) {
        pending.key = [payload subdataWithRange:NSMakeRange(4, 16)];
    } else {
        unsigned code = payload.length >= 6 ? ((unsigned)p[4] << 8) | p[5] : 0;
        S6Log(@"audio key error %04x", code);
        pending.error = S6MakeError(S6ErrorPlayback, [NSString stringWithFormat:L(@"Spotify refused the song's key (error %04x)."), code]);
    }
    dispatch_semaphore_signal(pending.done);
}

#pragma mark - Mercury

static NSData *S6U16(NSUInteger v)
{
    uint8_t b[2] = { (uint8_t)(v >> 8), (uint8_t)v };
    return [NSData dataWithBytes:b length:2];
}

- (NSArray *)mercuryGet:(NSString *)uri status:(NSInteger *)status error:(NSError **)error
{
    if (![self waitUntilReady:20 error:error]) return nil;
    S6PendingMercury *pending = [[S6PendingMercury alloc] init];
    pending.done = dispatch_semaphore_create(0);
    pending.parts = [NSMutableArray array];
    uint64_t n;
    S6AccessPoint *ap;
    @synchronized (self) { n = _mercurySeq++; ap = _ap; }
    uint8_t seqBytes[8];
    for (int i = 0; i < 8; i++) seqBytes[i] = (uint8_t)(n >> (56 - 8 * i));
    NSData *seq = [NSData dataWithBytes:seqBytes length:8];
    @synchronized (self) { [_pendingMercury setObject:pending forKey:seq]; }

    S6ProtoWriter *header = [S6ProtoWriter writer];
    [header string:uri field:1];
    [header string:@"GET" field:3];
    NSData *headerBytes = header.data;
    NSMutableData *packet = [NSMutableData dataWithData:S6U16(seq.length)];
    [packet appendData:seq];
    uint8_t flags = 1;   // final
    [packet appendBytes:&flags length:1];
    [packet appendData:S6U16(1)];
    [packet appendData:S6U16(headerBytes.length)];
    [packet appendData:headerBytes];
    if (![ap sendPacket:S6PacketMercuryReq payload:packet error:error]) {
        @synchronized (self) { [_pendingMercury removeObjectForKey:seq]; }
        return nil;
    }
    long timedOut = dispatch_semaphore_wait(pending.done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)));
    @synchronized (self) { [_pendingMercury removeObjectForKey:seq]; }
    if (timedOut || pending.error) {
        if (error) *error = pending.error ?: S6MakeError(S6ErrorTimeout, L(@"Spotify did not answer in time."));
        return nil;
    }
    if (status) *status = pending.status;
    return pending.result;
}

- (void)dispatchMercury:(uint8_t)cmd payload:(NSData *)payload
{
    const uint8_t *p = payload.bytes;
    NSUInteger len = payload.length, off = 0;
    if (len < 2) return;
    NSUInteger seqLen = ((NSUInteger)p[0] << 8) | p[1];
    off = 2;
    if (off + seqLen + 3 > len) return;
    NSData *seq = [payload subdataWithRange:NSMakeRange(off, seqLen)];
    off += seqLen;
    uint8_t flags = p[off++];
    NSUInteger count = ((NSUInteger)p[off] << 8) | p[off + 1];
    off += 2;
    S6PendingMercury *pending;
    @synchronized (self) { pending = [_pendingMercury objectForKey:seq]; }
    if (!pending) return;   // (events of subscriptions: not used)
    for (NSUInteger i = 0; i < count; i++) {
        if (off + 2 > len) return;
        NSUInteger size = ((NSUInteger)p[off] << 8) | p[off + 1];
        off += 2;
        if (off + size > len) return;
        NSData *part = [payload subdataWithRange:NSMakeRange(off, size)];
        off += size;
        if (pending.partial) {
            NSMutableData *joined = [pending.partial mutableCopy];
            [joined appendData:part];
            part = joined;
            pending.partial = nil;
        }
        if (i == count - 1 && flags == 2) pending.partial = part;
        else [pending.parts addObject:part];
    }
    if (flags != 1) return;
    NSData *header = pending.parts.count ? [pending.parts objectAtIndex:0] : nil;
    pending.status = (NSInteger)S6ProtoZigzag(S6ProtoVarint(header, 4, 0));
    pending.result = pending.parts.count > 1 ? [pending.parts subarrayWithRange:NSMakeRange(1, pending.parts.count - 1)] : [NSArray array];
    if (pending.status >= 400) pending.error = S6MakeError(pending.status, [NSString stringWithFormat:L(@"Spotify answered with error %ld."), (long)pending.status]);
    dispatch_semaphore_signal(pending.done);
}

// Debug: the whole handshake with a made-up account on a separate connection. Spotify must answer with an
// AuthFailure (bad credentials); anything readable proves apresolve, Diffie-Hellman, the server's signature
// and the Shannon cipher right. Logs the result.
- (void)debugHandshakeTest
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSArray *aps = nil;
        dispatch_sync(self->_queue, ^{
            if (!self->_accessPoints.count) [self resolveAccessPoints];
            aps = self->_accessPoints;
        });
        NSString *hostPort = S6Str([aps count] ? [aps objectAtIndex:0] : nil) ?: @"ap.spotify.com:443";
        NSRange colon = [hostPort rangeOfString:@":" options:NSBackwardsSearch];
        NSString *host = colon.location == NSNotFound ? hostPort : [hostPort substringToIndex:colon.location];
        int port = colon.location == NSNotFound ? 443 : [[hostPort substringFromIndex:colon.location + 1] intValue];
        S6AccessPoint *ap = [[S6AccessPoint alloc] init];
        NSDate *start = [NSDate date];
        NSError *e = nil;
        if (![ap connectToHost:host port:port error:&e]) { S6Log(@"aptest: handshake with %@ failed: %@", hostPort, e.localizedDescription); return; }
        S6Log(@"aptest: handshake with %@ done in %.2f s", hostPort, -[start timeIntervalSinceNow]);
        S6ProtoWriter *credentials = [S6ProtoWriter writer];
        [credentials string:@"sixify-handshake-test" field:10];
        [credentials varint:0 field:20];                                   // AUTHENTICATION_USER_PASS
        [credentials bytes:[@"not-a-password" dataUsingEncoding:NSUTF8StringEncoding] field:30];
        S6ProtoWriter *system = [S6ProtoWriter writer];
        [system varint:5 field:10];
        [system varint:5 field:60];
        [system string:@"librespot-sixify-1" field:90];
        [system string:[S6Settings deviceId] field:100];
        S6ProtoWriter *login = [S6ProtoWriter writer];
        [login message:credentials field:10];
        [login message:system field:50];
        [login string:@"librespot 0.8.0" field:70];
        uint8_t cmd = 0;
        NSData *payload = nil;
        if (![ap sendPacket:S6PacketLogin payload:login.data error:&e] || ![ap receivePacket:&cmd payload:&payload error:&e]) {
            S6Log(@"aptest: login packet failed: %@", e.localizedDescription);
        } else if (cmd == S6PacketAuthFailure) {
            S6Log(@"aptest: OK - AuthFailure, error code %llu (expected 12 = bad credentials)", S6ProtoVarint(payload, 10, 0));
        } else {
            S6Log(@"aptest: unexpected answer 0x%02x (%lu bytes)", cmd, (unsigned long)payload.length);
        }
        [ap close];
    });
}

- (NSString *)debugState
{
    return [NSString stringWithFormat:@"%@ as %@, %@, country %@, ap %@, spclient %@%@", [self stateName:self.state], self.username ?: @"-",
            [self.attributes objectForKey:@"type"] ?: @"?", self.country ?: @"?", _ap.host ?: @"-", self.spclientHost ?: @"-",
            self.lastError ? [NSString stringWithFormat:@", last error: %@", self.lastError.localizedDescription] : @""];
}

@end
