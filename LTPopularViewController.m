#import "LTPopularViewController.h"
#import "LTYouTubeClient.h"
#import "LTPlayerController.h"
#import "LTPlayerViewController.h"
#import "LTMediaCell.h"
#import "LTModel.h"

@interface LTPopularViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *tracks;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation LTPopularViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Popular";
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

    self.tracks = [NSMutableArray array];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(refreshTapped:)];
    [self loadTrending];
}

- (void)loadTrending {
    if (self.loading) return;
    self.loading = YES;
    [self showSpinner:YES];
    self.emptyLabel.hidden = YES;

    __weak LTPopularViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] fetchTrendingSongsWithCompletion:^(NSArray *tracks, NSError *error) {
        LTPopularViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loading = NO;
        [strongSelf showSpinner:NO];
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Failed to Load"
                                                            message:error.localizedDescription
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
            return;
        }
        [strongSelf.tracks removeAllObjects];
        [strongSelf.tracks addObjectsFromArray:tracks];
        [strongSelf.tableView reloadData];
        if (!strongSelf.tracks.count) {
            strongSelf.emptyLabel.text = @"No trending songs right now.\nTap the refresh button to try again.";
            strongSelf.emptyLabel.hidden = NO;
        }
    }];
}

- (void)refreshTapped:(id)sender {
    [self loadTrending];
}

- (void)showSpinner:(BOOL)show {
    if (show) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
                                            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        spinner.hidesWhenStopped = YES;
        [spinner startAnimating];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
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
    static NSString *CellId = @"LTPopularCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    LTTrack *track = [self.tracks objectAtIndex:(NSUInteger)indexPath.row];
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
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[LTPlayerController sharedController] playQueue:[self.tracks copy] atIndex:indexPath.row];
    LTPlayerViewController *player = [[LTPlayerViewController alloc] init];
    [self.navigationController pushViewController:player animated:YES];
}

@end
