#import "LTArtistViewController.h"
#import "LTTraitCompat.h"
#import "LTCardControls.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTMediaCell.h"
#import "LTHeaderView.h"
#import "LTArtistSongsViewController.h"
#import "LTTrackListViewController.h"
#import "LTTabBarController.h"
#import "LTPlayerController.h"
#import "LTSongMenu.h"
#import "LTTheme.h"
#import "LTThemedTableView.h"

// "1.4B", "363K" - the same shorthand the API used for these, so the number
// reads the way it does on the site.
static NSString *LTFormatCountForDisplay(long long n) {
    if (n >= 1000000000LL) return [NSString stringWithFormat:@"%.1fB", n / 1000000000.0];
    if (n >= 1000000LL)    return [NSString stringWithFormat:@"%.1fM", n / 1000000.0];
    if (n >= 1000LL)       return [NSString stringWithFormat:@"%.0fK", n / 1000.0];
    return [NSString stringWithFormat:@"%lld", n];
}

@interface LTArtistViewController () <UIActionSheetDelegate>
@property (nonatomic, copy) NSString *browseId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *topSongs;
@property (nonatomic, strong) NSArray *allSongs;
@property (nonatomic, strong) NSArray *albums;
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, strong) LTHeaderView *headerView;
@property (nonatomic, strong) LTSongMenu *songMenu;
@end

@implementation LTArtistViewController

- (id)initWithBrowseId:(NSString *)browseId title:(NSString *)title {
    self = [super init];
    if (self) {
        _browseId = [browseId copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.view.backgroundColor = [LTTheme groupedBackground];

    self.tableView = [[LTThemedTableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.view addSubview:self.tableView];

    self.headerView = [[LTHeaderView alloc] initWithWidth:self.view.bounds.size.width];
    __unsafe_unretained LTArtistViewController *weakSelf = self;
    self.headerView.onAction = ^(BOOL shuffled) {
        [weakSelf playAllShuffled:shuffled];
    };
    self.tableView.tableHeaderView = self.headerView;

    [self loadContent];
}

// Top songs, taken from the play-sorted list when possible so the two sections
// cannot disagree about the same song. Falls back to the shelf itself when the
// page carried nothing to sort.
- (NSArray *)topSongsFromAllSongs:(NSArray *)allSongs topSongs:(NSArray *)topSongs {
    if (allSongs.count < topSongs.count) return topSongs;
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (LTTrack *track in topSongs) {
        if (!track.videoId.length) continue;
        if ([seen containsObject:track.videoId]) continue;
        [seen addObject:track.videoId];
        for (LTTrack *candidate in allSongs) {
            if ([candidate.videoId isEqualToString:track.videoId]) {
                [result addObject:candidate];
                break;
            }
        }
    }
    return result.count ? result : topSongs;
}

// Subtitle line for a song row: album, then play count when the page supplied
// one. Showing the count is what makes the ordering checkable - a list claimed
// to be sorted by plays that shows no numbers is not much of a claim.
- (NSString *)detailTextForSong:(LTTrack *)track {
    NSMutableString *detail = [NSMutableString string];
    if (track.album.length) [detail appendString:track.album];
    if (track.playCount >= 0) {
        if (detail.length) [detail appendString:@"   "];
        [detail appendString:[LTFormatCountForDisplay(track.playCount) stringByAppendingString:@" plays"]];
    }
    return detail.length ? detail : nil;
}

- (void)updateHeaderActions {
    NSUInteger count = self.allSongs.count ?: self.topSongs.count;
    if (!count) {
        [self.headerView configurePlayAllTitle:nil shuffleTitle:nil];
        return;
    }
    [self.headerView configurePlayAllTitle:@"Play All" shuffleTitle:@"Shuffle All"];
    // tableHeaderView lays out from its frame, so reassign it for the new height.
    self.tableView.tableHeaderView = self.headerView;
}

- (void)playAllShuffled:(BOOL)shuffled {
    NSArray *songs = self.allSongs.count ? self.allSongs : self.topSongs;
    if (!songs.count) return;
    self.tableView.tableHeaderView = self.headerView; // refresh the title under the growing header
    LTPlayerController *player = [LTPlayerController sharedController];
    player.queueSourceName = self.title;
    if (shuffled) {
        [player playQueue:songs shuffle:YES];
    } else {
        [player playQueue:songs atIndex:0];
    }
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme groupedBackground];
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.tableView reloadData];
}

- (void)loadContent {
    __unsafe_unretained LTArtistViewController *weakSelf = self;
    __block BOOL avatarApplied = NO;
    [[LTYouTubeClient sharedClient] browseArtist:self.browseId
                                     completion:^(NSDictionary *info, NSArray *topSongs, NSArray *allSongs, NSArray *albums, NSError *error) {
        LTArtistViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Load Failed"
                                                            message:error.localizedDescription
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
            return;
        }
        strongSelf.info = info;
        // The "Top songs" shelf arrives in whatever order the renderer emitted,
        // which is not popularity order. Present it out of the sorted set so the
        // two lists agree rather than contradicting each other.
        strongSelf.allSongs = allSongs;
        strongSelf.topSongs = [strongSelf topSongsFromAllSongs:allSongs topSongs:topSongs];
        strongSelf.albums = albums;
        [strongSelf updateHeaderActions];
        [strongSelf.tableView reloadData];
        if ([info objectForKey:@"title"]) strongSelf.headerView.titleLabel.text = [info objectForKey:@"title"];
        if ([info objectForKey:@"subtitle"]) strongSelf.headerView.subtitleLabel.text = [info objectForKey:@"subtitle"];
        if (!avatarApplied) [strongSelf.headerView setArtworkURL:[info objectForKey:@"thumbnail"]];
    }
    avatarURL:^(NSString *avatarURL) {
        LTArtistViewController *strongSelf = weakSelf;
        if (!strongSelf || !avatarURL.length) return;
        NSString *square = [[LTYouTubeClient sharedClient] channelAvatarURL:avatarURL size:720];
        avatarApplied = YES;
        [strongSelf.headerView setArtworkURL:square];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = 0;
    if (self.topSongs.count) sections++;
    if (self.albums.count) sections++;
    return sections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0 && self.topSongs.count) return @"Top Songs";
    return @"Albums";
}

// A custom header for the songs section so "Show All" can sit on the right.
// Always offered while there are songs: a predictable way into the full list
// beats hiding it until the sorted set happens to be longer than the shelf.
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (!(section == 0 && self.topSongs.count)) return nil;
    if (!self.allSongs.count) return nil;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 32)];
    header.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 140, 32)];
    label.text = [NSString stringWithFormat:@"Top Songs (%d)", (int)self.allSongs.count];
    label.font = [UIFont boldSystemFontOfSize:13];
    label.textColor = [LTTheme secondaryText];
    label.backgroundColor = [UIColor clearColor];
    [header addSubview:label];

    UIButton *showAll = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    showAll.frame = CGRectMake(tableView.bounds.size.width - 96, 0, 80, 32);
    [showAll setTitle:@"Show All" forState:UIControlStateNormal];
    showAll.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [showAll setTitleColor:[LTTheme text] forState:UIControlStateNormal];
    [showAll addTarget:self action:@selector(showAllSongsTapped:) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:showAll];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0 && self.topSongs.count && self.allSongs.count) return 32.0f;
    return [self tableView:tableView titleForHeaderInSection:section].length ? 32.0f : 12.0f;
}

- (void)showAllSongsTapped:(id)sender {
    if (!self.allSongs.count) return;
    LTArtistSongsViewController *vc = [[LTArtistSongsViewController alloc] initWithArtistName:self.title
                                                                                        songs:self.allSongs];
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 && self.topSongs.count) return (NSInteger)self.topSongs.count;
    return (NSInteger)self.albums.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *TrackId = @"LTTrackCell";
    static NSString *AlbumId = @"LTAlbumCell";
    BOOL isSongs = (indexPath.section == 0 && self.topSongs.count);
    NSString *cellId = isSongs ? TrackId : AlbumId;
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
    }
    if (isSongs) {
        LTTrack *track = [self.topSongs objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = track.title;
        cell.detailTextLabel.text = [self detailTextForSong:track];
        cell.accessoryType = UITableViewCellAccessoryNone;
        UIButton *plus = [UIButton buttonWithType:UIButtonTypeContactAdd];
        plus.tag = (NSInteger)indexPath.row;
        [plus addTarget:self action:@selector(songPlusTapped:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = plus;
        [cell setImageFromURL:track.thumbnailURL];
    } else {
        LTBrowseItem *album = [self.albums objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = album.title;
        cell.detailTextLabel.text = album.subtitle;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [cell setImageFromURL:album.thumbnailURL];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 54.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL isSongs = (indexPath.section == 0 && self.topSongs.count);
    if (isSongs) {
        [LTPlayerController sharedController].queueSourceName = self.title;
        [[LTPlayerController sharedController] playQueue:self.topSongs atIndex:indexPath.row];
        [(LTTabBarController *)self.tabBarController showNowPlaying];
    } else {
        LTBrowseItem *album = [self.albums objectAtIndex:(NSUInteger)indexPath.row];
        LTTrackListViewController *vc = [[LTTrackListViewController alloc] initWithBrowseId:album.browseId
                                                                                        kind:LTBrowseKindAlbum
                                                                                       title:album.title];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)songPlusTapped:(UIButton *)button {
    NSInteger row = (NSInteger)button.tag;
    if (row < 0 || row >= (NSInteger)self.topSongs.count) return;
    LTTrack *track = [self.topSongs objectAtIndex:(NSUInteger)row];
    if (!self.songMenu) self.songMenu = [[LTSongMenu alloc] init];
    [self.songMenu presentForTrack:track fromViewController:self];
}

@end
