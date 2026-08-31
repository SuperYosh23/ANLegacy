#import "LTHomeViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTLocalPlaylistDetailViewController.h"
#import "LTStatsViewController.h"
#import "LTMediaCell.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Recently played horizontal strip

@interface LTHomeRecentsCell : UITableViewCell
@property (nonatomic, copy) void (^onTrackTapped)(LTTrack *track);
- (void)setTracks:(NSArray *)tracks;
@end

@implementation LTHomeRecentsCell {
    UIScrollView *_scrollView;
    NSArray *_tracks;
}

const CGFloat kHomeTileMinWidth = 90.0f;
const CGFloat kHomeTileMaxWidth = 130.0f;
const CGFloat kHomeTileArtRatio = 104.0f / 116.0f;

+ (CGFloat)tileWidth {
    CGFloat width = [[NSUserDefaults standardUserDefaults] floatForKey:@"LTHomeTileSize"];
    if (width < kHomeTileMinWidth || width > kHomeTileMaxWidth) {
        width = kHomeTileMinWidth;
        [[NSUserDefaults standardUserDefaults] setFloat:width forKey:@"LTHomeTileSize"];
    }
    return width;
}

+ (CGFloat)artworkHeight {
    return [LTHomeRecentsCell tileWidth] * kHomeTileArtRatio;
}

+ (CGFloat)contentHeight {
    return [LTHomeRecentsCell artworkHeight] + 54.0f;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.directionalLockEnabled = YES;
        _scrollView.bounces = NO;
        if ([_scrollView respondsToSelector:@selector(setAlwaysBounceVertical:)]) {
            _scrollView.alwaysBounceVertical = NO;
        }
        _scrollView.backgroundColor = [UIColor whiteColor];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.contentView addSubview:_scrollView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scrollView.frame = CGRectMake(0, 0, self.contentView.bounds.size.width, self.contentView.bounds.size.height);
}

- (void)setTracks:(NSArray *)tracks {
    _tracks = tracks;
    for (UIView *view in _scrollView.subviews) {
        [view removeFromSuperview];
    }
    CGFloat tileWidth = [LTHomeRecentsCell tileWidth];
    CGFloat artH = [LTHomeRecentsCell artworkHeight];
    CGFloat gap = 10.0f;
    CGFloat x = 10.0f;
    NSUInteger index = 0;
    for (LTTrack *track in tracks) {
        UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(x, 6, tileWidth, artH + 42)];

        UIButton *imageButton = [UIButton buttonWithType:UIButtonTypeCustom];
        imageButton.frame = CGRectMake(0, 0, tileWidth, artH);
        imageButton.backgroundColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
        imageButton.layer.cornerRadius = 8.0f;
        imageButton.clipsToBounds = YES;
        imageButton.tag = (NSInteger)index;
        [imageButton addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        [tile addSubview:imageButton];

        UIImageView *artwork = [[UIImageView alloc] initWithFrame:imageButton.bounds];
        artwork.contentMode = UIViewContentModeScaleAspectFill;
        artwork.clipsToBounds = YES;
        [imageButton addSubview:artwork];
        if (track.thumbnailURL.length) {
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:track.thumbnailURL];
            __weak UIImageView *weakArtwork = artwork;
            [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                if (image) weakArtwork.image = image;
            }];
        }

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(2, artH + 4, tileWidth - 4, 26)];
        titleLabel.font = [UIFont boldSystemFontOfSize:12];
        titleLabel.numberOfLines = 2;
        titleLabel.textColor = [UIColor darkGrayColor];
        titleLabel.text = track.title;
        [tile addSubview:titleLabel];

        UILabel *artistLabel = [[UILabel alloc] initWithFrame:CGRectMake(2, artH + 30, tileWidth - 4, 12)];
        artistLabel.font = [UIFont systemFontOfSize:11];
        artistLabel.textColor = [UIColor grayColor];
        artistLabel.text = track.artist.length ? track.artist : @"Unknown Artist";
        [tile addSubview:artistLabel];

        [_scrollView addSubview:tile];
        x += tileWidth + gap;
        index += 1;
    }
    CGFloat contentWidth = MAX(x, self.contentView.bounds.size.width + 1);
    _scrollView.contentSize = CGSizeMake(contentWidth, [LTHomeRecentsCell contentHeight]);
}

- (void)tileTapped:(UIButton *)button {
    NSUInteger index = (NSUInteger)button.tag;
    if (index >= _tracks.count) return;
    if (self.onTrackTapped) self.onTrackTapped([_tracks objectAtIndex:index]);
}

@end

#pragma mark - Home

@interface LTHomeViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *recentTracks;
@property (nonatomic, strong) NSArray *playlists;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UILabel *bannerTitleLabel;
@property (nonatomic, strong) UILabel *bannerSubtitleLabel;
@end

@implementation LTHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Home";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Stats"
                                                                             style:UIBarButtonItemStyleBordered
                                                                            target:self
                                                                            action:@selector(statsTapped:)];

    CGRect bounds = self.view.bounds;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.tableHeaderView = [self buildBanner];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 190, bounds.size.width - 48, 60)];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textColor = [UIColor grayColor];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
}

- (UIView *)buildBanner {
    CGFloat width = self.view.bounds.size.width;
    UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 92)];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = banner.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.06f green:0.22f blue:0.46f alpha:1.0f].CGColor,
        (id)[UIColor colorWithRed:0.0f green:0.42f blue:0.85f alpha:1.0f].CGColor,
    ];
    [banner.layer insertSublayer:gradient atIndex:0];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 20, width - 32, 30)];
    titleLabel.text = @"Welcome back.";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.backgroundColor = [UIColor clearColor];
    self.bannerTitleLabel = titleLabel;
    [banner addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 54, width - 32, 16)];
    subtitleLabel.text = @"";
    subtitleLabel.font = [UIFont systemFontOfSize:13];
    subtitleLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.75f];
    subtitleLabel.backgroundColor = [UIColor clearColor];
    self.bannerSubtitleLabel = subtitleLabel;
    [banner addSubview:subtitleLabel];

    [self updateBannerText];
    return banner;
}

- (void)updateBannerText {
    NSInteger count = [[LTPlaylistStore sharedStore] listenedSongsCount];
    self.bannerSubtitleLabel.text = [NSString stringWithFormat:@"You've listened to %d song%@.",
                                     (int)count, count == 1 ? @"" : @"s"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTRecentsDidChangeNotification
                                               object:nil];
    [self reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
    self.recentTracks = [[LTPlaylistStore sharedStore] recentTracks];
    self.playlists = [[LTPlaylistStore sharedStore] playlists];
    [self updateBannerText];
    [self.tableView reloadData];
    if (!self.recentTracks.count && !self.playlists.count) {
        self.emptyLabel.text = @"Nothing here yet.\nPlay a song and create playlists to see them.";
        self.emptyLabel.hidden = NO;
    } else {
        self.emptyLabel.hidden = YES;
    }
}

- (void)storeDidChange:(NSNotification *)notification {
    [self reloadData];
}

- (void)statsTapped:(id)sender {
    LTStatsViewController *stats = [[LTStatsViewController alloc] init];
    [self.navigationController pushViewController:stats animated:YES];
}

- (BOOL)hasRecents {
    return self.recentTracks.count > 0;
}

- (NSInteger)playlistSection {
    return [self hasRecents] ? 1 : 0;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = 0;
    if ([self hasRecents]) sections += 1;
    if (self.playlists.count) sections += 1;
    return sections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self hasRecents] && section == 0) return @"Recently Played";
    if (section == [self playlistSection] && self.playlists.count) return @"Your Playlists";
    return @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self hasRecents] && section == 0) return 1;
    return (NSInteger)self.playlists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasRecents] && indexPath.section == 0) {
        static NSString *StripCellId = @"LTHomeRecentsCell";
        LTHomeRecentsCell *cell = [tableView dequeueReusableCellWithIdentifier:StripCellId];
        if (!cell) {
            cell = [[LTHomeRecentsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:StripCellId];
        }
        __weak LTHomeViewController *weakSelf = self;
        cell.onTrackTapped = ^(LTTrack *track) {
            LTHomeViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            [[LTPlayerController sharedController] playQueue:@[track] atIndex:0];
            [(LTTabBarController *)strongSelf.tabBarController showNowPlaying];
        };
        [cell setTracks:self.recentTracks];
        return cell;
    }

    static NSString *CellId = @"LTHomeCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    LTLocalPlaylist *playlist = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = playlist.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%d tracks", (int)playlist.tracks.count];
    cell.accessoryView = nil;
    cell.imageView.image = nil;
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
    return cell;
}

#pragma mark - Editing (swipe to delete playlists)

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == [self playlistSection] && self.playlists.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.section != [self playlistSection]) return;
    LTLocalPlaylist *playlist = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    [[LTPlaylistStore sharedStore] deletePlaylist:playlist];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasRecents] && indexPath.section == 0) return [LTHomeRecentsCell contentHeight];
    return 64.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != [self playlistSection]) return;
    LTLocalPlaylist *playlist = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:playlist];
    [self.navigationController pushViewController:detail animated:YES];
}

@end