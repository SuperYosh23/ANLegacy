#import "LTSeedSearchViewController.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTTheme.h"
#import "LTThemedTableView.h"
#import "LTLog.h"
#import "LTGraphics.h"
#import "LTMediaCell.h"

@interface LTSeedSearchViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) NSString *seedType;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *results;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation LTSeedSearchViewController

- (id)initWithSeedType:(NSString *)seedType {
    self = [super init];
    if (self) {
        _seedType = seedType;
        _results = [NSArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    
    NSString *title = @"Search";
    if ([self.seedType isEqualToString:@"track"]) title = @"Add Song";
    else if ([self.seedType isEqualToString:@"artist"]) title = @"Add Artist";
    else if ([self.seedType isEqualToString:@"album"]) title = @"Add Album";
    
    self.title = title;
    self.view.backgroundColor = [LTTheme background];
    
    // Search bar
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    _searchBar.delegate = self;
    _searchBar.placeholder = [NSString stringWithFormat:@"Search for %@", [self.seedType lowercaseString]];
    _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:_searchBar];
    
    // Table view
    CGFloat tableY = _searchBar.frame.size.height;
    _tableView = [[LTThemedTableView alloc] initWithFrame:CGRectMake(0, tableY, self.view.bounds.size.width, self.view.bounds.size.height - tableY) style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.backgroundColor = [LTTheme background];
    [self.view addSubview:_tableView];
    
    // Spinner
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
    [self.view addSubview:_spinner];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_searchBar becomeFirstResponder];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSString *query = searchBar.text;
    if (!query.length) return;
    
    [self.spinner startAnimating];
    _results = [NSArray array];
    [_tableView reloadData];
    
    __unsafe_unretained typeof(self) weakSelf = self;
    void (^finish)(NSArray *, NSError *) = ^(NSArray *items, NSError *error) {
        [weakSelf.spinner stopAnimating];
        if (error) {
            LTLog(@"SEARCH error: %@", error);
            return;
        }
        weakSelf.results = items;
        [weakSelf.tableView reloadData];
    };
    
    if ([self.seedType isEqualToString:@"track"]) {
        [[LTYouTubeClient sharedClient] searchWithQuery:query type:@"songs" completion:finish];
    } else {
        NSString *type = [self.seedType isEqualToString:@"artist"] ? @"artists" : @"albums";
        [[LTYouTubeClient sharedClient] searchWithQuery:query type:type completion:finish];
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (!searchText.length) {
        _results = [NSArray array];
        [_tableView reloadData];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTMediaCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
    }
    
    if (indexPath.row >= (NSInteger)_results.count) {
        cell.textLabel.text = @"";
        cell.detailTextLabel.text = @"";
        cell.imageView.image = nil;
        return cell;
    }
    
    id item = [_results objectAtIndex:(NSUInteger)indexPath.row];
    
    if ([item isKindOfClass:[LTTrack class]]) {
        LTTrack *track = (LTTrack *)item;
        cell.textLabel.text = track.title ?: @"";
        cell.detailTextLabel.text = track.artist ?: @"";
        [cell setImageFromURL:track.thumbnailURL];
    } else if ([item isKindOfClass:[LTBrowseItem class]]) {
        LTBrowseItem *browse = (LTBrowseItem *)item;
        cell.textLabel.text = browse.title ?: @"";
        cell.detailTextLabel.text = browse.subtitle ?: @"";
        [cell setImageFromURL:browse.thumbnailURL];
    } else {
        cell.textLabel.text = @"";
        cell.detailTextLabel.text = @"";
        cell.imageView.image = nil;
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 54.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row >= (NSInteger)_results.count) {
        return;
    }
    
    id item = [_results objectAtIndex:(NSUInteger)indexPath.row];
    LTLog(@"SEEDSEARCH tap seedType=%@ itemClass=%@ resultCount=%lu", self.seedType, NSStringFromClass([item class]), (unsigned long)_results.count);
    LTStationSeed *seed = [[LTStationSeed alloc] init];
    seed.type = self.seedType;
    
    if ([item isKindOfClass:[LTTrack class]]) {
        LTTrack *track = (LTTrack *)item;
        seed.videoId = track.videoId ?: @"";
        seed.title = track.title ?: @"";
        seed.artist = track.artist ?: @"";
        seed.album = track.album ?: @"";
        seed.thumbnailURL = track.thumbnailURL ?: @"";
    } else if ([item isKindOfClass:[LTBrowseItem class]]) {
        LTBrowseItem *browse = (LTBrowseItem *)item;
        LTLog(@"SEEDSEARCH browse title=%@ browseId=%@ kind=%d", browse.title, browse.browseId, (int)browse.kind);
        if ([self.seedType isEqualToString:@"artist"]) {
            seed.artist = browse.title ?: @"";
            seed.thumbnailURL = browse.thumbnailURL ?: @"";
            seed.browseId = browse.browseId ?: @"";
        } else if ([self.seedType isEqualToString:@"album"]) {
            seed.album = browse.title ?: @"";
            seed.artist = browse.subtitle ?: @"";
            seed.thumbnailURL = browse.thumbnailURL ?: @"";
            seed.browseId = browse.browseId ?: @"";
        }
    } else {
        return;
    }
    
    if ([self.delegate respondsToSelector:@selector(seedSearchViewController:didSelectSeed:)]) {
        [self.delegate seedSearchViewController:self didSelectSeed:seed];
    }
    
    [self.navigationController popViewControllerAnimated:YES];
}

@end
