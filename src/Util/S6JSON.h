#import <Foundation/Foundation.h>

// Minimal JSON codec for iOS 4.x where NSJSONSerialization is unavailable.
// Supports objects, arrays, strings, numbers, booleans, and null.
@interface S6JSON : NSObject
+ (id)objectWithData:(NSData *)data error:(NSError **)error;
+ (id)objectWithString:(NSString *)string error:(NSError **)error;
+ (NSData *)dataWithObject:(id)object error:(NSError **)error;
+ (NSString *)stringWithObject:(id)object error:(NSError **)error;
@end
