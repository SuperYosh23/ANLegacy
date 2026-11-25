#import "LTArtistSongsViewController.h"
#import "LTTraitCompat.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTMediaCell.h"
#import "LTTheme.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTSongMenu.h"
#import "LTPlaylistStore.h"
#import "LTThemedTableView.h"

@interface LTArtistSongsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *artistName;
@property (nonatomic, strong) NSArray *songs;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) LTSongMenu *songMenu;
@end

@implementation LTArtistSongsViewController

- (id)initWithArtistName:(NSString *)artistName songs:(NSArray *)songs {
    self = [super init];
    if (self) {
        _artistName = [artistName copy];
        _songs = [songs copy];
        self.title = [NSString stringWithFormat:@"All Songs (%d)", (int)songs.count];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.view.backgroundColor = [LTTheme background];

    self.tableView = [[LTThemedTableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme background];
    [self.view addSubview:self.tableView];

    // Songs are already in play-count order; say so, since a bare list gives no
    // hint why one track sits above another.
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 28)];
    header.backgroundColor = [UIColor clearColor];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, header.frame.size.width - 32, 28)];
    label.text = @"Most played first";
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = [LTTheme secondaryText];
    label.backgroundColor = [UIColor clearColor];
    [header addSubview:label];
    self.tableView.tableHeaderView = header;
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme background];
    self.tableView.backgroundColor = [LTTheme background];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.songs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTArtistSongCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
    }
    LTTrack *track = [self.songs objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = track.title;

    NSMutableString *detail = [NSMutableString string];
    if (track.album.length) [detail appendString:track.album];
    // The count is shown here too, so the "most played first" caption above the
    // list is verifiable rather than a claim.
    if (track.playCount >= 0) {
        if (detail.length) [detail appendString:@"   "];
        long long count = track.playCount;
        NSString *plays;
        if (count >= 1000000000LL) plays = [NSString stringWithFormat:@"%.1fB", count / 1000000000.0];
        else if (count >= 1000000LL) plays = [NSString stringWithFormat:@"%.1fM", count / 1000000.0];
        else if (count >= 1000LL) plays = [NSString stringWithFormat:@"%.0fK", count / 1000.0];
        else plays = [NSString stringWithFormat:@"%lld", count];
        [detail appendString:[plays stringByAppendingString:@" plays"]];
    }
    if (track.duration > 0) {
        if (detail.length) [detail appendString:@"   "];
        NSInteger seconds = (NSInteger)track.duration;
        [detail appendString:[NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)]];
    }
    cell.detailTextLabel.text = detail.length ? detail : nil;

    cell.accessoryType = UITableViewCellAccessoryNone;
    UIButton *plus = [UIButton buttonWithType:UIButtonTypeContactAdd];
    plus.tag = indexPath.row;
    [plus addTarget:self action:@selector(songPlusTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = plus;

    [cell setImageFromURL:track.thumbnailURL];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 54.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LTPlayerController *player = [LTPlayerController sharedController];
    player.queueSourceName = self.artistName ?: @"Artist";
    [player playQueue:self.songs atIndex:indexPath.row];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)songPlusTapped:(UIButton *)button {
    NSInteger row = (NSInteger)button.tag;
    if (row < 0 || row >= (NSInteger)self.songs.count) return;
    LTTrack *track = [self.songs objectAtIndex:(NSUInteger)row];
    if (!self.songMenu) self.songMenu = [[LTSongMenu alloc] init];
    [self.songMenu presentForTrack:track fromViewController:self];
}

@end