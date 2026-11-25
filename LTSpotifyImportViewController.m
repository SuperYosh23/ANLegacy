#import "LTSpotifyImportViewController.h"
#import "S6JSON.h"
#import "LTPlaylistStore.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTTheme.h"
#import "LTLog.h"
#import "S6Catalog.h"
#import "S6Models.h"
#import "S6Session.h"
#import <objc/runtime.h>

static NSString *const kDeviceClientID = @"65b708073fc0480ea92a077233ca87bd";
static NSString *const kDeviceScope = @"streaming user-read-private user-read-email user-library-read user-library-modify playlist-read-private playlist-read-collaborative playlist-modify-private playlist-modify-public user-read-recently-played user-top-read";
static NSString *const kSpotifyTokenKey = @"LTSpotifyAccessToken";
static NSString *const kSpotifyRefreshKey = @"LTSpotifyRefreshToken";

@interface LTSpotifyImportViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *playlists;
@property (nonatomic, strong) NSMutableData *responseData;
@property (nonatomic, assign) NSInteger responseStatus;
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *startBtn;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL loginUIShown;
@property (nonatomic, assign) NSUInteger runId;
@property (nonatomic, strong) NSDictionary *deviceInfo;
@property (nonatomic, strong) LTLocalPlaylist *importPlaylist;
@property (nonatomic, strong) NSMutableArray *spotifyTrackQueue;
@property (nonatomic, assign) NSInteger spotifyTrackIndex;
@property (nonatomic, assign) BOOL isImporting;
@property (nonatomic, strong) NSMutableArray *choiceTracks;
@property (nonatomic, copy) void (^trackChosenBlock)(LTTrack *chosen);
@end

@implementation LTSpotifyImportViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Import from Spotify";
    self.view.backgroundColor = [LTTheme background];
    self.playlists = [NSMutableArray array];
    self.spotifyTrackQueue = [NSMutableArray array];
    self.accessToken = nil;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStyleDone target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = close;

    if (self.accessToken.length) {
        UIBarButtonItem *logout = [[UIBarButtonItem alloc] initWithTitle:@"Log out" style:UIBarButtonItemStylePlain target:self action:@selector(logoutTapped)];
        self.navigationItem.leftBarButtonItem = logout;
        [self fetchPlaylists];
    } else {
        [self showDeviceLoginUI];
    }
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)logoutTapped {
    self.accessToken = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSpotifyTokenKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSpotifyRefreshKey];
    self.playlists = [NSMutableArray array];
    [self.tableView reloadData];
    for (UIView *v in self.view.subviews) {
        if (v != self.tableView && v != self.spinner) [v removeFromSuperview];
    }
    self.tableView.hidden = YES;
    [self showDeviceLoginUI];
}

- (void)showDeviceLoginUI {
    // Remove any previous login UI views
    for (UIView *v in [self.view.subviews copy]) {
        if (v != self.tableView && v != self.spinner) [v removeFromSuperview];
    }
    self.tableView.hidden = YES;
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80.0f;

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 40)];
    hint.text = @"On your phone or computer open";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.font = [UIFont systemFontOfSize:14];
    hint.textColor = [LTTheme secondaryText];
    [self.view addSubview:hint];
    y += 36;

    UILabel *url = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 26)];
    url.text = @"spotify.com/pair";
    url.font = [UIFont boldSystemFontOfSize:20];
    url.textColor = [LTTheme accent];
    url.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:url];
    y += 34;

    self.codeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 52)];
    self.codeLabel.text = @"…";
    self.codeLabel.font = [UIFont fontWithName:@"Courier-Bold" size:38];
    self.codeLabel.textColor = [LTTheme text];
    self.codeLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.codeLabel];
    y += 60;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 40)];
    self.statusLabel.text = @"Tap below to get a code";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [LTTheme secondaryText];
    [self.view addSubview:self.statusLabel];
    y += 48;

    self.startBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.startBtn.frame = CGRectMake(40, y, w - 80, 44);
    [self.startBtn setTitle:@"Get Code" forState:UIControlStateNormal];
    [self.startBtn addTarget:self action:@selector(startPairing) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startBtn];
}

- (void)startPairing {
    self.cancelled = NO;
    self.runId++;
    NSUInteger run = self.runId;
    self.codeLabel.text = @"…";
    self.statusLabel.text = @"Requesting code from Spotify …";
    self.startBtn.hidden = YES;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        int st = 0;
        NSDictionary *j = [self formPost:@"/oauth2/device/authorize"
                                    body:[NSString stringWithFormat:@"client_id=%@&scope=%@", kDeviceClientID, kDeviceScope]
                                  status:&st];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (run != self.runId || self.cancelled) return;
            if (![[j objectForKey:@"device_code"] length] || ![[j objectForKey:@"user_code"] length]) {
                self.startBtn.hidden = NO;
                self.statusLabel.text = [NSString stringWithFormat:@"❌ %@", [j objectForKey:@"error_description"] ?: (st ? [NSString stringWithFormat:@"HTTP %d", st] : @"No connection to Spotify")];
                return;
            }
            self.deviceInfo = j;
            self.codeLabel.text = [j objectForKey:@"user_code"];
            self.statusLabel.text = @"Waiting for confirmation …";
            [UIApplication sharedApplication].idleTimerDisabled = YES;
            [self pollDevice:run];
        });
    });
}

- (void)pollDevice:(NSUInteger)run {
    NSDictionary *info = self.deviceInfo;
    NSString *code = [info objectForKey:@"device_code"];
    __block double interval = MAX([[info objectForKey:@"interval"] doubleValue], 2.0);
    double deadline = [NSDate timeIntervalSinceReferenceDate] + MAX([[info objectForKey:@"expires_in"] doubleValue], 60.0);

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *token = nil, *err = nil;
        while (!token && !err) {
            [NSThread sleepForTimeInterval:interval];
            if (self.cancelled || run != self.runId) { err = @"cancelled"; break; }
            if ([NSDate timeIntervalSinceReferenceDate] > deadline) { err = @"Code expired – please start again"; break; }
            int st = 0;
            NSDictionary *j = [self formPost:@"/api/token"
                                        body:[NSString stringWithFormat:@"grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant-type%%3Adevice_code&device_code=%@&client_id=%@", code, kDeviceClientID]
                                      status:&st];
            NSString *at = [j objectForKey:@"access_token"];
            NSString *e = [j objectForKey:@"error"];
            if (at.length) {
                token = at;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (run != self.runId || self.cancelled) return;
                    [UIApplication sharedApplication].idleTimerDisabled = NO;
                    self.accessToken = token;
                    self.statusLabel.text = @"Logging in to Spotify …";
                    NSData *td = [token dataUsingEncoding:NSUTF8StringEncoding];
                    [[S6Session shared] loginWithUsername:nil authType:3 authData:td];
                    // Wait for session ready
                    [self waitForSessionReady];
                });
            } else if ([e isEqualToString:@"authorization_pending"]) {
                continue;
            } else if ([e isEqualToString:@"slow_down"]) {
                interval += 5;
            } else if ([e isEqualToString:@"access_denied"]) {
                err = @"Login was declined on the other device";
            } else if ([e isEqualToString:@"expired_token"]) {
                err = @"Code expired – please start again";
            } else {
                err = [j objectForKey:@"error_description"] ?: [NSString stringWithFormat:@"HTTP %d", st];
            }
        }
        if (err && ![err isEqualToString:@"cancelled"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (run != self.runId) return;
                [UIApplication sharedApplication].idleTimerDisabled = NO;
                self.startBtn.hidden = NO;
                self.statusLabel.text = [NSString stringWithFormat:@"❌ %@", err];
            });
        }
    });
}

- (NSDictionary *)formPost:(NSString *)path body:(NSString *)body status:(int *)status {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://accounts.spotify.com%@", path]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    NSHTTPURLResponse *resp = nil;
    NSError *err = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
    if (status) *status = (int)[resp statusCode];
    if (!data) return nil;
    return [S6JSON objectWithData:data error:nil];
}

#pragma mark - Fetch playlists (Web API)

- (void)waitForSessionReady {
    // Observe session state
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionStateChanged:) name:S6SessionStateDidChangeNotification object:nil];
    // Also poll
    [self checkSessionState];
}

- (void)sessionStateChanged:(NSNotification *)n {
    [self checkSessionState];
}

- (void)checkSessionState {
    S6Session *s = [S6Session shared];
    if (s.state == S6SessionStateReady) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:S6SessionStateDidChangeNotification object:nil];
        self.statusLabel.text = @"Loading playlists …";
        [self fetchPlaylists];
    } else if (s.state == S6SessionStateFailed) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:S6SessionStateDidChangeNotification object:nil];
        self.statusLabel.text = [NSString stringWithFormat:@"Login failed: %@", s.lastError.localizedDescription];
        self.startBtn.hidden = NO;
    }
}

- (void)fetchPlaylists {
    [self.spinner startAnimating];
    self.tableView.hidden = NO;
    for (UIView *v in self.view.subviews) {
        if (v != self.tableView && v != self.spinner) v.hidden = YES;
    }
    LTLog(@"SPOTIFY session state=%d premium=%d host=%@", (int)[S6Session shared].state, [S6Session shared].premium, [S6Session shared].spclientHost);
    [S6Catalog library:@"Playlists" offset:0 limit:200 completion:^(NSArray *items, NSInteger total, NSError *error) {
        LTLog(@"SPOTIFY library Playlists count=%d total=%d error=%@", (int)items.count, (int)total, error.localizedDescription);
        [self.spinner stopAnimating];
        if (error) {
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Spotify Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [a show];
            return;
        }
        [self.playlists removeAllObjects];
        for (id p in items) {
            if ([p isKindOfClass:[S6Playlist class]]) [self.playlists addObject:p];
        }
        [self.tableView reloadData];
        if (self.playlists.count == 0) {
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Empty" message:@"No playlists found." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [a show];
        }
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.playlists.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"SpotifyPlaylistCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
    cell.backgroundColor = [LTTheme cellBackground];
    cell.textLabel.textColor = [LTTheme text];
    cell.detailTextLabel.textColor = [LTTheme secondaryText];
    id p = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    if ([p isKindOfClass:[S6Playlist class]]) {
        cell.textLabel.text = [(S6Playlist *)p name] ?: @"Playlist";
        int t = (int)[(S6Playlist *)p totalTracks];
        cell.detailTextLabel.text = t > 0 ? [NSString stringWithFormat:@"%d tracks", t] : @"Playlist";
    } else if ([p isKindOfClass:[NSDictionary class]]) {
        cell.textLabel.text = [(NSDictionary *)p objectForKey:@"name"] ?: @"Playlist";
        NSDictionary *tracks = [(NSDictionary *)p objectForKey:@"tracks"];
        int t = [[tracks objectForKey:@"total"] intValue];
        cell.detailTextLabel.text = t > 0 ? [NSString stringWithFormat:@"%d tracks", t] : @"Playlist";
    } else {
        cell.textLabel.text = @"Playlist";
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isImporting) return;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    S6Playlist *p = [self.playlists objectAtIndex:(NSUInteger)indexPath.row];
    [self importPlaylist:p];
}

#pragma mark - Import

- (void)importPlaylist:(id)playlist {
    S6Playlist *sp = nil;
    if ([playlist isKindOfClass:[S6Playlist class]]) sp = (S6Playlist *)playlist;
    if (!sp || !sp.uri.length) return;
    self.isImporting = YES;
    [self.spinner startAnimating];
    LTLocalPlaylist *local = [[LTPlaylistStore sharedStore] createPlaylistWithName:sp.name ?: @"Spotify Playlist"];
    if (!local) { [self.spinner stopAnimating]; self.isImporting = NO; return; }
    self.importPlaylist = local;
    self.spotifyTrackQueue = [NSMutableArray array];
    self.spotifyTrackIndex = 0;

    [S6Catalog playlist:sp.uri offset:0 limit:5000 completion:^(S6Playlist *pl, NSArray *tracks, NSInteger total, NSError *error) {
        LTLog(@"SPOTIFY playlist fetch uri=%@ tracks=%d error=%@", sp.uri, (int)tracks.count, error.localizedDescription);
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                self.isImporting = NO;
                UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Spotify Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                [a show];
            });
            return;
        }
        for (S6Track *t in tracks) {
            if (![t isKindOfClass:[S6Track class]]) continue;
            if (t.isEpisode) continue;
            NSString *title = t.name;
            NSString *artist = t.artists.count ? [(S6Artist *)[t.artists objectAtIndex:0] name] : nil;
            if (title.length) [self.spotifyTrackQueue addObject:@{@"title": title, @"artist": artist ?: @"", @"duration": @(t.durationMs)}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self processNextSpotifyTrack];
        });
    }];
}

- (void)processNextSpotifyTrack {
    if (self.spotifyTrackIndex >= (NSInteger)self.spotifyTrackQueue.count) {
        [self.spinner stopAnimating];
        self.isImporting = NO;
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Import Complete" message:[NSString stringWithFormat:@"Imported %d tracks.", (int)self.importPlaylist.tracks.count] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [a show];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"LTLibraryReloadNeeded" object:nil];
        [self.tableView reloadData];
        self.tableView.hidden = NO;
        return;
    }
    NSDictionary *info = [self.spotifyTrackQueue objectAtIndex:(NSUInteger)self.spotifyTrackIndex];
    NSString *title = [info objectForKey:@"title"];
    NSString *artist = [info objectForKey:@"artist"];
    NSString *query = artist.length ? [NSString stringWithFormat:@"%@ %@", artist, title] : title;
    [[LTYouTubeClient sharedClient] searchVideosWithQuery:query completion:^(NSArray *tracks, NSError *error) {
        NSString *spTitle = [[info objectForKey:@"title"] lowercaseString] ?: @"";
        NSString *spArtist = [[info objectForKey:@"artist"] lowercaseString] ?: @"";
        LTTrack *best = nil;
        NSMutableArray *candidates = [NSMutableArray array];
        // Pick best match (title contains spTitle, uploader contains spArtist, prefer Topic)
        for (LTTrack *t in tracks) {
            if (!t.videoId.length || !t.title.length) continue;
            NSString *tTitleL = [t.title lowercaseString] ?: @"";
            NSString *tArtistL = [t.artist lowercaseString] ?: @"";
            BOOL titleContains = [tTitleL rangeOfString:spTitle].location != NSNotFound;
            BOOL uploaderContains = [tArtistL rangeOfString:spArtist].location != NSNotFound;
            BOOL isTopic = [tArtistL rangeOfString:@"topic"].location != NSNotFound || [tArtistL rangeOfString:@"official audio"].location != NSNotFound;
            if (titleContains && uploaderContains) {
                if (!best || isTopic) best = t;
            }
            // Keep top 8 results for user pick regardless
            if (candidates.count < 8) [candidates addObject:t];
        }
        if (best) {
            [[LTPlaylistStore sharedStore] addTrack:best toPlaylist:self.importPlaylist];
            self.spotifyTrackIndex++;
            [self processNextSpotifyTrack];
            return;
        }
        if (candidates.count) {
            self.choiceTracks = candidates;
            __unsafe_unretained typeof(self) weakSelf = self;
            self.trackChosenBlock = ^(LTTrack *chosen) {
                if (chosen && chosen.videoId.length) {
                    [[LTPlaylistStore sharedStore] addTrack:chosen toPlaylist:weakSelf.importPlaylist];
                }
                weakSelf.spotifyTrackIndex++;
                [weakSelf processNextSpotifyTrack];
            };
            [self showTrackChoiceAlert];
            return;
        }
        self.spotifyTrackIndex++;
        [self processNextSpotifyTrack];
    }];
}

- (void)showTrackChoiceAlert {
    NSUInteger limit = self.choiceTracks.count > 8 ? 8 : self.choiceTracks.count;
    NSMutableArray *btnTitles = [NSMutableArray array];
    for (NSUInteger i = 0; i < limit; i++) {
        LTTrack *t = [self.choiceTracks objectAtIndex:(NSUInteger)i];
        [btnTitles addObject:t.title ?: @"Unknown"];
    }
    [btnTitles addObject:@"Skip"];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Choose the right track" message:@"Exact title + uploader didn't match any result. Pick the correct one." delegate:self cancelButtonTitle:nil otherButtonTitles:nil];
    alert.tag = 800;
    for (NSString *btn in btnTitles) {
        [alert addButtonWithTitle:btn];
    }
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 800) {
        NSUInteger skipIndex = self.choiceTracks.count > 8 ? 8 : self.choiceTracks.count;
        if (buttonIndex == (NSInteger)skipIndex) {
            if (self.trackChosenBlock) self.trackChosenBlock(nil);
            return;
        }
        if (buttonIndex >= 0 && buttonIndex < (NSInteger)self.choiceTracks.count) {
            LTTrack *t = [self.choiceTracks objectAtIndex:(NSUInteger)buttonIndex];
            if (self.trackChosenBlock) self.trackChosenBlock(t);
            return;
        }
        if (self.trackChosenBlock) self.trackChosenBlock(nil);
    }
}

@end