#import "LTLocalPlaylistDetailViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTPlayerViewController.h"
#import "LTLog.h"

@interface LTLocalPlaylistDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) LTLocalPlaylist *playlist;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *headerLabel;
@end

@implementation LTLocalPlaylistDetailViewController

- (id)initWithPlaylist:(LTLocalPlaylist *)playlist {
    self = [super init];
    if (self) {
        _playlist = playlist;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.playlist.name;
    self.view.backgroundColor = [UIColor whiteColor];

    self.headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, self.view.bounds.size.width - 32, 24)];
    self.headerLabel.font = [UIFont systemFontOfSize:13];
    self.headerLabel.textColor = [UIColor grayColor];
    self.headerLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.headerLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 36, self.view.bounds.size.width, self.view.bounds.size.height - 36)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Play All"
                                         style:UIBarButtonItemStyleBordered
                                        target:self
                                        action:@selector(playAllTapped:)],
        [[UIBarButtonItem alloc] initWithTitle:@"Download"
                                         style:UIBarButtonItemStyleBordered
                                        target:self
                                        action:@selector(downloadTapped:)],
    ];
    [self refreshHeader];
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

- (void)refreshHeader {
    self.headerLabel.text = [NSString stringWithFormat:@"%d tracks", (int)self.playlist.tracks.count];
}

#pragma mark - Actions

- (void)playAllTapped:(id)sender {
    if (!self.playlist.tracks.count) return;
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks atIndex:0];
    LTPlayerViewController *player = [[LTPlayerViewController alloc] init];
    [self.navigationController pushViewController:player animated:YES];
}

- (void)downloadTapped:(id)sender {
    if ([[LTPlaylistStore sharedStore] isDownloading]) return;
    NSMutableArray *missing = [NSMutableArray array];
    for (LTTrack *track in self.playlist.tracks) {
        if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
            [missing addObject:track];
        }
    }
    if (!missing.count) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"All Downloaded"
                                                        message:@"This playlist is already available offline."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }
    LTLog(@"PLAYLIST download %d tracks", (int)missing.count);
    [self setDownloadingUI:YES];
    [[LTPlaylistStore sharedStore] downloadTracks:missing completion:^{
        [self setDownloadingUI:NO];
        [self.tableView reloadData];
    }];
}

- (void)setDownloadingUI:(BOOL)downloading {
    if (downloading) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
                                            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        spinner.hidesWhenStopped = YES;
        [spinner startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    } else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Download"
                                                                                  style:UIBarButtonItemStyleBordered
                                                                                 target:self
                                                                                 action:@selector(downloadTapped:)];
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
    NSInteger index = [info[@"index"] integerValue];
    NSInteger total = [info[@"total"] integerValue];
    if (total > 0) {
        self.headerLabel.text = [NSString stringWithFormat:@"Downloading %d of %d...", (int)index + 1, (int)total];
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
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
    if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

- (NSString *)formatDuration:(NSTimeInterval)duration {
    NSInteger seconds = (NSInteger)duration;
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks atIndex:indexPath.row];
    LTPlayerViewController *player = [[LTPlayerViewController alloc] init];
    [self.navigationController pushViewController:player animated:YES];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [[LTPlaylistStore sharedStore] removeTrackAtIndex:indexPath.row fromPlaylist:self.playlist];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self refreshHeader];
    }
}

@end
