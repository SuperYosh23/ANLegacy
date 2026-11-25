#import "S6ListViewController.h"
#import "S6Theme.h"
#import "S6Player.h"
#import "S6Common.h"

@interface S6ListViewController ()
@property (nonatomic) BOOL loading;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic) BOOL loadedOnce;
@end

@implementation S6ListViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    if ((self = [super initWithStyle:style])) _refreshable = YES;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    S6Theme *theme = [S6Theme shared];
    [theme applyToTableView:self.tableView];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.textColor = [theme secondaryTextColor];
    self.messageLabel.font = [theme bodyFont];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];
    self.retryButton = [theme outlineButtonWithTitle:L(@"Try again")];
    [self.retryButton addTarget:self action:@selector(reload) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.view addSubview:self.retryButton];
    if (self.refreshable && NSClassFromString(@"UIRefreshControl") && [self respondsToSelector:@selector(setRefreshControl:)]) {
        id rc = [[NSClassFromString(@"UIRefreshControl") alloc] init];
        if ([rc respondsToSelector:@selector(setTintColor:)]) [rc performSelector:@selector(setTintColor:) withObject:[theme secondaryTextColor]];
        [rc addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
        [self performSelector:@selector(setRefreshControl:) withObject:rc];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged) name:S6PlayerDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!self.loadedOnce) {
        self.loadedOnce = YES;
        [self load];
    }
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat top = b.origin.y + MIN(b.size.height / 3, 220);
    self.spinner.center = CGPointMake(CGRectGetMidX(b), top);
    self.messageLabel.frame = CGRectMake(30, top - 40, b.size.width - 60, 80);
    self.retryButton.frame = CGRectMake(CGRectGetMidX(b) - 80, top + 50, 160, 34);
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return S6IsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

- (void)load { [self finishLoadingWithError:nil empty:NO emptyMessage:nil]; }

- (void)reload { [self load]; }

- (void)startLoading
{
    self.loading = YES;
    self.messageLabel.hidden = YES;
    self.retryButton.hidden = YES;
    if (!self.refreshControl.refreshing && [self.tableView numberOfSections] == 0) [self.spinner startAnimating];
    else if (!self.refreshControl.refreshing && [self tableView:self.tableView numberOfRowsInSection:0] == 0) [self.spinner startAnimating];
}

- (void)finishLoadingWithError:(NSError *)error empty:(BOOL)empty emptyMessage:(NSString *)message
{
    self.loading = NO;
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
    [self.tableView reloadData];
    if (empty || (error && !empty && [self.tableView numberOfSections] == 0)) {
        self.messageLabel.text = error ? error.localizedDescription : message;
        self.messageLabel.hidden = !self.messageLabel.text.length;
        self.retryButton.hidden = !error;
    } else {
        self.messageLabel.hidden = YES;
        self.retryButton.hidden = YES;
    }
    [self.view setNeedsLayout];
}

- (void)playerChanged
{
    if (!self.isViewLoaded || !self.view.window) return;
    // (the rows first, reloaded afterwards in one go: on iOS 6 visibleCells is the table's own array, and reloading
    // a row while going through it throws "mutated while being enumerated")
    NSMutableArray *rows = [NSMutableArray array];
    for (UITableViewCell *cell in [self.tableView.visibleCells copy]) {
        NSIndexPath *ip = [self.tableView indexPathForCell:cell];
        if (ip && [cell respondsToSelector:@selector(showTrack:number:)]) [rows addObject:ip];
    }
    if (rows.count) [self.tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
}

@end
