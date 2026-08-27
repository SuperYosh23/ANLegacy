#import "LTHomeViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTLocalPlaylistDetailViewController.h"
#import "LTMediaCell.h"
#import "LTModel.h"

@interface LTHomeViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *recentTracks;
@property (nonatomic, strong) NSArray *playlists;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation LTHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Home";
    self.view.backgroundColor = [UIColor whiteColor];

    CGRect bounds = self.view.bounds;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 120, bounds.size.width - 48, 60)];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textColor = [UIColor grayColor];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = 0;
    if (self.recentTracks.count) sections += 1;
    if (self.playlists.count) sections += 1;
    return sections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.recentTracks.count && self.playlists.count) {
        return section == 0 ? @"Recently Played" : @"Your Playlists";
    }
    if (self.recentTracks.count) return @"Recently Played";
    return @"Your Playlists";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    BOOL isWidescreen = ([UIScreen mainScreen].bounds.size.height >= 568.0f);
    NSInteger recentsLimit = isWidescreen ? 4 : 3;
    if (self.recentTracks.count && self.playlists.count) {
        if (section == 0) return MIN((NSInteger)self.recentTracks.count, recentsLimit);
        return (NSInteger)self.playlists.count;
    }
    if (self.recentTracks.count) return MIN((NSInteger)self.recentTracks.count, recentsLimit);
    return (NSInteger)self.playlists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTHomeCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    id item = [self itemForIndexPath:indexPath];
    if ([item isKindOfClass:[LTTrack class]]) {
        LTTrack *track = item;
        cell.textLabel.text = track.title;
        NSMutableString *detail = [NSMutableString string];
        if (track.artist.length) [detail appendString:track.artist];
        if (track.album.length) {
            if (detail.length) [detail appendString:@"  •  "];
            [detail appendString:track.album];
        }
        cell.detailTextLabel.text = detail;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        [cell setImageFromURL:track.thumbnailURL];
    } else if ([item isKindOfClass:[LTLocalPlaylist class]]) {
        LTLocalPlaylist *playlist = item;
        cell.textLabel.text = playlist.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%d tracks", (int)playlist.tracks.count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        cell.imageView.image = nil;
    }
    return cell;
}

- (id)itemForIndexPath:(NSIndexPath *)indexPath {
    if (self.recentTracks.count && self.playlists.count) {
        if (indexPath.section == 0) return [self.recentTracks objectAtIndex:(NSUInteger)indexPath.row];
        return [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    }
    if (self.recentTracks.count) return [self.recentTracks objectAtIndex:(NSUInteger)indexPath.row];
    return [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
}

#pragma mark - Editing (swipe to delete playlists)

// Playlist rows live in the last section; recents (when present) take section 0.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL playlistSection = self.recentTracks.count ? indexPath.section == 1 : YES;
    return playlistSection && self.playlists.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    BOOL playlistSection = self.recentTracks.count ? indexPath.section == 1 : YES;
    if (!playlistSection) return;
    LTLocalPlaylist *playlist = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    [[LTPlaylistStore sharedStore] deletePlaylist:playlist];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id item = [self itemForIndexPath:indexPath];
    if ([item isKindOfClass:[LTTrack class]]) {
        [[LTPlayerController sharedController] playQueue:[NSArray arrayWithObject:item] atIndex:0];
        [(LTTabBarController *)self.tabBarController showNowPlaying];
    } else if ([item isKindOfClass:[LTLocalPlaylist class]]) {
        LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:item];
        [self.navigationController pushViewController:detail animated:YES];
    }
}

@end
