#import "S6LibraryViewController.h"
#import "S6Cells.h"
#import "S6Router.h"
#import "S6Theme.h"
#import "S6Models.h"
#import "S6Catalog.h"
#import "S6Session.h"
#import "S6ImageLoader.h"
#import "S6Utils.h"
#import "S6Common.h"

static NSString *S6LibraryFilter(S6LibraryMode mode)
{
    switch (mode) {
        case S6LibraryPlaylists: return @"Playlists";
        case S6LibraryAlbums: return @"Albums";
        case S6LibraryArtists: return @"Artists";
        default: return @"Podcasts";
    }
}

@interface S6LibraryViewController () <UIAlertViewDelegate>
@property (nonatomic) BOOL switcher;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic) NSUInteger generation;          // a newer load makes the answers of an older one go unused
@property (nonatomic, strong) UISegmentedControl *segments;
@end

@implementation S6LibraryViewController

- (instancetype)initWithMode:(S6LibraryMode)mode switcher:(BOOL)switcher
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _mode = mode;
        _switcher = switcher;
        _items = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSString *)titleForMode:(S6LibraryMode)mode
{
    switch (mode) {
        case S6LibraryPlaylists: return L(@"Playlists");
        case S6LibraryAlbums: return L(@"Albums");
        case S6LibraryArtists: return L(@"Artists");
        default: return L(@"Podcasts");
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:[S6MediaCell class] forCellReuseIdentifier:@"media"];
    if (self.switcher) {
        self.segments = [[UISegmentedControl alloc] initWithItems:@[ L(@"Playlists"), L(@"Albums"), L(@"Artists"), L(@"Podcasts") ]];
        self.segments.segmentedControlStyle = UISegmentedControlStyleBar;
        self.segments.tintColor = [UIColor colorWithWhite:0.25 alpha:1];
        self.segments.selectedSegmentIndex = self.mode;
        [self.segments addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
        self.navigationItem.titleView = self.segments;
        self.title = L(@"Your Library");
    } else {
        self.title = [self titleForMode:self.mode];
    }
    [self updateAddButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:S6LibraryDidChangeNotification object:nil];
}

- (void)updateAddButton
{
    self.navigationItem.rightBarButtonItem = self.mode == S6LibraryPlaylists ?
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(newPlaylist)] : nil;
}

- (void)segmentChanged
{
    self.mode = (S6LibraryMode)self.segments.selectedSegmentIndex;
    [self.items removeAllObjects];
    [self.tableView reloadData];
    [self updateAddButton];
    [self load];
}

- (void)setMode:(S6LibraryMode)mode
{
    _mode = mode;
    if (!self.switcher && self.isViewLoaded) self.title = [self titleForMode:mode];
}

- (void)load
{
    if ([S6Session shared].state == S6SessionStateLoggedOut) { [self finishLoadingWithError:nil empty:NO emptyMessage:nil]; return; }
    [self startLoading];
    NSUInteger generation = ++self.generation;
    [self.items removeAllObjects];
    [self loadFrom:0 generation:generation];
}

// Page after page (50 at a time, at most 500)
- (void)loadFrom:(NSInteger)offset generation:(NSUInteger)generation
{
    S6LibraryMode mode = self.mode;
    __unsafe_unretained S6LibraryViewController *weakSelf = self;
    [S6Catalog library:S6LibraryFilter(mode) offset:offset limit:50 completion:^(NSArray *items, NSInteger total, NSError *error) {
        S6LibraryViewController *me = weakSelf;
        if (!me || generation != me.generation) return;
        [me.items addObjectsFromArray:items ?: [NSArray array]];
        if (!error && items.count && (NSInteger)me.items.count < MIN(total, 500)) {
            [me.tableView reloadData];
            [me loadFrom:offset + (NSInteger)items.count generation:generation];
            return;
        }
        NSString *empty = mode == S6LibraryAlbums ? L(@"Albums you save show up here.") : mode == S6LibraryArtists ? L(@"Artists you follow show up here.") :
                          mode == S6LibraryPodcasts ? L(@"Podcasts you follow show up here.") : L(@"Nothing here yet.");
        [me finishLoadingWithError:me.items.count ? nil : error empty:!me.items.count && mode != S6LibraryPlaylists emptyMessage:empty];
    }];
}

- (void)newPlaylist
{
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"New playlist") message:nil delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Create"), nil];
    a.alertViewStyle = UIAlertViewStylePlainTextInput;
    [a textFieldAtIndex:0].placeholder = L(@"Playlist name");
    [a show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *name = [[alertView textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) return;
    [S6Catalog createPlaylistNamed:name completion:^(S6Playlist *playlist, NSError *error) {
        if (!playlist) { [S6Router toast:error.localizedDescription ?: L(@"The playlist could not be created.")]; return; }
        [S6Router openPlaylist:playlist];
    }];
}

#pragma mark - Table

- (BOOL)hasLikedRow { return self.mode == S6LibraryPlaylists; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.items.count + ([self hasLikedRow] ? 1 : 0);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6MediaCell *cell = [tableView dequeueReusableCellWithIdentifier:@"media" forIndexPath:indexPath];
    NSInteger row = indexPath.row;
    if ([self hasLikedRow]) {
        if (row == 0) {
            cell.round = NO;
            [cell showTitle:L(@"Liked Songs") subtitle:L(@"Playlist") imageURL:nil];
            cell.art.image = [[S6Theme shared] icon:S6IconHeartFilled size:52 color:[[S6Theme shared] accentColor]];
            cell.art.contentMode = UIViewContentModeCenter;
            return cell;
        }
        row--;
    }
    cell.art.contentMode = UIViewContentModeScaleAspectFill;
    id item = self.items[(NSUInteger)row];
    cell.round = [item isKindOfClass:[S6Artist class]];
    if ([item isKindOfClass:[S6Playlist class]]) {
        S6Playlist *p = item;
        NSString *sub = [NSString stringWithFormat:L(@"by %@"), p.ownerName ?: @""];
        if (p.totalTracks) sub = [NSString stringWithFormat:@"%@ · %@", sub, [NSString stringWithFormat:L(@"%lu songs"), (unsigned long)p.totalTracks]];
        [cell showTitle:p.name subtitle:sub imageURL:[p imageURLForSize:120]];
    } else if ([item isKindOfClass:[S6Album class]]) {
        [cell showTitle:[item name] subtitle:[item artistNames] imageURL:[item imageURLForSize:120]];
    } else if ([item isKindOfClass:[S6Artist class]]) {
        [cell showTitle:[item name] subtitle:L(@"Artist") imageURL:[item imageURLForSize:120]];
    } else {
        [cell showTitle:[item name] subtitle:[item publisher] imageURL:[item imageURLForSize:120]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger row = indexPath.row;
    if ([self hasLikedRow]) {
        if (row == 0) { [S6Router openLikedSongs]; return; }
        row--;
    }
    if (row < (NSInteger)self.items.count) [S6Router openItem:self.items[(NSUInteger)row]];
}

@end

@interface S6PlaylistPickerViewController ()
@property (nonatomic, copy) void (^completion)(id playlist);
@property (nonatomic, strong) NSArray *playlists;
@end

@implementation S6PlaylistPickerViewController

- (instancetype)initWithCompletion:(void (^)(id))completion
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _completion = [completion copy];
        _playlists = [NSArray array];
        self.title = L(@"Add to playlist");
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = 68;
    [self.tableView registerClass:[S6MediaCell class] forCellReuseIdentifier:@"media"];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
}

- (void)cancel
{
    [self dismissViewControllerAnimated:YES completion:nil];
    if (self.completion) self.completion(nil);
    self.completion = nil;
}

- (void)load
{
    [self startLoading];
    __unsafe_unretained S6PlaylistPickerViewController *weakSelf = self;
    [S6Catalog editablePlaylistsFor:self.trackURI completion:^(NSArray *playlists, NSError *error) {
        weakSelf.playlists = playlists ?: [NSArray array];
        [weakSelf finishLoadingWithError:playlists.count ? nil : error empty:!playlists.count emptyMessage:L(@"You have no playlists of your own yet.")];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.playlists.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6MediaCell *cell = [tableView dequeueReusableCellWithIdentifier:@"media" forIndexPath:indexPath];
    S6Playlist *p = self.playlists[(NSUInteger)indexPath.row];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.art.contentMode = UIViewContentModeScaleAspectFill;
    [cell showTitle:p.name subtitle:p.ownerName.length ? [NSString stringWithFormat:L(@"by %@"), p.ownerName] : @"" imageURL:[p imageURLForSize:120]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6Playlist *p = self.playlists[(NSUInteger)indexPath.row];
    void (^completion)(id) = self.completion;
    self.completion = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
    if (completion) completion(p);
}

@end
