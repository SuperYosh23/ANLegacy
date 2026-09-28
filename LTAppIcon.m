#import "LTAppIcon.h"
#import "LTLog.h"
#import <UIKit/UIKit.h>

// The selectors arrived in iOS 10.3 but the armv7 slice builds against the iOS
// 9.3 SDK, so they are absent from the headers. Declaring the category keeps
// this compiling; every call is behind respondsToSelector:.
@interface UIApplication (LTAlternateIcon)
- (void)setAlternateIconName:(NSString *)iconName completionHandler:(void (^)(NSError *error))completion;
- (NSString *)alternateIconName;
@end

static NSString * const kLTRoundedName = @"Icon7";
static NSString * const kLTModernName = @"Icon11";
static NSString * const kLTChosenKey = @"LTChosenIcon";
static NSString * const kLTAutoAppliedKey = @"LTAutoIconApplied";

@implementation LTAppIcon

+ (BOOL)hasAlternateIconAPI {
    return [[UIApplication sharedApplication]
            respondsToSelector:@selector(setAlternateIconName:completionHandler:)];
}

+ (NSString *)classicIconName { return nil; }
+ (NSString *)roundedIconName { return kLTRoundedName; }
+ (NSString *)modernIconName { return kLTModernName; }

+ (BOOL)isPickerSupported {
    if (![self hasAlternateIconAPI]) return NO;
    return [[UIDevice currentDevice].systemVersion intValue] >= 11;
}

+ (NSString *)currentIconName {
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:kLTChosenKey];
    if (chosen.length) {
        return [chosen isEqualToString:@"classic"] ? nil : chosen;
    }
    if (![self hasAlternateIconAPI]) return nil;
    return [[UIApplication sharedApplication] alternateIconName];
}

+ (NSString *)currentIconLabel {
    NSString *name = [self currentIconName];
    if ([name isEqualToString:kLTModernName]) return @"Modern";
    if ([name isEqualToString:kLTRoundedName]) return @"Rounded";
    return @"Classic";
}

+ (void)applyIconNamed:(NSString *)iconName {
    if (![self hasAlternateIconAPI]) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Recording the choice here is what stops the first-run default from
    // overriding the user a moment later.
    [defaults setObject:(iconName.length ? iconName : @"classic") forKey:kLTChosenKey];
    [defaults synchronize];
    [defaults setBool:YES forKey:kLTAutoAppliedKey];
    [[UIApplication sharedApplication] setAlternateIconName:iconName
                                          completionHandler:^(NSError *error) {
        if (error) {
            LTLog(@"APP icon change to %@ failed: %@", iconName, error.localizedDescription);
        } else {
            LTLog(@"APP icon changed to %@", iconName);
        }
    }];
}

+ (void)applyModernIconIfNeeded {
    if (![self hasAlternateIconAPI]) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([[defaults stringForKey:kLTChosenKey] length]) return; // explicit choice wins
    if ([defaults boolForKey:kLTAutoAppliedKey]) return;
    if ([[[UIApplication sharedApplication] alternateIconName] isEqualToString:kLTModernName]) {
        [defaults setBool:YES forKey:kLTAutoAppliedKey];
        [defaults synchronize];
        return;
    }
    [self applyIconNamed:kLTModernName];
}

@end
