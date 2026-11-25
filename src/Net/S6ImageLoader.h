#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Posted on the main thread when an image asked for with -imageForURL: has arrived (or failed); [userInfo objectForKey:@"url"].
extern NSString * const S6ImageDidLoadNotification;

// Remote images through the app's own network layer: memory cache, disk cache (Caches/images), at most a few
// downloads at a time (the newest request first: what is on screen now), decoding off the main thread.
// GIFs with several frames become animated images when animation is allowed.
// Everything here is called on the main thread.
@interface S6ImageLoader : NSObject

+ (instancetype)shared;

// The image when it is in memory, else nil and the download starts; S6ImageDidLoadNotification follows.
- (UIImage *)imageForURL:(NSString *)url;
- (UIImage *)cachedImageForURL:(NSString *)url;      // memory only, never starts a download
- (BOOL)hasFailed:(NSString *)url;

// The completion runs on the main thread, at once when the image is in memory (then nil is returned).
// The returned token cancels the interest in the image (a reused cell); a download nobody waits for is dropped
// while it is still queued. maxPixels limits the longer side of the decoded image (0 = 1024).
- (id)loadImage:(NSString *)url maxPixels:(CGFloat)maxPixels completion:(void (^)(UIImage *image))completion;
- (void)cancelToken:(id)token;

@property (nonatomic) BOOL animationAllowed;         // default YES; NO = the first frame of animated images only

- (void)clearMemory;
- (void)clearDiskWithCompletion:(dispatch_block_t)completion;
- (void)diskUsage:(void (^)(unsigned long long bytes))completion;
- (void)pruneDisk;                                   // old files out, in the background (called at launch)

@end

// An image view that shows a remote image and survives reuse: a late answer for an earlier URL is ignored.
@interface S6ImageView : UIImageView
@property (nonatomic, copy, readonly) NSString *imageURL;
@property (nonatomic) CGFloat maxPixels;
- (void)setImageURL:(NSString *)url placeholder:(UIImage *)placeholder;
// The same, with a second URL to try when the first one fails (a picture the server may not have)
- (void)setImageURL:(NSString *)url fallback:(NSString *)fallback placeholder:(UIImage *)placeholder;
@end
