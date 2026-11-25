#import "LTPeekCoordinator.h"
#import "LTTraitCompat.h"
#import "LTPlaylistPeekViewController.h"
#import "LTArtworkPeekViewController.h"
#import "LTSearchViewController.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTMediaCell.h"
#import "LTTrackListViewController.h"
#import "LTArtistViewController.h"
#import "LTTabBarController.h"
#import "LTPlayerController.h"
#import "LTPlaylistStore.h"
#import "LTPlaylistPicker.h"
#import "LTLocalPlaylistDetailViewController.h"
#import "LTSpinnerView.h"
#import "LTGraphics.h"
#import "LTSimpleCell.h"
#import "LTTheme.h"
#import "LTCardControls.h"
#import "LTLog.h"
#import <QuartzCore/QuartzCore.h>
#import "LTThemedTableView.h"
#import "LTTransitionSettings.h"

@interface LTSearchViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate,
                                       UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *segControl;
@property (nonatomic, strong) LTPeekCoordinator *peekCoordinator;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *results;
@property (nonatomic, strong) NSArray *localResults;
@property (nonatomic, copy) NSString *currentQuery;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) LTTrack *pendingTrack;
// Rows awaiting an avatar-upgrade reload, coalesced onto one table update.
@property (nonatomic, strong) NSMutableArray *pendingAvatarReloads;
@property (nonatomic, assign) BOOL avatarReloadScheduled;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL ignorePlaylistChanges;
@property (nonatomic, assign) BOOL showingHistory;
@end

@implementation LTSearchViewController

- (id)init {
    return [self initWithType:@"songs"];
}

- (id)initWithType:(NSString *)type {
    self = [super init];
    if (self) {
        _type = [type copy] ?: @"songs";
        _results = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.view.backgroundColor = [LTTheme background];

    CGRect bounds = self.view.bounds;
    CGFloat tableY = 0;

    if (![self isPlaylistsMode]) {
        self.title = @"Search";
        self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, 44)];
        self.searchBar.placeholder = [self searchPlaceholderForType:self.type];
        self.searchBar.delegate = self;
        self.searchBar.showsCancelButton = YES;
        self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
        self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [self.view addSubview:self.searchBar];

        NSArray *types = @[@"songs", @"videos", @"albums", @"artists"];
        NSUInteger defaultIndex = [types indexOfObject:self.type];
        if (defaultIndex == NSNotFound) defaultIndex = 0;
        // The modern theme draws its own segmented control; the native one is
        // exactly right in the native theme.
        NSArray *segments = @[@"Songs", @"Videos", @"Albums", @"Artists"];
        self.segControl = [LTTheme isModern]
            ? (UISegmentedControl *)[[LTCardSegmented alloc] initWithItems:segments]
            : [[LTCompactSegmentedControl alloc] initWithItems:segments];
        self.segControl.selectedSegmentIndex = (NSInteger)defaultIndex;
        [self.segControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        self.segControl.frame = CGRectMake(8, 50, bounds.size.width - 16, 32);
        self.segControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [self.view addSubview:self.segControl];
        // -viewDidLayoutSubviews is iOS 5+. On iOS 4 it never runs, so the
        // compact style and font have to be applied here as well.
        [self lt_applySegmentedFont];

        tableY = 88;
    } else {
        self.title = @"Playlists";
    }

    self.tableView = [[LTThemedTableView alloc] initWithFrame:CGRectMake(0, tableY, bounds.size.width, bounds.size.height - tableY)
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme background];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 120, bounds.size.width - 48, 60)];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textColor = [LTTheme secondaryText];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];
    // 3D Touch peek on playlist rows; a no-op below iOS 9.
    __unsafe_unretained LTSearchViewController *peekSelf = self;
    self.peekCoordinator = [[LTPeekCoordinator alloc] initWithOwner:self
                                                      sourceView:self.tableView
                                                   peekProvider:^UIViewController *(CGPoint point) {
        return [peekSelf peekViewControllerAtPoint:point];
    } commit:^(UIViewController *peek) {
        [peekSelf handlePeekCommit:peek];
    }];
    [self.peekCoordinator registerPreview];
}

// Kept in one place so iOS 4 (which never sends -viewDidLayoutSubviews) and
// rotation both get the same compact style and font as iOS 5+.
- (void)lt_applySegmentedFont {
    if (!self.segControl) return;
    CGFloat width = self.view.bounds.size.width;
    if (width < 1.0f) return;
    UIFont *font = (width < 360.0f) ? [UIFont boldSystemFontOfSize:9]
                                    : [UIFont boldSystemFontOfSize:11];
    [LTTheme setTitleFont:font forSegmentedControl:self.segControl];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self lt_applySegmentedFont];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width;
    if (width < 1.0f) return;

    BOOL searchMode = ![self isPlaylistsMode];
    if (searchMode) {
        [self lt_applySegmentedFont];
        self.segControl.frame = CGRectMake(8, 50, width - 16, 32);
        self.searchBar.frame = CGRectMake(0, 0, width, 44);
    }

    CGFloat tableY = searchMode ? 88.0f : 46.0f;
    self.tableView.frame = CGRectMake(0, tableY, width, bounds.size.height - tableY);
    self.emptyLabel.frame = CGRectMake(24, tableY + 80, width - 48, 120);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playlistsDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadProgress:)
                                                 name:LTPlaylistDownloadProgressNotification
                                               object:nil];
    if ([self isPlaylistsMode]) {
        [self showLocalPlaylists];
    } else if (self.currentQuery.length && !self.results.count && !self.loading) {
        [self performSearch];
    } else if (!self.currentQuery.length && !self.showingHistory) {
        [self showSearchHistory];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme background];
    self.tableView.backgroundColor = [LTTheme background];
    self.emptyLabel.textColor = [LTTheme secondaryText];
    [self.tableView reloadData];
}

- (BOOL)isPlaylistsMode {
    return [self.type isEqualToString:@"playlists"];
}

- (NSString *)currentType {
    return self.type;
}

- (NSString *)searchPlaceholderForType:(NSString *)type {
    if ([type isEqualToString:@"videos"]) return @"Search YouTube";
    return @"Search YouTube Music";
}

- (BOOL)hasLocalSection {
    return (![self isPlaylistsMode] && !self.showingHistory && self.currentQuery.length);
}

- (NSArray *)libraryTracksMatchingQuery:(NSString *)query {
    if (!query.length) return nil;
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) return nil;
    NSMutableArray *matches = [NSMutableArray array];
    for (LTTrack *track in [[LTPlaylistStore sharedStore] libraryTracks]) {
        NSString *title = track.title.length ? track.title : @"";
        NSString *artist = track.artist.length ? track.artist : @"";
        if ([title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [artist rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [matches addObject:track];
        }
    }
    return matches;
}

- (id)itemAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasLocalSection] && indexPath.section == 0) {
        if (indexPath.row >= (NSInteger)self.localResults.count) return nil;
        return [self.localResults objectAtIndex:(NSUInteger)indexPath.row];
    }
    return [self.results objectAtIndex:(NSUInteger)indexPath.row];
}

#pragma mark - Segmented control

- (void)segmentChanged:(id)sender {
    NSArray *types = @[@"songs", @"videos", @"albums", @"artists"];
    NSInteger idx = self.segControl.selectedSegmentIndex;
    if (idx < 0 || idx >= (NSInteger)types.count) return;
    NSString *newType = [types objectAtIndex:(NSUInteger)idx];
    if ([newType isEqualToString:self.type]) return;
    self.type = newType;
    self.searchBar.placeholder = [self searchPlaceholderForType:newType];
    self.currentQuery = nil;
    [self.results removeAllObjects];
    self.localResults = nil;
    [self.tableView reloadData];
    self.emptyLabel.hidden = YES;
    NSString *query = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length) {
        [self performSearch];
    } else {
        [self showSearchHistory];
    }
}

#pragma mark - Actions

- (void)showLocalPlaylists {
    [self.results removeAllObjects];
    NSArray *playlists = [[LTPlaylistStore sharedStore] playlists];
    [self.results addObjectsFromArray:playlists];
    [self.tableView reloadData];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                           target:self
                                                                                           action:@selector(newPlaylistTapped:)];
    if (!playlists.count) {
        self.emptyLabel.text = @"No playlists yet.\nTap + to create one.";
        self.emptyLabel.hidden = NO;
    } else {
        self.emptyLabel.hidden = YES;
    }
}

- (void)newPlaylistTapped:(id)sender {
    [self promptForPlaylistNameWithTrack:nil];
}

- (void)showSearchHistory {
    self.showingHistory = YES;
    [self.results removeAllObjects];
    self.localResults = nil;
    [self.tableView reloadData];
    NSArray *history = [[LTPlaylistStore sharedStore] searchHistory];
    if (!history.count) {
        self.emptyLabel.text = @"No search history yet.\nSearch YouTube above to get started.";
        self.emptyLabel.hidden = NO;
    } else {
        self.emptyLabel.hidden = YES;
    }
}

- (void)performSearch {
    if ([self isPlaylistsMode]) {
        [self showLocalPlaylists];
        return;
    }
    [self.searchBar resignFirstResponder];
    NSString *query = self.searchBar.text;
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) {
        [self showSearchHistory];
        return;
    }
    self.showingHistory = NO;
    self.currentQuery = query;
    [[LTPlaylistStore sharedStore] recordSearchTerm:query];
    self.loading = YES;
    [self showSpinner:YES];

    NSString *type = [self currentType];
    if ([type isEqualToString:@"songs"]) {
        self.localResults = [self libraryTracksMatchingQuery:query];
    } else {
        self.localResults = nil;
    }
    LTLog(@"SEARCH query=%@ type=%@ downloaded=%d local=%d showHist=%d",
          query, type, (int)[[[LTPlaylistStore sharedStore] libraryTracks] count],
          (int)self.localResults.count, (int)self.showingHistory);
    [self.tableView reloadData];

    __unsafe_unretained LTSearchViewController *weakSelf = self;
    void (^finish)(NSArray *, NSError *) = ^(NSArray *items, NSError *error) {
        LTSearchViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loading = NO;
        [strongSelf showSpinner:NO];
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Search Failed"
                                                            message:error.localizedDescription
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
            return;
        }
        [strongSelf.results removeAllObjects];
        [strongSelf.results addObjectsFromArray:items];
        [strongSelf.tableView reloadData];
        strongSelf.emptyLabel.hidden = YES;
        if ([type isEqualToString:@"artists"]) {
            [strongSelf upgradeArtistAvatars];
        }
    };
    if ([type isEqualToString:@"videos"]) {
        [[LTYouTubeClient sharedClient] searchVideosWithQuery:query completion:finish];
    } else {
        [[LTYouTubeClient sharedClient] searchWithQuery:query type:type completion:finish];
    }
}

// Which section the remote (online) results actually live in. Whenever a query
// is running there is also a local on-device section, and those results sit in
// section 0 with the remote ones pushed down to section 1. Reloading a row in
// the wrong section throws NSInternalInconsistencyException the moment the row
// number runs past the local section's row count, which is exactly what
// searching for an artist does.
- (NSInteger)remoteResultsSection {
    if ([self isPlaylistsMode]) return 0;
    return [self hasLocalSection] ? 1 : 0;
}

// Avatar lookups all land back in the same runloop burst, and reloading rows
// while the table is still processing an earlier reload is itself a throw. Queue
// the rows and apply them once, coalesced, on the next turn of the runloop.
- (void)queueAvatarRowReloadForResultIndex:(NSUInteger)resultIndex {
    if (!self.pendingAvatarReloads) self.pendingAvatarReloads = [NSMutableArray array];

    BOOL alreadyQueued = NO;
    for (NSIndexPath *existing in self.pendingAvatarReloads) {
        if (existing.row == (NSInteger)resultIndex && existing.section == [self remoteResultsSection]) {
            alreadyQueued = YES;
            break;
        }
    }
    if (alreadyQueued) return;
    [self.pendingAvatarReloads addObject:
     [NSIndexPath indexPathForRow:(NSInteger)resultIndex inSection:[self remoteResultsSection]]];

    if (self.avatarReloadScheduled) return;
    self.avatarReloadScheduled = YES;
    __unsafe_unretained LTSearchViewController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        LTSearchViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.avatarReloadScheduled = NO;
        [strongSelf flushAvatarRowReloads];
    });
}

- (void)flushAvatarRowReloads {
    NSArray *pending = [self.pendingAvatarReloads copy];
    [self.pendingAvatarReloads removeAllObjects];
    if (!pending.count) return;

    // Ask the table how many rows it believes each section has, right now.
    // By the time this runs the query may have been replaced, or the local
    // section may have emptied, so nothing here may trust the earlier numbers.
    NSMutableArray *valid = [NSMutableArray array];
    for (NSIndexPath *path in pending) {
        if (path.section >= [self.tableView numberOfSections]) continue;
        if (path.row >= [self.tableView numberOfRowsInSection:path.section]) continue;
        [valid addObject:path];
    }
    if (!valid.count) return;
    [self.tableView reloadRowsAtIndexPaths:valid withRowAnimation:UITableViewRowAnimationNone];
}

- (void)upgradeArtistAvatars {
    for (NSUInteger i = 0; i < self.results.count; i++) {
        id item = [self.results objectAtIndex:i];
        if (![item isKindOfClass:[LTBrowseItem class]]) continue;
        LTBrowseItem *bi = item;
        if (bi.kind != LTBrowseKindArtist || !bi.browseId.length) continue;
        __unsafe_unretained LTSearchViewController *weakSelf = self;
        [[LTYouTubeClient sharedClient] channelAvatarURLForBrowseId:bi.browseId completion:^(NSString *avatarURL) {
            LTSearchViewController *strongSelf = weakSelf;
            if (!strongSelf || !avatarURL.length) return;
            NSString *square = [[LTYouTubeClient sharedClient] channelAvatarURL:avatarURL size:160];
            bi.thumbnailURL = square;
            // Only touch the table if this exact item is still at this exact
            // index; a newer search may have replaced the whole result set.
            if (i >= strongSelf.results.count) return;
            if ([strongSelf.results objectAtIndex:i] != bi) return;
            [strongSelf queueAvatarRowReloadForResultIndex:i];
        }];
    }
}

- (void)showSpinner:(BOOL)show {
    if (show) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
                                            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        spinner.hidesWhenStopped = YES;
        [spinner startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)showToast:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 220, 36)];
    label.center = CGPointMake(self.view.bounds.size.width / 2.0f, self.view.bounds.size.height - 80);
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75f];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:13];
    label.layer.cornerRadius = 6.0f;
    label.clipsToBounds = YES;
    label.text = text;
    [self.view addSubview:label];
    [LTTransitionSettings animateWithDuration:1.4 delay:1.0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ label.alpha = 0.0f; }
                     completion:^(BOOL finished) { [label removeFromSuperview]; }];
}

#pragma mark - Add to playlist / queue

- (void)showSongOptionsForTrack:(LTTrack *)track {
    self.pendingTrack = track;
    NSString *lastOption = [[LTPlaylistStore sharedStore] isTrackDownloaded:track] ? @"Remove Download" : @"Download";
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:track.title
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Add to Queue", @"Add to Playlist...", lastOption, nil];
    sheet.tag = 10;
    [sheet showInView:self.view];
}

- (void)showPlaylistPickerForTrack:(LTTrack *)track {
    __unsafe_unretained LTSearchViewController *weakSelf = self;
    [LTPlaylistPicker presentFromViewController:self
                                     panelTitle:track.title
                                      onPicked:^(LTLocalPlaylist *playlist) {
        // Captured track, not self.pendingTrack: the picker is presented
        // asynchronously and pendingTrack can be replaced while it is up.
        [LTPlaylistStore addTrack:track
                       toPlaylist:playlist
                    confirmingFrom:weakSelf
                       completion:^(BOOL added) {
            if (added) [weakSelf showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
            weakSelf.pendingTrack = nil;
        }];
    } onCreateNew:^(NSString *name) {
        LTLocalPlaylist *playlist = [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
        // A playlist that was just created is empty, so nothing can duplicate.
        if (playlist) {
            [LTPlaylistStore addTrack:track toPlaylist:playlist confirmingFrom:nil completion:nil];
            [weakSelf showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
        }
        weakSelf.pendingTrack = nil;
    }];
}

- (void)promptForPlaylistNameWithTrack:(LTTrack *)track {
    self.pendingTrack = track;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Playlist"
                                                    message:@"Enter a name for the playlist."
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Create", nil];
    alert.tag = 200;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert show];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == 10) {
        if (buttonIndex == 0) {
            [[LTPlayerController sharedController] enqueueTracks:@[self.pendingTrack]];
            [self showToast:@"Added to queue"];
            self.pendingTrack = nil;
        } else if (buttonIndex == 1) {
            [self showPlaylistPickerForTrack:self.pendingTrack];
        } else if (buttonIndex == 2) {
            LTTrack *track = self.pendingTrack;
            self.pendingTrack = nil;
            if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
                [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[track]];
                [self showToast:@"Removed download"];
            } else {
                if ([[LTPlaylistStore sharedStore] isDownloading]) {
                    [self showToast:@"A download is already in progress"];
                } else {
                    __unsafe_unretained LTSearchViewController *weakSelf = self;
                    [[LTPlaylistStore sharedStore] downloadTracks:@[track] completion:^{
                        [weakSelf showToast:@"Downloaded"];
                    }];
                }
            }
        }
    } else if (actionSheet.tag == 11) {
        // Handled by LTPlaylistPicker now.
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 200 && buttonIndex == 1) {
        NSString *name = [[alertView textFieldAtIndex:0] text];
        LTLocalPlaylist *playlist = [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
        if (playlist) {
            if (self.pendingTrack) {
                [[LTPlaylistStore sharedStore] addTrack:self.pendingTrack toPlaylist:playlist];
                [self showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
            } else {
                [self showLocalPlaylists];
                [self showToast:@"Playlist created"];
            }
        }
    }
    self.pendingTrack = nil;
}

#pragma mark - Notifications

- (void)playlistsDidChange:(NSNotification *)notification {
    if (self.ignorePlaylistChanges) return;
    if ([self isPlaylistsMode]) {
        [self showLocalPlaylists];
    }
}

- (void)downloadProgress:(NSNotification *)notification {
    [self.tableView reloadData];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self performSearch];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    searchBar.text = @"";
    self.currentQuery = nil;
    [self.results removeAllObjects];
    self.localResults = nil;
    self.emptyLabel.hidden = YES;
    [self showSearchHistory];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
    if (!searchBar.text.length && !self.currentQuery.length) {
        [self showSearchHistory];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([self isPlaylistsMode]) return 1;
    return [self hasLocalSection] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isPlaylistsMode]) return (NSInteger)self.results.count;
    if ([self hasLocalSection] && section == 0) {
        return self.localResults.count > 0 ? (NSInteger)self.localResults.count : 1;
    }
    if (self.showingHistory) {
        return (NSInteger)[[[LTPlaylistStore sharedStore] searchHistory] count];
    }
    return (NSInteger)self.results.count;
}

// The section title, drawn by us so it can be themed. UITableView draws its
// own header titles in a colour that cannot be set, which is black on every
// iOS before 13.
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title.length) return nil;
    return [LTSectionHeaderView headerWithTitle:title];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self hasLocalSection]) {
        if (section == 0) return @"From Your Library";
        if (section == 1) return @"YouTube";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self isPlaylistsMode] && [self hasLocalSection] && indexPath.section == 0) return 60.0f;
    if (self.showingHistory) return 44.0f;
    return 60.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.showingHistory) {
        static NSString *HistoryCellId = @"LTHistoryCell";
        NSArray *history = [[LTPlaylistStore sharedStore] searchHistory];
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:HistoryCellId];
        if (!cell) {
            cell = [[LTSimpleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:HistoryCellId];
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.textLabel.textColor = [LTTheme text];
        }
        cell.textLabel.textAlignment = NSTextAlignmentLeft;
        cell.textLabel.text = [history objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.textColor = [LTTheme text];
        cell.imageView.image = [LTGraphics searchIcon];
        cell.accessoryView = nil;
        return cell;
    }

    static NSString *CellId = @"LTMediaCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
    }
    if ([self hasLocalSection] && indexPath.section == 0 && !self.localResults.count) {
        cell.textLabel.text = @"No matches in your library";
        cell.textLabel.textColor = [LTTheme secondaryText];
        cell.detailTextLabel.text = @"";
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    id item = [self itemAtIndexPath:indexPath];
    if ([item isKindOfClass:[LTTrack class]]) {
        LTTrack *track = item;
        cell.textLabel.text = track.title;
        NSMutableString *detail = [NSMutableString string];
        if (track.artist.length) [detail appendString:track.artist];
        if (track.album.length) {
            if (detail.length) [detail appendString:@"  •  "];
            [detail appendString:track.album];
        }
        cell.detailTextLabel.text = detail;
        if ([[LTPlaylistStore sharedStore] isTrackDownloading:track]) {
            LTSpinnerView *spinner = [[LTSpinnerView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            UIButton *plus = [UIButton buttonWithType:UIButtonTypeContactAdd];
            NSInteger offset = ([self hasLocalSection] && indexPath.section == 0) ? 0 : 100000;
            plus.tag = offset + (NSInteger)indexPath.row;
            [plus addTarget:self action:@selector(songPlusTapped:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = plus;
        }
        [cell setImageFromURL:track.thumbnailURL];
    } else if ([item isKindOfClass:[LTBrowseItem class]]) {
        LTBrowseItem *bi = item;
        cell.textLabel.text = bi.title;
        cell.detailTextLabel.text = bi.subtitle;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [cell setImageFromURL:bi.thumbnailURL];
    } else if ([item isKindOfClass:[LTLocalPlaylist class]]) {
        LTLocalPlaylist *playlist = item;
        cell.textLabel.text = playlist.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%d tracks", (int)playlist.tracks.count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image = nil;
        [LTPlaylistStore providePlaylistArtwork:playlist toCell:cell];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isPlaylistsMode];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self isPlaylistsMode]) return UITableViewCellEditingStyleNone;
    if (indexPath.row >= (NSInteger)self.results.count) return UITableViewCellEditingStyleNone;
    id item = [self.results objectAtIndex:(NSUInteger)indexPath.row];
    return [item isKindOfClass:[LTLocalPlaylist class]] ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    id item = [self.results objectAtIndex:(NSUInteger)indexPath.row];
    if (![item isKindOfClass:[LTLocalPlaylist class]]) return;
    LTLocalPlaylist *playlist = item;
    // Let the store drive the refresh: -deletePlaylist: broadcasts the change and
    // -storeDidChange: rebuilds the model from it. Suppressing that notification
    // across the prompt, as this used to, is what left deleted rows on screen
    // until the next launch.
    __unsafe_unretained LTSearchViewController *weakSelf = self;
    [LTPlaylistStore confirmDeletePlaylist:playlist presenting:self completion:^(BOOL deleted) {
        if (!deleted) return;
        [weakSelf refreshEmptyState];
    }];
}

- (void)refreshEmptyState {
    if (![self isPlaylistsMode]) return;
    if (!self.results.count) {
        self.emptyLabel.text = @"No playlists yet.\nTap + to create one.";
        self.emptyLabel.hidden = NO;
    } else {
        self.emptyLabel.hidden = YES;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.showingHistory) {
        NSArray *history = [[LTPlaylistStore sharedStore] searchHistory];
        self.searchBar.text = [history objectAtIndex:(NSUInteger)indexPath.row];
        [self performSearch];
        return;
    }
    id item = [self itemAtIndexPath:indexPath];
    if (!item) return;
    if ([item isKindOfClass:[LTTrack class]]) {
        if ([self hasLocalSection] && indexPath.section == 0) {
            [[LTPlayerController sharedController] playQueue:self.localResults atIndex:indexPath.row];
            [LTPlayerController sharedController].queueSourceName = @"Library";
        } else {
            NSArray *tracks = [self tracksFromResults];
            NSInteger index = 0;
            for (NSUInteger i = 0; i < tracks.count; i++) {
                if ([[tracks objectAtIndex:i] isEqual:item]) { index = (NSInteger)i; break; }
            }
            [[LTPlayerController sharedController] playQueue:tracks atIndex:index];
            [LTPlayerController sharedController].queueSourceName = self.searchBar.text ?: @"Search";
        }
        [(LTTabBarController *)self.tabBarController showNowPlaying];
    } else if ([item isKindOfClass:[LTBrowseItem class]]) {
        LTBrowseItem *bi = item;
        UIViewController *detail = nil;
        switch (bi.kind) {
            case LTBrowseKindAlbum:
                detail = [[LTTrackListViewController alloc] initWithBrowseId:bi.browseId
                                                                       kind:LTBrowseKindAlbum
                                                                      title:bi.title];
                break;
            case LTBrowseKindPlaylist:
                detail = [[LTTrackListViewController alloc] initWithBrowseId:bi.browseId
                                                                       kind:LTBrowseKindPlaylist
                                                                      title:bi.title];
                break;
            case LTBrowseKindArtist:
            default:
                detail = [[LTArtistViewController alloc] initWithBrowseId:bi.browseId
                                                                   title:bi.title];
                break;
        }
        if (detail) [self.navigationController pushViewController:detail animated:YES];
    } else if ([item isKindOfClass:[LTLocalPlaylist class]]) {
        LTLocalPlaylist *playlist = item;
        LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:playlist];
        [self.navigationController pushViewController:detail animated:YES];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    [self showSongOptionsAtIndex:(NSInteger)indexPath.row section:(NSInteger)indexPath.section];
}

- (void)songPlusTapped:(UIButton *)button {
    NSInteger tag = (NSInteger)button.tag;
    NSInteger row = tag % 100000;
    NSInteger section = (tag < 100000) ? 0 : 1;
    [self showSongOptionsAtIndex:row section:section];
}

- (void)showSongOptionsAtIndex:(NSInteger)row section:(NSInteger)section {
    id item = nil;
    if ([self hasLocalSection] && section == 0) {
        if (row < 0 || row >= (NSInteger)self.localResults.count) return;
        item = [self.localResults objectAtIndex:(NSUInteger)row];
    } else {
        if (row < 0 || row >= (NSInteger)self.results.count) return;
        item = [self.results objectAtIndex:(NSUInteger)row];
    }
    if ([item isKindOfClass:[LTTrack class]]) {
        [self showSongOptionsForTrack:item];
    }
}

- (NSArray *)tracksFromResults {
    NSMutableArray *tracks = [NSMutableArray array];
    for (id item in self.results) {
        if ([item isKindOfClass:[LTTrack class]]) {
            [tracks addObject:item];
        }
    }
    return tracks;
}
#pragma mark - 3D Touch peek

// Only local playlists are peekable; browse results are pushed by tap and have
// nothing to preview, so they simply return nil.
- (LTLocalPlaylist *)peekPlaylistAtIndexPath:(NSIndexPath *)indexPath {
    if (self.showingHistory) return nil;
    id item = [self itemAtIndexPath:indexPath];
    if (![item isKindOfClass:[LTLocalPlaylist class]]) return nil;
    return (LTLocalPlaylist *)item;
}

- (void)peekCommitPlaylist:(LTLocalPlaylist *)playlist {
    if (!playlist.identifier.length) return;
    LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:playlist];
    [self.navigationController pushViewController:detail animated:YES];
}

// Results mix songs and playlists in one table, so a single preview covers
// both: playlist rows peek the playlist, song rows peek their artwork.
- (UIViewController *)peekViewControllerAtPoint:(CGPoint)point {
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:point];
    if (!indexPath) return nil;

    LTLocalPlaylist *playlist = [self peekPlaylistAtIndexPath:indexPath];
    if (playlist) return [[LTPlaylistPeekViewController alloc] initWithPlaylist:playlist];

    if (self.showingHistory) return nil;
    id item = [self itemAtIndexPath:indexPath];
    if (![item isKindOfClass:[LTTrack class]]) return nil;
    UIImage *art = [LTPeekCoordinator artworkForRowAtIndexPath:indexPath inTableView:self.tableView];
    return [[LTArtworkPeekViewController alloc] initWithTrack:(LTTrack *)item image:art];
}

- (void)handlePeekCommit:(UIViewController *)peek {
    if (![peek isKindOfClass:[LTPlaylistPeekViewController class]]) return;
    [self peekCommitPlaylist:[(LTPlaylistPeekViewController *)peek playlist]];
}
- (void)focusSearchField {
    [self.view layoutIfNeeded];
    [self.searchBar becomeFirstResponder];
}

@end
