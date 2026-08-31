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
#import <QuartzCore/QuartzCore.h>

@interface LTSearchViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate,
                                       UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *segControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *results;
@property (nonatomic, copy) NSString *currentQuery;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong) LTTrack *pendingTrack;
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
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.view.backgroundColor = [UIColor whiteColor];

    CGRect bounds = self.view.bounds;
    CGFloat tableY = 0;

    if (![self isPlaylistsMode]) {
        self.title = @"Search";
        self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, 44)];
        self.searchBar.placeholder = @"Search YouTube Music";
        self.searchBar.delegate = self;
        self.searchBar.showsCancelButton = YES;
        self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
        self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [self.view addSubview:self.searchBar];

        NSArray *types = @[@"songs", @"albums", @"artists"];
        NSUInteger defaultIndex = [types indexOfObject:self.type];
        if (defaultIndex == NSNotFound) defaultIndex = 0;
        self.segControl = [[UISegmentedControl alloc] initWithItems:@[@"Songs", @"Albums", @"Artists"]];
        self.segControl.selectedSegmentIndex = (NSInteger)defaultIndex;
        [self.segControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        self.segControl.frame = CGRectMake(8, 50, bounds.size.width - 16, 32);
        [self.view addSubview:self.segControl];

        tableY = 88;
    } else {
        self.title = @"Playlists";
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, tableY, bounds.size.width, bounds.size.height - tableY)
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

- (BOOL)isPlaylistsMode {
    return [self.type isEqualToString:@"playlists"];
}

- (NSString *)currentType {
    return self.type;
}

#pragma mark - Segmented control

- (void)segmentChanged:(id)sender {
    NSArray *types = @[@"songs", @"albums", @"artists"];
    NSInteger idx = self.segControl.selectedSegmentIndex;
    if (idx < 0 || idx >= (NSInteger)types.count) return;
    NSString *newType = [types objectAtIndex:(NSUInteger)idx];
    if ([newType isEqualToString:self.type]) return;
    self.type = newType;
    self.currentQuery = nil;
    [self.results removeAllObjects];
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
    __weak LTSearchViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] searchWithQuery:query type:type completion:^(NSArray *items, NSError *error) {
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
    }];
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
    [UIView animateWithDuration:1.4 delay:1.0 options:UIViewAnimationOptionCurveEaseIn
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
    [LTPlaylistPicker presentFromViewController:self
                                     panelTitle:track.title
                                      onPicked:^(LTLocalPlaylist *playlist) {
        [[LTPlaylistStore sharedStore] addTrack:self.pendingTrack toPlaylist:playlist];
        [self showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
        self.pendingTrack = nil;
    } onCreateNew:^(NSString *name) {
        LTLocalPlaylist *playlist = [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
        if (playlist && self.pendingTrack) {
            [[LTPlaylistStore sharedStore] addTrack:self.pendingTrack toPlaylist:playlist];
            [self showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
        }
        self.pendingTrack = nil;
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
                    __weak LTSearchViewController *weakSelf = self;
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
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.showingHistory) {
        NSUInteger count = [[[LTPlaylistStore sharedStore] searchHistory] count];
        return count ? (NSInteger)count + 1 : 0;
    }
    return (NSInteger)self.results.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.showingHistory) return 44.0f;
    return 60.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.showingHistory) {
        static NSString *HistoryCellId = @"LTHistoryCell";
        NSArray *history = [[LTPlaylistStore sharedStore] searchHistory];
        NSInteger clearRow = (NSInteger)history.count;
        if (indexPath.row == clearRow) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:HistoryCellId];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:HistoryCellId];
            }
            cell.textLabel.text = @"Clear Search History";
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIColor grayColor];
            cell.textLabel.font = [UIFont systemFontOfSize:14];
            cell.imageView.image = nil;
            cell.accessoryView = nil;
            return cell;
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:HistoryCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:HistoryCellId];
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.textLabel.textColor = [UIColor blackColor];
        }
        cell.textLabel.textAlignment = NSTextAlignmentLeft;
        cell.textLabel.text = [history objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.textColor = [UIColor blackColor];
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
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    id item = [self.results objectAtIndex:(NSUInteger)indexPath.row];
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
            plus.tag = (NSInteger)indexPath.row;
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
        if (playlist.coverPath.length) {
            cell.imageView.image = [UIImage imageWithContentsOfFile:playlist.coverPath];
        } else if (playlist.tracks.count) {
            LTTrack *first = [playlist.tracks objectAtIndex:0];
            if (first.thumbnailURL.length) {
                NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
                cell.imageView.image = nil;
                __weak UITableViewCell *weakCell = cell;
                [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                    if (image) weakCell.imageView.image = image;
                }];
            }
        }
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
    self.ignorePlaylistChanges = YES;
    [[LTPlaylistStore sharedStore] deletePlaylist:playlist];
    [self.results removeObject:playlist];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    self.ignorePlaylistChanges = NO;
    [self refreshEmptyState];
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
        if (indexPath.row >= (NSInteger)history.count) {
            [[LTPlaylistStore sharedStore] clearSearchHistory];
            [self showSearchHistory];
            return;
        }
        self.searchBar.text = [history objectAtIndex:(NSUInteger)indexPath.row];
        [self performSearch];
        return;
    }
    id item = [self.results objectAtIndex:(NSUInteger)indexPath.row];
    if ([item isKindOfClass:[LTTrack class]]) {
        NSArray *tracks = [self tracksFromResults];
        NSInteger index = 0;
        for (NSUInteger i = 0; i < tracks.count; i++) {
            if ([[tracks objectAtIndex:i] isEqual:item]) { index = (NSInteger)i; break; }
        }
        [[LTPlayerController sharedController] playQueue:tracks atIndex:index];
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
    [self showSongOptionsAtIndex:(NSInteger)indexPath.row];
}

- (void)songPlusTapped:(UIButton *)button {
    [self showSongOptionsAtIndex:(NSInteger)button.tag];
}

- (void)showSongOptionsAtIndex:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.results.count) return;
    id item = [self.results objectAtIndex:(NSUInteger)row];
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

@end
