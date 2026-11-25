#import <Foundation/Foundation.h>

extern NSString * const S6ConnectDidChangeNotification;   // main thread: registered, active, a command arrived

// Spotify Connect: this device shows up in the Spotify apps of the account (phone, computer) as "Sixify (iPad)". They
// can hand their playback over to it and control it - play, pause, skip, seek, shuffle, repeat, the queue, the volume -
// and they see what it plays (music started here shows there too). Spotify's push channel (the "dealer" websocket)
// brings the commands; the device's state goes to the connect-state service, as JSON.
@interface S6Connect : NSObject

+ (instancetype)shared;

- (void)start;     // starts by itself once the session is ready; stops on logout
- (void)stop;

@property (atomic, readonly) BOOL registered;              // in the account's device list
@property (atomic, readonly) BOOL active;                  // the account's playback is here
@property (atomic, readonly, copy) NSString *controller;   // the name of the device that sent the last command
@property (atomic, readonly, copy) NSString *lastEvent;

- (NSString *)debugState;
// Debug: a command sent to this device through Spotify, as another device would ({endpoint: "pause"...})
- (void)debugSendCommand:(NSDictionary *)command;

@end
