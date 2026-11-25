#import "S6SidebarViewController.h"
#import "S6Session.h"
#import "S6Settings.h"
#import "S6Catalog.h"
#import "S6Models.h"
#import "S6ImageLoader.h"
#import "S6Utils.h"
#import "S6Theme.h"
#import "S6Modern.h"
#import "S6Common.h"

enum { S6SideMain, S6SideLibrary, S6SidePlaylists, S6SideSectionCount };

@interface S6SidebarCell : UITableViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) BOOL current;
@end

@implementation S6SidebarCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        S6Theme *theme = [S6Theme shared];
        self.backgroundColor = [UIColor clearColor];
        self.backgroundView = [[UIImageView alloc] initWithImage:nil];
        UIView *pressed = [[UIView alloc] init];
        pressed.backgroundColor = [theme rowHighlightColor];
        self.selectedBackgroundView = pressed;
        _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _icon.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_icon];
        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.backgroundColor = [UIColor clearColor];
        _label.font = [theme boldBodyFont];
        _label.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
        _label.shadowOffset = CGSizeMake(0, -1);
        [self.contentView addSubview:_label];
    }
    return self;
}

- (void)setCurrent:(BOOL)current
{
    _current = current;
    S6Theme *theme = [S6Theme shared];
    ((UIImageView *)self.backgroundView).image = current ? [theme sidebarSelectionImage] : nil;
    self.label.textColor = current ? [UIColor whiteColor] : [theme secondaryTextColor];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.contentView.bounds.size;
    self.icon.frame = CGRectMake(12, 0, 26, s.height);
    self.label.frame = CGRectMake(46, 0, s.width - 54, s.height);
}

@end

@interface S6SidebarViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIImageView *logo;
@property (nonatomic, strong) UILabel *wordmark;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *footer;
@property (nonatomic, strong) S6ImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *planLabel;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) NSArray *mainRows;       // NSDictionary {title, icon, section}
@property (nonatomic, strong) NSArray *libraryRows;
@property (nonatomic, strong) NSArray *playlists;      // S6Playlist
@property (nonatomic) S6Section selected;
@property (nonatomic, copy) NSString *selectedPlaylist;
@property (nonatomic) NSUInteger playlistsGeneration;
@property (nonatomic, copy) NSString *loadedFor;       // the user whose playlists are shown
@end

@implementation S6SidebarViewController

- (instancetype)init
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _selected = (S6Section)-1;
        _playlists = [NSArray array];
        _mainRows = @[ @{ @"title": L(@"Home"), @"icon": @(S6IconHome), @"section": @(S6SectionHome) },
                       @{ @"title": L(@"Search"), @"icon": @(S6IconSearch), @"section": @(S6SectionSearch) } ];
        _libraryRows = @[ @{ @"title": L(@"Liked Songs"), @"icon": @(S6IconHeart), @"section": @(S6SectionLikedSongs) },
                          @{ @"title": L(@"Playlists"), @"icon": @(S6IconPlaylist), @"section": @(S6SectionPlaylists) },
                          @{ @"title": L(@"Albums"), @"icon": @(S6IconAlbum), @"section": @(S6SectionAlbums) },
                          @{ @"title": L(@"Artists"), @"icon": @(S6IconArtist), @"section": @(S6SectionArtists) },
                          @{ @"title": L(@"Podcasts"), @"icon": @(S6IconPodcast), @"section": @(S6SectionPodcasts) } ];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    S6Theme *theme = [S6Theme shared];
    self.view.backgroundColor = [theme panelColor];

    self.logo = [[UIImageView alloc] initWithImage:[theme brandMarkWithSize:30]];
    [self.view addSubview:self.logo];
    self.wordmark = [[UILabel alloc] initWithFrame:CGRectZero];
    self.wordmark.text = @"Sixify";
    self.wordmark.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:22] ?: [UIFont boldSystemFontOfSize:22];
    self.wordmark.textColor = [UIColor whiteColor];
    self.wordmark.backgroundColor = [UIColor clearColor];
    self.wordmark.shadowColor = [UIColor blackColor];
    self.wordmark.shadowOffset = CGSizeMake(0, -1);
    [self.view addSubview:self.wordmark];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.table.rowHeight = 40;
    self.table.scrollsToTop = NO;
    [self.view addSubview:self.table];

    self.footer = [[UIView alloc] initWithFrame:CGRectZero];
    UIImageView *footerBack = [[UIImageView alloc] initWithImage:[theme navigationBarImage]];
    footerBack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.footer addSubview:footerBack];
    self.avatar = [[S6ImageView alloc] initWithFrame:CGRectMake(10, 9, 34, 34)];
    self.avatar.layer.cornerRadius = 17;
    self.avatar.clipsToBounds = YES;
    self.avatar.image = [theme artistPlaceholderWithSize:34];
    [self.footer addSubview:self.avatar];
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.font = [theme boldBodyFont];
    self.nameLabel.textColor = [theme primaryTextColor];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    [self.footer addSubview:self.nameLabel];
    self.planLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.planLabel.font = [theme smallFont];
    self.planLabel.textColor = [theme accentTextColor];
    self.planLabel.backgroundColor = [UIColor clearColor];
    [self.footer addSubview:self.planLabel];
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.settingsButton setImage:[theme icon:S6IconSettings size:22 color:[theme secondaryTextColor]] forState:UIControlStateNormal];
    self.settingsButton.showsTouchWhenHighlighted = YES;
    self.settingsButton.accessibilityLabel = L(@"Settings");
    [self.settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.footer addSubview:self.settingsButton];
    UIButton *account = [UIButton buttonWithType:UIButtonTypeCustom];
    account.tag = 7;
    [account addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.footer insertSubview:account aboveSubview:footerBack];
    [self.view addSubview:self.footer];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(sessionChanged) name:S6SessionStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(reloadPlaylists) name:S6LibraryDidChangeNotification object:nil];
    [self sessionChanged];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize s = self.view.bounds.size;
    // (iOS 6 puts the view under the status bar; from iOS 7 on it lies behind it)
    CGFloat top = S6ModernTopInset(self.view, 0);
    self.logo.frame = CGRectMake(14, top + 12, 30, 30);
    self.wordmark.frame = CGRectMake(52, top + 10, s.width - 60, 34);
    CGFloat footerH = 52;
    self.table.frame = CGRectMake(0, top + 54, s.width, s.height - top - 54 - footerH);
    self.footer.frame = CGRectMake(0, s.height - footerH, s.width, footerH);
    self.nameLabel.frame = CGRectMake(52, 9, s.width - 100, 18);
    self.planLabel.frame = CGRectMake(52, 27, s.width - 100, 16);
    self.settingsButton.frame = CGRectMake(s.width - 46, 4, 44, 44);
    [self.footer viewWithTag:7].frame = CGRectMake(0, 0, s.width - 50, footerH);
}

#pragma mark - Data

- (void)sessionChanged
{
    S6Session *session = [S6Session shared];
    NSString *user = session.username ?: [S6Settings username];
    self.nameLabel.text = user ?: @"";
    self.planLabel.text = session.state == S6SessionStateReady ? (session.premium ? @"Premium" : L(@"Free")) :
                          session.state == S6SessionStateOffline ? L(@"Offline") :
                          session.state == S6SessionStateConnecting ? L(@"Connecting…") : @"";
    if (session.state == S6SessionStateReady && user.length && ![user isEqualToString:self.loadedFor]) {
        self.loadedFor = user;
        [self reloadPlaylists];
        [self loadProfile];
    }
    if (session.state == S6SessionStateLoggedOut) {
        self.loadedFor = nil;
        self.playlists = [NSArray array];
        [self.table reloadData];
    }
}

- (void)loadProfile
{
    __unsafe_unretained S6SidebarViewController *weakSelf = self;
    [S6Catalog profile:^(NSString *name, NSString *imageURL) {
        if (name.length) weakSelf.nameLabel.text = [S6Utils displayText:name];
        if (imageURL) [weakSelf.avatar setImageURL:imageURL placeholder:[[S6Theme shared] artistPlaceholderWithSize:34]];
    }];
}

- (void)reloadPlaylists
{
    if (![S6Settings hasAccount]) return;
    NSUInteger generation = ++self.playlistsGeneration;
    [self loadPlaylistsFrom:0 into:[NSMutableArray array] generation:generation];
}

// (the first 200 are plenty for a sidebar; the Playlists screen has them all)
- (void)loadPlaylistsFrom:(NSInteger)offset into:(NSMutableArray *)list generation:(NSUInteger)generation
{
    __unsafe_unretained S6SidebarViewController *weakSelf = self;
    [S6Catalog library:@"Playlists" offset:offset limit:50 completion:^(NSArray *items, NSInteger total, NSError *error) {
        S6SidebarViewController *me = weakSelf;
        if (!me || generation != me.playlistsGeneration || error) return;
        for (id item in items) if ([item isKindOfClass:[S6Playlist class]]) [list addObject:item];
        me.playlists = [list copy];
        [me.table reloadData];
        NSInteger next = offset + (NSInteger)items.count;
        if (items.count && next < MIN(total, 200)) [me loadPlaylistsFrom:next into:list generation:generation];
    }];
}

#pragma mark - Selection

- (void)selectSection:(S6Section)section
{
    self.selected = section;
    self.selectedPlaylist = nil;
    [self.table reloadData];
}

- (void)selectPlaylist:(NSString *)playlistId
{
    self.selected = (S6Section)-1;
    self.selectedPlaylist = playlistId;
    [self.table reloadData];
}

- (void)openSettings
{
    if (self.onSection) self.onSection(S6SectionSettings);
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return S6SideSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == S6SideMain) return (NSInteger)self.mainRows.count;
    if (section == S6SideLibrary) return (NSInteger)self.libraryRows.count;
    return (NSInteger)self.playlists.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == S6SideMain) return 4;
    if (section == S6SidePlaylists && !self.playlists.count) return 0;
    return 34;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 34)];
    v.backgroundColor = [[S6Theme shared] panelColor];
    if (section == S6SideMain) return v;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, 12, v.bounds.size.width - 28, 18)];
    l.text = [section == S6SideLibrary ? L(@"Your Library") : L(@"Playlists") uppercaseString];
    l.font = [[S6Theme shared] sectionFont];
    l.textColor = [[S6Theme shared] tertiaryTextColor];
    l.backgroundColor = [UIColor clearColor];
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
    l.shadowOffset = CGSizeMake(0, -1);
    [v addSubview:l];
    return v;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6SidebarCell *cell = [tableView dequeueReusableCellWithIdentifier:@"side"] ?: [[S6SidebarCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"side"];
    S6Theme *theme = [S6Theme shared];
    BOOL current;
    S6Icon icon;
    if (indexPath.section == S6SidePlaylists) {
        S6Playlist *p = self.playlists[(NSUInteger)indexPath.row];
        cell.label.text = [S6Utils displayText:p.name];
        icon = S6IconPlaylist;
        current = [p.playlistId isEqualToString:self.selectedPlaylist];
    } else {
        NSDictionary *row = (indexPath.section == S6SideMain ? self.mainRows : self.libraryRows)[(NSUInteger)indexPath.row];
        cell.label.text = [row objectForKey:@"title"];
        icon = (S6Icon)[[row objectForKey:@"icon"] integerValue];
        current = !self.selectedPlaylist && [[row objectForKey:@"section"] integerValue] == self.selected;
    }
    cell.current = current;
    cell.icon.image = [theme icon:icon size:20 color:current ? [theme accentColor] : [theme secondaryTextColor]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == S6SidePlaylists) {
        if (self.onPlaylist) self.onPlaylist(self.playlists[(NSUInteger)indexPath.row]);
        return;
    }
    NSDictionary *row = (indexPath.section == S6SideMain ? self.mainRows : self.libraryRows)[(NSUInteger)indexPath.row];
    if (self.onSection) self.onSection((S6Section)[[row objectForKey:@"section"] integerValue]);
}

@end
