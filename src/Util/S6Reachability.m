#import "S6Reachability.h"
#import "S6Common.h"
#import <CoreFoundation/CoreFoundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <netinet/in.h>

NSString *const S6ReachabilityChangedNotification = @"S6ReachabilityChangedNotification";

static void S6ReachabilityChanged(SCNetworkReachabilityRef reach,
                                  SCNetworkReachabilityFlags flags,
                                  void *info)
{
    // The ref is scheduled on the main run loop, so the callback is too.
    [[NSNotificationCenter defaultCenter] postNotificationName:S6ReachabilityChangedNotification object:nil];
}

static SCNetworkReachabilityRef S6SharedReachability(void)
{
    static SCNetworkReachabilityRef reach;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct sockaddr_in zero;
        memset(&zero, 0, sizeof(zero));
        zero.sin_len = sizeof(zero);
        zero.sin_family = AF_INET;
        reach = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&zero);
        if (reach) {
            SCNetworkReachabilityContext context = {0, NULL, NULL, NULL, NULL};
            if (SCNetworkReachabilitySetCallback(reach, S6ReachabilityChanged, &context)) {
                SCNetworkReachabilityScheduleWithRunLoop(reach, CFRunLoopGetMain(), kCFRunLoopCommonModes);
            }
        }
    });
    return reach;
}

static SCNetworkReachabilityFlags S6Flags(void)
{
    SCNetworkReachabilityRef reach = S6SharedReachability();
    SCNetworkReachabilityFlags flags = 0;
    if (!reach || !SCNetworkReachabilityGetFlags(reach, &flags)) return 0;
    return flags;
}

@implementation S6Reachability

+ (BOOL)online
{
    SCNetworkReachabilityFlags f = S6Flags();
    return (f & kSCNetworkReachabilityFlagsReachable) && !(f & kSCNetworkReachabilityFlagsConnectionRequired);
}

+ (BOOL)onCellular
{
    SCNetworkReachabilityFlags f = S6Flags();
    return (f & kSCNetworkReachabilityFlagsReachable) && (f & kSCNetworkReachabilityFlagsIsWWAN);
}

@end
