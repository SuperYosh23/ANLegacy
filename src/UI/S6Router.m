#import "S6Router.h"
#import "S6RootViewController.h"
#import "S6TrackListViewController.h"
#import "S6ArtistViewController.h"
#import "S6PlaylistPickerViewController.h"
#import "S6SearchViewController.h"
#import "S6Models.h"
#import "S6Player.h"
#import "S6Catalog.h"
#import "S6SpClient.h"
#import "S6Theme.h"
#import "S6Common.h"
#import "MusicHandoff.h"

@interface S6ActionSheet () <UIActionSheetDelegate>
@property (nonatomic, strong) UIActionSheet *sheet;
@property (nonatomic, strong) NSMutableArray *actions;
@property (nonatomic, strong) S6ActionSheet *keepAlive;
@end

@implementation S6ActionSheet

static __unsafe_unretained S6ActionSheet *S6ShownSheet;

+ (BOOL)pressButtonTitled:(NSString *)title
{
    S6ActionSheet *s = S6ShownSheet;
    if (!s.sheet.visible) return NO;
    for (NSInteger i = 0; i < s.sheet.numberOfButtons; i++) {
        if (![[s.sheet buttonTitleAtIndex:i] isEqualToString:title]) continue;
        [s.sheet dismissWithClickedButtonIndex:i animated:NO];
        return YES;
    }
    return NO;
}

- (instancetype)initWithTitle:(NSString *)title
{
    if ((self = [super init])) {
        _sheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        _sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
        _actions = [NSMutableArray array];
    }
    return self;
}

- (void)addButton:(NSString *)title action:(dispatch_block_t)action
{
    [self.sheet addButtonWithTitle:title];
    [self.actions addObject:[action copy] ?: [NSNull null]];
}

- (void)addDestructiveButton:(NSString *)title action:(dispatch_block_t)action
{
    self.sheet.destructiveButtonIndex = [self.sheet addButtonWithTitle:title];
    [self.actions addObject:[action copy] ?: [NSNull null]];
}

- (void)showFromView:(UIView *)view inController:(UIViewController *)controller
{
    self.sheet.cancelButtonIndex = [self.sheet addButtonWithTitle:L(@"Cancel")];
    [self.actions addObject:[NSNull null]];
    self.keepAlive = self;
    S6ShownSheet = self;
    if (S6IsPad() && view.window) [self.sheet showFromRect:view.bounds inView:view animated:YES];
    else [self.sheet showInView:controller.view.window ?: controller.view];
}

- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index
{
    if (index >= 0 && index < (NSInteger)self.actions.count) {
        id action = self.actions[(NSUInteger)index];
        if (action != [NSNull null]) ((dispatch_block_t)action)();
    }
    self.keepAlive = nil;
}

@end

@implementation S6Router

static NSUInteger S6HandoffGeneration;
+ (void)cancelHandoff { S6HandoffGeneration++; }

+ (void)playHandoff:(NSDictionary *)metadata
{
    NSUInteger generation = ++S6HandoffGeneration;
    NSString *uri = MHSpotifyURI([metadata objectForKey:@"url"]);
    S6Track *previousTrack = [S6Player shared].currentTrack;
    if (uri.length) {
        [S6Catalog tracksForURIs:@[uri] completion:^(NSArray *tracks, NSError *error) {
            if (generation != S6HandoffGeneration || [S6Player shared].currentTrack != previousTrack) return;
            S6Track *track = tracks.firstObject;
            if (track.playable) {
                [[S6Player shared] playTracks:@[track] startingAt:0 contextURI:track.uri contextName:track.name];
                [self showNowPlaying];
            } else [self toast:error.localizedDescription ?: L(@"This song is not available.")];
        }];
        return;
    }
    NSString *title = [metadata objectForKey:@"title"], *artist = [metadata objectForKey:@"artist"];
    if (!title.length || !artist.length) return;
    NSString *query = [NSString stringWithFormat:@"%@ %@", title, artist];
    double duration = MHDuration([metadata objectForKey:@"duration"]);
    [self toast:L(@"Finding the recognized song…")];
    [S6Catalog search:query completion:^(S6SearchResults *results, NSError *error) {
        if (generation != S6HandoffGeneration || [S6Player shared].currentTrack != previousTrack) return;
        S6Track *best = nil;
        double bestDifference = HUGE_VAL;
        for (id item in results.tracks) {
            if (![item isKindOfClass:[S6Track class]]) continue;
            S6Track *track = item;
            if (!track.playable || track.isEpisode || !track.uri.length) continue;
            if (!MHMatches(title, artist, duration, track.name, [track artistNames], track.durationMs / 1000.0, NO)) continue;
            double difference = duration > 0 ? fabs(duration - track.durationMs / 1000.0) : 0;
            if (!best || difference < bestDifference) { best = track; bestDifference = difference; }
        }
        if (best) {
            [[S6Player shared] playTracks:@[best] startingAt:0 contextURI:best.uri contextName:best.name];
            [self showNowPlaying];
        } else {
            S6RootViewController *root = [S6RootViewController shared];
            [root showSection:S6SectionSearch];
            UIViewController *search = root.contentNavigationController.viewControllers.firstObject;
            if ([search isKindOfClass:[S6SearchViewController class]]) [(S6SearchViewController *)search searchFor:query];
            [self toast:error.localizedDescription ?: L(@"No exact match. Choose a search result.")];
        }
    }];
}


+ (void)showSleepTimerFromView:(UIView *)view inController:(UIViewController *)controller
{
    S6Player *player = [S6Player shared];
    NSString *title = L(@"Sleep timer");
    if (player.sleepAtEndOfSong) title = L(@"The music stops at the end of this song.");
    else if (player.sleepAt) title = [NSString stringWithFormat:L(@"The music stops in %@."), S6FormatDurationMs((NSInteger)([player.sleepAt timeIntervalSinceNow] * 1000))];
    S6ActionSheet *sheet = [[S6ActionSheet alloc] initWithTitle:title];
    for (NSNumber *n in @[ @5, @10, @15, @30, @45, @60, @90 ]) {
        NSInteger minutes = [n integerValue];
        [sheet addButton:[NSString stringWithFormat:L(@"%ld minutes"), (long)minutes] action:^{
            [player setSleepTimerMinutes:minutes];
            [self toast:[NSString stringWithFormat:L(@"The music stops in %ld minutes"), (long)minutes]];
        }];
    }
    [sheet addButton:L(@"End of this song") action:^{
        [player setSleepTimerMinutes:-1];
        [self toast:L(@"The music stops at the end of this song")];
    }];
    if (player.sleepAt || player.sleepAtEndOfSong) {
        [sheet addDestructiveButton:L(@"Turn the timer off") action:^{
            [player setSleepTimerMinutes:0];
            [self toast:L(@"Sleep timer off")];
        }];
    }
    [sheet showFromView:view inController:controller];
}

+ (void)push:(UIViewController *)controller
{
    [[S6RootViewController shared] pushViewController:controller];
}

+ (void)openAlbum:(S6Album *)album
{
    if (album.albumId.length) [self push:[[S6TrackListViewController alloc] initWithAlbum:album]];
}

+ (void)openArtist:(S6Artist *)artist
{
    if (artist.artistId.length) [self push:[[S6ArtistViewController alloc] initWithArtist:artist]];
}

+ (void)openPlaylist:(S6Playlist *)playlist
{
    if (playlist.playlistId.length) [self push:[[S6TrackListViewController alloc] initWithPlaylist:playlist]];
}

+ (void)openShow:(S6Show *)show
{
    if (show.showId.length) [self push:[[S6TrackListViewController alloc] initWithShow:show]];
}

+ (void)openLikedSongs
{
    [self push:[[S6TrackListViewController alloc] initLikedSongs]];
}

+ (void)openURI:(NSString *)uri
{
    NSString *u = [uri stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // https://open.spotify.com/album/<id>?si=... -> spotify:album:<id>
    NSRange host = [u rangeOfString:@"open.spotify.com/"];
    if (host.location != NSNotFound) {
        NSString *rest = [u substringFromIndex:host.location + host.length];
        rest = [[rest componentsSeparatedByString:@"?"] firstObject];
        NSMutableArray *parts = [[rest componentsSeparatedByString:@"/"] mutableCopy];
        if (parts.count && [parts[0] hasPrefix:@"intl-"]) [parts removeObjectAtIndex:0];
        if (parts.count >= 2) u = [NSString stringWithFormat:@"spotify:%@:%@", parts[0], parts[1]];
    }
    NSString *type = S6URIType(u), *identifier = S6URIId(u);
    if (!identifier.length) return;
    if ([type isEqualToString:@"album"]) {
        S6Album *a = [[S6Album alloc] init];
        a.albumId = identifier;
        a.uri = u;
        [self openAlbum:a];
    } else if ([type isEqualToString:@"artist"]) {
        S6Artist *a = [[S6Artist alloc] init];
        a.artistId = identifier;
        a.uri = u;
        [self openArtist:a];
    } else if ([type isEqualToString:@"playlist"]) {
        S6Playlist *p = [[S6Playlist alloc] init];
        p.playlistId = identifier;
        p.uri = u;
        [self openPlaylist:p];
    } else if ([type isEqualToString:@"show"]) {
        S6Show *s = [[S6Show alloc] init];
        s.showId = identifier;
        s.uri = u;
        [self openShow:s];
    } else if ([type isEqualToString:@"track"] || [type isEqualToString:@"episode"]) {
        [S6Catalog tracksForURIs:@[ u ] completion:^(NSArray *tracks, NSError *error) {
            S6Track *t = tracks.firstObject;
            if (!t) { [self toast:error.localizedDescription ?: L(@"This song is not available.")]; return; }
            [[S6Player shared] playTracks:@[ t ] startingAt:0 contextURI:t.uri contextName:t.name];
            if (t.album.albumId.length && !t.isEpisode) [self openAlbum:t.album];
        }];
    } else if ([type isEqualToString:@"page"]) {
        [self push:[[S6CategoryViewController alloc] initWithCategoryId:u name:@""]];
    }
}

+ (void)openItem:(id)item
{
    if ([item isKindOfClass:[S6Album class]]) [self openAlbum:item];
    else if ([item isKindOfClass:[S6Playlist class]]) [self openPlaylist:item];
    else if ([item isKindOfClass:[S6Artist class]]) [self openArtist:item];
    else if ([item isKindOfClass:[S6Show class]]) [self openShow:item];
    else if ([item isKindOfClass:[S6Track class]]) {
        S6Track *t = item;
        [[S6Player shared] playTracks:@[ t ] startingAt:0 contextURI:t.uri contextName:t.isEpisode ? t.album.name : t.name];
    } else if ([item isKindOfClass:[NSDictionary class]] && [[item objectForKey:@"uri"] length]) {
        [self push:[[S6CategoryViewController alloc] initWithCategoryId:[item objectForKey:@"uri"] name:[item objectForKey:@"title"]]];
    }
}

+ (void)playRadioFor:(S6Track *)track
{
    if (!track.uri.length) return;
    [self toast:L(@"Starting radio…")];
    [S6SpClient radioForURI:track.uri completion:^(NSArray *uris, NSError *error) {
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *u in uris) if (list.count < 50 && ![u isEqualToString:track.uri]) [list addObject:u];
        if (!list.count) { [self toast:error.localizedDescription ?: L(@"No radio for this.")]; return; }
        [S6Catalog tracksForURIs:list completion:^(NSArray *found, NSError *e) {
            NSMutableArray *tracks = [NSMutableArray arrayWithObject:track];
            for (S6Track *x in found) if (x.uri.length && ![x.uri isEqualToString:track.uri]) [tracks addObject:x];
            if (tracks.count < 2) { [self toast:e.localizedDescription ?: L(@"No radio for this.")]; return; }
            [[S6Player shared] playTracks:tracks startingAt:0 contextURI:[@"spotify:station:track:" stringByAppendingString:track.trackId ?: @""]
                              contextName:[NSString stringWithFormat:L(@"%@ Radio"), track.name]];
        }];
    }];
}

+ (void)showNowPlaying
{
    [[S6RootViewController shared] presentNowPlaying];
}

+ (void)toast:(NSString *)text
{
    [[S6RootViewController shared] showToast:text];
}

+ (void)showActionsForTrack:(S6Track *)track fromView:(UIView *)view inController:(UIViewController *)controller playlist:(S6Playlist *)playlist
{
    if (!track) return;
    S6ActionSheet *sheet = [[S6ActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"%@\n%@", track.name ?: @"", [track artistNames] ?: @""]];
    S6Player *player = [S6Player shared];
    if (track.playable) {
        [sheet addButton:L(@"Play next") action:^{ [player playNext:track]; [self toast:L(@"Plays next")]; }];
        [sheet addButton:L(@"Add to queue") action:^{ [player addToQueue:track]; [self toast:L(@"Added to queue")]; }];
    }
    if (!track.isEpisode && track.trackId.length) {
        [sheet addButton:L(@"Save to Liked Songs") action:^{
            [S6Catalog setSaved:YES uris:@[ track.uri ] completion:^(NSError *error) { [self toast:error ? error.localizedDescription : L(@"Added to Liked Songs")]; }];
        }];
        [sheet addButton:L(@"Add to playlist") action:^{ [self addTrackToPlaylist:track]; }];
        [sheet addButton:L(@"Song radio") action:^{ [self playRadioFor:track]; }];
    }
    if (track.album.albumId.length) [sheet addButton:L(@"Go to album") action:^{ [self openAlbum:track.album]; }];
    S6Artist *artist = track.artists.firstObject;
    if (artist.artistId.length) [sheet addButton:L(@"Go to artist") action:^{ [self openArtist:artist]; }];
    if (track.trackId.length) {
        [sheet addButton:L(@"Copy link") action:^{
            [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://open.spotify.com/%@/%@", track.isEpisode ? @"episode" : @"track", track.trackId];
            [self toast:L(@"Link copied")];
        }];
    }
    if (playlist.editable && playlist.uri.length && track.uid.length) {
        [sheet addDestructiveButton:L(@"Remove from this playlist") action:^{
            [S6Catalog removeTrackUIDs:@[ track.uid ] fromPlaylist:playlist.uri completion:^(NSError *error) {
                [self toast:error ? error.localizedDescription : L(@"Removed")];
            }];
        }];
    }
    [sheet showFromView:view inController:controller];
}

+ (void)addTrackToPlaylist:(S6Track *)track
{
    if (!track.uri.length) return;
    S6PlaylistPickerViewController *picker = [[S6PlaylistPickerViewController alloc] initWithCompletion:^(S6Playlist *playlist) {
        if (!playlist) return;
        [S6Catalog addTracks:@[ track.uri ] toPlaylist:playlist.uri completion:^(NSError *error) {
            [self toast:error ? error.localizedDescription : [NSString stringWithFormat:L(@"Added to %@"), playlist.name]];
        }];
    }];
    picker.trackURI = track.uri;
    [[S6RootViewController shared] presentSheet:picker];
}

@end
