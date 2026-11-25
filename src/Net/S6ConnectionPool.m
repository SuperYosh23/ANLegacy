#import "S6ConnectionPool.h"
#import "S6TLSSocket.h"
#import "S6Common.h"

static const NSTimeInterval S6IdleTimeout = 25;     // most servers drop idle connections after 5 to 60 s
static const NSUInteger S6MaxIdlePerKey = 6;
static const NSUInteger S6MaxIdleTotal = 24;

@interface S6PooledConnection : NSObject
@property (nonatomic, strong) S6TLSSocket *socket;
@property (nonatomic) NSTimeInterval lastUsed;
@end

@implementation S6PooledConnection
@end

@implementation S6ConnectionPool {
    NSMutableDictionary *_idle;     // key -> NSMutableArray<S6PooledConnection>
    NSUInteger _count;
    NSUInteger _reuses;
}

+ (instancetype)shared
{
    static S6ConnectionPool *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = [[S6ConnectionPool alloc] init]; });
    return pool;
}

- (instancetype)init
{
    self = [super init];
    if (self) _idle = [NSMutableDictionary dictionary];
    return self;
}

// Must be called with the lock held. Moves expired connections into `dead`.
- (void)pruneLocked:(NSMutableArray *)dead
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableArray *emptyKeys = [NSMutableArray array];
    for (NSString *key in _idle) {
        NSMutableArray *list = [_idle objectForKey:key];
        for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
            S6PooledConnection *c = [list objectAtIndex:(NSUInteger)i];
            if (now - c.lastUsed > S6IdleTimeout) {
                [dead addObject:c.socket];
                [list removeObjectAtIndex:(NSUInteger)i];
                _count--;
            }
        }
        if (!list.count) [emptyKeys addObject:key];
    }
    [_idle removeObjectsForKeys:emptyKeys];
}

- (S6TLSSocket *)checkoutSocketForKey:(NSString *)key
{
    if (!key) return nil;
    NSMutableArray *dead = [NSMutableArray array];
    S6TLSSocket *result = nil;
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = [_idle objectForKey:key];
        while (list.count && !result) {
            S6PooledConnection *c = [list lastObject];
            [list removeLastObject];
            _count--;
            if ([c.socket isLikelyAlive]) result = c.socket;
            else [dead addObject:c.socket];
        }
        if (result) _reuses++;
    }
    for (S6TLSSocket *s in dead) [s close];
    return result;
}

- (void)checkinSocket:(S6TLSSocket *)socket forKey:(NSString *)key
{
    if (!socket || !key) return;
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = [_idle objectForKey:key];
        if (!list) {
            list = [NSMutableArray array];
            [_idle setObject:list forKey:key];
        }
        if (list.count >= S6MaxIdlePerKey || _count >= S6MaxIdleTotal) {
            [dead addObject:socket];
        } else {
            S6PooledConnection *c = [[S6PooledConnection alloc] init];
            c.socket = socket;
            c.lastUsed = [NSDate timeIntervalSinceReferenceDate];
            [list addObject:c];
            _count++;
        }
    }
    for (S6TLSSocket *s in dead) [s close];
}

- (void)drain
{
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        for (NSString *key in _idle) {
            for (S6PooledConnection *c in [_idle objectForKey:key]) [dead addObject:c.socket];
        }
        [_idle removeAllObjects];
        _count = 0;
    }
    for (S6TLSSocket *s in dead) [s close];
    if (dead.count) S6Log(@"Connection pool drained (%lu closed)", (unsigned long)dead.count);
}

- (NSUInteger)idleCount
{
    @synchronized (self) { return _count; }
}

- (NSUInteger)reuseCount
{
    @synchronized (self) { return _reuses; }
}

@end
