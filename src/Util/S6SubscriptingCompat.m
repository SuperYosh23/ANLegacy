#import "S6SubscriptingCompat.h"
#import <objc/runtime.h>
#include <stdio.h>

// Clang lowers Objective-C subscripting (arr[i], dict[k], assignments) to
// calls to these selector methods. They are unavailable on the iOS 4.x runtime,
// so we install implementations only when missing. On runtimes that already
// implement them, we leave the system implementations in place.

static id S6ObjectAtIndexedSubscript(id self, SEL _cmd, NSUInteger idx) {
    return [(NSArray *)self objectAtIndex:idx];
}

static void S6SetObjectAtIndexedSubscript(id self, SEL _cmd, id obj, NSUInteger idx) {
    if (!obj) [NSException raise:NSInvalidArgumentException format:@"setObject:atIndexedSubscript: object cannot be nil"];
    [(NSMutableArray *)self replaceObjectAtIndex:idx withObject:obj];
}

static id S6ObjectForKeyedSubscript(id self, SEL _cmd, id key) {
    if (!key) return nil;
    return [(NSDictionary *)self objectForKey:key];
}

static void S6SetObjectForKeyedSubscript(id self, SEL _cmd, id obj, id key) {
    if (!key) [NSException raise:NSInvalidArgumentException format:@"setObject:forKeyedSubscript: key cannot be nil"];
    NSMutableDictionary *dict = (NSMutableDictionary *)self;
    if (obj) {
        [dict setObject:obj forKey:key];
    } else {
        [dict removeObjectForKey:key];
    }
}

static void S6AddMethodIfMissing(Class cls, SEL sel, IMP imp, const char *types) {
    if (!cls || !sel || !imp || !types) return;
    if (![cls instancesRespondToSelector:sel]) {
        class_addMethod(cls, sel, imp, types);
    }
}

__attribute__((constructor))
static void S6InstallSubscriptingCompat(void) {
    @autoreleasepool {
        // id (*)(id, SEL, NSUInteger)
        char idxGetTypes[32];
        snprintf(idxGetTypes, sizeof(idxGetTypes), "@@:%s", @encode(NSUInteger));
        // void (*)(id, SEL, id, NSUInteger)
        char idxSetTypes[32];
        snprintf(idxSetTypes, sizeof(idxSetTypes), "v@:@@%s", @encode(NSUInteger));
        // id (*)(id, SEL, id)
        const char *keyGetTypes = "@@:@@";
        // void (*)(id, SEL, id, id)
        const char *keySetTypes = "v@:@@@";

        // Indexed subscripting: install on NSArray/NSMutableArray classes in case
        // concrete subclasses do not inherit a custom implementation on old runtimes.
        S6AddMethodIfMissing([NSArray class], @selector(objectAtIndexedSubscript:), (IMP)S6ObjectAtIndexedSubscript, idxGetTypes);
        S6AddMethodIfMissing([NSMutableArray class], @selector(objectAtIndexedSubscript:), (IMP)S6ObjectAtIndexedSubscript, idxGetTypes);
        S6AddMethodIfMissing([NSMutableArray class], @selector(setObject:atIndexedSubscript:), (IMP)S6SetObjectAtIndexedSubscript, idxSetTypes);

        // Keyed subscripting
        S6AddMethodIfMissing([NSDictionary class], @selector(objectForKeyedSubscript:), (IMP)S6ObjectForKeyedSubscript, keyGetTypes);
        S6AddMethodIfMissing([NSMutableDictionary class], @selector(objectForKeyedSubscript:), (IMP)S6ObjectForKeyedSubscript, keyGetTypes);
        S6AddMethodIfMissing([NSMutableDictionary class], @selector(setObject:forKeyedSubscript:), (IMP)S6SetObjectForKeyedSubscript, keySetTypes);
    }
}
