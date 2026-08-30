#import <Foundation/Foundation.h>

@interface LTWebExporter : NSObject

+ (instancetype)sharedExporter;

// Packages the given playlists (LTLocalPlaylist identifier strings) into a
// self-contained, offline AN Mini web player under <base>/web-export/.
// Any track missing cached artwork is fetched from its thumbnail URL first.
// completion is called on the main thread.
- (void)exportWithSelectedPlaylists:(NSArray *)playlistIdentifiers
                         completion:(void (^)(NSString *outDirectory, NSError *error))completion;

@end
