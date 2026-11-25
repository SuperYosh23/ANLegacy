#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, S6Quality) {
    S6QualityNormal = 0,    // Ogg Vorbis 96 kbit/s
    S6QualityHigh = 1,      // 160 kbit/s
    S6QualityVeryHigh = 2,  // 320 kbit/s (Premium)
};

// The app's preferences (NSUserDefaults) and the Spotify account (keychain). Changes post
// S6SettingsDidChangeNotification on the main thread.
@interface S6Settings : NSObject

+ (void)registerDefaults;
+ (void)save;

// The Spotify account: the reusable credentials Spotify handed out at the last login (kept in the keychain)
+ (NSString *)username;
+ (NSInteger)authType;
+ (NSData *)authData;
+ (BOOL)hasAccount;
+ (void)setUsername:(NSString *)username authType:(NSInteger)authType authData:(NSData *)authData;
+ (void)forgetAccount;

// This device as Spotify sees it: a fixed id and the name shown in the Spotify app's device list
+ (NSString *)deviceId;
+ (NSString *)deviceName;
+ (void)setDeviceName:(NSString *)name;

// Playback
+ (S6Quality)quality;
+ (void)setQuality:(S6Quality)quality;
+ (BOOL)normalize;                       // same loudness for every song (Spotify's ReplayGain values)
+ (void)setNormalize:(BOOL)value;
+ (NSInteger)crossfadeSeconds;           // 0 = off
+ (void)setCrossfadeSeconds:(NSInteger)value;
+ (BOOL)dataSaver;                       // on mobile data the Normal quality (96 kbit/s) whatever is chosen
+ (void)setDataSaver:(BOOL)value;
+ (BOOL)autoplay;                        // when the music runs out, similar songs follow
+ (void)setAutoplay:(BOOL)value;

// Appearance and network
+ (BOOL)classicPlayer;
+ (void)setClassicPlayer:(BOOL)value;
+ (BOOL)darkTheme;
+ (void)setDarkTheme:(BOOL)value;
+ (BOOL)verifyTLS;
+ (void)setVerifyTLS:(BOOL)value;

// Recent searches (newest first)
+ (NSArray *)recentSearches;
+ (void)addRecentSearch:(NSString *)query;
+ (void)clearRecentSearches;

@end
