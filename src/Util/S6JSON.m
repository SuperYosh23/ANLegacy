#import "S6JSON.h"

static NSError *S6JSONError(NSString *msg, NSUInteger index) {
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          msg ?: @"JSON parse error", NSLocalizedDescriptionKey,
                          [NSNumber numberWithUnsignedInteger:index], @"index", nil];
    return [NSError errorWithDomain:@"S6JSON" code:1 userInfo:info];
}

@interface S6JSONParser : NSObject {
    NSString *_s;
    NSUInteger _i;
    NSUInteger _len;
}
- (id)initWithString:(NSString *)s;
- (id)parse:(NSError **)error;
@end

@implementation S6JSONParser
- (id)initWithString:(NSString *)s {
    if ((self = [super init])) { _s = [s copy]; _len = [_s length]; _i = 0; }
    return self;
}
#if !__has_feature(objc_arc)
- (void)dealloc { [_s release]; [super dealloc]; }
#endif
- (unichar)peek { return _i < _len ? [_s characterAtIndex:_i] : 0; }
- (unichar)next { return _i < _len ? [_s characterAtIndex:_i++] : 0; }
- (void)skipWS { while (_i < _len) { unichar c = [_s characterAtIndex:_i]; if (c==' '||c=='\t'||c=='\n'||c=='\r') _i++; else break; } }
- (BOOL)match:(NSString *)lit {
    NSUInteger l = [lit length];
    if (_i + l > _len) return NO;
    if ([[_s substringWithRange:NSMakeRange(_i,l)] isEqualToString:lit]) { _i += l; return YES; }
    return NO;
}
- (id)parse:(NSError **)error {
    [self skipWS];
    id v = [self parseValue:error];
    if (!v && error && !*error) *error = S6JSONError(@"Invalid JSON", _i);
    [self skipWS];
    return v;
}
- (id)parseValue:(NSError **)error {
    [self skipWS];
    unichar c = [self peek];
    if (c == '"') return [self parseString:error];
    if (c == '{') return [self parseObject:error];
    if (c == '[') return [self parseArray:error];
    if (c == 't') { if ([self match:@"true"]) return [NSNumber numberWithBool:YES]; }
    if (c == 'f') { if ([self match:@"false"]) return [NSNumber numberWithBool:NO]; }
    if (c == 'n') { if ([self match:@"null"]) return [NSNull null]; }
    if (c == '-' || (c >= '0' && c <= '9')) return [self parseNumber:error];
    if (error) *error = S6JSONError(@"Unexpected character", _i);
    return nil;
}
- (NSString *)parseString:(NSError **)error {
    if ([self next] != '"') { if (error) *error = S6JSONError(@"Expected string", _i); return nil; }
    NSMutableString *out = [NSMutableString string];
    while (_i < _len) {
        unichar c = [self next];
        if (c == '"') return out;
        if (c == '\\') {
            if (_i >= _len) break;
            unichar e = [self next];
            switch (e) {
                case '"': [out appendString:@"\""]; break;
                case '\\': [out appendString:@"\\"]; break;
                case '/': [out appendString:@"/"]; break;
                case 'b': [out appendString:@"\b"]; break;
                case 'f': [out appendString:@"\f"]; break;
                case 'n': [out appendString:@"\n"]; break;
                case 'r': [out appendString:@"\r"]; break;
                case 't': [out appendString:@"\t"]; break;
                case 'u': {
                    if (_i + 4 > _len) { if (error) *error = S6JSONError(@"Bad unicode escape", _i); return nil; }
                    unsigned int code = 0;
                    for (int k=0;k<4;k++) {
                        unichar h = [_s characterAtIndex:_i++];
                        code <<= 4;
                        if (h>='0'&&h<='9') code |= (h-'0');
                        else if (h>='a'&&h<='f') code |= (h-'a'+10);
                        else if (h>='A'&&h<='F') code |= (h-'A'+10);
                        else { if (error) *error = S6JSONError(@"Bad unicode escape", _i); return nil; }
                    }
                    if (code >= 0xD800 && code <= 0xDBFF && _i + 6 <= _len && [_s characterAtIndex:_i]=='\\' && [_s characterAtIndex:_i+1]=='u') {
                        NSUInteger save = _i; _i += 2; unsigned int lo = 0; BOOL ok = YES;
                        for (int k=0;k<4;k++) {
                            unichar h = [_s characterAtIndex:_i++]; lo <<= 4;
                            if (h>='0'&&h<='9') lo |= (h-'0');
                            else if (h>='a'&&h<='f') lo |= (h-'a'+10);
                            else if (h>='A'&&h<='F') lo |= (h-'A'+10);
                            else { ok = NO; break; }
                        }
                        if (ok && lo >= 0xDC00 && lo <= 0xDFFF) {
                            UTF32Char cp = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00);
                            unichar chars[2]; chars[0] = (unichar)(0xD800 + ((cp - 0x10000) >> 10)); chars[1] = (unichar)(0xDC00 + ((cp - 0x10000) & 0x3FF));
                            [out appendString:[NSString stringWithCharacters:chars length:2]];
                            break;
                        } else { _i = save; }
                    }
                    unichar uc = (unichar)code;
                    [out appendString:[NSString stringWithCharacters:&uc length:1]];
                    break;
                }
                default: { unichar uc = e; [out appendString:[NSString stringWithCharacters:&uc length:1]]; break; }
            }
        } else {
            unichar uc = c; [out appendString:[NSString stringWithCharacters:&uc length:1]];
        }
    }
    if (error) *error = S6JSONError(@"Unterminated string", _i);
    return nil;
}
- (NSDictionary *)parseObject:(NSError **)error {
    if ([self next] != '{') return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [self skipWS];
    if ([self peek] == '}') { [self next]; return d; }
    while (1) {
        [self skipWS];
        NSString *key = [self parseString:error];
        if (!key) return nil;
        [self skipWS];
        if ([self next] != ':') { if (error) *error = S6JSONError(@"Expected ':'", _i); return nil; }
        id val = [self parseValue:error];
        if (val) [d setObject:val forKey:key]; else [d setObject:[NSNull null] forKey:key];
        [self skipWS];
        unichar c = [self next];
        if (c == '}') return d;
        if (c != ',') { if (error) *error = S6JSONError(@"Expected ',' or '}'", _i); return nil; }
    }
}
- (NSArray *)parseArray:(NSError **)error {
    if ([self next] != '[') return nil;
    NSMutableArray *a = [NSMutableArray array];
    [self skipWS];
    if ([self peek] == ']') { [self next]; return a; }
    while (1) {
        id val = [self parseValue:error];
        if (!val && error && *error) return nil;
        [a addObject:val ?: [NSNull null]];
        [self skipWS];
        unichar c = [self next];
        if (c == ']') return a;
        if (c != ',') { if (error) *error = S6JSONError(@"Expected ',' or ']'", _i); return nil; }
    }
}
- (NSNumber *)parseNumber:(NSError **)error {
    NSUInteger start = _i;
    if ([self peek] == '-') [self next];
    while (_i < _len) { unichar c = [_s characterAtIndex:_i]; if (c>='0'&&c<='9') _i++; else break; }
    BOOL isFloat = NO;
    if (_i < _len && [_s characterAtIndex:_i]=='.') { isFloat = YES; _i++; while (_i < _len){unichar c=[_s characterAtIndex:_i]; if(c>='0'&&c<='9')_i++; else break;} }
    if (_i < _len) { unichar c=[_s characterAtIndex:_i]; if(c=='e'||c=='E'){ isFloat=YES; _i++; if(_i<_len){unichar s=[_s characterAtIndex:_i]; if(s=='+'||s=='-')_i++;} while(_i<_len){unichar d=[_s characterAtIndex:_i]; if(d>='0'&&d<='9')_i++; else break;} } }
    NSString *num = [_s substringWithRange:NSMakeRange(start, _i-start)];
    if (isFloat) return [NSNumber numberWithDouble:[num doubleValue]];
    long long ll = [num longLongValue];
    if (ll >= INT_MIN && ll <= INT_MAX) return [NSNumber numberWithLongLong:ll];
    return [NSNumber numberWithDouble:[num doubleValue]];
}
@end

static void S6AppendEscapedString(NSMutableString *out, NSString *s) {
    [out appendString:@"\""];
    NSUInteger len = [s length];
    for (NSUInteger i=0;i<len;i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
            case '"': [out appendString:@"\\\""]; break;
            case '\\': [out appendString:@"\\\\"]; break;
            case '\b': [out appendString:@"\\b"]; break;
            case '\f': [out appendString:@"\\f"]; break;
            case '\n': [out appendString:@"\\n"]; break;
            case '\r': [out appendString:@"\\r"]; break;
            case '\t': [out appendString:@"\\t"]; break;
            default:
                if (c < 0x20) [out appendFormat:@"\\u%04x", (unsigned)c];
                else { unichar uc=c; [out appendString:[NSString stringWithCharacters:&uc length:1]]; }
        }
    }
    [out appendString:@"\""];
}

static BOOL S6WriteJSON(id obj, NSMutableString *out, NSError **error) {
    if (!obj || obj == [NSNull null]) { [out appendString:@"null"]; return YES; }
    if ([obj isKindOfClass:[NSString class]]) { S6AppendEscapedString(out, obj); return YES; }
    if ([obj isKindOfClass:[NSNumber class]]) {
        const char *t = [obj objCType];
        if (t && (strcmp(t, @encode(BOOL))==0 || strcmp(t,"c")==0)) {
            [out appendString:[obj boolValue]?@"true":@"false"];
        } else {
            double d = [obj doubleValue];
            if (isnan(d)||isinf(d)) { [out appendString:@"0"]; }
            else if (d == (long long)d && d >= -9007199254740992.0 && d <= 9007199254740992.0) [out appendFormat:@"%lld", (long long)d];
            else [out appendFormat:@"%.17g", d];
        }
        return YES;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        [out appendString:@"{"];
        NSArray *keys = [obj allKeys];
        for (NSUInteger i=0;i<[keys count];i++) {
            if (i) [out appendString:@","];
            id k = [keys objectAtIndex:i];
            S6AppendEscapedString(out, [k description]);
            [out appendString:@":"];
            if (!S6WriteJSON([obj objectForKey:k], out, error)) return NO;
        }
        [out appendString:@"}"];
        return YES;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        [out appendString:@"["];
        for (NSUInteger i=0;i<[obj count];i++) {
            if (i) [out appendString:@","];
            if (!S6WriteJSON([obj objectAtIndex:i], out, error)) return NO;
        }
        [out appendString:@"]"];
        return YES;
    }
    S6AppendEscapedString(out, [obj description]);
    return YES;
}

@implementation S6JSON
+ (id)objectWithData:(NSData *)data error:(NSError **)error {
    if (!data) return nil;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!s) { if (error) *error = S6JSONError(@"Bad encoding", 0); return nil; }
#if !__has_feature(objc_arc)
    id r = [self objectWithString:s error:error];
    [s release];
    return r;
#else
    return [self objectWithString:s error:error];
#endif
}
+ (id)objectWithString:(NSString *)string error:(NSError **)error {
    if (!string) return nil;
    S6JSONParser *p = [[S6JSONParser alloc] initWithString:string];
#if !__has_feature(objc_arc)
    id r = [p parse:error];
    [p release];
    return r;
#else
    return [p parse:error];
#endif
}
+ (NSData *)dataWithObject:(id)object error:(NSError **)error {
    NSString *s = [self stringWithObject:object error:error];
    return s ? [s dataUsingEncoding:NSUTF8StringEncoding] : nil;
}
+ (NSString *)stringWithObject:(id)object error:(NSError **)error {
    if (!object) return nil;
    NSMutableString *out = [NSMutableString string];
    if (!S6WriteJSON(object, out, error)) return nil;
    return out;
}
@end
