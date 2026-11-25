#import <objc/runtime.h>
#import <objc/message.h>
#include <stdint.h>
#include <stdlib.h>

// arc4random_uniform() only arrived in libSystem on iOS 4.3; the 6.1 SDK links
// it as a hard reference, so an iOS 4.0-4.2 launch fails in dyld before main.
// Supply it ourselves in the iOS 4 build (arc4random itself exists on 4.1).
uint32_t arc4random_uniform(uint32_t upperBound) {
    if (upperBound < 2) return 0;
    uint32_t min = (uint32_t)(-upperBound) % upperBound;
    uint32_t r;
    do {
        r = arc4random();
    } while (r < min);
    return r % upperBound;
}

__attribute__((weak)) id objc_retainBlock(id block) {
    // ARC's objc_retainBlock must return a +1 copy of the block. libobjc on
    // iOS 4.1 has no ARC runtime at all, so the dyld lazy bind for this symbol
    // aborted the first time a block was returned/stored (tapping an artist or
    // album) with "Symbol not found: _objc_retainBlock". The blocks runtime
    // itself is present in libSystem on 4.x.
    if (!block) return nil;
    extern void *_Block_copy(const void *aBlock);
    return (id)_Block_copy((const void *)block);
}

// Minimal ARC runtime shims for iOS 4.x ObjC runtime (no objc_retain/release/autorelease C APIs).
// Compiled without ARC.

static id S6Retain(id obj) {
    if (!obj) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel_registerName("retain"));
}
static void S6Release(id obj) {
    if (!obj) return;
    ((void (*)(id, SEL))objc_msgSend)(obj, sel_registerName("release"));
}
static id S6Autorelease(id obj) {
    if (!obj) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel_registerName("autorelease"));
}

__attribute__((weak)) id objc_retain(id obj) { return S6Retain(obj); }
__attribute__((weak)) void objc_release(id obj) { S6Release(obj); }
__attribute__((weak)) id objc_autorelease(id obj) { return S6Autorelease(obj); }

__attribute__((weak)) id objc_retainAutoreleasedReturnValue(id obj) {
    return S6Retain(obj);
}

__attribute__((weak)) id objc_retainAutoreleaseReturnValue(id obj) {
    return S6Autorelease(S6Retain(obj));
}

__attribute__((weak)) id objc_autoreleaseReturnValue(id obj) {
    return S6Autorelease(obj);
}

__attribute__((weak)) id objc_retainAutorelease(id obj) {
    return S6Autorelease(S6Retain(obj));
}

__attribute__((weak)) void objc_storeStrong(id *location, id obj) {
    if (!location) return;
    id prev = *location;
    if (prev == obj) return;
    if (obj) S6Retain(obj);
    *location = obj;
    if (prev) S6Release(prev);
}

__attribute__((weak)) id objc_loadWeakRetained(id *location) {
    if (!location) return nil;
    id obj = *location;
    return obj ? S6Retain(obj) : nil;
}

__attribute__((weak)) id objc_loadWeak(id *location) {
    return location ? *location : nil;
}

__attribute__((weak)) id objc_initWeak(id *location, id obj) {
    if (location) *location = obj;
    return obj;
}

__attribute__((weak)) void objc_destroyWeak(id *location) {
    if (location) *location = nil;
}

__attribute__((weak)) void objc_copyWeak(id *dest, id *src) {
    if (dest) *dest = src ? *src : nil;
}

__attribute__((weak)) void objc_moveWeak(id *dest, id *src) {
    if (dest) *dest = src ? *src : nil;
    if (src) *src = nil;
}

__attribute__((weak)) id objc_storeWeak(id *location, id obj) {
    if (location) *location = obj;
    return obj;
}
