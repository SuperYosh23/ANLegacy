#import "LTStatsDetailViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTMediaCell.h"
#import "LTYouTubeClient.h"

@interface LTStatsDetailViewController ()
@end

@implementation LTStatsDetailViewController {
    LTStatsDetailType _type;
    UITableView *_tableView;
    NSArray *_tracks;
    NSArray *_artists;
}

static NSString *LTDetailFormatDuration(NSTimeInterval seconds) {
    NSInteger s = (NSInteger)seconds;
    NSInteger h = s / 3600;
    NSInteger m = (s % 3600) / 60;
    if (h > 0) return [NSString stringWithFormat:@"%dh %dm", (int)h, (int)m];
    if (m > 0) return [NSString stringWithFormat:@"%dm %ds", (int)m, (int)(s % 60)];
    return [NSString stringWithFormat:@"%ds", (int)s];
}

- (id)initWithType:(LTStatsDetailType)type {
    self = [super init];
    if (self) {
        _type = type;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = (_type == LTStatsDetailTypeTracks) ? @"Most Played" : @"Top Artists";
    self.view.backgroundColor = [UIColor whiteColor];

    CGRect bounds = self.view.bounds;
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                              style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    if (_type == LTStatsDetailTypeTracks) {
        _tracks = [store mostPlayedTracks];
    } else {
        _artists = [store topArtists];
    }
    [_tableView reloadData];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (_type == LTStatsDetailTypeTracks) return (NSInteger)_tracks.count;
    return (NSInteger)_artists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_type == LTStatsDetailTypeTracks) {
        static NSString *CellId = @"LTStatsDetailTrackCell";
        LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
        if (!cell) {
            cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor grayColor];
        }
        LTStatsEntry *entry = [_tracks objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = entry.title.length ? entry.title : @"Unknown Song";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%d plays  •  %@",
                                     (int)entry.plays, LTDetailFormatDuration(entry.seconds)];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = nil;
        if (entry.thumbnailURL.length) {
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:entry.thumbnailURL];
            [cell setImageFromURL:artURL];
        }
        return cell;
    } else {
        static NSString *ArtistCellId = @"LTStatsDetailArtistCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ArtistCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ArtistCellId];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor grayColor];
            cell.imageView.image = nil;
        }
        NSDictionary *row = [_artists objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = [row objectForKey:@"name"];
        NSTimeInterval seconds = [[row objectForKey:@"seconds"] doubleValue];
        NSInteger plays = [[row objectForKey:@"plays"] integerValue];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %d plays",
                                     LTDetailFormatDuration(seconds), (int)plays];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_type != LTStatsDetailTypeTracks) return;
    LTStatsEntry *entry = [_tracks objectAtIndex:(NSUInteger)indexPath.row];
    LTTrack *track = [[LTTrack alloc] init];
    track.videoId = entry.videoId;
    track.title = entry.title;
    track.artist = entry.artist;
    track.thumbnailURL = entry.thumbnailURL;
    [[LTPlayerController sharedController] playQueue:@[track] atIndex:0];
    [(LTTabBarController *)self.navigationController.tabBarController showNowPlaying];
}

@end