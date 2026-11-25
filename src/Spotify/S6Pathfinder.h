#import <Foundation/Foundation.h>

// Spotify's own GraphQL API (api-partner.spotify.com/pathfinder), the one the desktop and web clients browse with:
// home, search, albums, artists, playlists, the library. Persisted queries: an operation's name and the hash of its
// text, as the web player of October 2026 sends them. (The public Web API answers this client id with "too many
// requests": every librespot-based app shares its quota.)
@interface S6Pathfinder : NSObject

+ (NSString *)hashFor:(NSString *)operation;

// Blocking: the response body as it came (for the debug commands)
+ (NSData *)rawQuery:(NSString *)operation hash:(NSString *)hash variables:(id)variables platform:(NSString *)platform
              status:(NSInteger *)status error:(NSError **)error;

// Blocking: the "data" object of the answer; a GraphQL error becomes the NSError
+ (NSDictionary *)query:(NSString *)operation variables:(NSDictionary *)variables error:(NSError **)error;

// The same in the background, the completion on the main thread
+ (void)query:(NSString *)operation variables:(NSDictionary *)variables completion:(void (^)(NSDictionary *data, NSError *error))completion;

@end
