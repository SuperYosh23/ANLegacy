#import "S6SearchViewController.h"
#import "S6Cells.h"
#import "S6Router.h"
#import "S6Theme.h"
#import "S6Models.h"
#import "S6Catalog.h"
#import "S6Player.h"
#import "S6Session.h"
#import "S6Settings.h"
#import "S6Utils.h"
#import "S6Common.h"

enum { S6SearchTop, S6SearchSongs, S6SearchArtists, S6SearchAlbums, S6SearchPlaylists, S6SearchShows, S6SearchEpisodes, S6SearchSectionCount };

@interface S6SearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) S6SearchResults *results;
@property (nonatomic, strong) NSArray *categories;   // NSDictionary {title, uri, image, color}
@property (nonatomic, strong) NSTimer *debounce;
@end

@implementation S6SearchViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = L(@"Search");
        self.refreshable = NO;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerClass:[S6TrackCell class] forCellReuseIdentifier:@"track"];
    [self.tableView registerClass:[S6MediaCell class] forCellReuseIdentifier:@"media"];
    [self.tableView registerClass:[S6TileRowCell class] forCellReuseIdentifier:@"tiles"];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = L(@"Artists, songs or podcasts");
    self.searchBar.delegate = self;
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    [[S6Theme shared] applyToSearchBar:self.searchBar];
    self.tableView.tableHeaderView = self.searchBar;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionChanged) name:S6SessionStateDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)sessionChanged
{
    if ([S6Session shared].state == S6SessionStateReady && !self.categories.count && ![self searching]) [self loadCategories];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    if (![self searching]) [self.tableView reloadData];   // (another number of tiles per row)
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.searchBar resignFirstResponder];
}

- (void)focusSearchField { [self.searchBar becomeFirstResponder]; }

- (void)searchFor:(NSString *)query
{
    self.searchBar.text = query;
    self.query = query;
    [self load];
}

- (BOOL)searching { return self.query.length > 0; }

- (void)load
{
    if (![self searching]) {
        self.results = nil;
        [self finishLoadingWithError:nil empty:NO emptyMessage:nil];
        if (!self.categories.count) [self loadCategories];
        return;
    }
    [self startLoading];
    NSString *q = self.query;
    __unsafe_unretained S6SearchViewController *weakSelf = self;
    [S6Catalog search:q completion:^(S6SearchResults *results, NSError *error) {
        S6SearchViewController *me = weakSelf;
        if (![q isEqualToString:me.query]) return;
        me.results = results;
        BOOL empty = !results || results.empty;
        [me finishLoadingWithError:empty ? error : nil empty:empty emptyMessage:[NSString stringWithFormat:L(@"Nothing found for \"%@\"."), q]];
    }];
}

- (void)loadCategories
{
    __unsafe_unretained S6SearchViewController *weakSelf = self;
    [S6Catalog browseCategories:^(NSArray *categories, NSError *error) {
        if (!categories.count) return;
        weakSelf.categories = categories;
        if (![weakSelf searching]) [weakSelf.tableView reloadData];
    }];
}

#pragma mark - Search bar

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self.debounce invalidate];
    self.debounce = [NSTimer scheduledTimerWithTimeInterval:0.45 target:self selector:@selector(debounced) userInfo:nil repeats:NO];
}

- (void)debounced
{
    NSString *q = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([q isEqualToString:self.query ?: @""]) return;
    self.query = q;
    [self load];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    [self debounced];
    if (self.query.length) [S6Settings addRecentSearch:self.query];
}

#pragma mark - Table

- (NSInteger)columns { return MAX(2, (NSInteger)((self.tableView.bounds.size.width - 12) / (S6IsPad() ? 180 : 150))); }

- (NSArray *)itemsIn:(NSInteger)section
{
    S6SearchResults *r = self.results;
    switch (section) {
        case S6SearchTop: return r.topResult ? @[ r.topResult ] : [NSArray array];
        case S6SearchSongs: return r.tracks;
        case S6SearchArtists: return r.artists;
        case S6SearchAlbums: return r.albums;
        case S6SearchPlaylists: return r.playlists;
        case S6SearchShows: return r.shows;
        default: return r.episodes;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [self searching] ? S6SearchSectionCount : 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (![self searching]) {
        if (section == 0) return (NSInteger)MIN((NSUInteger)8, [S6Settings recentSearches].count);
        NSInteger columns = [self columns];
        return ((NSInteger)self.categories.count + columns - 1) / columns;
    }
    NSInteger n = (NSInteger)[self itemsIn:section].count;
    return section == S6SearchSongs ? MIN(n, 10) : MIN(n, 6);
}

- (NSString *)titleFor:(NSInteger)section
{
    if (![self searching]) return section == 0 ? L(@"Recent searches") : L(@"Browse all");
    switch (section) {
        case S6SearchTop: return L(@"Top result");
        case S6SearchSongs: return L(@"Songs");
        case S6SearchArtists: return L(@"Artists");
        case S6SearchAlbums: return L(@"Albums");
        case S6SearchPlaylists: return L(@"Playlists");
        case S6SearchShows: return L(@"Podcasts");
        default: return L(@"Episodes");
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (![self tableView:tableView numberOfRowsInSection:section]) return nil;
    return S6SectionHeader([self titleFor:section], tableView.bounds.size.width);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [self tableView:tableView numberOfRowsInSection:section] ? 26 : 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (![self searching]) return indexPath.section == 0 ? 44 : [S6TileRowCell heightForWidth:tableView.bounds.size.width columns:[self columns]];
    if (indexPath.section == S6SearchTop) return 84;
    return indexPath.section == S6SearchSongs || indexPath.section == S6SearchEpisodes ? 56 : 68;
}

- (NSString *)subtitleFor:(id)item
{
    if ([item isKindOfClass:[S6Artist class]]) return L(@"Artist");
    if ([item isKindOfClass:[S6Album class]]) {
        S6Album *a = item;
        NSString *kind = [a.albumType isEqualToString:@"single"] ? L(@"Single") : [a.albumType isEqualToString:@"compilation"] ? L(@"Compilation") : L(@"Album");
        return a.year.length ? [NSString stringWithFormat:@"%@ · %@ · %@", kind, a.year, [a artistNames]] : [NSString stringWithFormat:@"%@ · %@", kind, [a artistNames]];
    }
    if ([item isKindOfClass:[S6Playlist class]]) return [NSString stringWithFormat:L(@"by %@"), [item ownerName] ?: @""];
    if ([item isKindOfClass:[S6Show class]]) return [item publisher] ?: L(@"Podcast");
    if ([item isKindOfClass:[S6Track class]]) {
        S6Track *t = item;
        return t.isEpisode ? [NSString stringWithFormat:@"%@ · %@", L(@"Episode"), t.album.name ?: @""] : [NSString stringWithFormat:@"%@ · %@", L(@"Song"), [t artistNames]];
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6Theme *theme = [S6Theme shared];
    if (![self searching]) {
        if (indexPath.section == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"recent"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"recent"];
            [theme styleCell:cell];
            cell.textLabel.text = [S6Settings recentSearches][(NSUInteger)indexPath.row];
            cell.imageView.image = [theme icon:S6IconClock size:18 color:[theme secondaryTextColor]];
            return cell;
        }
        S6TileRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"tiles" forIndexPath:indexPath];
        NSInteger columns = [self columns], start = indexPath.row * columns;
        NSRange range = NSMakeRange((NSUInteger)start, (NSUInteger)MIN(columns, (NSInteger)self.categories.count - start));
        [cell showTiles:[self.categories subarrayWithRange:range] columns:columns];
        cell.onSelect = ^(id item) { [S6Router openItem:item]; };
        return cell;
    }
    id item = [self itemsIn:indexPath.section][(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[S6Track class]] && indexPath.section != S6SearchTop) {
        S6TrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"track" forIndexPath:indexPath];
        cell.showsArt = YES;
        [cell showTrack:item number:0];
        [cell.moreButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [cell.moreButton addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
        cell.moreButton.tag = indexPath.section * 1000 + indexPath.row;
        return cell;
    }
    S6MediaCell *cell = [tableView dequeueReusableCellWithIdentifier:@"media" forIndexPath:indexPath];
    cell.round = [item isKindOfClass:[S6Artist class]];
    [cell showTitle:[item name] subtitle:[self subtitleFor:item] imageURL:[item imageURLForSize:120]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (![self searching]) {
        if (indexPath.section == 0) [self searchFor:[S6Settings recentSearches][(NSUInteger)indexPath.row]];
        return;
    }
    if (self.query.length) [S6Settings addRecentSearch:self.query];
    NSArray *items = [self itemsIn:indexPath.section];
    id item = items[(NSUInteger)indexPath.row];
    if (indexPath.section == S6SearchSongs) {
        // the songs found play one after the other, from the one tapped
        [[S6Player shared] playTracks:items startingAt:(NSUInteger)indexPath.row contextURI:nil
                          contextName:[NSString stringWithFormat:@"%@ “%@”", L(@"Search"), self.query]];
        return;
    }
    [S6Router openItem:item];
}

- (void)moreTapped:(UIButton *)sender
{
    NSArray *items = [self itemsIn:sender.tag / 1000];
    NSInteger row = sender.tag % 1000;
    if (row < (NSInteger)items.count && [items[(NSUInteger)row] isKindOfClass:[S6Track class]])
        [S6Router showActionsForTrack:items[(NSUInteger)row] fromView:sender inController:self playlist:nil];
}

@end

#pragma mark - A browse page

@interface S6CategoryViewController ()
@property (nonatomic, copy) NSString *pageURI;
@property (nonatomic, strong) NSArray *sections;   // S6Shelf
@end

@implementation S6CategoryViewController

- (instancetype)initWithCategoryId:(NSString *)categoryId name:(NSString *)name
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _pageURI = [categoryId copy];
        _sections = [NSArray array];
        self.title = name;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[S6ShelfCell class] forCellReuseIdentifier:@"shelf"];
}

- (CGFloat)cardWidth { return S6IsPad() ? 150 : 120; }

- (void)load
{
    [self startLoading];
    __unsafe_unretained S6CategoryViewController *weakSelf = self;
    [S6Catalog browsePage:self.pageURI completion:^(NSString *title, NSArray *sections, NSError *error) {
        S6CategoryViewController *me = weakSelf;
        if (title.length) me.title = title;
        me.sections = sections ?: [NSArray array];
        [me finishLoadingWithError:sections.count ? nil : error empty:!sections.count emptyMessage:L(@"Nothing here.")];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return (NSInteger)self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [S6ShelfCell heightForCardWidth:[self cardWidth]];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString *title = [self.sections[(NSUInteger)section] title];
    return title.length ? S6SectionHeader(title, tableView.bounds.size.width) : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [[self.sections[(NSUInteger)section] title] length] ? 26 : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6ShelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"shelf" forIndexPath:indexPath];
    NSMutableArray *cards = [NSMutableArray array];
    for (id item in [self.sections[(NSUInteger)indexPath.section] items]) {
        NSDictionary *card = S6CardFor(item);
        if (card) [cards addObject:card];
    }
    [cell showItems:cards cardWidth:[self cardWidth]];
    cell.onSelect = ^(id item) { [S6Router openItem:item]; };
    return cell;
}

@end
