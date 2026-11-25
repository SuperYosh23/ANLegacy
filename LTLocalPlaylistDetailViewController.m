#import "LTLocalPlaylistDetailViewController.h"
#import "LTTraitCompat.h"
#import <objc/message.h>
#import "LTPeekCoordinator.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTYouTubeClient.h"
#import "LTMediaCell.h"
#import "LTCustomActionSheet.h"
#import "LTGraphics.h"
#import "LTSpinnerView.h"
#import "LTTheme.h"
#import "LTLog.h"
#import "LTThemedTableView.h"

#define kHeaderHeight 96.0f
#define kArtworkSize 80.0f
#define kButtonHeight 36.0f

@interface LTLocalPlaylistDetailViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, LTCustomActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) LTLocalPlaylist *playlist;
@property (nonatomic, assign) BOOL isSmartPlaylist;
@property (nonatomic, assign) NSInteger smartIndex;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) LTPeekCoordinator *playlistDetailPeek;
@property (nonatomic, strong) UIImageView *artworkImageView;
@property (nonatomic, strong) UILabel *playlistNameLabel;
@property (nonatomic, strong) UILabel *trackCountLabel;
@property (nonatomic, strong) UIButton *playAllButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UIButton *renameButton;
@property (nonatomic, strong) LTSpinnerView *downloadSpinner;
@property (nonatomic, strong) UIActivityIndicatorView *smartSpinner;
@property (nonatomic, assign) BOOL smartLoading;
@property (nonatomic, assign) NSInteger downloadFailures;
@property (nonatomic, assign) NSInteger pendingRemoveRow;
@property (nonatomic, assign) BOOL playlistFullyDownloaded;
@property (nonatomic, strong) UIAlertView *renameAlert;
@end

@implementation LTLocalPlaylistDetailViewController

- (id)initWithPlaylist:(LTLocalPlaylist *)playlist {
    self = [super init];
    if (self) {
        _playlist = playlist;
        _isSmartPlaylist = NO;
        _smartIndex = -1;
    }
    return self;
}

- (id)initWithSmartIndex:(NSInteger)index name:(NSString *)name {
    self = [super init];
    if (self) {
        _smartIndex = index;
        _isSmartPlaylist = YES;
        LTLocalPlaylist *pl = [[LTLocalPlaylist alloc] init];
        pl.name = name;
        pl.identifier = [NSString stringWithFormat:@"smart-%ld", (long)index];
        [pl.tracks removeAllObjects];
        _playlist = pl;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = self.playlist.name;
    self.view.backgroundColor = [LTTheme background];

    self.tableView = [[LTThemedTableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme background];
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)]) {
        if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)]) ((void(*)(id,SEL,UIEdgeInsets))objc_msgSend)(self.tableView, @selector(setSeparatorInset:), UIEdgeInsetsMake(0, 60, 0, 0));
    }
    [self.view addSubview:self.tableView];

    [self buildHeaderView];
    [self refreshHeader];
    if (self.isSmartPlaylist) {
        // Loading placeholder: keep headers in sync, then fetch recommendations
        self.smartSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        self.smartSpinner.center = CGPointMake(self.view.bounds.size.width/2.0f, self.view.bounds.size.height/2.0f);
        self.smartSpinner.hidesWhenStopped = YES;
        [self.view addSubview:self.smartSpinner];
        [self fetchRecommendations];
    } else {
        [self loadArtwork];
    }
    // Peek any song row's artwork large; nothing opens on a full press.
    __unsafe_unretained LTLocalPlaylistDetailViewController *peekSelf = self;
    self.playlistDetailPeek = [LTPeekCoordinator songArtworkPeekForTableView:self.tableView
                                                      owner:self
                                            songAtIndexPath:^LTTrack *(NSIndexPath *indexPath) {
        return [peekSelf peekSongAtIndexPath:indexPath];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(trackDidChange:)
                                                 name:LTPlaylistTrackDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadProgress:)
                                                 name:LTPlaylistDownloadProgressNotification
                                               object:nil];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme background];
    self.tableView.backgroundColor = [LTTheme background];
    self.tableView.tableHeaderView.backgroundColor = [LTTheme background];
    self.artworkImageView.backgroundColor = [LTTheme placeholder];
    self.trackCountLabel.textColor = [LTTheme secondaryText];
    UIColor *fill = [LTTheme fill];
    self.playAllButton.backgroundColor = fill;
    self.shuffleButton.backgroundColor = fill;
    self.downloadButton.backgroundColor = fill;
    self.renameButton.backgroundColor = fill;
    [self.tableView reloadData];
}

#pragma mark - Header

- (void)buildHeaderView {
    CGFloat w = self.view.bounds.size.width;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, kHeaderHeight)];
    container.backgroundColor = [LTTheme background];

    CGFloat pad = 12.0f;

    if (!self.isSmartPlaylist) {
        // Artwork (left side, square)
        _artworkImageView = [[UIImageView alloc] initWithFrame:CGRectMake(pad, pad, kArtworkSize, kArtworkSize)];
        _artworkImageView.backgroundColor = [LTTheme placeholder];
        _artworkImageView.contentMode = UIViewContentModeScaleAspectFill;
        _artworkImageView.clipsToBounds = YES;
        _artworkImageView.layer.cornerRadius = 6.0f;
        _artworkImageView.userInteractionEnabled = YES;
        UITapGestureRecognizer *artTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(artworkTapped:)];
        [_artworkImageView addGestureRecognizer:artTap];
        [container addSubview:_artworkImageView];
    }
    CGFloat textX = self.isSmartPlaylist ? pad : pad + kArtworkSize + 10.0f;
    CGFloat textW = w - textX - pad;
    CGFloat y = pad;

    // Playlist name
    _playlistNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, y, textW, 20)];
    _playlistNameLabel.font = [UIFont boldSystemFontOfSize:16];
    // Without this the title is UIKit's default, which is black on every iOS
    // before 13 - the app paints its own dark background but the platform's
    // labels stay black on it.
    _playlistNameLabel.textColor = [LTTheme text];
    _playlistNameLabel.text = self.playlist.name;
    [container addSubview:_playlistNameLabel];

    y += 22.0f;

    // Track count
    _trackCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, y, textW, 16)];
    _trackCountLabel.font = [UIFont systemFontOfSize:12];
    _trackCountLabel.textColor = [LTTheme secondaryText];
    [container addSubview:_trackCountLabel];

    y += 20.0f;

    // Buttons row (next to artwork, left aligned like the playlist name)
    CGFloat btnY = y + 4.0f;
    CGFloat smallGap = 6.0f;
    CGFloat smallBtn = 34.0f;
    CGFloat smallH = 32.0f;

    _playAllButton = [self headerButtonWithIcon:[LTGraphics playIcon] frame:CGRectMake(textX, btnY, smallBtn, smallH)];
    [_playAllButton addTarget:self action:@selector(playAllTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_playAllButton];

    _shuffleButton = [self headerButtonWithIcon:[LTGraphics shuffleIcon] frame:CGRectMake(textX + (smallBtn + smallGap), btnY, smallBtn, smallH)];
    [_shuffleButton addTarget:self action:@selector(shuffleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_shuffleButton];

    if (self.isSmartPlaylist) {
        UIImage *plusIcon = [LTGraphics glyphIcon:'+' size:24 color:[LTGraphics actionIconColor]];
        _downloadButton = [self headerButtonWithIcon:plusIcon frame:CGRectMake(textX + (smallBtn + smallGap) * 2, btnY, smallBtn, smallH)];
        [_downloadButton addTarget:self action:@selector(saveSmartPlaylistTapped:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:_downloadButton];
        _renameButton = nil;
    } else {
        _downloadButton = [self headerButtonWithIcon:[LTGraphics downloadIcon] frame:CGRectMake(textX + (smallBtn + smallGap) * 2, btnY, smallBtn, smallH)];
        [_downloadButton addTarget:self action:@selector(downloadTapped:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:_downloadButton];

        _renameButton = [self headerButtonWithIcon:[LTGraphics renameIcon] frame:CGRectMake(textX + (smallBtn + smallGap) * 3, btnY, smallBtn, smallH)];
        [_renameButton addTarget:self action:@selector(renamePlaylistTapped:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:_renameButton];
    }

    // Download spinner
    _downloadSpinner = [[LTSpinnerView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
    _downloadSpinner.center = CGPointMake(textX + smallBtn / 2.0f, btnY + smallH / 2.0f);
    _downloadSpinner.hidesWhenStopped = YES;
    _downloadSpinner.hidden = YES;
    [container addSubview:_downloadSpinner];

    self.tableView.tableHeaderView = container;
}

- (UIButton *)headerButtonWithIcon:(UIImage *)icon frame:(CGRect)frame {
    // A custom button, not a system one: a system button treats its image as a
    // template and paints it in the tint colour, which put the blue back over
    // the themed glyph.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    [button setImage:[self scaledIcon:icon] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.backgroundColor = [LTTheme fill];
    button.layer.cornerRadius = 6.0f;
    button.clipsToBounds = YES;
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

- (void)refreshHeader {
    NSUInteger count = self.playlist.tracks.count;
    if (self.isSmartPlaylist) {
        if (count == 0 && [self.smartSpinner isAnimating]) {
            self.trackCountLabel.text = @"Finding songs like yours…";
        } else if (count == 0) {
            self.trackCountLabel.text = @"No recommendations yet";
        } else {
            self.trackCountLabel.text = [NSString stringWithFormat:@"Recommendations • %lu track%@",
                                         (unsigned long)count, count == 1 ? @"" : @"s"];
        }
        BOOL hasTracks = count > 0;
        self.playAllButton.enabled = hasTracks;
        self.shuffleButton.enabled = hasTracks;
        if (self.downloadButton) {
            self.downloadButton.enabled = hasTracks;
            self.downloadButton.alpha = hasTracks ? 1.0f : 0.4f;
        }
        self.playAllButton.alpha = hasTracks ? 1.0f : 0.4f;
        self.shuffleButton.alpha = hasTracks ? 1.0f : 0.4f;
        self.playlistFullyDownloaded = NO;
        return;
    }
    self.trackCountLabel.text = [NSString stringWithFormat:@"%lu track%@",
                                 (unsigned long)count, count == 1 ? @"" : @"s"];

    BOOL hasTracks = count > 0;
    self.playAllButton.enabled = hasTracks;
    self.shuffleButton.enabled = hasTracks;
    self.downloadButton.enabled = hasTracks;
    self.playAllButton.alpha = hasTracks ? 1.0f : 0.4f;
    self.shuffleButton.alpha = hasTracks ? 1.0f : 0.4f;
    self.downloadButton.alpha = hasTracks ? 1.0f : 0.4f;

    BOOL fullyDownloaded = hasTracks;
    if (fullyDownloaded) {
        LTPlaylistStore *store = [LTPlaylistStore sharedStore];
        for (LTTrack *track in self.playlist.tracks) {
            if (![store isTrackDownloaded:track]) { fullyDownloaded = NO; break; }
        }
    }
    self.playlistFullyDownloaded = fullyDownloaded;
    [self.downloadButton setImage:[self scaledIcon:fullyDownloaded ? [LTGraphics checkmarkIcon] : [LTGraphics downloadIcon]]
                        forState:UIControlStateNormal];
}

- (void)loadArtwork {
    if (self.isSmartPlaylist) return;
    // Custom cover takes priority
    if (self.playlist.coverPath.length) {
        UIImage *cover = [UIImage imageWithContentsOfFile:self.playlist.coverPath];
        if (cover) {
            self.artworkImageView.image = cover;
            return;
        }
    }
    // Fall back to first track thumbnail
    if (self.playlist.tracks.count > 0) {
        LTTrack *first = [self.playlist.tracks objectAtIndex:0];
        if (first.thumbnailURL.length) {
            // Hold the controller until the image arrives. It is popped off the
            // navigation stack quickly in normal use, and an unsafe-unretained
            // self here writes into freed memory when the late reply lands.
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
            [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                self.artworkImageView.image = image;
            }];
        }
    }
}

#pragma mark - Smart Playlist Recommendations

- (NSArray *)seedTracksForIndex:(NSInteger)index {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    if (index == 0) {
        NSArray *seeds = [store topPlayedTracks:5];
        if (!seeds.count) seeds = [store recentTracks];
        return seeds ?: [NSArray array];
    }
    if (index == 2) {
        NSArray *seeds = [store recentlyPlayedTracks:8];
        if (!seeds.count) seeds = [store topPlayedTracks:5];
        return seeds ?: [NSArray array];
    }
    return [NSArray array];
}

- (NSArray *)artistNamesForIndex:(NSInteger)index {
    if (index != 1) return [NSArray array];
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSArray *artists = [store topArtists];
    NSMutableArray *names = [NSMutableArray array];
    for (id row in artists) {
        if ((NSInteger)names.count >= 3) break;
        if ([row isKindOfClass:[NSDictionary class]]) {
            NSString *n = [(NSDictionary *)row objectForKey:@"name"];
            if (n.length && ![n isEqualToString:@"Unknown Artist"]) [names addObject:n];
        }
    }
    return names ?: [NSArray array];
}

- (void)shuffleArray:(NSMutableArray *)arr {
    NSUInteger n = [arr count];
    if (n < 2) return;
    for (NSUInteger i = n - 1; i > 0; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)(i+1));
        [arr exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
}

- (NSArray *)dedupedTracks:(NSArray *)tracks excludingVideoIds:(NSSet *)excluded {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    if (excluded) [seen unionSet:excluded];
    for (id obj in tracks) {
        if (![obj isKindOfClass:[LTTrack class]]) continue;
        LTTrack *t = (LTTrack *)obj;
        if (!t.videoId.length) continue;
        if ([seen containsObject:t.videoId]) continue;
        [seen addObject:t.videoId];
        [out addObject:t];
    }
    return out;
}

- (void)fetchRecommendations {
    self.smartLoading = YES;
    [self.smartSpinner startAnimating];
    [self refreshHeader];
    if (self.smartIndex == 1) {
        NSArray *artistNames = [self artistNamesForIndex:1];
        if (!artistNames.count) {
            [self finishLoadingWithTracks:[self seedTracksForIndex:0] fallback:YES];
            return;
        }
        NSMutableArray *all = [NSMutableArray array];
        __block NSInteger done = 0;
        NSInteger total = [artistNames count];
        NSArray *names = [artistNames copy];
        for (NSString *artistName in names) {
            NSString *an = [artistName copy];
            [[LTYouTubeClient sharedClient] fetchRadioForArtist:an completion:^(NSArray *tracks, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (tracks.count) {
                        @synchronized(all) { [all addObjectsFromArray:tracks]; }
                    }
                    done++;
                    if (done >= total) {
                        NSArray *deduped = [self dedupedTracks:all excludingVideoIds:nil];
                        NSMutableArray *shuffled = [deduped mutableCopy];
                        [self shuffleArray:shuffled];
                        NSArray *final = shuffled;
                        if (final.count > 50) final = [final subarrayWithRange:NSMakeRange(0, 50)];
                        if (final.count) {
                            [self finishLoadingWithTracks:final fallback:NO];
                        } else {
                            [self finishLoadingWithTracks:[self seedTracksForIndex:0] fallback:YES];
                        }
                    }
                });
            }];
        }
        return;
    }
    NSArray *seeds = [self seedTracksForIndex:self.smartIndex];
    if (!seeds.count) {
        [self finishLoadingWithTracks:[NSArray array] fallback:NO];
        return;
    }
    NSSet *excluded = nil;
    if (self.smartIndex == 2) {
        NSMutableSet *ex = [NSMutableSet set];
        for (id t in [[LTPlaylistStore sharedStore] topPlayedTracks:30]) {
            if ([t isKindOfClass:[LTTrack class]]) {
                NSString *vid = [(LTTrack *)t videoId];
                if (vid.length) [ex addObject:vid];
            }
        }
        for (id t in seeds) {
            if ([t isKindOfClass:[LTTrack class]]) {
                NSString *vid = [(LTTrack *)t videoId];
                if (vid.length) [ex addObject:vid];
            }
        }
        excluded = ex;
    }
    NSMutableArray *all = [NSMutableArray array];
    __block NSInteger done = 0;
    NSInteger total = [seeds count];
    NSArray *seedsCopy = [seeds copy];
    for (id seedObj in seedsCopy) {
        if (![seedObj isKindOfClass:[LTTrack class]]) {
            done++;
            continue;
        }
        LTTrack *seed = (LTTrack *)seedObj;
        [[LTYouTubeClient sharedClient] fetchRadioForTrack:seed completion:^(NSArray *tracks, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (tracks.count) {
                    @synchronized(all) { [all addObjectsFromArray:tracks]; }
                }
                done++;
                if (done >= total) {
                    NSArray *deduped = [self dedupedTracks:all excludingVideoIds:excluded];
                    NSMutableArray *shuffled = [deduped mutableCopy];
                    [self shuffleArray:shuffled];
                    NSArray *final = shuffled;
                    if (final.count > 50) final = [final subarrayWithRange:NSMakeRange(0, 50)];
                    if (final.count) {
                        [self finishLoadingWithTracks:final fallback:NO];
                    } else {
                        NSArray *fallback = [self seedTracksForIndex:self.smartIndex];
                        if (!fallback.count) fallback = [[LTPlaylistStore sharedStore] topPlayedTracks:50];
                        [self finishLoadingWithTracks:fallback fallback:YES];
                    }
                }
            });
        }];
    }
    if (total == 0) {
        [self finishLoadingWithTracks:[NSArray array] fallback:NO];
    }
}

- (void)finishLoadingWithTracks:(NSArray *)tracks fallback:(BOOL)fallback {
    self.smartLoading = NO;
    [self.smartSpinner stopAnimating];
    [self.playlist.tracks removeAllObjects];
    [self.playlist.tracks addObjectsFromArray:tracks ?: [NSArray array]];
    [self refreshHeader];
    [self.tableView reloadData];
    LTLog(@"SMART %@ fetched %lu tracks (fallback=%d)", self.playlist.name, (unsigned long)self.playlist.tracks.count, fallback ? 1 : 0);
}

#pragma mark - Actions

- (void)artworkTapped:(id)sender {
    if (self.isSmartPlaylist) return;
    LTCustomActionSheet *sheet = [[LTCustomActionSheet alloc] initWithTitle:@"Playlist Cover"
                                                              buttonTitles:@[@"Choose from Library", @"Remove Cover"]
                                                           destructiveIndex:1];
    sheet.delegate = self;
    [sheet show];
}

- (void)playAllTapped:(id)sender {
    if (!self.playlist.tracks.count) return;
    [LTPlayerController sharedController].queueSourceName = self.playlist.name;
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks atIndex:0];
    LTPlayerController *pc = [LTPlayerController sharedController];
    if (self.isSmartPlaylist) {
        pc.radioEnabled = YES;
        LTTrack *first = [self.playlist.tracks objectAtIndex:0];
        if (first.videoId.length) pc.radioSeedVideoId = first.videoId;
        [pc extendRadio];
    } else {
        pc.repeatMode = LTRepeatModeAll;
    }
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)shuffleTapped:(id)sender {
    if (!self.playlist.tracks.count) return;
    [LTPlayerController sharedController].queueSourceName = self.playlist.name;
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks shuffle:YES];
    LTPlayerController *pc = [LTPlayerController sharedController];
    if (self.isSmartPlaylist) {
        pc.radioEnabled = YES;
        LTTrack *first = [self.playlist.tracks objectAtIndex:0];
        if (first.videoId.length) pc.radioSeedVideoId = first.videoId;
        [pc extendRadio];
    } else {
        pc.repeatMode = LTRepeatModeAll;
    }
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)saveSmartPlaylistTapped:(id)sender {
    if (!self.playlist.tracks.count) return;
    LTLocalPlaylist *pl = [[LTPlaylistStore sharedStore] createPlaylistWithName:self.playlist.name];
    if (!pl) return;
    for (LTTrack *t in self.playlist.tracks) {
        [[LTPlaylistStore sharedStore] addTrack:t toPlaylist:pl];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:[LTPlaylistStore sharedStore]];
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Saved"
                                                message:[NSString stringWithFormat:@"Added %@ to your playlists", self.playlist.name]
                                               delegate:nil
                                      cancelButtonTitle:@"OK"
                                      otherButtonTitles:nil];
    [a show];
}

- (void)downloadTapped:(id)sender {
    BOOL allDownloaded = self.playlistFullyDownloaded;
    if (allDownloaded) {
        NSInteger count = self.playlist.tracks.count;
        self.pendingRemoveRow = -1;
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove Downloads"
                                                        message:[NSString stringWithFormat:@"Remove all %d downloaded track%@ from this playlist? They will no longer be available offline.", (int)count, count == 1 ? @"" : @"s"]
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Remove", nil];
        alert.tag = 951;
        [alert show];
        return;
    }

    NSMutableArray *missing = [NSMutableArray array];
    for (LTTrack *track in self.playlist.tracks) {
        if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
            [missing addObject:track];
        }
    }
    if (!missing.count) {
        return;
    }
    LTLog(@"PLAYLIST queue %d tracks for download", (int)missing.count);
    self.downloadFailures = 0;
    // Feed the persistent download queue; other playlists/songs can stack on top.
    [[LTPlaylistStore sharedStore] enqueueDownloads:missing completion:^{
        [self setDownloadingUI:NO];
        [self.tableView reloadData];
    }];
}

- (void)renamePlaylistTapped:(id)sender {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Rename Playlist"
                                                    message:nil
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Save", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.text = self.playlist.name;
    field.placeholder = @"Playlist name";
    self.renameAlert = alert;
    [alert show];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 950 && buttonIndex == 1) {
        NSInteger row = self.pendingRemoveRow;
        self.pendingRemoveRow = -1;
        if (row >= 0 && row < (NSInteger)self.playlist.tracks.count) {
            LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)row];
            LTLog(@"ROW remove download %@ title=%@", track.videoId, track.title);
            [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[track]];
        }
        return;
    }
    if (alertView.tag == 951 && buttonIndex == 1) {
        LTLog(@"PLAYLIST remove all downloads count=%lu", (unsigned long)self.playlist.tracks.count);
        [[LTPlaylistStore sharedStore] removeDownloadsForTracks:self.playlist.tracks];
        return;
    }
    if (alertView == self.renameAlert && buttonIndex == 1) {
        UITextField *field = [alertView textFieldAtIndex:0];
        NSString *name = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) {
            [[LTPlaylistStore sharedStore] renamePlaylist:self.playlist name:name];
            self.title = name;
            self.playlistNameLabel.text = name;
        }
    }
}

- (void)customActionSheet:(id)sheet tappedButtonAtIndex:(NSInteger)index {
    if (index == 0) {
        // Choose from Library - use native picker
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.delegate = self;
            picker.allowsEditing = YES;
            [self presentViewController:picker animated:YES completion:nil];
        }
    } else if (index == 1) {
        // Remove Cover
        [[LTPlaylistStore sharedStore] setCoverImage:nil forPlaylist:self.playlist];
        [self loadArtwork];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
    if (!image) image = [info objectForKey:UIImagePickerControllerOriginalImage];
    if (image) {
        [[LTPlaylistStore sharedStore] setCoverImage:image forPlaylist:self.playlist];
        [self loadArtwork];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)setDownloadingUI:(BOOL)downloading {
    if (downloading) {
        self.downloadButton.hidden = YES;
        self.renameButton.hidden = YES;
        [self.downloadSpinner startAnimating];
    } else {
        [self.downloadSpinner stopAnimating];
        self.downloadButton.hidden = NO;
        self.renameButton.hidden = NO;
        [self refreshHeader];
        [self.tableView reloadData];
    }
}

#pragma mark - Notifications

- (void)storeDidChange:(NSNotification *)notification {
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)trackDidChange:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)downloadProgress:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    NSString *status = [info objectForKey:@"status"];
    if ([status isEqualToString:@"error"]) {
        self.downloadFailures += 1;
    }
    NSInteger index = [[info objectForKey:@"index"] integerValue];
    NSInteger total = [[info objectForKey:@"total"] integerValue];
    if (total > 0 && index < total) {
        self.trackCountLabel.text = [NSString stringWithFormat:@"Downloading %d of %d...", (int)index + 1, (int)total];
    } else {
        [self refreshHeader];
    }
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.playlist.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTPlaylistTrackCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%d. %@", (int)indexPath.row + 1, track.title];

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
        [[LTPlaylistStore sharedStore] resolveThumbnailForTrack:track completion:^(NSString *thumbnailURL) {
            if (thumbnailURL.length) {
                [cell setImageFromURL:thumbnailURL];
            }
        }];
    }
    if ([[LTPlaylistStore sharedStore] isTrackDownloading:track]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self rowSpinnerForRow:indexPath.row];
    } else if ([[LTPlaylistStore sharedStore] isTrackPendingDownload:track]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self rowQueuedBadge];
    } else if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self rowRemoveButtonForRow:indexPath.row];
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self rowDownloadButtonForRow:indexPath.row];
    }
    return cell;
}

- (UIView *)rowSpinnerForRow:(NSInteger)row {
    LTSpinnerView *spinner = [[LTSpinnerView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
    [spinner startAnimating];
    return spinner;
}

// Static "queued" badge shown for tracks waiting in the download queue.
- (UIView *)rowQueuedBadge {
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 62, 22)];
    badge.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.9f];
    badge.layer.cornerRadius = 4.0f;
    badge.clipsToBounds = YES;
    UILabel *label = [[UILabel alloc] initWithFrame:badge.bounds];
    label.text = @"Queued";
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:11];
    label.textAlignment = NSTextAlignmentCenter;
    [badge addSubview:label];
    return badge;
}

- (UIButton *)rowRemoveButtonForRow:(NSInteger)row {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 32);
    [button setImage:[self scaledIcon:[LTGraphics checkmarkIcon]] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.tag = row;
    [button addTarget:self action:@selector(rowRemoveTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)rowRemoveTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.playlist.tracks.count) return;
    LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)row];
    if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    self.pendingRemoveRow = row;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove Download"
                                                    message:[NSString stringWithFormat:@"Remove \"%@\" from your offline downloads?", track.title]
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Remove", nil];
    alert.tag = 950;
    [alert show];
}

- (UIButton *)rowDownloadButtonForRow:(NSInteger)row {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 32);
    [button setImage:[self scaledIcon:[LTGraphics downloadIcon]] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.tag = row;
    [button addTarget:self action:@selector(rowDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)rowDownloadTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.playlist.tracks.count) return;
    LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)row];
    if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    if ([[LTPlaylistStore sharedStore] isTrackPendingDownload:track]) return;
    LTLog(@"ROW queue download %@ title=%@", track.videoId, track.title);
    [[LTPlaylistStore sharedStore] enqueueDownloads:@[track]];
    [self.tableView reloadData];
}

- (NSString *)formatDuration:(NSTimeInterval)duration {
    NSInteger seconds = (NSInteger)duration;
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 54.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [LTPlayerController sharedController].queueSourceName = self.playlist.name;
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks atIndex:indexPath.row];
    if (self.isSmartPlaylist) {
        LTPlayerController *pc = [LTPlayerController sharedController];
        pc.radioEnabled = YES;
        LTTrack *first = [self.playlist.tracks objectAtIndex:0];
        if (first.videoId.length) pc.radioSeedVideoId = first.videoId;
        [pc extendRadio];
    }
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isSmartPlaylist) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isSmartPlaylist) return NO;
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)indexPath.row];
        LTLog(@"PLAYLIST remove track %@ title=%@", track.videoId, track.title);
        [[LTPlaylistStore sharedStore] removeTrackAtIndex:indexPath.row fromPlaylist:self.playlist];
    }
}
- (LTTrack *)peekSongAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = self.playlist.tracks;
    if ((NSUInteger)indexPath.row >= rows.count) return nil;
    id item = [rows objectAtIndex:(NSUInteger)indexPath.row];
    return [item isKindOfClass:[LTTrack class]] ? (LTTrack *)item : nil;
}

@end
