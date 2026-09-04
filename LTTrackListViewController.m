#import <QuartzCore/QuartzCore.h>
#import "LTTrackListViewController.h"
#import "LTYouTubeClient.h"
#import "LTMediaCell.h"
#import "LTGraphics.h"
#import "LTTabBarController.h"
#import "LTPlayerController.h"
#import "LTPlaylistStore.h"
#import "LTPlaylistPicker.h"
#import "LTSongMenu.h"
#import "LTLog.h"
#import <QuartzCore/QuartzCore.h>

#define kLTHeaderHeight 96.0f
#define kLTArtworkSize 80.0f

@interface LTTrackListViewController () <UITableViewDataSource, UITableViewDelegate,
                                         UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, copy) NSString *browseId;
@property (nonatomic, assign) LTBrowseKind kind;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *tracks;
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, strong) UIImageView *artworkImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *playAllButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UIView *containerHeaderView;
@property (nonatomic, strong) LTSongMenu *songMenu;
@property (nonatomic, assign) BOOL allDownloaded;
@end

@implementation LTTrackListViewController

- (id)initWithBrowseId:(NSString *)browseId kind:(LTBrowseKind)kind title:(NSString *)title {
    self = [super init];
    if (self) {
        _browseId = [browseId copy];
        _kind = kind;
        _tracks = [NSMutableArray array];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.view.backgroundColor = [UIColor whiteColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    self.tableView.tableHeaderView = [self buildHeaderView];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Add All"
                                         style:UIBarButtonItemStyleBordered
                                        target:self
                                        action:@selector(addAllTapped:)],
        [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                         style:UIBarButtonItemStyleBordered
                                        target:self
                                        action:@selector(saveTapped:)],
    ];

    [self loadContent];
}

- (UIView *)buildHeaderView {
    CGFloat w = self.view.bounds.size.width;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, kLTHeaderHeight)];
    container.backgroundColor = [UIColor whiteColor];

    CGFloat pad = 12.0f;

    self.artworkImageView = [[UIImageView alloc] initWithFrame:CGRectMake(pad, pad, kLTArtworkSize, kLTArtworkSize)];
    self.artworkImageView.backgroundColor = [UIColor colorWithWhite:0.92f alpha:1.0f];
    self.artworkImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkImageView.clipsToBounds = YES;
    self.artworkImageView.layer.cornerRadius = 6.0f;
    [container addSubview:self.artworkImageView];

    CGFloat textX = pad + kLTArtworkSize + 10.0f;
    CGFloat textW = w - textX - pad;
    CGFloat y = pad;

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, y, textW, 20)];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [container addSubview:self.titleLabel];

    y += 22.0f;

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, y, textW, 16)];
    self.subtitleLabel.font = [UIFont systemFontOfSize:12];
    self.subtitleLabel.textColor = [UIColor grayColor];
    [container addSubview:self.subtitleLabel];

    y += 20.0f;

    CGFloat btnY = y + 4.0f;
    CGFloat smallGap = 6.0f;
    CGFloat smallBtn = 34.0f;
    CGFloat smallH = 32.0f;

    self.playAllButton = [self headerButtonWithIcon:[LTGraphics playIcon] frame:CGRectMake(textX, btnY, smallBtn, smallH)];
    [self.playAllButton addTarget:self action:@selector(playAllTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.playAllButton];

    self.shuffleButton = [self headerButtonWithIcon:[LTGraphics shuffleIcon] frame:CGRectMake(textX + (smallBtn + smallGap), btnY, smallBtn, smallH)];
    [self.shuffleButton addTarget:self action:@selector(shuffleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.shuffleButton];

    self.downloadButton = [self headerButtonWithIcon:[LTGraphics downloadIcon] frame:CGRectMake(textX + (smallBtn + smallGap) * 2, btnY, smallBtn, smallH)];
    [self.downloadButton addTarget:self action:@selector(downloadTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.downloadButton];

    self.containerHeaderView = container;
    return container;
}

- (UIButton *)headerButtonWithIcon:(UIImage *)icon frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setImage:[self scaledIcon:icon] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
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

- (void)playAllTapped:(id)sender {
    if (!self.tracks.count) return;
    [LTPlayerController sharedController].queueSourceName = self.title;
    [[LTPlayerController sharedController] playQueue:self.tracks atIndex:0];
    [[LTPlayerController sharedController] setRepeatMode:LTRepeatModeAll];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)shuffleTapped:(id)sender {
    if (!self.tracks.count) return;
    [LTPlayerController sharedController].queueSourceName = self.title;
    [[LTPlayerController sharedController] playQueue:self.tracks shuffle:YES];
    [[LTPlayerController sharedController] setRepeatMode:LTRepeatModeAll];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)downloadTapped:(id)sender {
    if (!self.tracks.count) return;
    if ([[LTPlaylistStore sharedStore] isDownloading]) {
        [self showToast:@"A download is already in progress"];
        return;
    }
    if (self.allDownloaded) {
        NSInteger count = self.tracks.count;
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove Downloads"
                                                        message:[NSString stringWithFormat:@"Remove all %d downloaded track%@? They will no longer be available offline.", (int)count, count == 1 ? @"" : @"s"]
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Remove", nil];
        alert.tag = 951;
        [alert show];
        return;
    }
    NSMutableArray *missing = [NSMutableArray array];
    for (LTTrack *track in self.tracks) {
        if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
            [missing addObject:track];
        }
    }
    if (!missing.count) return;
    __weak LTTrackListViewController *weakSelf = self;
    [[LTPlaylistStore sharedStore] downloadTracks:missing completion:^{
        [weakSelf updateDownloadState];
    }];
    [self showToast:[NSString stringWithFormat:@"Downloading %d", (int)missing.count]];
}

- (void)addAllTapped:(id)sender {
    if (!self.tracks.count) return;
    [[LTPlayerController sharedController] enqueueTracks:self.tracks];
    [self showToast:[NSString stringWithFormat:@"Added %d to queue", (int)self.tracks.count]];
}

- (void)saveTapped:(id)sender {
    if (!self.tracks.count) return;
    NSString *subtitle = [NSString stringWithFormat:@"%d tracks", (int)self.tracks.count];
    [LTPlaylistPicker presentFromViewController:self
                                     panelTitle:subtitle
                                      onPicked:^(LTLocalPlaylist *playlist) {
        for (LTTrack *track in self.tracks) {
            [[LTPlaylistStore sharedStore] addTrack:track toPlaylist:playlist];
        }
        [self showToast:[NSString stringWithFormat:@"Added %d to %@", (int)self.tracks.count, playlist.name]];
    } onCreateNew:^(NSString *name) {
        LTLocalPlaylist *playlist = [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
        if (playlist) {
            for (LTTrack *track in self.tracks) {
                [[LTPlaylistStore sharedStore] addTrack:track toPlaylist:playlist];
            }
            [self showToast:[NSString stringWithFormat:@"Added %d to %@", (int)self.tracks.count, playlist.name]];
        }
    }];
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

- (void)loadContent {
    __weak LTTrackListViewController *weakSelf = self;
    void (^finish)(NSDictionary *, NSArray *) = ^(NSDictionary *info, NSArray *tracks) {
        LTTrackListViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.info = info;
        [strongSelf.tracks removeAllObjects];
        [strongSelf.tracks addObjectsFromArray:tracks];
        [strongSelf updateHeader];
        [strongSelf.tableView reloadData];
    };

    if (self.kind == LTBrowseKindPlaylist) {
        [[LTYouTubeClient sharedClient] browsePlaylist:self.browseId completion:^(NSDictionary *info, NSArray *tracks, NSError *error) {
            if (error) { [self showError:error]; return; }
            finish(info, tracks);
        }];
    } else {
        [[LTYouTubeClient sharedClient] browseAlbum:self.browseId completion:^(NSDictionary *info, NSArray *tracks, NSError *error) {
            if (error) { [self showError:error]; return; }
            finish(info, tracks);
        }];
    }
}

- (void)updateHeader {
    NSString *title = self.info[@"title"];
    if (!title.length) title = self.title;
    if (title.length) self.titleLabel.text = title;
    NSString *subtitle = self.info[@"subtitle"];
    if (subtitle.length) {
        self.subtitleLabel.text = subtitle;
    } else {
        self.subtitleLabel.text = [self trackCountText];
    }
    NSString *thumb = self.info[@"thumbnail"];
    if (thumb.length) thumb = [[LTYouTubeClient sharedClient] highResThumbnailURL:thumb];
    [self setArtworkURL:thumb];
    [self updateDownloadState];
}

- (NSString *)trackCountText {
    NSInteger count = (NSInteger)self.tracks.count;
    if (count <= 0) return @"";
    return [NSString stringWithFormat:@"%d track%@", (int)count, count == 1 ? @"" : @"s"];
}

- (void)updateDownloadState {
    BOOL hasTracks = self.tracks.count > 0;
    self.playAllButton.enabled = hasTracks;
    self.shuffleButton.enabled = hasTracks;
    self.downloadButton.enabled = hasTracks;
    self.playAllButton.alpha = hasTracks ? 1.0f : 0.4f;
    self.shuffleButton.alpha = hasTracks ? 1.0f : 0.4f;
    self.downloadButton.alpha = hasTracks ? 1.0f : 0.4f;

    BOOL fullyDownloaded = hasTracks;
    if (fullyDownloaded) {
        LTPlaylistStore *store = [LTPlaylistStore sharedStore];
        for (LTTrack *track in self.tracks) {
            if (![store isTrackDownloaded:track]) { fullyDownloaded = NO; break; }
        }
    }
    self.allDownloaded = fullyDownloaded;
    [self.downloadButton setImage:[self scaledIcon:fullyDownloaded ? [LTGraphics checkmarkIcon] : [LTGraphics downloadIcon]]
                        forState:UIControlStateNormal];
}

- (void)setArtworkURL:(NSString *)urlString {
    self.artworkImageView.image = nil;
    LTLog(@"ALBUM header art url=%@ len=%lu", urlString, (unsigned long)urlString.length);
    if (!urlString.length) {
        [self fallbackArtwork];
        return;
    }
    __weak LTTrackListViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:urlString completion:^(UIImage *image) {
        LTTrackListViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (image) {
            LTLog(@"ALBUM header art APPLIED w=%d h=%d", (int)image.size.width, (int)image.size.height);
            strongSelf.artworkImageView.image = image;
            [strongSelf.artworkImageView setNeedsLayout];
        } else {
            LTLog(@"ALBUM header art FAILED, falling back");
            [strongSelf fallbackArtwork];
        }
    }];
}

- (void)fallbackArtwork {
    LTLog(@"ALBUM fallback tracks=%lu", (unsigned long)self.tracks.count);
    if (self.tracks.count) {
        LTTrack *first = [self.tracks objectAtIndex:0];
        LTLog(@"ALBUM fallback first thumb=%@", first.thumbnailURL);
        if (first.thumbnailURL.length) {
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
            LTLog(@"ALBUM fallback loading %@", artURL);
            __weak LTTrackListViewController *weakSelf = self;
            [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                LTTrackListViewController *strongSelf = weakSelf;
                LTLog(@"ALBUM fallback completed img=%@", image);
                if (strongSelf && image) {
                    strongSelf.artworkImageView.image = image;
                }
            }];
        }
    }
}

- (void)showError:(NSError *)error {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Load Failed"
                                                    message:error.localizedDescription
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTTrackCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%d. %@", (int)indexPath.row + 1, track.title];

    NSMutableString *detail = [NSMutableString string];
    if (track.artist.length) [detail appendString:track.artist];
    if (track.duration > 0) {
        if (detail.length) [detail appendString:@"   "];
        [detail appendString:[self formatDuration:track.duration]];
    }
    cell.detailTextLabel.text = detail;
    UIButton *plus = [UIButton buttonWithType:UIButtonTypeContactAdd];
    plus.tag = (NSInteger)indexPath.row;
    [plus addTarget:self action:@selector(songPlusTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = plus;
    if (track.thumbnailURL.length) {
        [cell setImageFromURL:track.thumbnailURL];
    } else {
        cell.imageView.image = nil;
    }
    return cell;
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
    [LTPlayerController sharedController].queueSourceName = self.title;
    [[LTPlayerController sharedController] playQueue:self.tracks atIndex:indexPath.row];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)songPlusTapped:(UIButton *)button {
    NSInteger row = (NSInteger)button.tag;
    if (row < 0 || row >= (NSInteger)self.tracks.count) return;
    LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)row];
    if (!self.songMenu) self.songMenu = [[LTSongMenu alloc] init];
    [self.songMenu presentForTrack:track fromViewController:self];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 951 && buttonIndex == 1) {
        [[LTPlaylistStore sharedStore] removeDownloadsForTracks:self.tracks];
        [self updateDownloadState];
        return;
    }
}

@end
