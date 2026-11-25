#import <Foundation/Foundation.h>

// The server key (shared secret for the Pi helper) in the keychain, with a preferences fallback when the
// keychain refuses (no entitlement). Small strings only.
@interface S6Keychain : NSObject
+ (NSString *)stringForKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;
@end
