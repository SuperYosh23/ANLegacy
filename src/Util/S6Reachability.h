#import <Foundation/Foundation.h>

// Posted on the main thread whenever the device's reachability changes.
extern NSString *const S6ReachabilityChangedNotification;

// Which way the device is online right now (asked each time, cheap)
@interface S6Reachability : NSObject
+ (BOOL)online;
+ (BOOL)onCellular;      // mobile data, not Wi-Fi
@end
