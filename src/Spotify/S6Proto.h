#import <Foundation/Foundation.h>

// The bits of Protocol Buffers that Spotify's messages need, written by hand (no generated code): a writer for the
// requests, and readers that pick fields out of a received message by number.
@interface S6ProtoWriter : NSObject
+ (instancetype)writer;
- (void)varint:(uint64_t)value field:(uint32_t)field;
- (void)sint:(int64_t)value field:(uint32_t)field;            // zigzag (sint32/sint64)
- (void)boolean:(BOOL)value field:(uint32_t)field;
- (void)bytes:(NSData *)value field:(uint32_t)field;          // nil writes nothing; empty writes an empty field
- (void)string:(NSString *)value field:(uint32_t)field;       // nil writes nothing
- (void)message:(S6ProtoWriter *)value field:(uint32_t)field; // nil writes nothing; empty writes an empty message
@property (nonatomic, readonly) NSData *data;
@end

typedef struct {
    uint32_t field;
    int wire;              // 0 varint, 1 fixed64, 2 length-delimited, 5 fixed32
    uint64_t varint;       // wire 0, 1 and 5
    NSRange range;         // wire 2: where the bytes are in the message
} S6ProtoField;

// Walks the fields of `message` from *offset; NO at the end or on malformed input
BOOL S6ProtoNext(NSData *message, NSUInteger *offset, S6ProtoField *field);

NSData *S6ProtoBytes(NSData *message, uint32_t field);                 // the first one, nil when absent
NSArray *S6ProtoAllBytes(NSData *message, uint32_t field);             // every one (repeated fields)
NSString *S6ProtoString(NSData *message, uint32_t field);
uint64_t S6ProtoVarint(NSData *message, uint32_t field, uint64_t fallback);
NSArray *S6ProtoAllVarints(NSData *message, uint32_t field);           // NSNumber; packed ones too
int64_t S6ProtoZigzag(uint64_t value);
BOOL S6ProtoHas(NSData *message, uint32_t field);
