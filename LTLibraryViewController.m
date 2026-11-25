#import "LTPeekCoordinator.h"
#import "LTTraitCompat.h"
#import <objc/runtime.h>
#import "LTPlaylistPeekViewController.h"
#import "LTStationPeekViewController.h"
#import "LTArtworkPeekViewController.h"
#import "LTLibraryViewController.h"
#import "LTLibrarySongsViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTextPrompt.h"
#import "LTTabBarController.h"
#import "LTMediaCell.h"
#import "LTYouTubeClient.h"
#import "LTLocalPlaylistDetailViewController.h"
#import "LTStationDetailViewController.h"
#import "LTSmartPlaylistDetailViewController.h"
#import "LTSeedSearchViewController.h"
#import "LTGraphics.h"
#import "LTModel.h"
#import "LTLog.h"
#import "LTSimpleCell.h"
#import "LTTheme.h"
#import "LTCardControls.h"
#import "LTThemedTableView.h"
#import "LTTransitionSettings.h"
#import "S6Reachability.h"

typedef NS_ENUM(NSInteger, LTLibrarySegment) {
    LTLibrarySegmentPlaylists = 0,
    LTLibrarySegmentSongs,
    LTLibrarySegmentArtists,
    LTLibrarySegmentAlbums,
    LTLibrarySegmentStations,
};

// Smart playlists and stations need iOS 6+. On iOS 5 and below the segment is
// left out entirely rather than shown as a tab that cannot be used.
static BOOL LTModernLibraryFeaturesAllowed(void) {
    return [[[UIDevice currentDevice] systemVersion] integerValue] > 5;
}

@interface LTLibraryViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UISegmentedControl *segControl;
@property (nonatomic, strong) LTPeekCoordinator *peekCoordinator;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) NSInteger currentSegment;
@property (nonatomic, strong) NSMutableArray *playlists;
@property (nonatomic, strong) NSMutableArray *songs;
@property (nonatomic, strong) NSArray *artists;
@property (nonatomic, strong) NSArray *albums;
// Sorted once per -reloadModels rather than per row; see -currentItems.
@property (nonatomic, strong) NSArray *sortedArtists;
@property (nonatomic, strong) NSArray *sortedAlbums;
@property (nonatomic, strong) LTTrack *pendingRemoveTrack;
@property (nonatomic, assign) BOOL ignorePlaylistChanges;
// Tracks whether this tab has been shown before, so the first appearance does
// not repeat the model rebuild -viewDidLoad just did. See -viewWillAppear:.
@property (nonatomic, assign) BOOL hasAppearedOnce;
@property (nonatomic, strong) NSMutableSet *attemptedArtistAvatars;
// Artist avatars resolve in bursts; reload rows once, coalesced, on the next
// runloop turn rather than once per callback (reloading mid-reload throws).
@property (nonatomic, strong) NSMutableIndexSet *pendingAvatarRows;
@property (nonatomic, assign) BOOL avatarReloadScheduled;
@end

@implementation LTLibraryViewController

// Identifies which station a cell was last asked to draw, so a late artwork
// reply cannot land on a row that has since been reused.
static const void *kLTStationCellArtTokenKey = &kLTStationCellArtTokenKey;

// iOS 4 never sends -viewDidLayoutSubviews, so the compact font/style is also
// applied from viewDidLoad and rotation.
- (void)lt_applySegmentedFont {
    if (!self.segControl) return;
    CGFloat width = self.view.bounds.size.width;
    if (width < 1.0f) return;
    UIFont *font = (width < 360.0f) ? [UIFont boldSystemFontOfSize:9]
                                    : [UIFont boldSystemFontOfSize:11];
    [LTTheme setTitleFont:font forSegmentedControl:self.segControl];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self lt_applySegmentedFont];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    if (width < 1.0f) return;

    CGFloat tableY = 42.0f;

    [self lt_applySegmentedFont];

    self.segControl.frame = CGRectMake(8, 6, width - 16, 30);
    self.tableView.frame = CGRectMake(0, tableY, width, bounds.size.height - tableY);
    self.emptyLabel.frame = CGRectMake(24, tableY + 150, width - 48, 60);
}

- (void)viewDidLoad {
    // TEMP instrumentation: see LTTabBarController -snapshotContentOfView.
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = @"Library";
    self.view.backgroundColor = [LTTheme background];
    self.currentSegment = LTLibrarySegmentPlaylists;
    self.attemptedArtistAvatars = [NSMutableSet set];

    CGRect bounds = self.view.bounds;
    // The modern theme draws its own segmented control; the native one is
    // exactly right in the native theme.
    NSMutableArray *segments = [NSMutableArray arrayWithObjects:@"Playlists", @"Songs", @"Artists", @"Albums", nil];
    if (LTModernLibraryFeaturesAllowed()) [segments addObject:@"Stations"];
    self.segControl = [LTTheme isModern]
        ? (UISegmentedControl *)[[LTCardSegmented alloc] initWithItems:segments]
        : [[LTCompactSegmentedControl alloc] initWithItems:segments];
    self.segControl.selectedSegmentIndex = 0;
    [self.segControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.segControl.frame = CGRectMake(8, 6, bounds.size.width - 16, 30);
    self.segControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.segControl];
    [self lt_applySegmentedFont];

    CGFloat tableY = 42.0f;
    self.tableView = [[LTThemedTableView alloc] initWithFrame:CGRectMake(0, tableY, bounds.size.width, bounds.size.height - tableY)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme background];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, tableY + 100, bounds.size.width - 48, 60)];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textColor = [LTTheme secondaryText];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    [self reloadModels];
    [self reloadForSegment];
    // 3D Touch peek on playlist rows; a no-op below iOS 9.
    __unsafe_unretained LTLibraryViewController *peekSelf = self;
    self.peekCoordinator = [[LTPeekCoordinator alloc] initWithOwner:self
                                                      sourceView:self.tableView
                                                   peekProvider:^UIViewController *(CGPoint point) {
        return [peekSelf peekViewControllerAtPoint:point];
    } commit:^(UIViewController *peek) {
        [peekSelf handlePeekCommit:peek];
    }];
    [self.peekCoordinator registerPreview];
    LTLog(@"TABPROF library viewDidLoad=%.0fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryReloadNeeded:) name:@"LTLibraryReloadNeeded" object:nil];
}

- (void)libraryReloadNeeded:(NSNotification *)n {
    [self reloadModels];
    [self reloadForSegment];
}

- (void)reachabilityChanged:(NSNotification *)n {
    [self reloadForSegment];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"LTLibraryReloadNeeded" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    // TEMP instrumentation: see LTTabBarController -snapshotContentOfView.
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
    // Hide smart playlists as soon as the connection drops, without waiting
    // for the user to switch subtabs or revisit the library.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged:)
                                                 name:S6ReachabilityChangedNotification
                                               object:nil];
    // -viewDidLoad has already built the models and reloaded on the very first
    // appearance, and UIKit calls it immediately before this. Re-running the
    // full disk scan here meant the first visit to this tab did the work twice,
    // back to back, with nothing able to have changed in between.
    if (_hasAppearedOnce) {
        [self reloadModels];
    }
    _hasAppearedOnce = YES;
    CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
    [self reloadForSegment];
    LTLog(@"TABPROF library viewWillAppear models=%.0fms reloadData=%.0fms total=%.0fms",
          (t1 - t0) * 1000.0,
          (CFAbsoluteTimeGetCurrent() - t1) * 1000.0,
          (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme background];
    self.tableView.backgroundColor = [LTTheme background];
    self.emptyLabel.textColor = [LTTheme secondaryText];
    [self.tableView reloadData];
}

#pragma mark - Data

- (void)reloadModels {
    // TEMP instrumentation: see LTTabBarController -snapshotContentOfView.
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    self.playlists = [[[LTPlaylistStore sharedStore] playlists] mutableCopy] ?: [NSMutableArray array];
    CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
    // libraryTracks, not downloadedTracks: a song you put in a playlist belongs
    // to you even when it is not on the device, and downloads already feed the
    // library, so this is a superset rather than a swap.
    self.songs = [[[LTPlaylistStore sharedStore] libraryTracks] mutableCopy] ?: [NSMutableArray array];
    CFAbsoluteTime t2 = CFAbsoluteTimeGetCurrent();

    NSMutableDictionary *artistMap = [NSMutableDictionary dictionary];
    for (LTTrack *track in self.songs) {
        NSString *name = (track.artist.length ? track.artist : @"Unknown Artist");
        NSString *key = [name lowercaseString];
        NSMutableDictionary *bucket = [artistMap objectForKey:key];
        if (!bucket) {
            bucket = [NSMutableDictionary dictionaryWithObjectsAndKeys:name, @"name",
                                                             [NSMutableArray array], @"tracks", nil];
            [artistMap setObject:bucket forKey:key];
        }
        [[bucket objectForKey:@"tracks"] addObject:track];
    }
    self.artists = [artistMap allValues];
    CFAbsoluteTime t3 = CFAbsoluteTimeGetCurrent();

    NSMutableDictionary *albumMap = [NSMutableDictionary dictionary];
    for (LTTrack *track in self.songs) {
        NSString *rawAlbum = (track.album.length ? track.album : (track.title.length ? track.title : @"Unknown Album"));
        NSString *album = [self isUnknownAlbumPlaceholder:rawAlbum] ? @"Unknown Album" : rawAlbum;
        NSString *artist = (track.artist.length ? track.artist : @"Unknown Artist");
        NSString *key = [NSString stringWithFormat:@"%@|%@", [artist lowercaseString], [album lowercaseString]];
        NSMutableDictionary *bucket = [albumMap objectForKey:key];
        if (!bucket) {
            bucket = [NSMutableDictionary dictionaryWithObjectsAndKeys:album, @"name",
                                                             artist, @"artist",
                                                             [NSMutableArray array], @"tracks", nil];
            [albumMap setObject:bucket forKey:key];
        }
        [[bucket objectForKey:@"tracks"] addObject:track];
    }
    self.albums = [albumMap allValues];
    [self rebuildSortedCache];
    LTLog(@"TABPROF reloadModels playlists=%.0fms downloaded=%.0fms(%d) artists=%.0fms",
          (t1 - t0) * 1000.0, (t2 - t1) * 1000.0, (int)self.songs.count,
          (t3 - t2) * 1000.0);
}

- (NSArray *)sortedByName:(NSArray *)buckets {
    return [buckets sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a objectForKey:@"name"] caseInsensitiveCompare:[b objectForKey:@"name"]];
    }];
}

// Sorting is done once per model rebuild and cached, rather than inside
// -currentItems. -currentItems is called from -numberOfRowsInSection AND from
// every -cellForRowAtIndexPath:, so the old arrangement re-sorted the entire
// artist or album list once per visible row on every reload: O(rows * n log n)
// of case-insensitive string compares just to draw a list. Switching to the
// Artists or Albums subtab paid the full N+1 sorts before the first cell drew.
- (void)rebuildSortedCache {
    _sortedArtists = self.artists.count ? [self sortedByName:self.artists] : [NSArray array];
    _sortedAlbums = self.albums.count ? [self sortedByName:self.albums] : [NSArray array];
}

- (NSArray *)currentItems {
    switch (self.currentSegment) {
        case LTLibrarySegmentPlaylists: return self.playlists;
        case LTLibrarySegmentSongs: return self.songs;
        case LTLibrarySegmentArtists: return self.sortedArtists;
        case LTLibrarySegmentAlbums: return self.sortedAlbums;
        case LTLibrarySegmentStations: return [[LTPlaylistStore sharedStore] stations];
    }
    return nil;
}

- (BOOL)isUnknownAlbumPlaceholder:(NSString *)name {
    if (name.length != 1) return NO;
    unichar character = [name characterAtIndex:0];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    if ([letters characterIsMember:character]) return NO;
    if ([digits characterIsMember:character]) return NO;
    return YES;
}

- (void)reloadForSegment {
    [self updateRightBarButton];
    [self.tableView reloadData];
    [self refreshEmptyState];
}

- (void)updateRightBarButton {
    if (self.currentSegment == LTLibrarySegmentPlaylists) {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                               target:self
                                                                                               action:@selector(newPlaylistTapped:)];
        self.navigationItem.rightBarButtonItem.style = UIBarButtonItemStyleBordered;
    } else if (self.currentSegment == LTLibrarySegmentStations) {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                               target:self
                                                                                               action:@selector(newStationTapped:)];
        self.navigationItem.rightBarButtonItem.style = UIBarButtonItemStyleBordered;
    } else if (self.currentSegment == LTLibrarySegmentSongs) {
        UIBarButtonItem *shuffleItem = [[UIBarButtonItem alloc] initWithTitle:@"Shuffle"
                                                                        style:UIBarButtonItemStyleBordered
                                                                       target:self
                                                                       action:@selector(shuffleAllTapped)];
        UIBarButtonItem *playItem = [[UIBarButtonItem alloc] initWithTitle:@"Play All"
                                                                     style:UIBarButtonItemStyleBordered
                                                                    target:self
                                                                    action:@selector(playAllTapped)];
        shuffleItem.enabled = self.songs.count > 0;
        playItem.enabled = self.songs.count > 0;
        self.navigationItem.leftBarButtonItem = shuffleItem;
        self.navigationItem.rightBarButtonItem = playItem;
    } else if (self.currentSegment == LTLibrarySegmentStations) {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                               target:self
                                                                                               action:@selector(newStationTapped:)];
        self.navigationItem.rightBarButtonItem.style = UIBarButtonItemStyleBordered;
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)newStationTapped:(id)sender {
    if (!LTModernLibraryFeaturesAllowed()) return;
    __unsafe_unretained LTLibraryViewController *weakSelf = self;
    [LTTextPrompt presentIn:self
                      title:@"New Station"
                    message:@"Enter a name for the station."
                placeholder:@"Station name"
                initialText:nil
                 completion:^(NSString *text, BOOL cancelled) {
        LTLibraryViewController *strongSelf = weakSelf;
        if (!strongSelf || cancelled) return;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length) name = @"New Station";
        LTStation *station = [[LTPlaylistStore sharedStore] createStationWithName:name seeds:[NSArray array]];
        [strongSelf reloadForSegment];
        if (station) {
            LTStationDetailViewController *detail = [[LTStationDetailViewController alloc] initWithStation:station];
            [strongSelf.navigationController pushViewController:detail animated:YES];
#if !__has_feature(objc_arc)
            [detail release];
#endif
        }
    }];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    // UIKit calls this automatically on tap; handle everything here.
    if (actionSheet.tag == 9999) {
        if (!LTModernLibraryFeaturesAllowed()) return;
        NSString *seedType = nil;
        if (buttonIndex == 0) seedType = @"track";
        else if (buttonIndex == 1) seedType = @"artist";
        else if (buttonIndex == 2) seedType = @"album";
        if (seedType) {
            LTSeedSearchViewController *searchVC = [[LTSeedSearchViewController alloc] initWithSeedType:seedType];
            searchVC.delegate = self;
            [self.navigationController pushViewController:searchVC animated:YES];
        }
        return;
    }
    if (actionSheet.tag == 8888) {
        NSArray *songs = self.songs ?: [NSArray array];
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)songs.count) return;
        LTTrack *t = [songs objectAtIndex:(NSUInteger)buttonIndex];
        LTStationSeed *seed = [[LTStationSeed alloc] init];
        seed.type = @"track";
        seed.videoId = t.videoId;
        seed.title = t.title;
        seed.artist = t.artist;
        seed.album = t.album;
        seed.thumbnailURL = t.thumbnailURL;
        NSString *name = t.artist.length ? [NSString stringWithFormat:@"%@ Radio", t.artist] : (t.title.length ? t.title : @"Station");
        [[LTPlaylistStore sharedStore] createStationWithName:name seeds:@[seed]];
#if !__has_feature(objc_arc)
        [seed release];
#endif
        [self selectSegment:(NSInteger)LTLibrarySegmentStations];
        return;
    }
    if (actionSheet.tag == 7777) {
        NSArray *artists = self.sortedArtists ?: [NSArray array];
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)artists.count) return;
        NSDictionary *a = [artists objectAtIndex:(NSUInteger)buttonIndex];
        NSString *aname = [a objectForKey:@"name"] ?: @"Unknown Artist";
        LTStationSeed *seed = [[LTStationSeed alloc] init];
        seed.type = @"artist";
        seed.artist = aname;
        
        // Get thumbnail from first track of this artist
        NSArray *artistTracks = [a objectForKey:@"tracks"];
        if (artistTracks.count > 0) {
            LTTrack *firstTrack = [artistTracks objectAtIndex:0];
            if (firstTrack.thumbnailURL.length) {
                seed.thumbnailURL = firstTrack.thumbnailURL;
            }
        }
        
        NSString *name = [NSString stringWithFormat:@"%@ Radio", aname];
        [[LTPlaylistStore sharedStore] createStationWithName:name seeds:@[seed]];
#if !__has_feature(objc_arc)
        [seed release];
#endif
        [self selectSegment:(NSInteger)LTLibrarySegmentStations];
        return;
    }
    if (actionSheet.tag == 6666) {
        NSArray *albums = self.sortedAlbums ?: [NSArray array];
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)albums.count) return;
        NSDictionary *al = [albums objectAtIndex:(NSUInteger)buttonIndex];
        NSString *name = [al objectForKey:@"name"] ?: @"Album";
        NSString *artist = [al objectForKey:@"artist"];
        LTStationSeed *seed = [[LTStationSeed alloc] init];
        seed.type = @"album";
        seed.album = name;
        seed.artist = artist;
        
        // Get thumbnail from first track of this album
        NSArray *albumTracks = [al objectForKey:@"tracks"];
        if (albumTracks.count > 0) {
            LTTrack *firstTrack = [albumTracks objectAtIndex:0];
            if (firstTrack.thumbnailURL.length) {
                seed.thumbnailURL = firstTrack.thumbnailURL;
            }
        }
        
        NSString *sname = artist.length ? [NSString stringWithFormat:@"%@ - %@ Radio", artist, name] : [NSString stringWithFormat:@"%@ Radio", name];
        [[LTPlaylistStore sharedStore] createStationWithName:sname seeds:@[seed]];
#if !__has_feature(objc_arc)
        [seed release];
#endif
        [self selectSegment:(NSInteger)LTLibrarySegmentStations];
        return;
    }
}

- (void)createStationFromSong {
    if (!LTModernLibraryFeaturesAllowed()) return;
    NSArray *songs = self.songs ?: [NSArray array];
    if (songs.count == 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Songs" message:@"Add songs to your library first." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
#if !__has_feature(objc_arc)
        [alert release];
#endif
        return;
    }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Choose a Song"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    sheet.tag = 8888;
    for (LTTrack *t in songs) {
        NSString *name = t.title.length ? t.title : @"Unknown";
        if (t.artist.length) name = [NSString stringWithFormat:@"%@ - %@", t.artist, t.title];
        [sheet addButtonWithTitle:name];
    }
    [sheet addButtonWithTitle:@"Cancel"];
    sheet.cancelButtonIndex = (NSInteger)songs.count;
    [sheet showInView:self.view];
#if !__has_feature(objc_arc)
    [sheet release];
#endif
}

- (void)createStationFromArtist {
    if (!LTModernLibraryFeaturesAllowed()) return;
    NSArray *artists = self.sortedArtists ?: [NSArray array];
    if (artists.count == 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Artists" message:@"Add songs to your library first." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
#if !__has_feature(objc_arc)
        [alert release];
#endif
        return;
    }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Choose an Artist"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    sheet.tag = 7777;
    for (NSDictionary *a in artists) {
        [sheet addButtonWithTitle:[a objectForKey:@"name"] ?: @"Unknown"];
    }
    [sheet addButtonWithTitle:@"Cancel"];
    sheet.cancelButtonIndex = (NSInteger)artists.count;
    [sheet showInView:self.view];
#if !__has_feature(objc_arc)
    [sheet release];
#endif
}

- (void)createStationFromAlbum {
    if (!LTModernLibraryFeaturesAllowed()) return;
    NSArray *albums = self.sortedAlbums ?: [NSArray array];
    if (albums.count == 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Albums" message:@"Add songs to your library first." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
#if !__has_feature(objc_arc)
        [alert release];
#endif
        return;
    }
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Choose an Album"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    sheet.tag = 6666;
    for (NSDictionary *a in albums) {
        [sheet addButtonWithTitle:[a objectForKey:@"name"] ?: @"Unknown"];
    }
    [sheet addButtonWithTitle:@"Cancel"];
    sheet.cancelButtonIndex = (NSInteger)albums.count;
    [sheet showInView:self.view];
#if !__has_feature(objc_arc)
    [sheet release];
#endif
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    // no-op; handled in clickedButtonAtIndex
}

- (void)shuffleAllTapped {
    LTPlayerController *player = [LTPlayerController sharedController];
    player.repeatMode = LTRepeatModeAll;
    player.queueSourceName = @"Library";
    [player playQueue:self.songs shuffle:YES];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)playAllTapped {
    if (!self.songs.count) return;
    LTPlayerController *player = [LTPlayerController sharedController];
    player.repeatMode = LTRepeatModeAll;
    player.queueSourceName = @"Library";
    [player playQueue:self.songs atIndex:0];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)refreshEmptyState {
    NSArray *items = [self currentItems];
    if (items.count) {
        self.emptyLabel.hidden = YES;
        return;
    }
    switch (self.currentSegment) {
        case LTLibrarySegmentPlaylists:
            self.emptyLabel.text = @"No playlists yet.\nTap + to create one.";
            break;
        case LTLibrarySegmentSongs:
            // Songs is your library, not just what is on the device: a song you
            // added to a playlist belongs here whether or not it was downloaded.
            self.emptyLabel.text = @"No songs yet.\nAdd songs to a playlist, or download them, to build your library.";
            break;
        case LTLibrarySegmentArtists:
        case LTLibrarySegmentAlbums:
        default:
            self.emptyLabel.text = @"Download songs to build your library.";
            break;
    }
    self.emptyLabel.hidden = NO;
}

#pragma mark - Actions

// Stations need iOS 6+ and fetch their seeds and tracks from the network.
// On old systems the tab is not offered at all; offline it is rejected with
// an explanation. UIAlertView works unchanged on iOS 4 through iOS 9.
- (BOOL)stationsAllowed {
    if (!LTModernLibraryFeaturesAllowed()) return NO;
    if ([S6Reachability online]) return YES;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Stations"
                                                    message:@"Stations require an internet connection."
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
#if !__has_feature(objc_arc)
    [alert release];
#endif
    return NO;
}

- (void)selectSegment:(NSInteger)index {
    if (index == (NSInteger)LTLibrarySegmentStations && ![self stationsAllowed]) {
        // Leave the control and the table on the subtab the user came from.
        self.segControl.selectedSegmentIndex = self.currentSegment;
        return;
    }
    self.currentSegment = index;
    [self reloadForSegment];
}

- (void)segmentChanged:(id)sender {
    [self selectSegment:self.segControl.selectedSegmentIndex];
}

- (void)newPlaylistTapped:(id)sender {
    __unsafe_unretained LTLibraryViewController *weakSelf = self;
    [LTTextPrompt presentIn:self
                      title:@"New Playlist"
                    message:@"Enter a name for the playlist."
                placeholder:@"Playlist name"
                initialText:nil
                 completion:^(NSString *text, BOOL cancelled) {
        LTLibraryViewController *strongSelf = weakSelf;
        if (!strongSelf || cancelled) return;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) {
            [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
            [strongSelf showToast:@"Playlist created"];
        }
    }];
}

- (void)storeDidChange:(NSNotification *)notification {
    if (self.ignorePlaylistChanges) return;
    [self reloadModels];
    [self reloadForSegment];
}

- (void)showToast:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 220, 36)];
    label.center = CGPointMake(self.view.bounds.size.width / 2.0f, self.view.bounds.size.height - 80);
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75f];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:13];
    label.layer.cornerRadius = 6.0f;
    label.clipsToBounds = YES;
    label.text = text;
    [self.view addSubview:label];
    [LTTransitionSettings animateWithDuration:1.4 delay:1.0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ label.alpha = 0.0f; }
                     completion:^(BOOL finished) { [label removeFromSuperview]; }];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 620 && buttonIndex == 1) {
        if (self.pendingRemoveTrack) {
            LTTrack *track = self.pendingRemoveTrack;
            self.pendingRemoveTrack = nil;
            LTLog(@"LIB remove download %@ title=%@", track.videoId, track.title);
            [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[track]];
        }
        return;
    }
    if (alertView.tag == 621 && buttonIndex == 1) {
        // Removal from the library posts its own change notification, so
        // -storeDidChange: refreshes the list; do not touch the model here.
        if (self.pendingRemoveTrack) {
            LTTrack *track = self.pendingRemoveTrack;
            self.pendingRemoveTrack = nil;
            LTLog(@"LIB remove from library %@ title=%@", track.videoId, track.title);
            [[LTPlaylistStore sharedStore] removeTrackFromLibrary:track];
        }
        return;
    }
    // Tags 700/710 (new playlist/station) are handled via LTTextPrompt.
}

#pragma mark - UITableViewDataSource

- (BOOL)smartPlaylistsEnabled {
    // Smart playlists need iOS 6+ and their recommendations need the network.
    // Hide them on older systems and while offline, regardless of the setting.
    if (!LTModernLibraryFeaturesAllowed()) return NO;
    if (![S6Reachability online]) return NO;
    return ![[NSUserDefaults standardUserDefaults] boolForKey:@"LTDisableSmartPlaylists"];
}

- (NSArray *)smartPlaylists {
    if (!self.smartPlaylistsEnabled) return [NSArray array];
    return [LTSmartPlaylistDetailViewController smartPlaylistNames];
}

- (NSArray *)smartTracksForIndex:(NSInteger)idx {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    if (idx == 0) return [store topPlayedTracks:50];
    if (idx == 1) return [store recentlyPlayedTracks:50];
    return [store mostTimeListenedTracks:50];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.currentSegment == LTLibrarySegmentPlaylists) {
        return self.smartPlaylistsEnabled ? 2 : 1;
    }
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled) {
        if (section == 0) return (NSInteger)self.smartPlaylists.count;
        return (NSInteger)self.playlists.count;
    }
    return (NSInteger)[[self currentItems] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled) {
        return section == 0 ? @"Smart Playlists" : @"Playlists";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *TrackCellId = @"LTLibraryTrackCell";
    static NSString *BucketCellId = @"LTLibraryBucketCell";
    // TEMP instrumentation: see LTTabBarController -snapshotContentOfView.
    CFAbsoluteTime tRow = CFAbsoluteTimeGetCurrent();

    // Smart playlists section in Playlists segment
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled && indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:BucketCellId];
        if (!cell) {
            cell = [[LTSimpleCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:BucketCellId];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor grayColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        NSString *name = [self.smartPlaylists objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = name;
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.text = @"";
        cell.imageView.image = nil;
        cell.contentView.frame = CGRectMake(0, 0, cell.bounds.size.width, 36.0f);
        return cell;
    }

    NSArray *items = [self currentItems];
    NSInteger rowIndex = indexPath.row;
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled && indexPath.section == 1) {
        // items is self.playlists; rowIndex already correct
    }
    id item = [items objectAtIndex:(NSUInteger)rowIndex];

    if (self.currentSegment == LTLibrarySegmentSongs) {
        LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:TrackCellId];
        if (!cell) {
            cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:TrackCellId];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor grayColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        LTTrack *track = item;
        cell.textLabel.text = track.title;
        NSMutableString *detail = [NSMutableString string];
        if (track.artist.length) [detail appendString:track.artist];
        if (track.duration > 0) {
            if (detail.length) [detail appendString:@"   "];
            [detail appendString:[self formatDuration:track.duration]];
        }
        cell.detailTextLabel.text = detail;
        if (track.thumbnailURL.length) {
            [cell setImageFromURL:track.thumbnailURL];
        } else {
            cell.imageView.image = nil;
        }
        cell.accessoryView = [self accessoryButtonForRow:indexPath.row];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:BucketCellId];
    if (!cell) {
        cell = [[LTSimpleCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:BucketCellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.imageView.image = nil;

    if ([item isKindOfClass:[LTLocalPlaylist class]]) {
        LTLocalPlaylist *playlist = item;
        cell.textLabel.text = playlist.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%d track%@", (int)playlist.tracks.count, playlist.tracks.count == 1 ? @"" : @"s"];
        [LTPlaylistStore providePlaylistArtwork:playlist toCell:cell];
    } else if ([item isKindOfClass:[LTStation class]]) {
        LTStation *station = item;
        cell.textLabel.text = station.name;
        if (station.seeds.count) {
            LTStationSeed *s = [station.seeds objectAtIndex:0];
            if ([s.type isEqualToString:@"track"] && s.title.length) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"From %@", s.title];
            } else if ([s.type isEqualToString:@"artist"] && s.artist.length) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ Radio", s.artist];
            } else if ([s.type isEqualToString:@"album"] && s.album.length) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ Radio", s.album];
            } else {
                cell.detailTextLabel.text = @"Radio Station";
            }
        } else {
            cell.detailTextLabel.text = @"Radio Station";
        }
        
        // Custom cover takes priority
        if (station.coverPath.length) {
            UIImage *cover = [UIImage imageWithContentsOfFile:station.coverPath];
            if (cover) {
                cell.imageView.image = cover;
                return cell;
            }
        }

        // Use station.png with seed overlay logic
        NSString *stationPath = [[NSBundle mainBundle] pathForResource:@"station" ofType:@"png"];
        UIImage *stationBase = [UIImage imageWithContentsOfFile:stationPath];
        
        // Ensure imageView is properly sized
        cell.imageView.frame = CGRectMake(0, 0, 44, 44);
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        
        if (station.seeds.count > 0) {
            LTStationSeed *seed = [station.seeds objectAtIndex:0];
            if (seed.thumbnailURL.length) {
                // Strong capture, plus a token: the cell can go away while the
                // seed artwork is loading, and an unsafe-unretained pointer
                // then writes into freed memory when the reply lands.
                NSString *artToken = station.identifier ?: (station.name ?: @"");
                objc_setAssociatedObject(cell, kLTStationCellArtTokenKey, artToken,
                                         OBJC_ASSOCIATION_COPY_NONATOMIC);
                NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:seed.thumbnailURL];
                [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *seedImage) {
                    NSString *current = objc_getAssociatedObject(cell, kLTStationCellArtTokenKey);
                    if (![current isEqualToString:artToken]) return; // reused row
                    if (!seedImage) {
                        cell.imageView.image = stationBase ?: [LTGraphics musicIcon];
                        return;
                    }
                    
                    // Create composite image
                    CGSize size = CGSizeMake(44, 44);
                    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
                    
                    if (stationBase) {
                        [stationBase drawInRect:CGRectMake(0, 0, size.width, size.height)];
                    }
                    
                    // Green circle in 512x512 image is at 108x109+263+238
                    // Scaled to 44px: ~9x9 at position ~23,20
                    CGFloat insetX = 23.0f;
                    CGFloat insetY = 21.0f;
                    CGFloat overlayWidth = 9.0f;
                    CGFloat overlayHeight = 9.0f;
                    CGRect seedRect = CGRectMake(insetX, insetY, overlayWidth, overlayHeight);
                    
                    // Create circular path for clipping
                    CGContextRef context = UIGraphicsGetCurrentContext();
                    CGContextSaveGState(context);
                    UIBezierPath *circlePath = [UIBezierPath bezierPathWithOvalInRect:seedRect];
                    [circlePath addClip];
                    
                    [seedImage drawInRect:seedRect];
                    
                    CGContextRestoreGState(context);
                    
                    UIImage *composite = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    
                    cell.imageView.image = composite;
                }];
            } else {
                cell.imageView.image = stationBase ?: [LTGraphics musicIcon];
            }
        } else {
            cell.imageView.image = stationBase ?: [LTGraphics musicIcon];
        }
    } else {
        NSDictionary *bucket = item;
        NSArray *tracks = [bucket objectForKey:@"tracks"];
        NSString *name = [bucket objectForKey:@"name"];
        BOOL isArtist = (self.currentSegment == LTLibrarySegmentArtists);
        if (isArtist) {
            cell.textLabel.text = name;
            // -accessibilityIdentifier is iOS 5+, and sending it on iOS 4.1 is
            // an unrecognised selector (it crashed on the first scroll of the
            // Artists list). Nothing depends on it there.
            if ([cell respondsToSelector:@selector(setAccessibilityIdentifier:)]) {
                cell.accessibilityIdentifier = name;
            }
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d song%@", (int)tracks.count, tracks.count == 1 ? @"" : @"s"];
        } else {
            cell.textLabel.text = name;
            NSString *artist = [bucket objectForKey:@"artist"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@   %d song%@",
                                         artist, (int)tracks.count, tracks.count == 1 ? @"" : @"s"];
        }
        NSString *avatarURL = isArtist ? [[LTPlaylistStore sharedStore] artistAvatarURLForName:name] : nil;
        // One URL per row. The avatar is preferred for an artist because it is
        // the artist's own image, but a 120px avatar in a 40pt cell reads as
        // nothing, so ask for a size that survives the scale factor, and fall
        // through to the track's artwork when there is no avatar at all.
        NSString *rowArtURL = avatarURL.length
            ? [[LTYouTubeClient sharedClient] channelAvatarURL:avatarURL size:480]
            : nil;
        if (isArtist && !rowArtURL.length) [self resolveAvatarForArtistName:name];
        if (!rowArtURL.length && tracks.count) {
            LTTrack *first = [tracks objectAtIndex:0];
            rowArtURL = first.thumbnailURL;
        }
        if (rowArtURL.length) {
            LTLog(@"LIBROW %@ '%@' avatar=%d art=%@", isArtist ? @"artist" : @"album",
                  name, avatarURL.length ? 1 : 0, rowArtURL);
            [[LTYouTubeClient sharedClient] loadArtworkURL:rowArtURL intoCell:cell];
        } else {
            LTLog(@"LIBROW %@ '%@' NO ART (tracks=%d)", isArtist ? @"artist" : @"album",
                  name, (int)tracks.count);
            // Never leave the row blank. A music note reads as "no artwork yet",
            // where an empty image view just looks broken.
            cell.imageView.image = [LTGraphics musicIcon];
        }
    }
    LTLog(@"TABPROF cell row=%d %.0fms", (int)indexPath.row, (CFAbsoluteTimeGetCurrent() - tRow) * 1000.0);
    return cell;
}

- (void)queueAvatarRowReload:(NSInteger)row {
    if (!self.pendingAvatarRows) self.pendingAvatarRows = [NSMutableIndexSet indexSet];
    [self.pendingAvatarRows addIndex:(NSUInteger)row];
    if (self.avatarReloadScheduled) return;
    self.avatarReloadScheduled = YES;
    __unsafe_unretained LTLibraryViewController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        LTLibraryViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.avatarReloadScheduled = NO;
        [strongSelf flushAvatarRowReloads];
    });
}

- (void)flushAvatarRowReloads {
    NSIndexSet *pending = [self.pendingAvatarRows copy];
    [self.pendingAvatarRows removeAllIndexes];
    if (!pending.count) return;
    NSInteger rows = [self.tableView numberOfRowsInSection:0];
    NSMutableArray *paths = [NSMutableArray array];
    // The segment can change under us while avatars are in flight, so re-check
    // every index against what the table currently has.
    [pending enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if ((NSInteger)idx < rows) {
            [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)idx inSection:0]];
        }
    }];
    if (!paths.count) return;
    [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
}

- (void)resolveAvatarForArtistName:(NSString *)name {
    if (!name.length) return;
    NSString *key = [name lowercaseString];
    if ([self.attemptedArtistAvatars containsObject:key]) return;
    [self.attemptedArtistAvatars addObject:key];
    __unsafe_unretained LTLibraryViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] resolveArtistAvatarForName:name completion:^(NSString *avatarURL) {
        LTLibraryViewController *strongSelf = weakSelf;
        if (!strongSelf || !avatarURL.length) return;
        if (strongSelf.currentSegment != LTLibrarySegmentArtists) return;
        NSArray *items = [strongSelf currentItems];
        for (NSUInteger i = 0; i < items.count; i++) {
            id candidate = [items objectAtIndex:i];
            if (![candidate isKindOfClass:[NSDictionary class]]) continue;
            if (![[candidate objectForKey:@"name"] isEqualToString:name]) continue;
            [strongSelf queueAvatarRowReload:(NSInteger)i];
            break;
        }
    }];
}

// The row accessory has to reflect whether the song is actually on the device.
// This used to be an unconditional checkmark meaning "downloaded", which was
// true when the list was built from downloadedTracks alone but became a lie
// once playlist songs were admitted: a song you had merely put in a playlist
// got the same green tick, and tapping it did nothing because
// -rowRemoveTapped: is gated on isTrackDownloaded:.
//
// Now it is a tick that removes a download, and a bin that removes the song
// from the library. The bin is the important one: the library gains entries
// from downloads, from adding a song to a playlist, and from peer sync, and
// until now it could only grow - so a song removed from a playlist stayed in
// the library forever with no way out.
- (UIButton *)accessoryButtonForRow:(NSInteger)row {
    LTTrack *track = nil;
    NSArray *items = [self currentItems];
    if (row >= 0 && row < (NSInteger)items.count) {
        id candidate = [items objectAtIndex:(NSUInteger)row];
        if ([candidate isKindOfClass:[LTTrack class]]) track = candidate;
    }
    BOOL downloaded = track && [[LTPlaylistStore sharedStore] isTrackDownloaded:track];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 32);
    UIImage *icon = downloaded ? [LTGraphics checkmarkIcon] : [LTGraphics removeIcon];
    [button setImage:[self scaledIcon:icon] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.tag = row;
    [button addTarget:self
                  action:downloaded ? @selector(rowRemoveTapped:) : @selector(rowRemoveFromLibraryTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIImage *)scaledIcon:(UIImage *)image {
    if (!image) return nil;
    CGSize target = CGSizeMake(22.0f, 22.0f);
    UIGraphicsBeginImageContextWithOptions(target, NO, image.scale);
    CGFloat scale = MIN(target.width / image.size.width, target.height / image.size.height);
    CGFloat dw = image.size.width * scale;
    CGFloat dh = image.size.height * scale;
    CGRect rect = CGRectMake((target.width - dw) / 2.0f, (target.height - dh) / 2.0f, dw, dh);
    [image drawInRect:rect];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled;
}

- (void)rowRemoveFromLibraryTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    NSArray *items = [self currentItems];
    if (row < 0 || row >= (NSInteger)items.count) return;
    LTTrack *track = [items objectAtIndex:(NSUInteger)row];
    if (![track isKindOfClass:[LTTrack class]]) return;
    if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    self.pendingRemoveTrack = track;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove from Library"
                                                    message:[NSString stringWithFormat:@"Remove \"%@\" from your library? Playlists it is in are not affected.", track.title]
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Remove", nil];
    alert.tag = 621;
    [alert show];
}

- (void)rowRemoveTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    NSArray *items = [self currentItems];
    if (row < 0 || row >= (NSInteger)items.count) return;
    LTTrack *track = [items objectAtIndex:(NSUInteger)row];
    if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    self.pendingRemoveTrack = track;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove Download"
                                                    message:[NSString stringWithFormat:@"Remove \"%@\" from your offline downloads?", track.title]
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Remove", nil];
    alert.tag = 620;
    [alert show];
}

- (NSString *)formatDuration:(NSTimeInterval)duration {
    NSInteger seconds = (NSInteger)duration;
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled && indexPath.section == 0) return 36.0f;
    return 58.0f;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled && indexPath.section == 0) return NO;
    if (self.currentSegment == LTLibrarySegmentPlaylists) return YES;
    if (self.currentSegment == LTLibrarySegmentStations) return YES;
    return NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentSegment == LTLibrarySegmentStations) {
        NSArray *items = [self currentItems];
        if (indexPath.row < (NSInteger)items.count && [[items objectAtIndex:(NSUInteger)indexPath.row] isKindOfClass:[LTStation class]]) {
            return UITableViewCellEditingStyleDelete;
        }
        return UITableViewCellEditingStyleNone;
    }
    if (self.currentSegment != LTLibrarySegmentPlaylists) return UITableViewCellEditingStyleNone;
    if (self.smartPlaylistsEnabled && indexPath.section == 0) return UITableViewCellEditingStyleNone;
    if (indexPath.row >= (NSInteger)self.playlists.count) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Delete";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (self.currentSegment == LTLibrarySegmentStations) {
        NSArray *items = [self currentItems];
        if (indexPath.row >= (NSInteger)items.count) return;
        id item = [items objectAtIndex:(NSUInteger)indexPath.row];
        if ([item isKindOfClass:[LTStation class]]) {
            [[LTPlaylistStore sharedStore] deleteStation:item];
            [self reloadForSegment];
            return;
        }
        return;
    }
    if (indexPath.row >= (NSInteger)self.playlists.count) return;
    LTLocalPlaylist *playlist = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    __unsafe_unretained LTLibraryViewController *weakSelf = self;
    [LTPlaylistStore confirmDeletePlaylist:playlist presenting:self completion:^(BOOL deleted) {
        if (!deleted) return;
        [weakSelf refreshEmptyState];
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // Smart playlists — use the standard playlist view (smart mode)
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled && indexPath.section == 0) {
        NSString *name = [self.smartPlaylists objectAtIndex:(NSUInteger)indexPath.row];
        LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithSmartIndex:indexPath.row name:name];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    NSArray *items = [self currentItems];
    NSInteger rowIdx = indexPath.row;
    if (rowIdx >= (NSInteger)items.count) return;
    id item = [items objectAtIndex:(NSUInteger)rowIdx];

    if (self.currentSegment == LTLibrarySegmentSongs) {
        [LTPlayerController sharedController].queueSourceName = @"Library";
        [[LTPlayerController sharedController] playQueue:[self currentItems] atIndex:indexPath.row];
        [(LTTabBarController *)self.tabBarController showNowPlaying];
    } else if (self.currentSegment == LTLibrarySegmentPlaylists && [item isKindOfClass:[LTLocalPlaylist class]]) {
        LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:item];
        [self.navigationController pushViewController:detail animated:YES];
    } else if ([item isKindOfClass:[LTStation class]]) {
        LTStationDetailViewController *detail = [[LTStationDetailViewController alloc] initWithStation:item];
        [self.navigationController pushViewController:detail animated:YES];
    } else if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *bucket = item;
        NSArray *tracks = [bucket objectForKey:@"tracks"];
        NSString *name = [bucket objectForKey:@"name"];
        LTLibrarySongsViewController *detail = [[LTLibrarySongsViewController alloc] initWithTracks:tracks title:name];
        [self.navigationController pushViewController:detail animated:YES];
    }}
#pragma mark - 3D Touch peek

// Only meaningful on the Playlists segment, so the segment is checked at peek
// time rather than when the coordinator is registered.
- (LTLocalPlaylist *)peekPlaylistAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentSegment != LTLibrarySegmentPlaylists) return nil;
    if (self.smartPlaylistsEnabled && indexPath.section == 0) return nil;
    if ((NSUInteger)indexPath.row >= self.playlists.count) return nil;
    return [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
}

- (LTStation *)peekStationAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentSegment != LTLibrarySegmentStations) return nil;
    NSArray *stations = [[LTPlaylistStore sharedStore] stations];
    if ((NSUInteger)indexPath.row >= stations.count) return nil;
    return [stations objectAtIndex:(NSUInteger)indexPath.row];
}

- (void)peekCommitPlaylist:(LTLocalPlaylist *)playlist {
    if (!playlist.identifier.length) return;
    LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:playlist];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)peekCommitStation:(LTStation *)station {
    if (!station.identifier.length) return;
    LTStationDetailViewController *detail = [[LTStationDetailViewController alloc] initWithStation:station];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)showPlaylistsSegment {
    self.segControl.selectedSegmentIndex = LTLibrarySegmentPlaylists;
    self.currentSegment = LTLibrarySegmentPlaylists;
    [self reloadForSegment];
}
- (void)showSongsSegment {
    self.segControl.selectedSegmentIndex = LTLibrarySegmentSongs;
    self.currentSegment = LTLibrarySegmentSongs;
    [self reloadForSegment];
}
- (LTTrack *)peekSongAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = self.songs;
    if ((NSUInteger)indexPath.row >= rows.count) return nil;
    id item = [rows objectAtIndex:(NSUInteger)indexPath.row];
    return [item isKindOfClass:[LTTrack class]] ? (LTTrack *)item : nil;
}
// A table can show playlists (Playlists segment) and songs (Songs segment), so
// one preview serves both: playlist rows peek the playlist, everything else
// falls through to the artwork peek. Two coordinators on one table view would
// leave UIKit to choose between them.
- (UIViewController *)peekViewControllerAtPoint:(CGPoint)point {
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) return nil;

    // Smart playlist rows intentionally have no 3D Touch peek — pressing does nothing.
    if (self.currentSegment == LTLibrarySegmentPlaylists && self.smartPlaylistsEnabled && indexPath.section == 0) return nil;

    LTLocalPlaylist *playlist = [self peekPlaylistAtIndexPath:indexPath];
    if (playlist) return [[LTPlaylistPeekViewController alloc] initWithPlaylist:playlist];

    LTStation *station = [self peekStationAtIndexPath:indexPath];
    if (station) return [[LTStationPeekViewController alloc] initWithStation:station];

    LTTrack *track = [self peekSongAtIndexPath:indexPath];
    if (track) {
        UIImage *art = [LTPeekCoordinator artworkForRowAtIndexPath:indexPath inTableView:self.tableView];
        return [[LTArtworkPeekViewController alloc] initWithTrack:track image:art];
    }
    return nil;
}

- (void)handlePeekCommit:(UIViewController *)peek {
    if ([peek isKindOfClass:[LTPlaylistPeekViewController class]]) {
        [self peekCommitPlaylist:[(LTPlaylistPeekViewController *)peek playlist]];
        return;
    }
    if ([peek isKindOfClass:[LTStationPeekViewController class]]) {
        [self peekCommitStation:[(LTStationPeekViewController *)peek station]];
        return;
    }
}

- (void)playStation:(LTStation *)station {
    if (!station.seeds.count) return;
    LTStationSeed *seed = [station.seeds objectAtIndex:0];

    UIAlertView *loading = [[UIAlertView alloc] initWithTitle:@"Loading Station"
                                                     message:@"Fetching music..."
                                                    delegate:nil
                                           cancelButtonTitle:nil
                                          otherButtonTitles:nil];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.center = CGPointMake(140.0, 80.0);
    [spinner startAnimating];
    [loading addSubview:spinner];
    [loading show];
#if !__has_feature(objc_arc)
    [spinner release];
#endif

    void (^finish)(void) = ^{
        [loading dismissWithClickedButtonIndex:0 animated:YES];
#if !__has_feature(objc_arc)
        [loading release];
#endif
    };

    if ([seed.type isEqualToString:@"track"] && seed.videoId.length) {
        LTTrack *t = [[LTTrack alloc] init];
        t.videoId = seed.videoId;
        t.title = seed.title;
        t.artist = seed.artist;
        t.album = seed.album;
        t.thumbnailURL = seed.thumbnailURL;
        [[LTYouTubeClient sharedClient] fetchRadioForTrack:t completion:^(NSArray *tracks, NSError *error) {
            NSMutableArray *q = [NSMutableArray arrayWithObject:t];
            if (tracks.count) {
                for (LTTrack *tr in tracks) {
                    if (![[LTPlayerController sharedController] isStationBlacklistedVideoId:tr.videoId]) [q addObject:tr];
                }
            }
            [[LTPlayerController sharedController] playQueue:q shuffle:NO];
            LTPlayerController *pc = [LTPlayerController sharedController];
            pc.radioEnabled = YES;
            pc.radioSeedVideoId = t.videoId;
            pc.queueSourceName = station.name;
            [pc extendRadio];
            [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:pc];
            [self replayLikedForStation:station];
            finish();
            [(LTTabBarController *)self.tabBarController showNowPlaying];
        }];
#if !__has_feature(objc_arc)
        [t release];
#endif
        return;
    }
    if ([seed.type isEqualToString:@"artist"] && seed.artist.length) {
        void (^playCatalog)(NSString *) = ^(NSString *resolvedBrowseId) {
            if (resolvedBrowseId.length) {
                seed.browseId = resolvedBrowseId;
                [[LTPlaylistStore sharedStore] saveStations];
                [[LTYouTubeClient sharedClient] browseArtist:resolvedBrowseId
                                                  completion:^(NSDictionary *info, NSArray *topSongs, NSArray *allSongs, NSArray *albums, NSError *error) {
                    if (allSongs.count) {
                        [[LTPlayerController sharedController] playQueue:allSongs shuffle:YES];
                        LTPlayerController *pc = [LTPlayerController sharedController];
                        pc.radioEnabled = YES;
                        LTTrack *firstSeed = [allSongs objectAtIndex:0];
                        if (firstSeed.videoId.length) pc.radioSeedVideoId = firstSeed.videoId;
                        pc.queueSourceName = station.name;
                        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:pc];
                        [pc extendRadio];
                    } else {
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Songs"
                                                                         message:@"Could not find songs for this artist."
                                                                        delegate:nil
                                                               cancelButtonTitle:@"OK"
                                                               otherButtonTitles:nil];
                        [alert show];
                    }
                    [self replayLikedForStation:station];
                    finish();
                    [(LTTabBarController *)self.tabBarController showNowPlaying];
                } avatarURL:nil];
            } else {
                // Fallback to name-based radio
                [[LTYouTubeClient sharedClient] fetchRadioForArtist:seed.artist completion:^(NSArray *tracks, NSError *error) {
                    if (tracks.count) {
                        NSMutableArray *filtered = [NSMutableArray array];
                        for (LTTrack *t in tracks) {
                            if (![[LTPlayerController sharedController] isStationBlacklistedVideoId:t.videoId]) [filtered addObject:t];
                        }
                        [[LTPlayerController sharedController] playQueue:filtered shuffle:NO];
                        LTPlayerController *pc = [LTPlayerController sharedController];
                        pc.radioEnabled = YES;
                        LTTrack *firstFb = filtered.count ? [filtered objectAtIndex:0] : nil;
                        if (firstFb.videoId.length) pc.radioSeedVideoId = firstFb.videoId;
                        pc.queueSourceName = station.name;
                        [pc extendRadio];
                        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:pc];
                    }
                    [self replayLikedForStation:station];
                    finish();
                    [(LTTabBarController *)self.tabBarController showNowPlaying];
                }];
            }
        };
        if (seed.browseId.length) {
            playCatalog(seed.browseId);
        } else {
            [[LTYouTubeClient sharedClient] resolveArtistBrowseId:seed.artist completion:playCatalog];
        }
        return;
    }
    if ([seed.type isEqualToString:@"album"] && seed.album.length) {
        NSString *q = seed.artist.length ? [NSString stringWithFormat:@"%@ %@", seed.artist, seed.album] : seed.album;
        [[LTYouTubeClient sharedClient] searchVideosWithQuery:q completion:^(NSArray *tracks, NSError *error) {
            if (tracks.count) {
                NSMutableArray *filtered = [NSMutableArray array];
                for (LTTrack *t in tracks) {
                    if (![[LTPlayerController sharedController] isStationBlacklistedVideoId:t.videoId]) [filtered addObject:t];
                }
                if (!filtered.count) filtered = [tracks mutableCopy];
                LTTrack *first = [filtered objectAtIndex:0];
                [[LTYouTubeClient sharedClient] fetchRadioForTrack:first completion:^(NSArray *radioTracks, NSError *error) {
                    NSMutableArray *q = [NSMutableArray arrayWithObject:first];
                    if (radioTracks.count) {
                        for (LTTrack *tr in radioTracks) {
                            if (![[LTPlayerController sharedController] isStationBlacklistedVideoId:tr.videoId]) [q addObject:tr];
                        }
                    }
                    [[LTPlayerController sharedController] playQueue:q shuffle:NO];
                    LTPlayerController *pc = [LTPlayerController sharedController];
                    pc.radioEnabled = YES;
                    pc.radioSeedVideoId = first.videoId;
                    pc.queueSourceName = station.name;
                    [pc extendRadio];
                    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:pc];
                    [self replayLikedForStation:station];
                    finish();
                    [(LTTabBarController *)self.tabBarController showNowPlaying];
                }];
            } else {
                finish();
            }
        }];
        return;
    }
    finish();
}

#pragma mark - LTSeedSearchViewControllerDelegate

- (void)seedSearchViewController:(LTSeedSearchViewController *)controller didSelectSeed:(LTStationSeed *)seed {
    if (!LTModernLibraryFeaturesAllowed()) return;
    NSString *name = @"Station";
    if ([seed.type isEqualToString:@"track"]) {
        name = seed.artist.length ? [NSString stringWithFormat:@"%@ Radio", seed.artist] : (seed.title.length ? seed.title : @"Station");
    } else if ([seed.type isEqualToString:@"artist"]) {
        name = [NSString stringWithFormat:@"%@ Radio", seed.artist.length ? seed.artist : @"Station"];
    } else if ([seed.type isEqualToString:@"album"]) {
        name = seed.artist.length ? [NSString stringWithFormat:@"%@ - %@ Radio", seed.artist, seed.album] : [NSString stringWithFormat:@"%@ Radio", seed.album.length ? seed.album : @"Station"];
    }
    [[LTPlaylistStore sharedStore] createStationWithName:name seeds:@[seed]];
    [self selectSegment:(NSInteger)LTLibrarySegmentStations];
}

- (void)replayLikedForStation:(LTStation *)station {
    LTPlayerController *pc = [LTPlayerController sharedController];
    NSArray *liked = [pc likedVideoIdsForCurrentStation];
    if (!liked.count) return;
    NSInteger cap = 3;
    if (liked.count < cap) cap = liked.count;
    for (NSInteger i = 0; i < cap; i++) {
        NSString *vid = [liked objectAtIndex:(NSUInteger)i];
        if (!vid.length) continue;
        LTTrack *t = [[LTTrack alloc] init];
        t.videoId = vid;
        [[LTYouTubeClient sharedClient] fetchRadioForTrack:t completion:^(NSArray *tracks, NSError *error) {
            if (!tracks.count) {
#if !__has_feature(objc_arc)
                [t release];
#endif
                return;
            }
            NSMutableArray *toAdd = [NSMutableArray array];
            for (LTTrack *tr in tracks) {
                if ([pc isStationBlacklistedVideoId:tr.videoId]) continue;
                BOOL exists = NO;
                for (LTTrack *q in pc.queue) {
                    if ([q.videoId isEqualToString:tr.videoId]) { exists = YES; break; }
                }
                if (!exists) [toAdd addObject:tr];
                if (toAdd.count >= 10) break;
            }
            if (toAdd.count) [pc enqueueTracks:toAdd];
        }];
#if !__has_feature(objc_arc)
        // keep t alive until fetch completes; release after? fetch holds t? It uses t.videoId only synchronously? fetchRadioForTrack reads track.videoId synchronously before async. So we can release now.
        [t release];
#endif
    }
}

@end