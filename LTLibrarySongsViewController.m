#import "LTLibrarySongsViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTMediaCell.h"
#import "LTGraphics.h"
#import "LTModel.h"
#import "LTLog.h"

@interface LTLibrarySongsViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) NSMutableArray *tracks;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) NSInteger pendingRemoveRow;
@property (nonatomic, assign) BOOL ignoreStoreChanges;
@end

@implementation LTLibrarySongsViewController

- (id)initWithTracks:(NSArray *)tracks title:(NSString *)title {
    self = [super init];
    if (self) {
        _tracks = tracks ? [tracks mutableCopy] : [NSMutableArray array];
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
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)]) {
        self.tableView.separatorInset = UIEdgeInsetsMake(0, 60, 0, 0);
    }
    [self.view addSubview:self.tableView];

    UIBarButtonItem *shuffleItem = [[UIBarButtonItem alloc] initWithTitle:@"Shuffle"
                                                                    style:UIBarButtonItemStyleBordered
                                                                   target:self
                                                                   action:@selector(shuffleAllTapped)];
    UIBarButtonItem *playItem = [[UIBarButtonItem alloc] initWithTitle:@"Play All"
                                                                 style:UIBarButtonItemStyleBordered
                                                                target:self
                                                                action:@selector(playAllTapped)];
    self.navigationItem.rightBarButtonItems = @[shuffleItem, playItem];
    [self updateToolbarEnabled];
}

- (void)updateToolbarEnabled {
    BOOL has = self.tracks.count > 0;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) {
        item.enabled = has;
    }
}

- (void)shuffleAllTapped {
    if (!self.tracks.count) return;
    LTPlayerController *player = [LTPlayerController sharedController];
    player.repeatMode = LTRepeatModeAll;
    player.queueSourceName = self.title;
    [player playQueue:self.tracks shuffle:YES];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)playAllTapped {
    if (!self.tracks.count) return;
    LTPlayerController *player = [LTPlayerController sharedController];
    player.repeatMode = LTRepeatModeAll;
    player.queueSourceName = self.title;
    [player playQueue:self.tracks atIndex:0];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)storeDidChange:(NSNotification *)notification {
    if (self.ignoreStoreChanges) return;
    NSMutableArray *stillDownloaded = [NSMutableArray array];
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    for (LTTrack *track in self.tracks) {
        if ([store isTrackDownloaded:track]) {
            [stillDownloaded addObject:track];
        }
    }
    self.tracks = stillDownloaded;
    [self.tableView reloadData];
    [self updateToolbarEnabled];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 630 && buttonIndex == 1) {
        NSInteger row = self.pendingRemoveRow;
        self.pendingRemoveRow = -1;
        if (row < 0 || row >= (NSInteger)self.tracks.count) return;
        LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)row];
        LTLog(@"LIB-SONGS remove download %@ title=%@", track.videoId, track.title);
        self.ignoreStoreChanges = YES;
        [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[track]];
        [self.tracks removeObjectAtIndex:(NSUInteger)row];
        [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
        self.ignoreStoreChanges = NO;
        [self updateToolbarEnabled];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTLibrarySongsCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = track.title;
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
    cell.accessoryView = [self removeAccessoryButtonForRow:indexPath.row];
    return cell;
}

- (UIButton *)removeAccessoryButtonForRow:(NSInteger)row {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 32);
    [button setImage:[self scaledIcon:[LTGraphics checkmarkIcon]] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.tag = row;
    [button addTarget:self action:@selector(rowRemoveTapped:) forControlEvents:UIControlEventTouchUpInside];
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

- (void)rowRemoveTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.tracks.count) return;
    LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)row];
    if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    self.pendingRemoveRow = row;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove Download"
                                                    message:[NSString stringWithFormat:@"Remove \"%@\" from your offline downloads?", track.title]
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Remove", nil];
    alert.tag = 630;
    [alert show];
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

@end