#import <Foundation/Foundation.h>
#import "LTWebServer.h"

@class LTTrack;

// The native half of the web app's backend.
//
// The desktop app talks to a Flask server with a handful of JSON routes. On the
// phone the same routes are answered here, backed by LTYouTubeClient, so the
// web bundle runs unmodified.
//
// Track shapes match what the desktop backend returns, because the web app's
// own mappers (toSong / toAlbum) expect that shape.
@interface LTWebAPI : NSObject <LTWebAPIResponding, LTWebFileResponding>

// Answers a request. Returns the JSON body; `status` receives the HTTP status.
- (NSData *)handleMethod:(NSString *)method
                    path:(NSString *)path
                   query:(NSString *)query
                    body:(NSData *)body
                  status:(NSInteger *)status;

// The shape a track is presented in.
+ (NSDictionary *)dictionaryForTrack:(LTTrack *)track;

// The bytes of a downloaded track, for the /audio/<videoId> route.
+ (NSData *)audioFileDataForVideoId:(NSString *)videoId;

@end
