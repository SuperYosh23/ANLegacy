#import "LTPlaylistSelectViewController.h"
#import "LTPlaylistStore.h"

@interface LTPlaylistSelectViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *playlists;
@property (nonatomic, strong) NSMutableSet *selectedIdentifiers;
@property (nonatomic, copy) LTPlaylistSelectCompletion completion;
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation LTPlaylistSelectViewController

- (instancetype)initWithPlaylists:(NSArray *)playlists
                       completion:(LTPlaylistSelectCompletion)completion {
    self = [super init];
    if (self) {
        _playlists = playlists ?: @[];
        _completion = [completion copy];
        _selectedIdentifiers = [NSMutableSet set];
        for (LTLocalPlaylist *p in _playlists) {
            if (p.identifier.length) [_selectedIdentifiers addObject:p.identifier];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Include Playlists";
    self.view.backgroundColor = [UIColor colorWithWhite:0.11f alpha:1.0f];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                             target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Create" style:UIBarButtonItemStyleDone
               target:self action:@selector(createTapped)];

    CGFloat top = 0;
    CGRect bounds = self.view.bounds;
    // Footer summary label under the table.
    self.footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, top + 8, bounds.size.width - 40, 40)];
    self.footerLabel.font = [UIFont systemFontOfSize:13];
    self.footerLabel.textColor = [UIColor lightGrayColor];
    self.footerLabel.numberOfLines = 0;
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.footerLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, top + 52, bounds.size.width, bounds.size.height - top - 52)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.11f alpha:1.0f];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    [self updateFooter];
}

- (void)updateFooter {
    NSUInteger selected = self.selectedIdentifiers.count;
    NSUInteger total = self.playlists.count;
    if (!total) {
        self.footerLabel.text = @"No playlists with downloaded tracks are available.";
    } else {
        self.footerLabel.text = [NSString stringWithFormat:@"%d of %d playlists will be included.", (int)selected, (int)total];
    }
    self.navigationItem.rightBarButtonItem.enabled = selected > 0;
}

- (void)cancelTapped {
    if (self.completion) self.completion(nil, YES);
}

- (void)createTapped {
    NSArray *ids = [self.selectedIdentifiers allObjects];
    if (self.completion) self.completion(ids, NO);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.playlists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTPlaylistSelectCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }
    LTLocalPlaylist *p = [self.playlists objectAtIndex:indexPath.row];
    cell.textLabel.text = p.name ?: @"Untitled";
    NSUInteger downloaded = 0;
    for (LTTrack *t in p.tracks) {
        if ([[LTPlaylistStore sharedStore] isTrackDownloaded:t]) downloaded += 1;
    }
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%d downloaded", (int)downloaded];
    BOOL sel = (p.identifier.length && [self.selectedIdentifiers containsObject:p.identifier]);
    cell.accessoryType = sel ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LTLocalPlaylist *p = [self.playlists objectAtIndex:indexPath.row];
    if (!p.identifier.length) return;
    if ([self.selectedIdentifiers containsObject:p.identifier]) {
        [self.selectedIdentifiers removeObject:p.identifier];
    } else {
        [self.selectedIdentifiers addObject:p.identifier];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateFooter];
}

@end
