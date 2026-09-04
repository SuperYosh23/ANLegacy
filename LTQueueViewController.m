#import "LTQueueViewController.h"
#import "LTPlayerController.h"
#import "LTYouTubeClient.h"
#import "LTGraphics.h"
#import "LTLog.h"

@interface LTQueueViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UIView *scrimView;
@end

@implementation LTQueueViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Queue";
    self.view.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];

    self.headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, self.view.bounds.size.width - 32, 24)];
    self.headerLabel.font = [UIFont boldSystemFontOfSize:15];
    self.headerLabel.textColor = [UIColor whiteColor];
    self.headerLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.headerLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 36, self.view.bounds.size.width, self.view.bounds.size.height - 36)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.tableView];

    [self applyBackgroundPref];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) self.navigationController.navigationBarHidden = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:LTPlayerQueueDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:LTPlayerTrackDidChangeNotification
                                               object:nil];
    [self applyBackgroundPref];
    [self reloadQueue];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadQueue {
    LTPlayerController *controller = [LTPlayerController sharedController];
    NSInteger count = (NSInteger)controller.queue.count;
    if (controller.currentIndex >= 0 && controller.currentIndex < count) {
        self.headerLabel.text = [NSString stringWithFormat:@"Now playing: %d of %d", (int)controller.currentIndex + 1, (int)count];
    } else {
        self.headerLabel.text = @"Nothing in queue";
    }
    [self.tableView reloadData];
}

- (void)queueDidChange:(NSNotification *)notification {
    [self reloadQueue];
}

- (BOOL)artworkBackgroundEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"LTPlayerArtworkBackground"] == nil) {
        BOOL modern = ([UIDevice currentDevice].systemVersion.intValue >= 7);
        [defaults setBool:modern forKey:@"LTPlayerArtworkBackground"];
        return modern;
    }
    return [defaults boolForKey:@"LTPlayerArtworkBackground"];
}

- (void)applyBackgroundPref {
    if ([self artworkBackgroundEnabled]) {
        if (!self.backgroundImageView) {
            self.backgroundImageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
            self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
            self.backgroundImageView.clipsToBounds = YES;
            self.backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.view insertSubview:self.backgroundImageView atIndex:0];

            self.scrimView = [[UIView alloc] initWithFrame:self.view.bounds];
            self.scrimView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
            self.scrimView.userInteractionEnabled = NO;
            self.scrimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.view insertSubview:self.scrimView aboveSubview:self.backgroundImageView];
        }
        [self loadBackgroundArt];
    } else {
        [self.backgroundImageView removeFromSuperview];
        self.backgroundImageView = nil;
        [self.scrimView removeFromSuperview];
        self.scrimView = nil;
    }
}

- (void)loadBackgroundArt {
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    if (!track || !track.thumbnailURL.length) return;
    NSString *url = [[LTYouTubeClient sharedClient] highResThumbnailURL:track.thumbnailURL];
    __weak LTQueueViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:url completion:^(UIImage *image) {
        if (!image) return;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            UIImage *blurred = [LTGraphics blurredImageFromImage:image];
            if (!blurred) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                LTQueueViewController *strongSelf = weakSelf;
                if (strongSelf) strongSelf.backgroundImageView.image = blurred;
            });
        });
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[LTPlayerController sharedController] queue].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTQueueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.15f alpha:0.6f];
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    }
    LTPlayerController *controller = [LTPlayerController sharedController];
    LTTrack *track = [[controller queue] objectAtIndex:(NSUInteger)indexPath.row];
    NSInteger idx = (NSInteger)indexPath.row;
    if (idx == controller.currentIndex) {
        cell.imageView.image = [self scaledIcon:[UIImage imageNamed:@"IcoPlay"]];
        cell.imageView.contentMode = UIViewContentModeCenter;
        cell.textLabel.text = track.title;
        cell.textLabel.textColor = [UIColor colorWithRed:0.35f green:0.68f blue:1.0f alpha:1.0f];
    } else {
        cell.imageView.image = nil;
        cell.textLabel.text = [NSString stringWithFormat:@"%d. %@", (int)idx + 1, track.title];
        cell.textLabel.textColor = [UIColor whiteColor];
    }
    NSMutableString *detail = [NSMutableString string];
    if (track.artist.length) [detail appendString:track.artist];
    if (track.album.length) {
        if (detail.length) [detail appendString:@"  \u2022  "];
        [detail appendString:track.album];
    }
    cell.detailTextLabel.text = detail;
    return cell;
}

- (UIImage *)scaledIcon:(UIImage *)image {
    if (!image) return nil;
    CGFloat s = [UIScreen mainScreen].scale;
    CGSize size = CGSizeMake(14.0f, 14.0f);
    UIGraphicsBeginImageContextWithOptions(size, NO, s);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LTLog(@"QUEUE jump to %d", (int)indexPath.row);
    [[LTPlayerController sharedController] jumpToIndex:indexPath.row];
    [self.navigationController popViewControllerAnimated:YES];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        LTLog(@"QUEUE delete row %d", (int)indexPath.row);
        [[LTPlayerController sharedController] removeTrackAtIndex:indexPath.row];
        [self reloadQueue];
    }
}

@end
