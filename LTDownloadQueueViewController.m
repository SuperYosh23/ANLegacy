#import "LTDownloadQueueViewController.h"
#import "LTPlaylistStore.h"
#import "LTModel.h"

@interface LTDownloadQueueViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray *tracks;
@end

@implementation LTDownloadQueueViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Download Queue";
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0f];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    [self buildHeader];
    [self buildTable];
    [self buildEmptyLabel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueChanged:)
                                                 name:LTPlaylistDownloadProgressNotification
                                               object:nil];
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 58)];
    header.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0f];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 6, self.view.bounds.size.width - 150, 20)];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    [header addSubview:self.statusLabel];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleButton.frame = CGRectMake(self.view.bounds.size.width - 92, 4, 78, 26);
    self.toggleButton.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1.0f];
    self.toggleButton.layer.cornerRadius = 5.0f;
    [self.toggleButton setTitle:@"Pause" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.toggleButton addTarget:self action:@selector(toggleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:self.toggleButton];

    self.clearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.clearButton.frame = CGRectMake(self.view.bounds.size.width - 92, 32, 78, 24);
    self.clearButton.backgroundColor = [UIColor colorWithRed:0.55 green:0.16 blue:0.16 alpha:1.0f];
    self.clearButton.layer.cornerRadius = 5.0f;
    [self.clearButton setTitle:@"Clear All" forState:UIControlStateNormal];
    [self.clearButton setTitleColor:[UIColor colorWithRed:1.0f green:0.4f blue:0.4f alpha:1.0f] forState:UIControlStateNormal];
    self.clearButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.clearButton addTarget:self action:@selector(clearTapped:) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:self.clearButton];

    [self.view addSubview:header];
}

- (void)buildTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 58, self.view.bounds.size.width, self.view.bounds.size.height - 58)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.25 alpha:1.0f];
    self.tableView.rowHeight = 46.0f;
    if ([self.tableView respondsToSelector:@selector(setCellLayoutMarginsFollowReadableWidth:)]) {
        self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    }
    [self.view addSubview:self.tableView];
}

- (void)buildEmptyLabel {
    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 90, self.view.bounds.size.width - 40, 60)];
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0f];
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 2;
    self.emptyLabel.text = @"Nothing queued.\nUse the download button on a song or playlist to add it here.";
    [self.view addSubview:self.emptyLabel];
}

#pragma mark - Data

- (void)queueChanged:(NSNotification *)notification {
    [self reload];
}

- (void)reload {
    self.tracks = [[LTPlaylistStore sharedStore] pendingDownloadTracks];
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSInteger pending = (NSInteger)self.tracks.count;
    BOOL busy = [store isDownloading];
    if (pending == 0) {
        self.statusLabel.text = @"Queue empty";
    } else if (busy) {
        self.statusLabel.text = [NSString stringWithFormat:@"Downloading... %d left", (int)pending];
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"Paused - %d waiting", (int)pending];
    }
    [self.toggleButton setTitle:(busy ? @"Pause" : @"Resume") forState:UIControlStateNormal];
    self.toggleButton.enabled = (pending > 0);
    self.clearButton.enabled = (pending > 0);
    self.clearButton.alpha = (pending > 0) ? 1.0f : 0.4f;
    self.emptyLabel.hidden = (pending > 0);
    self.tableView.hidden = (pending == 0);
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)toggleTapped:(id)sender {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    if ([store isDownloading]) {
        [store pausePendingDownloads];
    } else {
        [store resumePendingDownloads];
    }
    [self reload];
}

- (void)clearTapped:(id)sender {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Clear Download Queue"
                                                    message:@"Remove all queued downloads? Tracks already downloaded are kept."
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Clear", nil];
    alert.tag = 700;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 700 && buttonIndex == 1) {
        [[LTPlaylistStore sharedStore] cancelPendingDownloads];
        [self reload];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LTDownloadQueueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = track.title;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.text = track.artist;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0f];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor clearColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = [self removeButtonForRow:indexPath.row];
    return cell;
}

- (UIButton *)removeButtonForRow:(NSInteger)row {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 44, 32);
    [button setTitle:@"✕" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:1.0f green:0.4f blue:0.4f alpha:1.0f] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17];
    button.tag = row;
    [button addTarget:self action:@selector(removeTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)removeTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.tracks.count) return;
    LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)row];
    [[LTPlaylistStore sharedStore] removeDownloadsFromQueue:@[track]];
    [self reload];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
