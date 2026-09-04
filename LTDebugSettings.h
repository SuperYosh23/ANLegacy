#import <Foundation/Foundation.h>

@interface LTDebugSettings : NSObject
+ (BOOL)forceNonWidescreen;
+ (void)setForceNonWidescreen:(BOOL)on;
+ (BOOL)forceWidescreen;
+ (void)setForceWidescreen:(BOOL)on;
@end