#import "S6Utils.h"
#import <objc/message.h>
#import "S6JSON.h"
#import "S6Common.h"
#include <CommonCrypto/CommonDigest.h>
#include <sys/types.h>
#include <sys/sysctl.h>
#include <math.h>

@implementation S6Utils

#pragma mark - Formatting

+ (NSString *)formatCount:(NSInteger)count
{
    if (count >= 1000000) {
        double m = count / 1000000.0;
        if (m >= 10) return [NSString stringWithFormat:@"%.0fM", m];
        return [NSString stringWithFormat:@"%.1fM", m];
    }
    if (count >= 1000) {
        double k = count / 1000.0;
        if (k >= 100) return [NSString stringWithFormat:@"%.0fK", k];
        return [NSString stringWithFormat:@"%.1fK", k];
    }
    return [NSString stringWithFormat:@"%ld", (long)MAX(count, (NSInteger)0)];
}

+ (NSString *)formatViewers:(NSInteger)count
{
    return [NSString stringWithFormat:L(@"%@ viewers"), [self formatCount:count]];
}

+ (NSString *)formatDuration:(NSTimeInterval)seconds
{
    if (!(seconds > 0) || isinf(seconds)) seconds = 0;
    long total = (long)floor(seconds + 0.5);
    long h = total / 3600, m = (total % 3600) / 60, s = total % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", h, m, s];
    return [NSString stringWithFormat:@"%ld:%02ld", m, s];
}

+ (NSString *)formatUptimeSince:(NSDate *)date
{
    if (!date) return @"";
    NSTimeInterval dt = -[date timeIntervalSinceNow];
    if (dt < 0) dt = 0;
    long minutes = (long)(dt / 60);
    if (minutes < 60) return [NSString stringWithFormat:L(@"%ld min"), MAX(minutes, 1L)];
    return [NSString stringWithFormat:@"%ld:%02ld", minutes / 60, minutes % 60];
}

+ (NSString *)formatRelativeDate:(NSDate *)date
{
    if (!date) return @"";
    NSTimeInterval dt = -[date timeIntervalSinceNow];
    if (dt < 90) return L(@"just now");
    if (dt < 3600) return [NSString stringWithFormat:L(@"%ld min ago"), (long)(dt / 60)];
    if (dt < 86400) return [NSString stringWithFormat:L(@"%ld h ago"), (long)(dt / 3600)];
    if (dt < 86400 * 2) return L(@"yesterday");
    if (dt < 86400 * 30) return [NSString stringWithFormat:L(@"%ld days ago"), (long)(dt / 86400)];
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    });
    return [formatter stringFromDate:date];
}

+ (NSString *)formatFileSize:(unsigned long long)bytes
{
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    if (bytes < 1024ULL * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

+ (NSString *)truncate:(NSString *)string to:(NSUInteger)length
{
    if (!string) return @"";
    NSString *s = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (s.length <= length) return s;
    NSRange r = [s rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, length)];
    return [[s substringWithRange:r] stringByAppendingString:@"…"];
}

// Emoji added to Unicode after iOS 6 (2012) have no glyph in its fonts and come out as empty boxes.
static BOOL S6CodePointHasNoGlyph(UTF32Char c)
{
    static const UTF32Char ranges[][2] = {
        { 0x200D, 0x200D },     // zero-width joiner: a joined sequence falls apart into its parts, which do draw
        { 0xFFFC, 0xFFFC },     // object replacement character (a dotted box): the chat layout uses it for its images
        // symbols that became emoji in 2014 (⌨ ⏏ ☘ ☠ ☢ ⚔ ⚖ ⚙ ⛈ ⛏ ✍ ✝ ❣ …): no font of this system has them
        { 0x2328, 0x2328 }, { 0x23CF, 0x23CF }, { 0x23ED, 0x23EF }, { 0x23F1, 0x23F2 }, { 0x23F8, 0x23FA }, { 0x2618, 0x2618 },
        { 0x2620, 0x2620 }, { 0x2622, 0x2623 }, { 0x2626, 0x2626 }, { 0x262A, 0x262A }, { 0x262E, 0x262F }, { 0x2638, 0x2639 },
        { 0x2692, 0x2692 }, { 0x2694, 0x2697 }, { 0x2699, 0x2699 }, { 0x269B, 0x269C }, { 0x26A7, 0x26A7 }, { 0x26B0, 0x26B1 },
        { 0x26C8, 0x26C8 }, { 0x26CF, 0x26CF }, { 0x26D1, 0x26D1 }, { 0x26D3, 0x26D3 }, { 0x26E9, 0x26E9 }, { 0x26F0, 0x26F1 },
        { 0x26F4, 0x26F4 }, { 0x26F7, 0x26F9 }, { 0x270D, 0x270D }, { 0x271D, 0x271D }, { 0x2721, 0x2721 }, { 0x2763, 0x2763 },
        { 0x1F1E6, 0x1F1FF },   // regional indicators (flags): only ten flags have pictures here
        { 0x1F321, 0x1F32F }, { 0x1F336, 0x1F336 }, { 0x1F37D, 0x1F37F }, { 0x1F394, 0x1F39F }, { 0x1F3CB, 0x1F3DF },
        { 0x1F3F1, 0x1F3FF },   // (0x1F3FB-0x1F3FF are the skin tone modifiers)
        { 0x1F43F, 0x1F43F }, { 0x1F441, 0x1F441 }, { 0x1F4F8, 0x1F4F8 }, { 0x1F4FD, 0x1F4FF }, { 0x1F53E, 0x1F54F },
        { 0x1F568, 0x1F5FA }, { 0x1F641, 0x1F644 }, { 0x1F6C6, 0x1F6FF }, { 0x1F7E0, 0x1F7FF }, { 0x1F900, 0x1F9FF },
        { 0x1FA70, 0x1FAFF },
    };
    if (c < 0x200D) return NO;
    for (size_t i = 0; i < sizeof(ranges) / sizeof(ranges[0]); i++) {
        if (c >= ranges[i][0] && c <= ranges[i][1]) return YES;
    }
    return NO;
}

// The "fancy fonts" of names and captions (𝐀𝐝𝐡𝐚𝐦, 𝓢𝓪𝓻𝓪, 𝟏𝟐𝟑) are Unicode's mathematical letters and digits, which no font
// of this system has: they become the plain letters they stand for (0 = not one of them)
static unichar S6PlainLetter(UTF32Char c)
{
    if (c >= 0x1D400 && c <= 0x1D6A3) {   // A-Z a-z in thirteen styles, one after another
        UTF32Char i = (c - 0x1D400) % 52;
        return (unichar)(i < 26 ? 'A' + i : 'a' + (i - 26));
    }
    if (c == 0x1D6A4) return 'i';
    if (c == 0x1D6A5) return 'j';
    if (c >= 0x1D7CE && c <= 0x1D7FF) return (unichar)('0' + (c - 0x1D7CE) % 10);   // 0-9 in five styles
    return 0;
}

+ (NSString *)displayText:(NSString *)text
{
    return [self displayText:text dropped:nil];
}

+ (NSString *)displayText:(NSString *)text dropped:(NSMutableArray *)dropped
{
    NSUInteger n = text.length;
    if (!n) return text;
    NSMutableString *out = nil;   // (made only when something has to go: most strings pass through untouched)
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [text characterAtIndex:i];
        UTF32Char cp = c;
        NSUInteger len = 1;
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < n) {
            unichar low = [text characterAtIndex:i + 1];
            if (CFStringIsSurrogateLowCharacter(low)) {
                cp = CFStringGetLongCharacterForSurrogatePair(c, low);
                len = 2;
            }
        }
        unichar plain = len > 1 ? S6PlainLetter(cp) : 0;
        if (plain) {
            if (!out) out = [[text substringToIndex:i] mutableCopy];
            [out appendFormat:@"%C", plain];
            [dropped addObject:[NSValue valueWithRange:NSMakeRange(i + 1, len - 1)]];   // (one of its two units)
        } else if (S6CodePointHasNoGlyph(cp)) {
            if (!out) out = [[text substringToIndex:i] mutableCopy];
            NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
            // the emoji's own variation selector goes with it; at the start of the text so does the space after it
            if (i + len < n && [text characterAtIndex:i + len] == 0xFE0F) len++;
            while (out.length == 0 && i + len < n && [spaces characterIsMember:[text characterAtIndex:i + len]]) len++;
            BOOL spaceBefore = out.length == 0 || [spaces characterIsMember:[out characterAtIndex:out.length - 1]];
            // "DRUHÁ ⚔️ OPENING": with a space on both sides one of them goes with the emoji
            if (spaceBefore && out.length && i + len < n && [spaces characterIsMember:[text characterAtIndex:i + len]]) len++;
            // an emoji squeezed between two words stood for a space (a live event title): one is left in its place
            BOOL spaceAfter = i + len >= n || [spaces characterIsMember:[text characterAtIndex:i + len]];
            NSUInteger kept = 0;
            if (!spaceBefore && !spaceAfter) {
                [out appendString:@" "];
                kept = 1;
            }
            if (len > kept) [dropped addObject:[NSValue valueWithRange:NSMakeRange(i, len - kept)]];
        } else if (out) {
            [out appendString:[text substringWithRange:NSMakeRange(i, len)]];
        }
        i += len - 1;
    }
    if (!out) return text;
    // (only the end is trimmed: a shorter start would move the emote positions)
    while (out.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[out characterAtIndex:out.length - 1]]) {
        [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    }
    return out;
}

#pragma mark - Encoding

+ (NSString *)urlEncode:(NSString *)string
{
    if (!string.length) return @"";
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = utf8.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:utf8.length * 3];
    for (NSUInteger i = 0; i < utf8.length; i++) {
        uint8_t c = bytes[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
            [out appendFormat:@"%c", (char)c];
        } else {
            [out appendFormat:@"%%%02X", c];
        }
    }
    return out;
}

+ (NSString *)sha1:(NSString *)string
{
    NSData *d = [string ?: @"" dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(d.bytes, (CC_LONG)d.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

+ (NSString *)base64Encode:(NSData *)data
{
    static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSMutableString *out = [NSMutableString stringWithCapacity:(length + 2) / 3 * 4];
    for (NSUInteger i = 0; i < length; i += 3) {
        uint32_t v = (uint32_t)bytes[i] << 16;
        if (i + 1 < length) v |= (uint32_t)bytes[i + 1] << 8;
        if (i + 2 < length) v |= bytes[i + 2];
        [out appendFormat:@"%c%c", table[(v >> 18) & 63], table[(v >> 12) & 63]];
        [out appendFormat:@"%c", i + 1 < length ? table[(v >> 6) & 63] : '='];
        [out appendFormat:@"%c", i + 2 < length ? table[v & 63] : '='];
    }
    return out;
}

+ (NSData *)base64Decode:(NSString *)string
{
    if (!string.length) return nil;
    NSString *clean = string;
    NSRange marker = [clean rangeOfString:@"base64," options:NSCaseInsensitiveSearch];
    if (marker.location != NSNotFound) {
        clean = [clean substringFromIndex:marker.location + marker.length];
    }
    static int8_t decodeTable[256];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        memset(decodeTable, -1, sizeof(decodeTable));
        for (int i = 'A'; i <= 'Z'; i++) decodeTable[i] = (int8_t)(i - 'A');
        for (int i = 'a'; i <= 'z'; i++) decodeTable[i] = (int8_t)(i - 'a' + 26);
        for (int i = '0'; i <= '9'; i++) decodeTable[i] = (int8_t)(i - '0' + 52);
        decodeTable[(uint8_t)'+'] = 62;
        decodeTable[(uint8_t)'/'] = 63;
    });

    const char *chars = [clean UTF8String];
    if (!chars) return nil;
    size_t len = strlen(chars);
    NSMutableData *data = [NSMutableData dataWithCapacity:(len * 3) / 4];
    uint32_t buffer = 0;
    int bits = 0;
    for (size_t i = 0; i < len; i++) {
        uint8_t c = (uint8_t)chars[i];
        if (c == '=') break;
        int8_t val = decodeTable[c];
        if (val == -1) continue;
        buffer = (buffer << 6) | (uint32_t)val;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            uint8_t byte = (uint8_t)((buffer >> bits) & 0xFF);
            [data appendBytes:&byte length:1];
        }
    }
    return data.length ? data : nil;
}

+ (id)JSONObjectFromData:(NSData *)data
{
    if (!data.length) return nil;
    NSError *error = nil;
    id object = [S6JSON objectWithData:data error:&error];
    return error ? nil : object;
}

+ (NSData *)JSONDataFromObject:(id)object
{
    if (!object) return nil;
    NSError *error = nil;
    NSData *data = [S6JSON dataWithObject:object error:&error];
    if (error) {
        S6Log(@"JSON serialization failed: %@", error);
        return nil;
    }
    return data;
}

+ (NSDictionary *)parseQuery:(NSString *)query
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        if (!pair.length) continue;
        NSRange eq = [pair rangeOfString:@"="];
        NSString *name = eq.location == NSNotFound ? pair : [pair substringToIndex:eq.location];
        NSString *value = eq.location == NSNotFound ? @"" : [pair substringFromIndex:eq.location + 1];
        value = [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
        [result setObject:([value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: value) forKey:name];
    }
    return result;
}

#pragma mark - Device

+ (NSString *)deviceModel
{
    static NSString *model;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char buffer[64];
        size_t size = sizeof(buffer);
        memset(buffer, 0, sizeof(buffer));
        if (sysctlbyname("hw.machine", buffer, &size, NULL, 0) == 0 && buffer[0]) model = [NSString stringWithUTF8String:buffer];
        if (!model) model = [UIDevice currentDevice].model ?: @"?";
    });
    return model;
}

+ (BOOL)deviceIsOldGeneration
{
    static BOOL old;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Everything iOS 6 runs on that has an A4 or older chip: iPhone 3GS (iPhone2,1), iPhone 4 (iPhone3,x),
        // iPod touch 4 (iPod4,1). The iPad 2, iPhone 4S, iPod touch 5 and newer have an A5 or better.
        NSString *m = [self deviceModel];
        old = [m hasPrefix:@"iPhone1,"] || [m hasPrefix:@"iPhone2,"] || [m hasPrefix:@"iPhone3,"] ||
              [m hasPrefix:@"iPod1,"] || [m hasPrefix:@"iPod2,"] || [m hasPrefix:@"iPod3,"] || [m hasPrefix:@"iPod4,"] ||
              [m hasPrefix:@"iPad1,"];
    });
    return old;
}

+ (NSUInteger)physicalMemoryMB
{
    return (NSUInteger)([NSProcessInfo processInfo].physicalMemory / (1024ULL * 1024ULL));
}

+ (CGFloat)screenScale
{
    static CGFloat scale;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ scale = [UIScreen mainScreen].scale; });
    return scale;
}

#pragma mark - App

+ (NSString *)appVersion
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    return [NSString stringWithFormat:@"%@ (%@)", [info objectForKey:@"CFBundleShortVersionString"] ?: @"0", [info objectForKey:@"CFBundleVersion"] ?: @"0"];
}

+ (NSString *)ensureDirectory:(NSString *)path
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return path;
}

+ (NSString *)cachesPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [self ensureDirectory:[paths objectAtIndex:0]];
}

+ (NSString *)documentsPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return [self ensureDirectory:[paths objectAtIndex:0]];
}

+ (void)alertWithTitle:(NSString *)title message:(NSString *)message
{
    S6Main(^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil];
        [alert show];
    });
}

#pragma mark - Colors

+ (UIColor *)colorFromHex:(NSString *)hex
{
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *s = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
    if (s.length != 6) return nil;
    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) return nil;
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1.0];
}

+ (UIColor *)readableColor:(UIColor *)color onDark:(BOOL)dark
{
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if ([color respondsToSelector:@selector(getRed:green:blue:alpha:)] && ((BOOL(*)(id,SEL,CGFloat*,CGFloat*,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getRed:green:blue:alpha:), &r, &g, &b, &a)) {
        // ok
    } else if ([color respondsToSelector:@selector(getWhite:alpha:)]) {
        CGFloat w = 0;
        if (!((BOOL(*)(id,SEL,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getWhite:alpha:), &w, &a)) return color;
        r = g = b = w;
    } else {
        // iOS 4 fallback: try CGColor components
        CGColorRef cg = color.CGColor;
        size_t n = CGColorGetNumberOfComponents(cg);
        const CGFloat *c = CGColorGetComponents(cg);
        if (n >= 3) { r = c[0]; g = c[1]; b = c[2]; a = c[n-1]; }
        else if (n >= 2) { r = g = b = c[0]; a = c[1]; }
        else return color;
    }
    // perceived brightness (ITU-R BT.601)
    CGFloat luma = 0.299 * r + 0.587 * g + 0.114 * b;
    if (dark && luma < 0.42) {
        // lighten towards white until readable on a dark background
        CGFloat t = (0.42 - luma) / (1.0 - luma);
        r += (1 - r) * t; g += (1 - g) * t; b += (1 - b) * t;
    } else if (!dark && luma > 0.62) {
        // darken towards black until readable on a light background
        CGFloat t = 0.62 / luma;
        r *= t; g *= t; b *= t;
    } else {
        return color;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

#pragma mark - Images

+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size
{
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
