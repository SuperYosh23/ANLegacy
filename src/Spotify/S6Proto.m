#import "S6Proto.h"

@implementation S6ProtoWriter {
    NSMutableData *_data;
}

+ (instancetype)writer { return [[self alloc] init]; }

- (instancetype)init
{
    if ((self = [super init])) _data = [NSMutableData data];
    return self;
}

- (NSData *)data { return [_data copy]; }

- (void)rawVarint:(uint64_t)v
{
    uint8_t buf[10];
    int n = 0;
    do {
        uint8_t b = v & 0x7F;
        v >>= 7;
        if (v) b |= 0x80;
        buf[n++] = b;
    } while (v);
    [_data appendBytes:buf length:(NSUInteger)n];
}

- (void)tag:(uint32_t)field wire:(int)wire { [self rawVarint:((uint64_t)field << 3) | (uint64_t)wire]; }

- (void)varint:(uint64_t)value field:(uint32_t)field
{
    [self tag:field wire:0];
    [self rawVarint:value];
}

- (void)sint:(int64_t)value field:(uint32_t)field
{
    [self varint:((uint64_t)value << 1) ^ (uint64_t)(value >> 63) field:field];
}

- (void)boolean:(BOOL)value field:(uint32_t)field { [self varint:value ? 1 : 0 field:field]; }

- (void)bytes:(NSData *)value field:(uint32_t)field
{
    if (!value) return;
    [self tag:field wire:2];
    [self rawVarint:value.length];
    [_data appendData:value];
}

- (void)string:(NSString *)value field:(uint32_t)field
{
    if (!value) return;
    [self bytes:[value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data] field:field];
}

- (void)message:(S6ProtoWriter *)value field:(uint32_t)field
{
    if (!value) return;
    [self bytes:value.data field:field];
}

@end

static BOOL S6ReadVarint(const uint8_t *p, NSUInteger len, NSUInteger *off, uint64_t *out)
{
    uint64_t v = 0;
    int shift = 0;
    while (*off < len && shift < 64) {
        uint8_t b = p[(*off)++];
        v |= (uint64_t)(b & 0x7F) << shift;
        if (!(b & 0x80)) { *out = v; return YES; }
        shift += 7;
    }
    return NO;
}

BOOL S6ProtoNext(NSData *message, NSUInteger *offset, S6ProtoField *field)
{
    const uint8_t *p = message.bytes;
    NSUInteger len = message.length;
    if (!p || *offset >= len) return NO;
    uint64_t key = 0;
    if (!S6ReadVarint(p, len, offset, &key)) return NO;
    field->field = (uint32_t)(key >> 3);
    field->wire = (int)(key & 7);
    field->varint = 0;
    field->range = NSMakeRange(0, 0);
    switch (field->wire) {
        case 0:
            return S6ReadVarint(p, len, offset, &field->varint);
        case 1: {
            if (*offset + 8 > len) return NO;
            uint64_t v = 0;
            for (int i = 7; i >= 0; i--) v = (v << 8) | p[*offset + (NSUInteger)i];
            field->varint = v;
            *offset += 8;
            return YES;
        }
        case 2: {
            uint64_t n = 0;
            if (!S6ReadVarint(p, len, offset, &n) || n > len - *offset) return NO;
            field->range = NSMakeRange(*offset, (NSUInteger)n);
            *offset += (NSUInteger)n;
            return YES;
        }
        case 5: {
            if (*offset + 4 > len) return NO;
            field->varint = (uint64_t)p[*offset] | ((uint64_t)p[*offset + 1] << 8) | ((uint64_t)p[*offset + 2] << 16) | ((uint64_t)p[*offset + 3] << 24);
            *offset += 4;
            return YES;
        }
        default:
            return NO;   // (groups are not used by any of Spotify's messages here)
    }
}

NSData *S6ProtoBytes(NSData *message, uint32_t field)
{
    NSUInteger off = 0;
    S6ProtoField f;
    while (S6ProtoNext(message, &off, &f)) {
        if (f.field == field && f.wire == 2) return [message subdataWithRange:f.range];
    }
    return nil;
}

NSArray *S6ProtoAllBytes(NSData *message, uint32_t field)
{
    NSMutableArray *all = [NSMutableArray array];
    NSUInteger off = 0;
    S6ProtoField f;
    while (S6ProtoNext(message, &off, &f)) {
        if (f.field == field && f.wire == 2) [all addObject:[message subdataWithRange:f.range]];
    }
    return all;
}

NSString *S6ProtoString(NSData *message, uint32_t field)
{
    NSData *d = S6ProtoBytes(message, field);
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
}

uint64_t S6ProtoVarint(NSData *message, uint32_t field, uint64_t fallback)
{
    NSUInteger off = 0;
    S6ProtoField f;
    while (S6ProtoNext(message, &off, &f)) {
        if (f.field == field && f.wire != 2) return f.varint;
    }
    return fallback;
}

NSArray *S6ProtoAllVarints(NSData *message, uint32_t field)
{
    NSMutableArray *all = [NSMutableArray array];
    NSUInteger off = 0;
    S6ProtoField f;
    while (S6ProtoNext(message, &off, &f)) {
        if (f.field != field) continue;
        if (f.wire == 2) {
            // packed
            const uint8_t *p = (const uint8_t *)message.bytes + f.range.location;
            NSUInteger o = 0;
            uint64_t v = 0;
            while (o < f.range.length && S6ReadVarint(p, f.range.length, &o, &v)) [all addObject:@(v)];
        } else {
            [all addObject:@(f.varint)];
        }
    }
    return all;
}

int64_t S6ProtoZigzag(uint64_t value) { return (int64_t)(value >> 1) ^ -(int64_t)(value & 1); }

BOOL S6ProtoHas(NSData *message, uint32_t field)
{
    NSUInteger off = 0;
    S6ProtoField f;
    while (S6ProtoNext(message, &off, &f)) if (f.field == field) return YES;
    return NO;
}
