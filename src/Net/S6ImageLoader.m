#import "S6ImageLoader.h"
#import <objc/message.h>
#import "S6HTTP.h"
#import "S6Utils.h"
#import "S6Common.h"
#import <ImageIO/ImageIO.h>

NSString * const S6ImageDidLoadNotification = @"S6ImageDidLoadNotification";

static const NSUInteger S6MaxImageFileBytes = 6 * 1024 * 1024;
static const NSInteger S6MaxConcurrentLoads = 4;
static const NSTimeInterval S6FailureRetryInterval = 45;          // a failed image is asked for again after this
static const NSTimeInterval S6DiskMaxAge = 10 * 86400.0;
static const unsigned long long S6DiskMaxBytes = 120ULL * 1024 * 1024;
static const NSUInteger S6MaxAnimationEntries = 600;              // frames after spreading unequal delays

#pragma mark - Decoding (any thread)

// A bitmap copy of the image: decoded now, on this thread, instead of at the first draw on the main thread.
static CGImageRef S6CreateDecodedImage(CGImageRef source)
{
    size_t w = CGImageGetWidth(source), h = CGImageGetHeight(source);
    if (w == 0 || h == 0 || w > 8192 || h > 8192) return NULL;
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(source);
    BOOL opaque = alpha == kCGImageAlphaNone || alpha == kCGImageAlphaNoneSkipFirst || alpha == kCGImageAlphaNoneSkipLast;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo info = (CGBitmapInfo)(kCGBitmapByteOrder32Little | (opaque ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst));
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, space, info);
    CGColorSpaceRelease(space);
    if (!ctx) return NULL;
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), source);
    CGImageRef result = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return result;
}

static NSInteger S6GCD(NSInteger a, NSInteger b)
{
    while (b != 0) { NSInteger t = a % b; a = b; b = t; }
    return a;
}

// Every frame of a GIF as one animated image; nil when the frames would take more than `budget` bytes.
static UIImage *S6AnimatedImage(CGImageSourceRef source, size_t count, NSUInteger budget, NSUInteger *costOut)
{
    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray *delays = [NSMutableArray arrayWithCapacity:count];   // hundredths of a second
    NSUInteger bytes = 0;
    for (size_t i = 0; i < count; i++) {
        @autoreleasepool {
            CGImageRef raw = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (!raw) continue;
            CGImageRef decoded = S6CreateDecodedImage(raw);
            CGImageRelease(raw);
            if (!decoded) continue;
            NSUInteger frameBytes = CGImageGetBytesPerRow(decoded) * CGImageGetHeight(decoded);
            bytes += frameBytes;
            if (i == 0 && frameBytes * count > budget) {
                CGImageRelease(decoded);
                return nil;
            }
            [frames addObject:[UIImage imageWithCGImage:decoded scale:1.0 orientation:UIImageOrientationUp]];
            CGImageRelease(decoded);
            double delay = 0.1;
            CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
            if (props) {
                NSDictionary *gif = S6Dict([(__bridge NSDictionary *)props objectForKey:(__bridge NSString *)kCGImagePropertyGIFDictionary]);
                NSNumber *n = [gif objectForKey:(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime];
                if (![n isKindOfClass:[NSNumber class]] || n.doubleValue <= 0) n = [gif objectForKey:(__bridge NSString *)kCGImagePropertyGIFDelayTime];
                if ([n isKindOfClass:[NSNumber class]] && n.doubleValue > 0) delay = n.doubleValue;
                CFRelease(props);
            }
            if (delay < 0.011) delay = 0.1;   // (as browsers do: "as fast as possible" means a tenth of a second)
            [delays addObject:@((NSInteger)lrint(delay * 100.0))];
        }
    }
    if (frames.count < 2) return nil;
    NSInteger gcd = 0, total = 0;
    for (NSNumber *d in delays) {
        gcd = gcd == 0 ? d.integerValue : S6GCD(gcd, d.integerValue);
        total += d.integerValue;
    }
    if (gcd < 1) gcd = 1;
    NSArray *sequence = frames;
    if ((NSUInteger)(total / gcd) <= S6MaxAnimationEntries && (NSUInteger)(total / gcd) != frames.count) {
        // UIImage shows every entry for the same time: a frame that stays longer is entered several times
        NSMutableArray *spread = [NSMutableArray arrayWithCapacity:(NSUInteger)(total / gcd)];
        for (NSUInteger i = 0; i < frames.count; i++) {
            NSInteger repeat = [[delays objectAtIndex:i] integerValue] / gcd;
            for (NSInteger k = 0; k < repeat; k++) [spread addObject:[frames objectAtIndex:i]];
        }
        if (spread.count) sequence = spread;
    }
    if (costOut) *costOut = bytes;
    if ([UIImage respondsToSelector:@selector(animatedImageWithImages:duration:)]) return ((UIImage *(*)(id,SEL,id,NSTimeInterval))objc_msgSend)([UIImage class], @selector(animatedImageWithImages:duration:), sequence, total / 100.0);
    return [sequence count] ? [sequence objectAtIndex:0] : nil;
}

static UIImage *S6DecodeImage(NSData *data, CGFloat maxPixels, BOOL animate, NSUInteger animationBudget, NSUInteger *costOut)
{
    if (!data.length) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    UIImage *result = nil;
    size_t count = CGImageSourceGetCount(source);
    if (count > 1 && animate) result = S6AnimatedImage(source, count, animationBudget, costOut);
    if (!result && count > 0) {
        CGFloat limit = maxPixels > 0 ? maxPixels : 1024;
        CGImageRef image = NULL;
        CGImageRef raw = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        if (raw && (CGFloat)MAX(CGImageGetWidth(raw), CGImageGetHeight(raw)) > limit) {
            NSDictionary *options = @{
                (__bridge id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @(limit),
                (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES,
            };
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        } else if (raw) {
            image = S6CreateDecodedImage(raw);
            if (!image) image = CGImageRetain(raw);
        }
        if (raw) CGImageRelease(raw);
        if (image) {
            if (costOut) *costOut = CGImageGetBytesPerRow(image) * CGImageGetHeight(image);
            result = [UIImage imageWithCGImage:image scale:1.0 orientation:UIImageOrientationUp];
            CGImageRelease(image);
        }
    }
    CFRelease(source);
    return result;
}

#pragma mark - Bookkeeping

@interface S6ImageToken : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) void (^completion)(UIImage *image);
@end

@implementation S6ImageToken
@end

@interface S6ImageJob : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic) CGFloat maxPixels;
@property (nonatomic, strong) NSMutableArray *tokens;
@property (nonatomic) BOOL notify;      // somebody asked through -imageForURL:
@property (nonatomic) BOOL started;
@end

@implementation S6ImageJob
@end

@interface S6ImageLoader ()
@property (nonatomic, strong) NSCache *memory;
@property (nonatomic, strong) NSMutableDictionary *jobs;      // url -> S6ImageJob
@property (nonatomic, strong) NSMutableArray *queue;          // jobs not started yet, the newest last
@property (nonatomic, strong) NSMutableDictionary *failed;    // url -> NSDate
@property (nonatomic) NSInteger running;
@property (nonatomic, assign) dispatch_queue_t workQueue;
@property (nonatomic, copy) NSString *directory;
@end

@implementation S6ImageLoader

+ (instancetype)shared
{
    static S6ImageLoader *loader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ loader = [[S6ImageLoader alloc] init]; });
    return loader;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _memory = [[NSCache alloc] init];
        _memory.totalCostLimit = ([S6Utils physicalMemoryMB] >= 400 ? 24 : 10) * 1024 * 1024;
        _jobs = [NSMutableDictionary dictionary];
        _queue = [NSMutableArray array];
        _failed = [NSMutableDictionary dictionary];
        _animationAllowed = YES;
        self.workQueue = dispatch_queue_create("com.samcejko.sixify.images", NULL /* was DISPATCH_QUEUE_CONCURRENT */);
        _directory = [[S6Utils cachesPath] stringByAppendingPathComponent:@"images"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (NSString *)pathForURL:(NSString *)url
{
    return [self.directory stringByAppendingPathComponent:[S6Utils sha1:url]];
}

- (NSUInteger)animationBudget
{
    return ([S6Utils physicalMemoryMB] >= 400 ? 4 : 2) * 1024 * 1024;
}

#pragma mark - Lookup

- (UIImage *)cachedImageForURL:(NSString *)url
{
    return url.length ? [self.memory objectForKey:url] : nil;
}

- (BOOL)hasFailed:(NSString *)url
{
    NSDate *when = url.length ? [self.failed objectForKey:url] : nil;
    if (!when) return NO;
    if (-[when timeIntervalSinceNow] > S6FailureRetryInterval) {
        [self.failed removeObjectForKey:url];
        return NO;
    }
    return YES;
}

- (S6ImageJob *)jobForURL:(NSString *)url maxPixels:(CGFloat)maxPixels
{
    S6ImageJob *job = [self.jobs objectForKey:url];
    if (!job) {
        job = [[S6ImageJob alloc] init];
        job.url = url;
        job.maxPixels = maxPixels;
        job.tokens = [NSMutableArray array];
        [self.jobs setObject:job forKey:url];
        [self.queue addObject:job];
    } else if (!job.started) {
        // asked for again: to the front of the line
        [self.queue removeObjectIdenticalTo:job];
        [self.queue addObject:job];
    }
    return job;
}

- (UIImage *)imageForURL:(NSString *)url
{
    if (!url.length) return nil;
    UIImage *image = [self.memory objectForKey:url];
    if (image) return image;
    if ([self hasFailed:url]) return nil;
    S6ImageJob *job = [self jobForURL:url maxPixels:0];
    job.notify = YES;
    [self pump];
    return nil;
}

- (id)loadImage:(NSString *)url maxPixels:(CGFloat)maxPixels completion:(void (^)(UIImage *))completion
{
    if (!url.length) {
        if (completion) completion(nil);
        return nil;
    }
    UIImage *image = [self.memory objectForKey:url];
    if (image || [self hasFailed:url]) {
        if (completion) completion(image);
        return nil;
    }
    S6ImageJob *job = [self jobForURL:url maxPixels:maxPixels];
    S6ImageToken *token = [[S6ImageToken alloc] init];
    token.url = url;
    token.completion = completion;
    [job.tokens addObject:token];
    [self pump];
    return token;
}

- (void)cancelToken:(id)token
{
    if (![token isKindOfClass:[S6ImageToken class]]) return;
    S6ImageToken *t = token;
    t.completion = nil;
    S6ImageJob *job = t.url ? [self.jobs objectForKey:t.url] : nil;
    if (!job) return;
    [job.tokens removeObjectIdenticalTo:t];
    if (!job.started && !job.notify && job.tokens.count == 0) {
        [self.queue removeObjectIdenticalTo:job];
        [self.jobs removeObjectForKey:job.url];
    }
}

#pragma mark - Loading

- (void)pump
{
    while (self.running < S6MaxConcurrentLoads && self.queue.count) {
        S6ImageJob *job = [self.queue lastObject];
        [self.queue removeLastObject];
        job.started = YES;
        self.running++;
        [self startJob:job];
    }
}

- (void)startJob:(S6ImageJob *)job
{
    NSString *url = job.url;
    NSString *path = [self pathForURL:url];
    CGFloat maxPixels = job.maxPixels;
    BOOL animate = self.animationAllowed;
    NSUInteger budget = [self animationBudget];
    dispatch_async(self.workQueue, ^{
        @autoreleasepool {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSUInteger cost = 0;
            UIImage *image = data.length ? S6DecodeImage(data, maxPixels, animate, budget, &cost) : nil;
            if (image) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self finishJob:job image:image cost:cost]; });
                return;
            }
            if (data) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];   // (unreadable: fetched again)
            dispatch_async(dispatch_get_main_queue(), ^{ [self downloadJob:job path:path]; });
        }
    });
}

- (void)downloadJob:(S6ImageJob *)job path:(NSString *)path
{
    CGFloat maxPixels = job.maxPixels;
    BOOL animate = self.animationAllowed;
    NSUInteger budget = [self animationBudget];
    NSDictionary *headers = @{ @"Accept": @"image/png,image/gif,image/jpeg,image/*;q=0.8,*/*;q=0.5" };
    [S6HTTP get:job.url headers:headers completion:^(NSInteger status, NSData *body, NSDictionary *responseHeaders, NSError *error) {
        if (error || status != 200 || body.length == 0 || body.length > S6MaxImageFileBytes) {
            [self finishJob:job image:nil cost:0];
            return;
        }
        dispatch_async(self.workQueue, ^{
            @autoreleasepool {
                NSUInteger cost = 0;
                UIImage *image = S6DecodeImage(body, maxPixels, animate, budget, &cost);
                if (image) [body writeToFile:path atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{ [self finishJob:job image:image cost:cost]; });
            }
        });
    }];
}

- (void)finishJob:(S6ImageJob *)job image:(UIImage *)image cost:(NSUInteger)cost
{
    self.running--;
    if ([self.jobs objectForKey:job.url] == job) [self.jobs removeObjectForKey:job.url];
    if (image) {
        [self.memory setObject:image forKey:job.url cost:MAX(cost, (NSUInteger)1024)];
        [self.failed removeObjectForKey:job.url];
    } else {
        [self.failed setObject:[NSDate date] forKey:job.url];
    }
    for (S6ImageToken *token in [job.tokens copy]) {
        void (^completion)(UIImage *) = token.completion;
        token.completion = nil;
        if (completion) completion(image);
    }
    if (job.notify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:S6ImageDidLoadNotification object:self userInfo:@{ @"url": job.url }];
    }
    [self pump];
}

#pragma mark - Housekeeping

- (void)clearMemory
{
    [self.memory removeAllObjects];
}

- (void)clearDiskWithCompletion:(dispatch_block_t)completion
{
    [self clearMemory];
    [self.failed removeAllObjects];
    NSString *dir = self.directory;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *fm = [[NSFileManager alloc] init];
        [fm removeItemAtPath:dir error:NULL];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

- (void)diskUsage:(void (^)(unsigned long long))completion
{
    NSString *dir = self.directory;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *fm = [[NSFileManager alloc] init];
        unsigned long long total = 0;
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            total += [[fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL] fileSize];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(total); });
    });
}

- (void)pruneDisk
{
    NSString *dir = self.directory;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = [[NSFileManager alloc] init];
            NSMutableArray *files = [NSMutableArray array];   // @[date, size, path]
            unsigned long long total = 0;
            NSDate *now = [NSDate date];
            NSUInteger removed = 0;
            for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
                NSString *path = [dir stringByAppendingPathComponent:name];
                NSDictionary *attributes = [fm attributesOfItemAtPath:path error:NULL];
                NSDate *modified = [attributes fileModificationDate] ?: now;
                if ([now timeIntervalSinceDate:modified] > S6DiskMaxAge) {
                    [fm removeItemAtPath:path error:NULL];
                    removed++;
                    continue;
                }
                total += [attributes fileSize];
                [files addObject:@[modified, @([attributes fileSize]), path]];
            }
            if (total > S6DiskMaxBytes) {
                [files sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [[a objectAtIndex:0] compare:[b objectAtIndex:0]]; }];
                for (NSArray *f in files) {
                    if (total <= S6DiskMaxBytes * 3 / 4) break;
                    [fm removeItemAtPath:[f objectAtIndex:2] error:NULL];
                    total -= MIN(total, [[f objectAtIndex:1] unsignedLongLongValue]);
                    removed++;
                }
            }
            if (removed) S6Log(@"Image cache: %lu old files removed, %@ kept", (unsigned long)removed, [S6Utils formatFileSize:total]);
        }
    });
}

@end

#pragma mark - Image view

@interface S6ImageView ()
@property (nonatomic, copy, readwrite) NSString *imageURL;
@property (nonatomic, strong) id token;
@end

@implementation S6ImageView

- (void)dealloc
{
    if (_token) [[S6ImageLoader shared] cancelToken:_token];
}

- (void)setImageURL:(NSString *)url placeholder:(UIImage *)placeholder
{
    [self setImageURL:url fallback:nil placeholder:placeholder];
}

- (void)setImageURL:(NSString *)url fallback:(NSString *)fallback placeholder:(UIImage *)placeholder
{
    S6ImageLoader *loader = [S6ImageLoader shared];
    if (self.token) {
        [loader cancelToken:self.token];
        self.token = nil;
    }
    if (!url.length) { url = fallback; fallback = nil; }
    if ([fallback isEqualToString:url]) fallback = nil;
    self.imageURL = url;
    if (!url.length) {
        self.image = placeholder;
        return;
    }
    UIImage *cached = [loader cachedImageForURL:url];
    if (cached) {
        self.image = cached;
        return;
    }
    if ([loader hasFailed:url] && fallback.length) {
        // (known not to be there: straight to the second one)
        [self setImageURL:fallback fallback:nil placeholder:placeholder];
        return;
    }
    self.image = placeholder;
    __unsafe_unretained S6ImageView *weakSelf = self;
    NSString *expected = [url copy];
    __block BOOL answered = NO;
    id token = [loader loadImage:url maxPixels:self.maxPixels completion:^(UIImage *image) {
        answered = YES;
        S6ImageView *view = weakSelf;
        if (!view || ![view.imageURL isEqualToString:expected]) return;
        view.token = nil;
        if (image) view.image = image;
        else if (fallback.length) [view setImageURL:fallback fallback:nil placeholder:placeholder];
    }];
    if (!answered) self.token = token;
}

@end
