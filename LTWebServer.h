#import <Foundation/Foundation.h>

// Answers the /api routes. Implemented by LTWebAPI.
@protocol LTWebAPIResponding <NSObject>

- (NSData *)handleMethod:(NSString *)method
                    path:(NSString *)path
                   query:(NSString *)query
                    body:(NSData *)body
                  status:(NSInteger *)status;

@end

// Answers a request for a file's bytes. Implemented by LTWebAPI, which serves
// the phone's downloaded tracks.
@protocol LTWebFileResponding <NSObject>

- (NSData *)fileDataForPath:(NSString *)path;

@end

// A minimal HTTP/1.1 server on the loopback interface.
//
// WHY: the desktop app's UI is a web app that talks to a local backend over
// HTTP on 127.0.0.1. Rather than teach the web app about a native bridge, the
// phone hosts the same thing: it serves the web bundle and answers the same
// /api routes. The web app then runs completely unmodified, and localStorage
// works, because it has a real origin.
//
// Only bound to 127.0.0.1, so nothing off the device can reach it.
@interface LTWebServer : NSObject

// Starts listening. `port` is the port to bind; pass 0 to have one chosen.
// Returns NO if the socket could not be set up.
- (BOOL)startOnPort:(NSInteger)port;

// The port actually bound. Meaningless before -startOnPort: returns YES.
@property (nonatomic, assign, readonly) NSInteger port;

- (void)stop;

// Set this to answer /api requests. When nil, /api paths are 404.
@property (nonatomic, strong) id<LTWebAPIResponding> api;

// Set this to answer /audio/<videoId> requests with the bytes of a file. When
// nil, those paths are 404.
@property (nonatomic, strong) id<LTWebFileResponding> fileProvider;

// Content type for a static file, by extension. Defaults to a sane guess.
- (NSString *)contentTypeForPath:(NSString *)path;

// Directory static files are served from. Files are looked up by their path
// within it, and a path that tries to escape it is refused.
@property (nonatomic, copy) NSString *staticRoot;

@end
