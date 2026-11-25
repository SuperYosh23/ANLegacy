#import "S6Catalog.h"
#import "S6Pathfinder.h"
#import "S6SpClient.h"
#import "S6Session.h"
#import "S6Models.h"
#import "S6Utils.h"
#import "S6Common.h"

@implementation S6Shelf
@end

@implementation S6ArtistPage
@end

@implementation S6SearchResults
- (BOOL)empty { return !self.topResult && !self.tracks.count && !self.artists.count && !self.albums.count && !self.playlists.count && !self.shows.count && !self.episodes.count; }
@end

// The integration the web player names itself with (Home and browse pages are put together for it)
static NSString * const S6Integration = @"INTEGRATION_WEB_PLAYER";

// An entity whose uri sits on its wrapper ({_uri, data: {…}}): the uri is put into the data
static NSDictionary *S6WithURI(NSDictionary *wrapper)
{
    NSDictionary *data = S6Dict([wrapper objectForKey:@"data"]);
    NSString *uri = S6Str([wrapper objectForKey:@"_uri"]);
    if (!data || S6Str([data objectForKey:@"uri"]).length || !uri.length) return data ?: wrapper;
    NSMutableDictionary *d = [data mutableCopy];
    [d setObject:uri forKey:@"uri"];
    return d;
}

// The model in a list item of any shape: {item: …}, {content: …}, {entity: …}, {track: …}, {itemV2: …} or the entity
static id S6ItemEntity(NSDictionary *item)
{
    NSDictionary *i = S6Dict(item);
    for (NSString *key in @[ @"item", @"content", @"entity", @"track", @"itemV2" ]) {
        NSDictionary *inner = S6Dict([i objectForKey:key]);
        if (!inner) continue;
        if (S6Dict([inner objectForKey:@"data"])) return S6EntityFromGraphQL(S6WithURI(inner));
        return S6EntityFromGraphQL(inner);
    }
    if (S6Dict([i objectForKey:@"data"])) return S6EntityFromGraphQL(S6WithURI(i));
    return S6EntityFromGraphQL(i);
}

static NSArray *S6Entities(id items)
{
    NSMutableArray *out = [NSMutableArray array];
    for (id item in S6Arr(items)) {
        id e = S6ItemEntity(item);
        if (e) [out addObject:e];
    }
    return out;
}

// A browse card (a category page): {title, uri, image, color}
static NSDictionary *S6CategoryCard(NSDictionary *item)
{
    NSString *uri = S6Str([item objectForKey:@"uri"]);
    NSDictionary *wrapper = S6Dict([item objectForKey:@"content"]);            // BrowseSectionContainerWrapper
    NSDictionary *container = S6Dict([wrapper objectForKey:@"data"]);           // BrowseSectionContainer
    NSDictionary *card = S6Dict([S6Dict([container objectForKey:@"data"]) objectForKey:@"cardRepresentation"]);
    NSString *title = S6Str([S6Dict([card objectForKey:@"title"]) objectForKey:@"transformedLabel"]);
    if (![uri hasPrefix:@"spotify:page:"] || !title.length) return nil;
    return @{ @"title": title, @"uri": uri, @"image": [S6Image urlIn:[S6Dict([card objectForKey:@"artwork"]) objectForKey:@"sources"] forSize:300] ?: @"",
              @"color": S6Str([S6Dict([card objectForKey:@"backgroundColor"]) objectForKey:@"hex"]) ?: @"#535353" };
}

// The sections of Home or a browse page
static NSArray *S6Sections(id sectionList, NSString *untitled)
{
    NSMutableArray *sections = [NSMutableArray array];
    for (id s in S6Arr([S6Dict(sectionList) objectForKey:@"items"])) {
        NSDictionary *section = S6Dict(s);
        NSMutableArray *items = [NSMutableArray array];
        for (id item in S6Arr([S6Dict([section objectForKey:@"sectionItems"]) objectForKey:@"items"])) {
            id e = S6ItemEntity(item);
            if (!e) e = S6CategoryCard(S6Dict(item));
            if (e) [items addObject:e];
        }
        if (!items.count) continue;
        S6Shelf *out = [[S6Shelf alloc] init];
        out.title = S6Str([S6Dict([S6Dict([section objectForKey:@"data"]) objectForKey:@"title"]) objectForKey:@"transformedLabel"]) ?: untitled;
        out.items = items;
        [sections addObject:out];
    }
    return sections;
}

@implementation S6Catalog

+ (dispatch_queue_t)queue
{
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.samcejko.sixify.catalog", NULL /* DISPATCH_QUEUE_CONCURRENT unavailable on iOS 4.0 */); });
    return q;
}

// One query in the background: `work` runs there (it may query more), its result goes to `done` on the main thread
+ (void)background:(id (^)(NSError **error))work done:(void (^)(id result, NSError *error))done
{
    dispatch_async([self queue], ^{
        NSError *error = nil;
        id result = work(&error);
        dispatch_async(dispatch_get_main_queue(), ^{ done(result, result ? nil : (error ?: S6MakeError(S6ErrorBadResponse, L(@"Spotify sent something unexpected.")))); });
    });
}

#pragma mark - Home and browsing

+ (void)home:(void (^)(NSString *, NSArray *, NSError *))completion
{
    NSDictionary *vars = @{ @"homeEndUserIntegration": S6Integration, @"timeZone": [NSTimeZone localTimeZone].name ?: @"Europe/Prague",
                            @"sp_t": @"", @"facet": @"", @"sectionItemsLimit": @15, @"includeEpisodeContentRatingsV2": @NO };
    [self background:^id(NSError **error) {
        NSDictionary *home = [S6Dict([S6Pathfinder query:@"home" variables:vars error:error]) objectForKey:@"home"];
        if (!home) return nil;
        NSString *greeting = S6Str([S6Dict([home objectForKey:@"greeting"]) objectForKey:@"transformedLabel"]) ?: @"";
        return @[ greeting, S6Sections([S6Dict([home objectForKey:@"sectionContainer"]) objectForKey:@"sections"], L(@"Quick picks")) ];
    } done:^(NSArray *r, NSError *error) {
        completion(r ? [r objectAtIndex:0] : nil, r ? [r objectAtIndex:1] : nil, error);
    }];
}

+ (void)search:(NSString *)query completion:(void (^)(S6SearchResults *, NSError *))completion
{
    NSDictionary *vars = @{ @"searchTerm": query ?: @"", @"offset": @0, @"limit": @20, @"numberOfTopResults": @5, @"includeAudiobooks": @NO,
                            @"includeArtistHasConcertsField": @NO, @"includePreReleases": @NO, @"includeLocalConcertsField": @NO, @"includeAuthors": @NO };
    [self background:^id(NSError **error) {
        NSDictionary *s = [S6Dict([S6Pathfinder query:@"searchDesktop" variables:vars error:error]) objectForKey:@"searchV2"];
        if (!s) return nil;
        S6SearchResults *r = [[S6SearchResults alloc] init];
        NSArray *topItems = S6Entities([S6Dict([s objectForKey:@"topResultsV2"]) objectForKey:@"itemsV2"]);
        r.topResult = [topItems count] ? [topItems objectAtIndex:0] : nil;
        r.tracks = S6Entities([S6Dict([s objectForKey:@"tracksV2"]) objectForKey:@"items"]);
        r.artists = S6Entities([S6Dict([s objectForKey:@"artists"]) objectForKey:@"items"]);
        r.albums = S6Entities([S6Dict([s objectForKey:@"albumsV2"]) objectForKey:@"items"]);
        r.playlists = S6Entities([S6Dict([s objectForKey:@"playlists"]) objectForKey:@"items"]);
        r.shows = S6Entities([S6Dict([s objectForKey:@"podcasts"]) objectForKey:@"items"]);
        r.episodes = S6Entities([S6Dict([s objectForKey:@"episodes"]) objectForKey:@"items"]);
        return r;
    } done:^(id r, NSError *e) { completion(r, e); }];
}

+ (void)browseCategories:(void (^)(NSArray *, NSError *))completion
{
    NSDictionary *vars = @{ @"pagePagination": @{ @"offset": @0, @"limit": @10 }, @"sectionPagination": @{ @"offset": @0, @"limit": @99 },
                            @"browseEndUserIntegration": S6Integration };
    [self background:^id(NSError **error) {
        NSDictionary *start = [S6Dict([S6Pathfinder query:@"browseAll" variables:vars error:error]) objectForKey:@"browseStart"];
        if (!start) return nil;
        NSMutableArray *cards = [NSMutableArray array];
        for (id s in S6Arr([S6Dict([start objectForKey:@"sections"]) objectForKey:@"items"])) {
            for (id item in S6Arr([S6Dict([S6Dict(s) objectForKey:@"sectionItems"]) objectForKey:@"items"])) {
                NSDictionary *card = S6CategoryCard(S6Dict(item));
                if (card) [cards addObject:card];
            }
        }
        return cards;
    } done:^(id r, NSError *e) { completion(r, e); }];
}

+ (void)browsePage:(NSString *)uri completion:(void (^)(NSString *, NSArray *, NSError *))completion
{
    NSDictionary *vars = @{ @"uri": uri ?: @"", @"pagePagination": @{ @"offset": @0, @"limit": @10 },
                            @"sectionPagination": @{ @"offset": @0, @"limit": @30 }, @"browseEndUserIntegration": S6Integration };
    [self background:^id(NSError **error) {
        NSDictionary *page = [S6Dict([S6Pathfinder query:@"browsePage" variables:vars error:error]) objectForKey:@"browse"];
        if (!page) return nil;
        NSString *title = S6Str([S6Dict([S6Dict([page objectForKey:@"header"]) objectForKey:@"title"]) objectForKey:@"transformedLabel"]) ?: @"";
        return @[ title, S6Sections([page objectForKey:@"sections"], @"") ];
    } done:^(NSArray *r, NSError *error) {
        completion(r ? [r objectAtIndex:0] : nil, r ? [r objectAtIndex:1] : nil, error);
    }];
}

#pragma mark - Pages

+ (void)album:(NSString *)uri completion:(void (^)(S6Album *, NSError *))completion
{
    [self background:^id(NSError **error) {
        S6Album *album = nil;
        NSMutableArray *tracks = [NSMutableArray array];
        for (NSInteger offset = 0; offset < 1000; ) {
            NSDictionary *vars = @{ @"uri": uri ?: @"", @"locale": @"", @"offset": @(offset), @"limit": @50 };
            NSDictionary *a = [S6Dict([S6Pathfinder query:@"getAlbum" variables:vars error:error]) objectForKey:@"albumUnion"];
            if (!a) return album;   // (a later page failing keeps what came)
            if (!album) album = [S6Album albumFromGraphQL:a];
            if (!album) return nil;
            NSArray *items = S6Arr([S6Dict([a objectForKey:@"tracksV2"]) objectForKey:@"items"]);
            for (id item in items) {
                S6Track *t = [S6Track trackFromGraphQL:S6Dict([item objectForKey:@"track"]) album:album];
                if (t) [tracks addObject:t];
            }
            offset += 50;
            NSInteger total = S6Int([S6Dict([a objectForKey:@"tracksV2"]) objectForKey:@"totalCount"]);
            if (items.count < 50 || offset >= total) break;
        }
        album.tracks = tracks;
        if (!album.totalTracks) album.totalTracks = (NSInteger)tracks.count;
        return album;
    } done:^(id r, NSError *e) { completion(r, e); }];
}

static NSArray *S6Releases(id groups)
{
    // discography groups: {releases: {items: [album]}}
    NSMutableArray *out = [NSMutableArray array];
    for (id g in S6Arr([S6Dict(groups) objectForKey:@"items"])) {
        NSArray *_relItems = S6Arr([S6Dict([S6Dict(g) objectForKey:@"releases"]) objectForKey:@"items"]); S6Album *a = [S6Album albumFromGraphQL:(_relItems.count ? [_relItems objectAtIndex:0] : nil)];
        if (a) [out addObject:a];
    }
    return out;
}

+ (void)artist:(NSString *)uri completion:(void (^)(S6ArtistPage *, NSError *))completion
{
    NSDictionary *vars = @{ @"uri": uri ?: @"", @"locale": @"", @"includePrerelease": @NO };
    [self background:^id(NSError **error) {
        NSDictionary *a = [S6Dict([S6Pathfinder query:@"queryArtistOverview" variables:vars error:error]) objectForKey:@"artistUnion"];
        S6Artist *artist = [S6Artist artistFromGraphQL:a];
        if (!artist) return nil;
        S6ArtistPage *page = [[S6ArtistPage alloc] init];
        page.artist = artist;
        NSDictionary *disco = S6Dict([a objectForKey:@"discography"]);
        NSMutableArray *top = [NSMutableArray array];
        for (id item in S6Arr([S6Dict([disco objectForKey:@"topTracks"]) objectForKey:@"items"])) {
            S6Track *t = [S6Track trackFromGraphQL:S6Dict([item objectForKey:@"track"]) album:nil];
            if (t) [top addObject:t];
        }
        page.topTracks = top;
        NSMutableArray *popular = [NSMutableArray array];
        for (id item in S6Arr([S6Dict([disco objectForKey:@"popularReleasesAlbums"]) objectForKey:@"items"])) {
            S6Album *x = [S6Album albumFromGraphQL:item];
            if (x) [popular addObject:x];
        }
        page.albums = S6Releases([disco objectForKey:@"albums"]);
        if (!page.albums.count) page.albums = popular;
        page.singles = S6Releases([disco objectForKey:@"singles"]);
        page.compilations = S6Releases([disco objectForKey:@"compilations"]);
        NSDictionary *related = S6Dict([a objectForKey:@"relatedContent"]);
        page.appearsOn = S6Releases([related objectForKey:@"appearsOn"]);
        NSMutableArray *fans = [NSMutableArray array];
        for (id item in S6Arr([S6Dict([related objectForKey:@"relatedArtists"]) objectForKey:@"items"])) {
            S6Artist *x = [S6Artist artistFromGraphQL:item];
            if (x) [fans addObject:x];
        }
        page.related = fans;
        page.playlists = S6Entities([S6Dict([related objectForKey:@"featuringV2"]) objectForKey:@"items"]);
        return page;
    } done:^(id r, NSError *e) { completion(r, e); }];
}

+ (void)playlist:(NSString *)uri offset:(NSInteger)offset limit:(NSInteger)limit
      completion:(void (^)(S6Playlist *, NSArray *, NSInteger, NSError *))completion
{
    NSDictionary *vars = @{ @"uri": uri ?: @"", @"offset": @(offset), @"limit": @(limit), @"enableWatchFeedEntrypoint": @NO };
    [self background:^id(NSError **error) {
        NSDictionary *p = [S6Dict([S6Pathfinder query:@"fetchPlaylist" variables:vars error:error]) objectForKey:@"playlistV2"];
        S6Playlist *playlist = [S6Playlist playlistFromGraphQL:p];
        if (!playlist) {
            if (p && error && !*error) *error = S6MakeError(S6ErrorRestricted, L(@"This playlist is not available."));
            return nil;
        }
        NSDictionary *content = S6Dict([p objectForKey:@"content"]);
        NSMutableArray *tracks = [NSMutableArray array];
        for (id item in S6Arr([content objectForKey:@"items"])) {
            NSDictionary *i = S6Dict(item);
            S6Track *t = [S6Track trackFromGraphQL:S6WithURI(S6Dict([i objectForKey:@"itemV2"])) album:nil];
            if (!t) continue;
            t.uid = S6Str([i objectForKey:@"uid"]);
            NSString *added = S6Str([S6Dict([i objectForKey:@"addedAt"]) objectForKey:@"isoString"]);
            if (added.length >= 10 && ![added hasPrefix:@"1970"]) t.addedAt = [added substringToIndex:10];
            [tracks addObject:t];
        }
        return @[ playlist, tracks, @(S6Int([content objectForKey:@"totalCount"])) ];
    } done:^(NSArray *r, NSError *error) {
        completion(r ? [r objectAtIndex:0] : nil, r ? [r objectAtIndex:1] : nil, r ? [[r objectAtIndex:2] integerValue] : 0, error);
    }];
}

+ (void)likedSongsOffset:(NSInteger)offset limit:(NSInteger)limit completion:(void (^)(NSArray *, NSInteger, NSError *))completion
{
    NSDictionary *vars = @{ @"offset": @(offset), @"limit": @(limit) };
    [self background:^id(NSError **error) {
        NSDictionary *result = [S6Pathfinder query:@"fetchLibraryTracks" variables:vars error:error];
        NSDictionary *me = S6Dict([result objectForKey:@"me"]);
        NSDictionary *library = S6Dict([me objectForKey:@"library"]);
        NSDictionary *page = S6Dict([library objectForKey:@"tracks"]);
        if (!page) return nil;
        NSMutableArray *tracks = [NSMutableArray array];
        for (id item in S6Arr([page objectForKey:@"items"])) {
            NSDictionary *i = S6Dict(item);
            S6Track *t = [S6Track trackFromGraphQL:S6WithURI(S6Dict([i objectForKey:@"track"])) album:nil];
            if (!t) continue;
            NSString *added = S6Str([S6Dict([i objectForKey:@"addedAt"]) objectForKey:@"isoString"]);
            if (added.length >= 10) t.addedAt = [added substringToIndex:10];
            [tracks addObject:t];
        }
        return @[ tracks, @(S6Int([page objectForKey:@"totalCount"])) ];
    } done:^(NSArray *r, NSError *error) {
        completion(r ? [r objectAtIndex:0] : nil, r ? [[r objectAtIndex:1] integerValue] : 0, error);
    }];
}

+ (void)show:(NSString *)uri completion:(void (^)(S6Show *, NSError *))completion
{
    NSDictionary *vars = @{ @"uri": uri ?: @"", @"includeContentCapabilityTrait": @NO, @"includeEpisodeContentRatingsV2": @NO };
    [self background:^id(NSError **error) {
        return [S6Show showFromGraphQL:[[S6Pathfinder query:@"queryShowMetadataV2" variables:vars error:error] objectForKey:@"podcastUnionV2"]];
    } done:^(id r, NSError *e) { completion(r, e); }];
}

+ (void)showEpisodes:(NSString *)uri offset:(NSInteger)offset limit:(NSInteger)limit completion:(void (^)(NSArray *, NSInteger, NSError *))completion
{
    NSDictionary *vars = @{ @"uri": uri ?: @"", @"offset": @(offset), @"limit": @(limit), @"includeEpisodeContentRatingsV2": @NO };
    [self background:^id(NSError **error) {
        NSDictionary *page = S6Dict([S6Dict([[S6Pathfinder query:@"queryPodcastEpisodes" variables:vars error:error] objectForKey:@"podcastUnionV2"]) objectForKey:@"episodesV2"]);
        if (!page) return nil;
        NSMutableArray *episodes = [NSMutableArray array];
        for (id item in S6Arr([page objectForKey:@"items"])) {
            S6Track *t = [S6Track trackFromGraphQL:S6WithURI(S6Dict([item objectForKey:@"entity"])) album:nil];
            if (t) [episodes addObject:t];
        }
        return @[ episodes, @(S6Int([page objectForKey:@"totalCount"])) ];
    } done:^(NSArray *r, NSError *error) {
        completion(r ? [r objectAtIndex:0] : nil, r ? [[r objectAtIndex:1] integerValue] : 0, error);
    }];
}

+ (void)tracksForURIs:(NSArray *)uris completion:(void (^)(NSArray *, NSError *))completion
{
    NSArray *all = [uris copy];
    [self background:^id(NSError **error) {
        NSMutableArray *tracks = [NSMutableArray array];
        for (NSUInteger i = 0; i < all.count; i += 50) {
            NSArray *batch = [all subarrayWithRange:NSMakeRange(i, MIN((NSUInteger)50, all.count - i))];
            NSDictionary *data = [S6Pathfinder query:@"decorateContextTracks" variables:@{ @"uris": batch } error:error];
            if (!data) return tracks.count ? tracks : nil;
            for (id t in S6Arr([data objectForKey:@"tracks"])) {
                S6Track *track = [S6Track trackFromGraphQL:t album:nil];
                if (track) [tracks addObject:track];
            }
        }
        return tracks;
    } done:^(id r, NSError *e) { completion(r, e); }];
}

#pragma mark - The library

+ (void)library:(NSString *)filter offset:(NSInteger)offset limit:(NSInteger)limit completion:(void (^)(NSArray *, NSInteger, NSError *))completion
{
    NSDictionary *vars = @{ @"filters": filter.length ? @[ filter ] : [NSArray array], @"order": [NSNull null], @"textFilter": [NSNull null], @"features": [NSArray array],
                            @"limit": @(limit), @"offset": @(offset), @"flatten": @YES, @"expandedFolders": [NSArray array], @"folderUri": [NSNull null],
                            @"includeFoldersWhenFlattening": @NO };
    [self background:^id(NSError **error) {
        NSDictionary *data = [S6Pathfinder query:@"libraryV3" variables:vars error:error];
        if (!data) return nil;
        NSDictionary *page = S6Dict([S6Dict([data objectForKey:@"me"]) objectForKey:@"libraryV3"]);
        // (a filter the library does not offer - no followed artists, say - is an empty list)
        if (![S6Str([page objectForKey:@"__typename"]) isEqualToString:@"LibraryPage"]) return @[ [NSArray array], @0 ];
        return @[ S6Entities([page objectForKey:@"items"]), @(S6Int([page objectForKey:@"totalCount"])) ];
    } done:^(NSArray *r, NSError *error) {
        completion(r ? [r objectAtIndex:0] : nil, r ? [[r objectAtIndex:1] integerValue] : 0, error);
    }];
}

+ (void)editablePlaylistsFor:(NSString *)trackURI completion:(void (^)(NSArray *, NSError *))completion
{
    NSDictionary *vars = @{ @"offset": @0, @"limit": @200, @"textFilter": @"", @"folderUri": [NSNull null], @"uris": trackURI.length ? @[ trackURI ] : [NSArray array] };
    [self background:^id(NSError **error) {
        NSDictionary *page = S6Dict([S6Dict([[S6Pathfinder query:@"editablePlaylists" variables:vars error:error] objectForKey:@"me"]) objectForKey:@"editablePlaylists"]);
        if (!page) return nil;
        NSMutableArray *out = [NSMutableArray array];
        for (id e in S6Entities([page objectForKey:@"items"])) if ([e isKindOfClass:[S6Playlist class]]) [out addObject:e];
        return out;
    } done:^(id r, NSError *e) { completion(r, e); }];
}

+ (void)profile:(void (^)(NSString *, NSString *))completion
{
    [self background:^id(NSError **error) {
        return S6Dict([S6Dict([[S6Pathfinder query:@"profileAttributes" variables:[NSDictionary dictionary] error:error] objectForKey:@"me"]) objectForKey:@"profile"]);
    } done:^(NSDictionary *profile, NSError *error) {
        completion(S6Str([profile objectForKey:@"name"]), [S6Image urlIn:[S6Dict([profile objectForKey:@"avatar"]) objectForKey:@"sources"] forSize:100]);
    }];
}

+ (void)areSaved:(NSArray *)uris completion:(void (^)(NSArray *, NSError *))completion
{
    NSArray *list = [uris copy];
    [self background:^id(NSError **error) {
        NSArray *lookup = S6Arr([[S6Pathfinder query:@"areEntitiesInLibrary" variables:@{ @"uris": list } error:error] objectForKey:@"lookup"]);
        if (!lookup) return nil;
        NSMutableArray *out = [NSMutableArray array];
        for (NSUInteger i = 0; i < list.count; i++) {
            NSDictionary *d = i < lookup.count ? S6Dict([S6Dict([lookup objectAtIndex:i]) objectForKey:@"data"]) : nil;
            [out addObject:@(S6Bool([d objectForKey:@"saved"]))];
        }
        return out;
    } done:^(id r, NSError *e) { completion(r, e); }];
}

+ (void)mutation:(NSString *)operation variables:(NSDictionary *)vars completion:(void (^)(NSError *))completion
{
    [self background:^id(NSError **error) {
        return [S6Pathfinder query:operation variables:vars error:error];
    } done:^(id result, NSError *error) {
        if (!error) [[NSNotificationCenter defaultCenter] postNotificationName:S6LibraryDidChangeNotification object:nil];
        if (completion) completion(error);
    }];
}

+ (void)setSaved:(BOOL)saved uris:(NSArray *)uris completion:(void (^)(NSError *))completion
{
    if (!uris.count) { if (completion) completion(nil); return; }
    if (saved) [self mutation:@"addToLibrary" variables:@{ @"libraryItemUris": uris, @"interactionId": [NSNull null] } completion:completion];
    else [self mutation:@"removeFromLibrary" variables:@{ @"libraryItemUris": uris } completion:completion];
}

+ (void)addTracks:(NSArray *)uris toPlaylist:(NSString *)playlistURI completion:(void (^)(NSError *))completion
{
    NSDictionary *vars = @{ @"playlistUri": playlistURI ?: @"", @"playlistItemUris": uris ?: [NSArray array],
                            @"newPosition": @{ @"moveType": @"BOTTOM_OF_PLAYLIST", @"fromUid": [NSNull null] } };
    [self mutation:@"addToPlaylist" variables:vars completion:completion];
}

+ (void)removeTrackUIDs:(NSArray *)uids fromPlaylist:(NSString *)playlistURI completion:(void (^)(NSError *))completion
{
    [self mutation:@"removeFromPlaylist" variables:@{ @"playlistUri": playlistURI ?: @"", @"uids": uids ?: [NSArray array] } completion:completion];
}

// As the web player does it: the playlist is made with its name (playlist service), then put first in the user's
// list of playlists (the rootlist, which wants its current revision)
+ (void)createPlaylistNamed:(NSString *)name completion:(void (^)(S6Playlist *, NSError *))completion
{
    NSString *username = [S6Session shared].username;
    [self background:^id(NSError **error) {
        if (!username.length) { if (error) *error = S6MakeError(S6ErrorNotLoggedIn, L(@"You are not logged in.")); return nil; }
        NSDictionary *source = @{ @"source": @{ @"client": @"WEBPLAYER" } };
        NSDictionary *create = @{ @"ops": @[ @{ @"kind": @"UPDATE_LIST_ATTRIBUTES",
                                                @"updateListAttributes": @{ @"newAttributes": @{ @"values": @{ @"name": name ?: @"", @"formatAttributes": [NSArray array], @"pictureSize": [NSArray array] },
                                                                                                 @"noValue": [NSArray array] } } } ],
                                  @"info": source };
        NSData *made = [S6SpClient request:@"POST" path:@"/playlist/v2/playlist" body:[S6Utils JSONDataFromObject:create]
                               contentType:@"application/json" accept:@"application/json" status:NULL error:error];
        NSString *uri = S6Str([S6Dict([S6Utils JSONObjectFromData:made]) objectForKey:@"uri"]);
        if (!uri.length) return nil;
        NSString *rootPath = [NSString stringWithFormat:@"/playlist/v2/user/%@/rootlist", [S6Utils urlEncode:username]];
        NSData *root = [S6SpClient request:@"GET" path:[rootPath stringByAppendingString:@"?decorate=revision&from=0&length=0"] body:nil
                               contentType:nil accept:@"application/json" status:NULL error:error];
        NSString *revision = S6Str([S6Dict([S6Utils JSONObjectFromData:root]) objectForKey:@"revision"]);
        long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
        NSMutableDictionary *changes = [NSMutableDictionary dictionaryWithDictionary:@{
            @"deltas": @[ @{ @"ops": @[ @{ @"kind": @"ADD", @"add": @{ @"addFirst": @YES,
                                                                       @"items": @[ @{ @"uri": uri, @"attributes": @{ @"timestamp": [NSString stringWithFormat:@"%lld", now],
                                                                                                                       @"formatAttributes": [NSArray array], @"availableSignals": [NSArray array] } } ] } } ],
                             @"info": source } ],
            @"wantResultingRevisions": @NO, @"wantSyncResult": @NO, @"nonces": [NSArray array] }];
        if (revision.length) [changes setObject:revision forKey:@"baseRevision"];
        NSError *addError = nil;
        if (![S6SpClient request:@"POST" path:[rootPath stringByAppendingString:@"/changes"] body:[S6Utils JSONDataFromObject:changes]
                     contentType:@"application/json" accept:@"application/json" status:NULL error:&addError]) {
            S6Log(@"new playlist %@ made, but not put into the list: %@", uri, addError.localizedDescription);
        }
        S6Playlist *p = [[S6Playlist alloc] init];
        p.uri = uri;
        p.playlistId = S6URIId(uri);
        p.name = name;
        p.ownerId = username;
        p.editable = YES;
        return p;
    } done:^(id r, NSError *e) {
        if (r) [[NSNotificationCenter defaultCenter] postNotificationName:S6LibraryDidChangeNotification object:nil];
        completion(r, e);
    }];
}

@end
