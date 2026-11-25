#import "S6Keychain.h"
#import "S6Common.h"
#import <Security/Security.h>

static NSString * const S6KeychainService = @"com.samcejko.sixify";

@implementation S6Keychain

+ (NSMutableDictionary *)queryForKey:(NSString *)key
{
    return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService: S6KeychainService,
               (__bridge id)kSecAttrAccount: key ?: @"" } mutableCopy];
}

+ (NSString *)stringForKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    [q setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnData];
    [q setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) == errSecSuccess && result) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    NSMutableDictionary *qOld = [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                    (__bridge id)kSecAttrService: @"com.samcejko.spot6",
                                    (__bridge id)kSecAttrAccount: key ?: @"" } mutableCopy];
    [qOld setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnData];
    [qOld setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    CFTypeRef oldResult = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)qOld, &oldResult) == errSecSuccess && oldResult) {
        NSData *data = (__bridge_transfer NSData *)oldResult;
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (s.length) {
            [self setString:s forKey:key];
            return s;
        }
    }
    NSString *fallback = [[NSUserDefaults standardUserDefaults] stringForKey:[@"kc." stringByAppendingString:key]];
    return fallback;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key
{
    NSMutableDictionary *q = [self queryForKey:key];
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!value.length) {
        NSMutableDictionary *legacy = [self queryForKey:key];
        [legacy setObject:@"com.samcejko.spot6" forKey:(__bridge id)kSecAttrService];
        SecItemDelete((__bridge CFDictionaryRef)legacy);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"kc." stringByAppendingString:key]];
        return;
    }
    [q setObject:[value dataUsingEncoding:NSUTF8StringEncoding] forKey:(__bridge id)kSecValueData];
    [q setObject:(__bridge id)kSecAttrAccessibleAfterFirstUnlock forKey:(__bridge id)kSecAttrAccessible];
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    if (status == errSecSuccess) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"kc." stringByAppendingString:key]];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:value forKey:[@"kc." stringByAppendingString:key]];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

@end
