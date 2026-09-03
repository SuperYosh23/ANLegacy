#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LTModel.h"

extern NSString *const LTAPIKey;
extern NSString *const LTBrowserUserAgent;

@interface LTYouTubeClient : NSObject

+ (instancetype)sharedClient;

@property (nonatomic, copy) NSString *visitorData;

- (void)searchWithQuery:(NSString *)query type:(NSString *)type
             completion:(void (^)(NSArray *items, NSError *error))completion;

- (void)searchVideosWithQuery:(NSString *)query
                   completion:(void (^)(NSArray *tracks, NSError *error))completion;

- (void)browseAlbum:(NSString *)browseId
         completion:(void (^)(NSDictionary *info, NSArray *tracks, NSError *error))completion;

- (void)browsePlaylist:(NSString *)browseId
            completion:(void (^)(NSDictionary *info, NSArray *tracks, NSError *error))completion;

- (void)browseArtist:(NSString *)browseId
          completion:(void (^)(NSDictionary *info, NSArray *topSongs, NSArray *albums, NSError *error))completion;

- (void)fetchTrendingSongsWithCompletion:(void (^)(NSArray *tracks, NSError *error))completion;

- (void)streamURLForVideo:(NSString *)videoId
               completion:(void (^)(NSString *streamURL, BOOL muxedStream, NSInteger audioBitrateKbps, NSError *error))completion;

- (void)trackMetadataForVideoId:(NSString *)videoId
                     completion:(void (^)(NSString *title, NSString *artist, NSTimeInterval duration, NSString *thumbnailURL, NSError *error))completion;

- (void)loadImageWithURL:(NSString *)urlString
              completion:(void (^)(UIImage *image))completion;

- (NSString *)highResThumbnailURL:(NSString *)urlString;

@end
