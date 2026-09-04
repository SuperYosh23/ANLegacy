#import "LTLibraryViewController.h"
#import "LTLibrarySongsViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTMediaCell.h"
#import "LTYouTubeClient.h"
#import "LTLocalPlaylistDetailViewController.h"
#import "LTGraphics.h"
#import "LTModel.h"
#import "LTLog.h"

typedef NS_ENUM(NSInteger, LTLibrarySegment) {
    LTLibrarySegmentPlaylists = 0,
    LTLibrarySegmentSongs,
    LTLibrarySegmentArtists,
    LTLibrarySegmentAlbums,
};

@interface LTLibraryViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UISegmentedControl *segControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) NSInteger currentSegment;
@property (nonatomic, strong) NSMutableArray *playlists;
@property (nonatomic, strong) NSMutableArray *songs;
@property (nonatomic, strong) NSArray *artists;
@property (nonatomic, strong) NSArray *albums;
@property (nonatomic, assign) NSInteger pendingRemoveRow;
@property (nonatomic, assign) BOOL ignorePlaylistChanges;
@end

@implementation LTLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Library";
    self.view.backgroundColor = [UIColor whiteColor];
    self.currentSegment = LTLibrarySegmentPlaylists;

    CGRect bounds = self.view.bounds;
    self.segControl = [[UISegmentedControl alloc] initWithItems:@[@"Playlists", @"Songs", @"Artists", @"Albums"]];
    self.segControl.selectedSegmentIndex = 0;
    [self.segControl setTitleTextAttributes:@{UITextAttributeFont: [UIFont boldSystemFontOfSize:11]}
                                   forState:UIControlStateNormal];
    [self.segControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.segControl.frame = CGRectMake(8, 6, bounds.size.width - 16, 30);
    [self.view addSubview:self.segControl];

    CGFloat tableY = 42.0f;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, tableY, bounds.size.width, bounds.size.height - tableY)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, tableY + 100, bounds.size.width - 48, 60)];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textColor = [UIColor grayColor];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    [self reloadModels];
    [self reloadForSegment];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
    [self reloadModels];
    [self reloadForSegment];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Data

- (void)reloadModels {
    self.playlists = [[[LTPlaylistStore sharedStore] playlists] mutableCopy] ?: [NSMutableArray array];
    self.songs = [[[LTPlaylistStore sharedStore] downloadedTracks] mutableCopy] ?: [NSMutableArray array];

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
}

- (NSArray *)sortedByName:(NSArray *)buckets {
    return [buckets sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a objectForKey:@"name"] caseInsensitiveCompare:[b objectForKey:@"name"]];
    }];
}

- (NSArray *)currentItems {
    switch (self.currentSegment) {
        case LTLibrarySegmentPlaylists: return self.playlists;
        case LTLibrarySegmentSongs: return self.songs;
        case LTLibrarySegmentArtists: return [self sortedByName:self.artists];
        case LTLibrarySegmentAlbums: return [self sortedByName:self.albums];
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
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)shuffleAllTapped {
    if (!self.songs.count) return;
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
            self.emptyLabel.text = @"No downloaded songs yet.\nUse the download button in Search or in a playlist.";
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

- (void)segmentChanged:(id)sender {
    self.currentSegment = self.segControl.selectedSegmentIndex;
    [self reloadForSegment];
}

- (void)newPlaylistTapped:(id)sender {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Playlist"
                                                    message:@"Enter a name for the playlist."
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Create", nil];
    alert.tag = 700;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert show];
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
    [UIView animateWithDuration:1.4 delay:1.0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ label.alpha = 0.0f; }
                     completion:^(BOOL finished) { [label removeFromSuperview]; }];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 620 && buttonIndex == 1) {
        NSInteger row = self.pendingRemoveRow;
        self.pendingRemoveRow = -1;
        if (row >= 0 && row < (NSInteger)self.songs.count) {
            LTTrack *track = [self.songs objectAtIndex:(NSUInteger)row];
            LTLog(@"LIB remove download %@ title=%@", track.videoId, track.title);
            [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[track]];
        }
        return;
    }
    if (alertView.tag == 700 && buttonIndex == 1) {
        NSString *name = [[alertView textFieldAtIndex:0] text];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) {
            [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
            [self showToast:@"Playlist created"];
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[self currentItems] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *TrackCellId = @"LTLibraryTrackCell";
    static NSString *BucketCellId = @"LTLibraryBucketCell";
    NSArray *items = [self currentItems];
    id item = [items objectAtIndex:(NSUInteger)indexPath.row];

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
        cell.accessoryView = [self removeAccessoryButtonForRow:indexPath.row];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:BucketCellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:BucketCellId];
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
        if (playlist.coverPath.length) {
            cell.imageView.image = [UIImage imageWithContentsOfFile:playlist.coverPath];
        } else if (playlist.tracks.count) {
            LTTrack *first = [playlist.tracks objectAtIndex:0];
            if (first.thumbnailURL.length) {
                NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
                __weak UITableViewCell *weakCell = cell;
                [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                    if (image) weakCell.imageView.image = image;
                }];
            }
        }
    } else {
        NSDictionary *bucket = item;
        NSArray *tracks = [bucket objectForKey:@"tracks"];
        NSString *name = [bucket objectForKey:@"name"];
        if (self.currentSegment == LTLibrarySegmentArtists) {
            cell.textLabel.text = name;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d song%@", (int)tracks.count, tracks.count == 1 ? @"" : @"s"];
        } else {
            cell.textLabel.text = name;
            NSString *artist = [bucket objectForKey:@"artist"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@   %d song%@",
                                         artist, (int)tracks.count, tracks.count == 1 ? @"" : @"s"];
        }
        if (tracks.count) {
            LTTrack *first = [tracks objectAtIndex:0];
            if (first.thumbnailURL.length) {
                NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
                __weak UITableViewCell *weakCell = cell;
                [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                    if (image) weakCell.imageView.image = image;
                }];
            }
        }
    }
    return cell;
}

- (UIButton *)removeAccessoryButtonForRow:(NSInteger)row {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 32);
    [button setImage:[self scaledIcon:[LTGraphics checkmarkIcon]] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.tag = row;
    [button addTarget:self action:@selector(rowRemoveTapped:) forControlEvents:UIControlEventTouchUpInside];
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

- (void)rowRemoveTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.songs.count) return;
    LTTrack *track = [self.songs objectAtIndex:(NSUInteger)row];
    if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    self.pendingRemoveRow = row;
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
    return 58.0f;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.currentSegment == LTLibrarySegmentPlaylists;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.currentSegment != LTLibrarySegmentPlaylists) return UITableViewCellEditingStyleNone;
    if (indexPath.row >= (NSInteger)self.playlists.count) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.playlists.count) return;
    LTLocalPlaylist *playlist = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    self.ignorePlaylistChanges = YES;
    [[LTPlaylistStore sharedStore] deletePlaylist:playlist];
    [self.playlists removeObject:playlist];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    self.ignorePlaylistChanges = NO;
    [self refreshEmptyState];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *items = [self currentItems];
    if (indexPath.row >= (NSInteger)items.count) return;
    id item = [items objectAtIndex:(NSUInteger)indexPath.row];

    if (self.currentSegment == LTLibrarySegmentSongs) {
        [LTPlayerController sharedController].queueSourceName = @"Library";
        [[LTPlayerController sharedController] playQueue:self.songs atIndex:indexPath.row];
        [(LTTabBarController *)self.tabBarController showNowPlaying];
    } else if (self.currentSegment == LTLibrarySegmentPlaylists && [item isKindOfClass:[LTLocalPlaylist class]]) {
        LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:item];
        [self.navigationController pushViewController:detail animated:YES];
    } else if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *bucket = item;
        NSArray *tracks = [bucket objectForKey:@"tracks"];
        NSString *name = [bucket objectForKey:@"name"];
        LTLibrarySongsViewController *detail = [[LTLibrarySongsViewController alloc] initWithTracks:tracks title:name];
        [self.navigationController pushViewController:detail animated:YES];
    }
}

@end