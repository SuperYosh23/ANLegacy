#import "LTStatsViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTMediaCell.h"
#import "LTYouTubeClient.h"
#import "LTStatsDetailViewController.h"

@interface LTStatsViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation LTStatsViewController {
    UITableView *_tableView;
    UILabel *_totalTimeLabel;
    UILabel *_songsLabel;
    UILabel *_playsLabel;
    NSArray *_mostPlayed;
    NSArray *_topArtists;
    NSArray *_allMostPlayed;
    NSArray *_allTopArtists;
}

static NSString *LTFormatDuration(NSTimeInterval seconds) {
    NSInteger s = (NSInteger)seconds;
    NSInteger h = s / 3600;
    NSInteger m = (s % 3600) / 60;
    if (h > 0) return [NSString stringWithFormat:@"%dh %dm", (int)h, (int)m];
    if (m > 0) return [NSString stringWithFormat:@"%dm %ds", (int)m, (int)(s % 60)];
    return [NSString stringWithFormat:@"%ds", (int)s];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Listening Stats";
    self.view.backgroundColor = [UIColor whiteColor];

    CGRect bounds = self.view.bounds;
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                              style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    CGFloat width = bounds.size.width;
    CGFloat margin = 12.0f;
    CGFloat gap = 12.0f;
    CGFloat panelW = (width - margin * 2.0f - gap * 2.0f) / 3.0f;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 96)];
    header.backgroundColor = [UIColor whiteColor];

    NSArray *titles = @[@"Time Listened", @"Unique Songs", @"Plays"];
    UILabel *totalTimeLabel = nil;
    UILabel *songsLabel = nil;
    UILabel *playsLabel = nil;

    for (NSInteger i = 0; i < 3; i++) {
        CGFloat x = margin + (CGFloat)i * (panelW + gap);
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(x, 8, panelW, 80)];
        card.backgroundColor = [UIColor colorWithRed:0.07f green:0.33f blue:0.68f alpha:1.0f];
        card.layer.cornerRadius = 10.0f;
        card.clipsToBounds = YES;

        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = card.bounds;
        gradient.colors = @[
            (id)[UIColor colorWithRed:0.05f green:0.48f blue:0.9f alpha:1.0f].CGColor,
            (id)[UIColor colorWithRed:0.08f green:0.28f blue:0.55f alpha:1.0f].CGColor,
        ];
        [card.layer insertSublayer:gradient atIndex:0];

        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, panelW, 26)];
        valueLabel.textAlignment = NSTextAlignmentCenter;
        valueLabel.font = [UIFont boldSystemFontOfSize:20];
        valueLabel.textColor = [UIColor whiteColor];
        valueLabel.backgroundColor = [UIColor clearColor];
        valueLabel.minimumFontSize = 12;
        valueLabel.adjustsFontSizeToFitWidth = YES;
        valueLabel.text = @"–";
        [card addSubview:valueLabel];
        if (i == 0) totalTimeLabel = valueLabel;
        if (i == 1) songsLabel = valueLabel;
        if (i == 2) playsLabel = valueLabel;

        UILabel *captionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, panelW, 16)];
        captionLabel.textAlignment = NSTextAlignmentCenter;
        captionLabel.font = [UIFont systemFontOfSize:11];
        captionLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.8f];
        captionLabel.backgroundColor = [UIColor clearColor];
        captionLabel.text = [titles objectAtIndex:(NSUInteger)i];
        [card addSubview:captionLabel];

        [header addSubview:card];
    }
    _totalTimeLabel = totalTimeLabel;
    _songsLabel = songsLabel;
    _playsLabel = playsLabel;

    _tableView.tableHeaderView = header;
    [self.view addSubview:_tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
}

- (void)reloadData {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    _totalTimeLabel.text = LTFormatDuration([store totalListeningTime]);
    _songsLabel.text = [NSString stringWithFormat:@"%d", (int)[store listenedSongsCount]];
    _playsLabel.text = [NSString stringWithFormat:@"%d", (int)[store totalPlayCount]];

    NSArray *mostPlayed = [store mostPlayedTracks];
    NSArray *topArtists = [store topArtists];
    _allMostPlayed = mostPlayed;
    _allTopArtists = topArtists;
    _mostPlayed = mostPlayed.count > 5 ? [mostPlayed subarrayWithRange:NSMakeRange(0, 5)] : mostPlayed;
    _topArtists = topArtists.count > 5 ? [topArtists subarrayWithRange:NSMakeRange(0, 5)] : topArtists;
    [_tableView reloadData];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 30.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = (section == 0) ? @"Most Played" : @"Top Artists";
    BOOL hasMore;
    if (section == 0) {
        hasMore = _allMostPlayed.count > 5;
    } else {
        hasMore = _allTopArtists.count > 5;
    }

    CGFloat width = tableView.bounds.size.width;
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 30)];
    view.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 6, width - 110, 18)];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:14];
    label.textColor = [UIColor grayColor];
    label.backgroundColor = [UIColor clearColor];
    [view addSubview:label];

    if (hasMore) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(width - 86, 3, 70, 24);
        button.tag = section;
        [button setTitle:@"See All" forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:13];
        [button setTitleColor:[UIColor colorWithRed:0.1f green:0.4f blue:0.85f alpha:1.0f]
                     forState:UIControlStateNormal];
        [button addTarget:self action:@selector(seeAllTapped:) forControlEvents:UIControlEventTouchUpInside];
        [view addSubview:button];
    }

    return view;
}

- (void)seeAllTapped:(UIButton *)sender {
    LTStatsDetailViewController *detail =
        [[LTStatsDetailViewController alloc] initWithType:(LTStatsDetailType)sender.tag];
    [self.navigationController pushViewController:detail animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return (NSInteger)_mostPlayed.count;
    return (NSInteger)_topArtists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *CellId = @"LTStatsTrackCell";
        LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
        if (!cell) {
            cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor grayColor];
        }
        LTStatsEntry *entry = [_mostPlayed objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = entry.title.length ? entry.title : @"Unknown Song";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%d plays  •  %@",
                                     (int)entry.plays, LTFormatDuration(entry.seconds)];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = nil;
        if (entry.thumbnailURL.length) {
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:entry.thumbnailURL];
            [cell setImageFromURL:artURL];
        }
        return cell;
    } else {
        static NSString *ArtistCellId = @"LTStatsArtistCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ArtistCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ArtistCellId];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor grayColor];
            cell.imageView.image = nil;
        }
        NSDictionary *row = [_topArtists objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = [row objectForKey:@"name"];
        NSTimeInterval seconds = [[row objectForKey:@"seconds"] doubleValue];
        NSInteger plays = [[row objectForKey:@"plays"] integerValue];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  •  %d plays",
                                     LTFormatDuration(seconds), (int)plays];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    LTStatsEntry *entry = [_mostPlayed objectAtIndex:(NSUInteger)indexPath.row];
    LTTrack *track = [[LTTrack alloc] init];
    track.videoId = entry.videoId;
    track.title = entry.title;
    track.artist = entry.artist;
    track.thumbnailURL = entry.thumbnailURL;
    [LTPlayerController sharedController].queueSourceName = nil;
    [[LTPlayerController sharedController] playQueue:@[track] atIndex:0];
    [(LTTabBarController *)self.navigationController.tabBarController showNowPlaying];
}

@end