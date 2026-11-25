#import <Foundation/Foundation.h>

// Spotify's own client API ("spclient": metadata, storage, lyrics, contexts, radio) as the logged-in user.
// Blocking calls for worker threads; the async ones answer on the main thread.
@interface S6SpClient : NSObject

// A request to the spclient with the user's access token and the client token; `path` starts with "/"
+ (NSData *)request:(NSString *)method path:(NSString *)path body:(NSData *)body contentType:(NSString *)contentType
             accept:(NSString *)accept status:(NSInteger *)status error:(NSError **)error;
+ (NSData *)request:(NSString *)method path:(NSString *)path body:(NSData *)body contentType:(NSString *)contentType
             accept:(NSString *)accept headers:(NSDictionary *)headers status:(NSInteger *)status error:(NSError **)error;

// The Track message (metadata.proto) of a track through the extended-metadata endpoint
+ (NSData *)trackMetadata:(NSData *)gid error:(NSError **)error;
// The Episode message of a podcast episode
+ (NSData *)episodeMetadata:(NSData *)gid error:(NSError **)error;
// Where an audio file can be downloaded (CDN addresses, valid for a while)
+ (NSArray *)cdnURLsForFile:(NSData *)fileId error:(NSError **)error;

+ (void)lyricsForTrack:(NSString *)trackId completion:(void (^)(NSDictionary *json, NSError *error))completion;
+ (void)radioForURI:(NSString *)uri completion:(void (^)(NSArray *trackURIs, NSError *error))completion;   // autoplay / "song radio"

@end
