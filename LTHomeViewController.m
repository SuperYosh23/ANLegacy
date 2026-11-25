#import "LTHomeViewController.h"
#import "LTTraitCompat.h"
#import "LTCardControls.h"
#import "LTPeekCoordinator.h"
#import "LTPlaylistPeekViewController.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"
#import "LTYouTubeClient.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTLocalPlaylistDetailViewController.h"
#import "LTStatsViewController.h"
#import "LTMediaCell.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "LTThemedTableView.h"

#pragma mark - Recently played horizontal strip

@interface LTHomeRecentsCell : UITableViewCell
@property (nonatomic, copy) void (^onTrackTapped)(LTTrack *track);
- (void)setTracks:(NSArray *)tracks;
@end

@implementation LTHomeRecentsCell {
    UIScrollView *_scrollView;
    NSArray *_tracks;
    // What the currently-built tiles represent, so an identical -setTracks: is a
    // no-op. See -setTracks:.
    NSArray *_builtIds;
    BOOL _builtDark;
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
        _scrollView.backgroundColor = [LTTheme background];
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
    // Rebuilding this strip destroys and recreates 20 tiles (4 views each) and
    // kicks off 20 artwork loads. It is called from -cellForRowAtIndexPath:, so
    // every dequeue paid for it — and every tab switch to Home re-reads
    // recents.plist, producing a fresh-but-equal array each time, so the rebuild
    // produced the identical result every single time.
    //
    // Skip it when the list and the theme are unchanged; the existing tiles are
    // already correct. The comparison is by videoId array rather than pointer
    // identity because -recentTracks returns newly-parsed LTTrack objects on
    // every call. An array of ids compares directly, with no per-item string
    // formatting -- the previous signature built 20 formatted strings per dequeue,
    // which is a real cost when its only job is to answer "did this change?".
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:tracks.count];
    for (LTTrack *track in tracks) [ids addObject:track.videoId ?: @""];
    BOOL dark = [LTTheme isDark];
    if (_builtIds && [_builtIds isEqualToArray:ids] && _builtDark == dark) {
        _tracks = tracks;
        return;
    }

    _tracks = tracks;
    _builtIds = ids;
    _builtDark = dark;
    _scrollView.backgroundColor = [LTTheme background];
    self.backgroundColor = [LTTheme background];
    self.contentView.backgroundColor = [LTTheme background];
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
        imageButton.backgroundColor = [LTTheme placeholder];
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
            // Retain the view until the image arrives; the strip is rebuilt
            // when the section reloads, so an unsafe-unretained view can be
            // gone by the time the completion runs.
            [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                if (image) artwork.image = image;
            }];
        }

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(2, artH + 4, tileWidth - 4, 26)];
        titleLabel.font = [UIFont boldSystemFontOfSize:12];
        titleLabel.numberOfLines = 2;
        titleLabel.textColor = [LTTheme text];
        titleLabel.text = track.title;
        [tile addSubview:titleLabel];

        UILabel *artistLabel = [[UILabel alloc] initWithFrame:CGRectMake(2, artH + 30, tileWidth - 4, 12)];
        artistLabel.font = [UIFont systemFontOfSize:11];
        artistLabel.textColor = [LTTheme secondaryText];
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
@property (nonatomic, strong) LTPeekCoordinator *peekCoordinator;
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
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = @"Home";
    self.view.backgroundColor = [LTTheme background];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Stats"
                                                                             style:UIBarButtonItemStyleBordered
                                                                            target:self
                                                                            action:@selector(statsTapped:)];

    CGRect bounds = self.view.bounds;
    self.tableView = [[LTThemedTableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme background];
    self.tableView.tableHeaderView = [self buildBanner];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 190, bounds.size.width - 48, 60)];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textColor = [LTTheme secondaryText];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    // 3D Touch peek on playlist rows; a no-op below iOS 9.
    __unsafe_unretained LTHomeViewController *peekSelf = self;
    self.peekCoordinator = [[LTPeekCoordinator alloc] initWithOwner:self
                                                      sourceView:self.tableView
                                                   peekProvider:^UIViewController *(CGPoint point) {
        LTLocalPlaylist *playlist = [peekSelf peekPlaylistAtPoint:point];
        if (!playlist) return nil;
        return [[LTPlaylistPeekViewController alloc] initWithPlaylist:playlist];
    } commit:^(UIViewController *peek) {
        if (![peek isKindOfClass:[LTPlaylistPeekViewController class]]) return;
        [peekSelf peekCommitPlaylist:[(LTPlaylistPeekViewController *)peek playlist]];
    }];
    [self.peekCoordinator registerPreview];
}

- (UIView *)buildBanner {
    CGFloat width = self.view.bounds.size.width;
    UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 92)];

    // The banner takes the theme's accent colour, so the modern themes get the
    // amber rather than the fixed blue the native theme has always used.
    UIColor *bannerColour = [LTTheme isModern]
        ? ([LTTheme accent] ?: [UIColor colorWithRed:0.72f green:0.28f blue:0.37f alpha:1.0f])
        : [UIColor colorWithRed:0.0f green:0.42f blue:0.85f alpha:1.0f];
    UIColor *topCol = [LTTheme shade:bannerColour by:0.55f] ?: bannerColour;
    UIColor *botCol = [LTTheme shade:bannerColour by:1.0f] ?: bannerColour;
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = banner.bounds;
    CGColorRef topCG = topCol.CGColor ?: [UIColor blueColor].CGColor;
    CGColorRef botCG = botCol.CGColor ?: [UIColor blueColor].CGColor;
    gradient.colors = @[(__bridge id)topCG, (__bridge id)botCG];
    [banner.layer insertSublayer:gradient atIndex:0];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 20, width - 32, 30)];
    titleLabel.text = @"Welcome back.";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    if ([UIColor respondsToSelector:@selector(whiteColor)]) titleLabel.textColor = [UIColor whiteColor];
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

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme background];
    self.tableView.backgroundColor = [LTTheme background];
    [self.tableView reloadData];
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

// The section title, drawn by us so it can be themed. UITableView draws its
// own header titles in a colour that cannot be set, which is black on every
// iOS before 13.
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title.length) return nil;
    return [LTSectionHeaderView headerWithTitle:title];
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
        __unsafe_unretained LTHomeViewController *weakSelf = self;
        cell.onTrackTapped = ^(LTTrack *track) {
            LTHomeViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            [LTPlayerController sharedController].queueSourceName = @"Home";
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
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    LTLocalPlaylist *playlist = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = playlist.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%d tracks", (int)playlist.tracks.count];
    cell.accessoryView = nil;
    cell.imageView.image = nil;
    [LTPlaylistStore providePlaylistArtwork:playlist toCell:cell];
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
    // Confirm first: the row stays put until the prompt is answered, so the
    // table never shows a playlist that is still there.
    __unsafe_unretained LTHomeViewController *weakSelf = self;
    [LTPlaylistStore confirmDeletePlaylist:playlist presenting:self completion:^(BOOL deleted) {
        if (deleted) [weakSelf.tableView reloadData];
    }];
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


#pragma mark - 3D Touch peek

// Pressing a playlist row in shows LTPlaylistPeekViewController; pressing all
// the way in commits and pushes the same detail screen a tap would have.
- (LTLocalPlaylist *)peekPlaylistAtPoint:(CGPoint)point {
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) return nil;
    if (indexPath.section != [self playlistSection]) return nil;
    if ((NSUInteger)indexPath.row >= self.playlists.count) return nil;
    return [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
}

- (void)peekCommitPlaylist:(LTLocalPlaylist *)playlist {
    if (!playlist.identifier.length) return;
    LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:playlist];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
