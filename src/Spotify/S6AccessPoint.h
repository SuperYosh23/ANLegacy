#import <Foundation/Foundation.h>

// Packet types of Spotify's access point protocol (the ones this app sends or handles)
enum {
    S6PacketSecretBlock = 0x02,
    S6PacketPing = 0x04,
    S6PacketRequestKey = 0x0c,
    S6PacketAesKey = 0x0d,
    S6PacketAesKeyError = 0x0e,
    S6PacketCountryCode = 0x1b,
    S6PacketPong = 0x49,
    S6PacketPongAck = 0x4a,
    S6PacketProductInfo = 0x50,
    S6PacketLegacyWelcome = 0x69,
    S6PacketLicenseVersion = 0x76,
    S6PacketLogin = 0xab,
    S6PacketAPWelcome = 0xac,
    S6PacketAuthFailure = 0xad,
    S6PacketMercuryReq = 0xb2,
    S6PacketMercurySub = 0xb3,
    S6PacketMercuryUnsub = 0xb4,
    S6PacketMercuryEvent = 0xb5,
};

// One connection to an access point ("ap-gew4.spotify.com:4070"): plain TCP, a Diffie-Hellman handshake whose keys
// are checked against Spotify's server key, then Shannon-encrypted packets (command byte, length, payload, MAC).
// Blocking calls; one thread reads, any thread may send.
@interface S6AccessPoint : NSObject

- (BOOL)connectToHost:(NSString *)host port:(int)port error:(NSError **)error;   // TCP and handshake
- (BOOL)sendPacket:(uint8_t)command payload:(NSData *)payload error:(NSError **)error;
// Waits for the next packet; NO on a closed or broken connection
- (BOOL)receivePacket:(uint8_t *)command payload:(NSData **)payload error:(NSError **)error;
- (void)setReadTimeout:(NSTimeInterval)seconds;
- (void)close;

@property (atomic, readonly) BOOL connected;
@property (nonatomic, readonly, copy) NSString *host;

@end
