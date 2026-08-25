#import <QuartzCore/QuartzCore.h>
#import "LTTrackListViewController.h"
#import "LTYouTubeClient.h"
#import "LTMediaCell.h"
#import "LTHeaderView.h"
#import "LTTabBarController.h"
#import "LTPlayerController.h"
#import "LTPlaylistStore.h"
#import "LTPlaylistPicker.h"
#import <QuartzCore/QuartzCore.h>

@interface LTTrackListViewController () <UITableViewDataSource, UITableViewDelegate,
                                         UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, copy) NSString *browseId;
@property (nonatomic, assign) LTBrowseKind kind;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *tracks;
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, strong) LTHeaderView *headerView;
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

    self.headerView = [[LTHeaderView alloc] initWithWidth:self.view.bounds.size.width];
    self.tableView.tableHeaderView = self.headerView;

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
    if (title.length) self.headerView.titleLabel.text = title;
    NSString *subtitle = self.info[@"subtitle"];
    if (subtitle.length) self.headerView.subtitleLabel.text = subtitle;
    [self.headerView setArtworkURL:self.info[@"thumbnail"]];
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
    [[LTPlayerController sharedController] playQueue:self.tracks atIndex:indexPath.row];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

@end
