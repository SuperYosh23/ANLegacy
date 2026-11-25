#import "S6Pathfinder.h"
#import "S6Session.h"
#import "S6Tokens.h"
#import "S6Utils.h"
#import "S6Common.h"

static NSString * const S6PathfinderURL = @"https://api-partner.spotify.com/pathfinder/v2/query";

@implementation S6Pathfinder

+ (NSDictionary *)hashes
{
    static NSDictionary *hashes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // (from the web player's bundles, 2026-10-04)
        hashes = @{
        @"home": @"76243c78b0e20ecdbe41b794dec8cbe73f75e585b0a7201b8d2e84578412847a",
        @"homeSection": @"76243c78b0e20ecdbe41b794dec8cbe73f75e585b0a7201b8d2e84578412847a",
        @"searchDesktop": @"eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03",
        @"searchTracks": @"b02683192a98dde7966b5e6655a79eeb62713eab703eda9902c932818dd52751",
        @"searchArtists": @"7bf95d754fdbe32c8b161fbbe54d1ae50974900df4dce4c8f1afcbcad153224d",
        @"searchAlbums": @"202cb3305e31e5a0767ba7925f28bd728cf8f8b0217e6da43909056071cd70e9",
        @"searchPlaylists": @"d520014e748f9ea44f7707d8df1819867ac1205e8b7f3e28f22fe5fc858921b1",
        @"searchPodcasts": @"0195d9f61b43606d490bca64c3456e3593528cea6cc05c7e822c7c42beed0f4e",
        @"searchTopResultsList": @"dd78eaff943eba629ed70ee25517b9cea0dcaa41193e2592ae2727660b21892c",
        @"browseAll": @"dbd8b55e09a58afc52eab438bc228ba28fd72ac2f2148c6c26354980e4579001",
        @"browsePage": @"f5c4e6d668f5716464a231c1cc8b22c1cbf6ad68b09929fd7de813a30581298b",
        @"browseSection": @"b13c1cccbfcb6947753c2613411b3566485c21fd5f36d80a80bb64be61ba2d51",
        @"getAlbum": @"6a74b456cd1735c9193d9e8ec8cc5184cad7ce13572210315229db3975964361",
        @"queryAlbumTracks": @"6a74b456cd1735c9193d9e8ec8cc5184cad7ce13572210315229db3975964361",
        @"queryArtistOverview": @"9f8134ef565e78621f1e1793555bd6633c5ac144ae0f89604ed3ae3f80b3c8e6",
        @"queryArtistDiscographyAll": @"5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599",
        @"queryArtistDiscographyAlbums": @"5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599",
        @"queryArtistDiscographySingles": @"5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599",
        @"queryArtistAppearsOn": @"9a4bb7a20d6720fe52d7b47bc001cfa91940ddf5e7113761460b4a288d18a4c1",
        @"queryArtistRelated": @"3d031d6cb22a2aa7c8d203d49b49df731f58b1e2799cc38d9876d58771aa66f3",
        @"queryArtistPlaylists": @"54f7e5a5a2af05b7dc98526df376a46c6b15c05440c8dfdc8f6cecb1a807eca7",
        @"queryArtistDiscoveredOn": @"71c2392e4cecf6b48b9ad1311ae08838cbdabcfd189c6bf0c66c2430b8dcfdb1",
        @"fetchPlaylist": @"8964e8eafb21aa992a7d951d256d83285c04be2105d209262901de70cb97584a",
        @"fetchPlaylistContents": @"8964e8eafb21aa992a7d951d256d83285c04be2105d209262901de70cb97584a",
        @"fetchPlaylistMetadata": @"8964e8eafb21aa992a7d951d256d83285c04be2105d209262901de70cb97584a",
        @"libraryV3": @"390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455",
        @"fetchLibraryTracks": @"087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",
        @"areEntitiesInLibrary": @"134337999233cc6fdd6b1e6dbf94841409f04a946c5c7b744b09ba0dfe5a85ed",
        @"addToLibrary": @"896ebcb47815681340860d121cb5d494e157e2a78d3950385cd54e0393c67148",
        @"removeFromLibrary": @"896ebcb47815681340860d121cb5d494e157e2a78d3950385cd54e0393c67148",
        @"addToPlaylist": @"47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990",
        @"removeFromPlaylist": @"47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990",
        @"editablePlaylists": @"d5c4b8096437dcc2ac9528c91dfcd299e35b747cda2f8f75d28f41f49c5092ba",
        @"profileAttributes": @"08ffb4730af3746e04a8301396f20875dbbce10c75243803091a9274eacc8ac0",
        @"accountAttributes": @"41cb03e50f4db7f661057895c23cbec5248dcc5dd3d5cde2ed4bc809ccc2d2e3",
        @"userTopContent": @"49ee15704de4a7fdeac65a02db20604aa11e46f02e809c55d9a89f6db9754356",
        @"fetchEntitiesForRecentlyPlayed": @"cf5d2e94ffd82788470788ae1f6090cc3e9e774fb8fd383580634c6e6f50f7be",
        @"decorateContextTracks": @"383de00240775c39a6afe0b1055dc562b2a3930894201f9762f3fc32a74971c7",
        @"getTrack": @"a8ef9e9f02b836feb0da3003c31dbb30decc6f4b473ef89ca88c882386d668de",
        @"queryShowMetadataV2": @"b475447846f37cc426add800b995a7859c169c53c72b62de6338c0c40a5dacea",
        @"queryPodcastEpisodes": @"3539d746cf882f3909660de40b4ef472b3f5893a0761d617c282541de5d412c5",
        @"getEpisodeOrChapter": @"5f77db47e5a2ce6680330bb61317aa09e17ddd1d189513cb218e7cd3e43288be",
        @"recents": @"698be5892a3cc95331deebeff463d05dfdd5febf5254bea30b895b5a93dfb584",
        @"queryNpvArtist": @"e1ae46a21911a3075c1aa29bf09a6c60f9a45b6a2b1132429f10ad06c299b5d7",
        @"queryTrackArtists": @"ee2b038198f5e62c679c3996584d9249bbee55fe69fc212271c56492a022c798",
        @"internalLinkRecommenderTrack": @"c77098ee9d6ee8ad3eb844938722db60570d040b49f41f5ec6e7be9160a7c86b",
        @"userAccountId": @"c56c2b33c2ded49960530771844ed482ffc1518169fb3d0dda91ac1608b019e2",
        };
    });
    return hashes;
}

+ (NSString *)hashFor:(NSString *)operation { return [[self hashes] objectForKey:operation]; }

+ (dispatch_queue_t)queue
{
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.samcejko.sixify.pathfinder", NULL /* DISPATCH_QUEUE_CONCURRENT unavailable on iOS 4.0 */); });
    return q;
}

+ (NSData *)rawQuery:(NSString *)operation hash:(NSString *)hash variables:(id)variables platform:(NSString *)platform
              status:(NSInteger *)status error:(NSError **)error
{
    if (![[S6Session shared] waitUntilReady:20 error:error]) return nil;
    NSDictionary *body = @{ @"variables": variables ?: [NSDictionary dictionary], @"operationName": operation ?: @"",
                            @"extensions": @{ @"persistedQuery": @{ @"version": @1, @"sha256Hash": hash ?: @"" } } };
    NSData *json = [S6Utils JSONDataFromObject:body];
    for (int attempt = 0; attempt < 2; attempt++) {
        NSString *token = [[S6Tokens shared] accessTokenWithError:error];
        if (!token) return nil;
        NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:@{
            @"Authorization": [@"Bearer " stringByAppendingString:token],
            @"Content-Type": @"application/json;charset=UTF-8",
            @"Accept": @"application/json",
            @"Accept-Language": ([[NSLocale preferredLanguages] count] ? [[NSLocale preferredLanguages] objectAtIndex:0] : nil) ?: @"en",
        }];
        NSString *clientToken = [[S6Tokens shared] clientTokenWithError:NULL];
        if (clientToken) [headers setObject:clientToken forKey:@"client-token"];
        if (platform.length) [headers setObject:platform forKey:@"app-platform"];
        NSInteger s = 0;
        NSData *data = S6SyncRequest(@"POST", S6PathfinderURL, headers, json, &s, NULL, error);
        if (!data) return nil;
        if (s == 401 && attempt == 0) { [[S6Tokens shared] invalidateAccessToken]; continue; }
        if (status) *status = s;
        return data;
    }
    if (error) *error = S6MakeError(401, L(@"Spotify did not accept the access token."));
    return nil;
}

+ (NSDictionary *)query:(NSString *)operation variables:(NSDictionary *)variables error:(NSError **)error
{
    NSString *hash = [self hashFor:operation];
    NSInteger status = 0;
    NSData *data = [self rawQuery:operation hash:hash variables:variables platform:nil status:&status error:error];
    if (!data) return nil;
    NSDictionary *json = S6Dict([S6Utils JSONObjectFromData:data]);
    NSDictionary *result = S6Dict([json objectForKey:@"data"]);
    NSArray *errors = S6Arr([json objectForKey:@"errors"]);
    if (status >= 400 || (!result && errors.count) || !json) {
        NSString *message = S6Str([S6Dict([errors count] ? [errors objectAtIndex:0] : nil) objectForKey:@"message"]);
        S6Log(@"pathfinder %@: HTTP %ld %@", operation, (long)status, message ?: @"");
        if (error) *error = S6MakeError(status >= 400 ? status : S6ErrorAPI, message.length ? message : [NSString stringWithFormat:L(@"Spotify answered with error %ld."), (long)(status >= 400 ? status : S6ErrorAPI)]);
        return nil;
    }
    if (errors.count) S6Log(@"pathfinder %@: partial answer: %@", operation, S6Str([S6Dict([errors count] ? [errors objectAtIndex:0] : nil) objectForKey:@"message"]) ?: @"?");
    return result ?: [NSDictionary dictionary];
}

+ (void)query:(NSString *)operation variables:(NSDictionary *)variables completion:(void (^)(NSDictionary *, NSError *))completion
{
    dispatch_async([self queue], ^{
        NSError *error = nil;
        NSDictionary *data = [self query:operation variables:variables error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(data, error); });
    });
}

@end
