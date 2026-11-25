#import "LTSettingsViewController.h"
#import "LTTraitCompat.h"
#import "LTSpotifyImportViewController.h"
#import "LTArtworkBackground.h"
#import "LTLog.h"
#import "LTPlaylistStore.h"
#import "LTListenBrainzScrobbler.h"
#import "LTListenBrainzAuthViewController.h"
#import "LTPlayerController.h"
#import "LTP2PSync.h"
#import "LTDownloadQueueViewController.h"
#import "LTTransitionSettings.h"
#import "LTTransitionSpeedViewController.h"
#import "LTRecentsTileSizeViewController.h"
#import "LTOneHandedMode.h"
#import "LTAppIcon.h"
#import "LTSleepTimer.h"
#import "LTLyricsSettings.h"
#import "LTLyricsOffsetViewController.h"
#import "LTTheme.h"
#import "LTCardNavBar.h"
#import "LTCardControls.h"
#import "LTThemePickerViewController.h"
#import "LTAccentPickerViewController.h"
#import "LTOneHandedModeViewController.h"
#import "LTWebExporter.h"
#import "LTPlaylistSelectViewController.h"
#import "LTHomeViewController.h"
#import "LTDebugMenuViewController.h"
#import "LTiPodViewController.h"
#import "LTHaptics.h"
#import "LTHapticStrengthViewController.h"
#import "LTLog.h"
#import "LTThemedTableView.h"

typedef NS_ENUM(NSInteger, LTSettingsTab) {
    LTSettingsTabPlayback = 0,
    LTSettingsTabAppearance,
    LTSettingsTabLibrary,
    LTSettingsTabData,
    LTSettingsTabAbout,
};

// Smart playlists require iOS 6+; on older systems the setting is hidden too.
static BOOL LTSmartPlaylistsSupported(void) {
    return [[[UIDevice currentDevice] systemVersion] integerValue] > 5;
}

@interface LTSettingsViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *segControl;
@property (nonatomic, assign) NSInteger currentTab;
@property (nonatomic, strong) id<LTToggleControl> awakeSwitch;
@property (nonatomic, strong) id<LTToggleControl> kbpsSwitch;
@property (nonatomic, strong) id<LTToggleControl> bgSwitch;
@property (nonatomic, strong) id<LTToggleControl> animSwitch;
@property (nonatomic, strong) id<LTToggleControl> ipodSwitch;
@property (nonatomic, strong) id<LTToggleControl> smartPlaylistsSwitch;
@property (nonatomic, strong) UIAlertView *progressAlert;
@property (nonatomic, assign) BOOL refreshingMetadata;
@property (nonatomic, assign) NSInteger versionTapCount;
@end

@implementation LTSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = @"Settings";
    self.view.backgroundColor = [LTTheme groupedBackground];

    CGRect bounds = self.view.bounds;
    self.currentTab = LTSettingsTabPlayback;
    NSArray *tabs = @[@"Playback", @"View", @"Library", @"Data", @"About"];
    self.segControl = [LTTheme isModern]
        ? (UISegmentedControl *)[[LTCardSegmented alloc] initWithItems:tabs]
        : [[LTCompactSegmentedControl alloc] initWithItems:tabs];
    self.segControl.selectedSegmentIndex = 0;
    [self.segControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.segControl.frame = CGRectMake(8, 6, bounds.size.width - 16, 30);
    self.segControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.segControl];
    // Apply after the frame is set: on iOS 4 resizing the control can reset
    // the fonts set on its private labels.
    [LTTheme setTitleFont:[UIFont boldSystemFontOfSize:11] forSegmentedControl:self.segControl];

    self.tableView = [[LTThemedTableView alloc] initWithFrame:CGRectMake(0, 42, bounds.size.width, bounds.size.height - 42)
                                                  style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyTheme];
    [self.tableView reloadData];
}

- (void)applyTheme {
    self.view.backgroundColor = [LTTheme groupedBackground];
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.segControl setNeedsDisplay];
}

- (void)segmentChanged:(id)sender {
    self.currentTab = self.segControl.selectedSegmentIndex;
    [self.tableView reloadData];
}

#pragma mark - Controls

// Makes the switch for the current theme.
//
// The native theme uses the platform's own switch. The modern themes use ours,
// because the themed table moves the accessory out of the cell and into the row
// it draws, and a platform switch that has been re-parented that way stops
// answering taps: the touch lands on it and nothing happens.
- (id<LTToggleControl>)makeSwitch {
    if ([LTTheme isModern]) return [[LTCardSwitch alloc] init];
    return [[UISwitch alloc] init];
}

- (id<LTToggleControl>)awakeSwitch {
    if (!_awakeSwitch) {
        _awakeSwitch = [self makeSwitch];
        _awakeSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTKeepAwake"];
        [(UIControl *)_awakeSwitch addTarget:self action:@selector(awakeChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _awakeSwitch;
}

- (void)awakeChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.awakeSwitch.on forKey:@"LTKeepAwake"];
    BOOL playing = [[LTPlayerController sharedController] isPlaying];
    [[UIApplication sharedApplication] setIdleTimerDisabled:(self.awakeSwitch.on && playing)];
}

- (id<LTToggleControl>)kbpsSwitch {
    if (!_kbpsSwitch) {
        _kbpsSwitch = [self makeSwitch];
        _kbpsSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTShowKbpsCounter"];
        [(UIControl *)_kbpsSwitch addTarget:self action:@selector(kbpsChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _kbpsSwitch;
}

- (void)kbpsChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.kbpsSwitch.on forKey:@"LTShowKbpsCounter"];
}

- (id<LTToggleControl>)bgSwitch {
    if (!_bgSwitch) {
        _bgSwitch = [self makeSwitch];
        _bgSwitch.on = [self artworkBackgroundEnabled];
        [(UIControl *)_bgSwitch addTarget:self action:@selector(bgChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _bgSwitch;
}

- (void)bgChanged:(id)sender {
    [LTArtworkBackground setEnabled:self.bgSwitch.on];
}

- (BOOL)artworkBackgroundEnabled {
    return [LTArtworkBackground enabled];
}

- (id<LTToggleControl>)animSwitch {
    if (!_animSwitch) {
        _animSwitch = [self makeSwitch];
        _animSwitch.on = [LTTransitionSettings animationsEnabled];
        [(UIControl *)_animSwitch addTarget:self action:@selector(animChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _animSwitch;
}

- (void)animChanged:(id)sender {
    [LTTransitionSettings setAnimationsEnabled:self.animSwitch.on];
}

- (id<LTToggleControl>)smartPlaylistsSwitch {
    if (!_smartPlaylistsSwitch) {
        _smartPlaylistsSwitch = [self makeSwitch];
        _smartPlaylistsSwitch.on = ![[NSUserDefaults standardUserDefaults] boolForKey:@"LTDisableSmartPlaylists"];
        [(UIControl *)_smartPlaylistsSwitch addTarget:self action:@selector(smartPlaylistsChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _smartPlaylistsSwitch;
}

- (void)smartPlaylistsChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:!self.smartPlaylistsSwitch.on forKey:@"LTDisableSmartPlaylists"];
}

- (id<LTToggleControl>)ipodSwitch {
    if (!_ipodSwitch) {
        _ipodSwitch = [self makeSwitch];
        _ipodSwitch.on = [LTiPodViewController isEnabled];
        [(UIControl *)_ipodSwitch addTarget:self action:@selector(ipodChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _ipodSwitch;
}

- (void)ipodChanged:(id)sender {
    [LTiPodViewController setEnabled:self.ipodSwitch.on];
    [LTiPodViewController applyiPodModeAnimated:YES];
}


#pragma mark - Storage

- (void)clearDownloadsTapped {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Clear Offline Downloads"
                                                    message:@"This removes all downloaded tracks from the device. Streaming is not affected."
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Clear", nil];
    alert.tag = 900;
    [alert show];
}

- (void)clearOfflineFiles {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[store audioDirectory] error:&error];
    if ([files isKindOfClass:[NSArray class]]) {
        for (NSString *name in files) {
            if (![name hasSuffix:@".m4a"] && ![name hasSuffix:@".mp4"]) continue;
            NSString *path = [[store audioDirectory] stringByAppendingPathComponent:name];
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:store];
    [self.tableView reloadData];
}

- (void)clearSearchHistoryTapped {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Clear Search History"
                                                    message:@"Remove all saved search terms?"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Clear", nil];
    alert.tag = 903;
    [alert show];
}

- (void)clearRecentsTapped {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Clear Recently Played"
                                                    message:@"Remove all recently played tracks from the Home screen?"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Clear", nil];
    alert.tag = 904;
    [alert show];
}

- (void)resetStatsTapped {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Reset Listening Stats"
                                                    message:@"This clears the Stats screen, the most-played list, the listening counter, any stats synced from other devices, and listening history. This cannot be undone."
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Reset", nil];
    alert.tag = 902;
    [alert show];
}

- (void)resetListeningStats {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    [store clearListeningStats];
    [self.tableView reloadData];
}

#pragma mark - Metadata refresh

- (void)refreshMetadataTapped {
    if (self.refreshingMetadata) return;
    NSInteger count = [[LTPlaylistStore sharedStore] offlineTrackCount];
    if (!count) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Offline Songs"
                                                        message:@"Download some tracks to a playlist first."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Refresh Metadata"
                                                    message:[NSString stringWithFormat:@"Re-fetch titles, artists, durations and full-res album art for %d offline track(s)?", (int)count]
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Refresh", nil];
    alert.tag = 901;
    [alert show];
}

- (void)startMetadataRefresh {
    self.refreshingMetadata = YES;
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSInteger total = [store offlineTrackCount];
    __unsafe_unretained LTSettingsViewController *weakSelf = self;
    [store refreshOfflineMetadataWithProgress:^(NSInteger done, NSInteger totalItems) {
        LTSettingsViewController *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.progressAlert) return;
        strongSelf.progressAlert.message = [NSString stringWithFormat:@"Updating %d of %d…", (int)done, (int)totalItems];
    } completion:^(NSInteger updated, NSInteger failed) {
        LTSettingsViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.refreshingMetadata = NO;
        [strongSelf.progressAlert dismissWithClickedButtonIndex:0 animated:NO];
        strongSelf.progressAlert = nil;
        [strongSelf.tableView reloadData];
        NSString *message = failed
            ? [NSString stringWithFormat:@"Updated %d track(s). %d failed — try again later.", (int)updated, (int)failed]
            : [NSString stringWithFormat:@"Updated %d track(s), including full-res album art.", (int)updated];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Refresh Complete"
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    }];
    UIAlertView *progress = [[UIAlertView alloc] initWithTitle:@"Refreshing"
                                                       message:[NSString stringWithFormat:@"Updating 0 of %d…", (int)total]
                                                      delegate:nil
                                             cancelButtonTitle:nil
                                             otherButtonTitles:nil];
    [progress show];
    self.progressAlert = progress;
}

#pragma mark - Web export

- (void)exportToWebTapped {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSInteger count = [store offlineFileCount];
    if (!count) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Nothing to Export"
                                                        message:@"Download some tracks to a playlist first, then you can create an AN Mini instance."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }

    // Only offer playlists that actually contain downloaded tracks.
    NSMutableArray *eligible = [NSMutableArray array];
    for (LTLocalPlaylist *p in store.playlists) {
        BOOL hasDownloaded = NO;
        for (LTTrack *t in p.tracks) {
            if ([store isTrackDownloaded:t]) { hasDownloaded = YES; break; }
        }
        if (hasDownloaded) [eligible addObject:p];
    }
    if (!eligible.count) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Nothing to Export"
                                                        message:@"Download some tracks to a playlist first, then you can create an AN Mini instance."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
        return;
    }

    __unsafe_unretained LTSettingsViewController *weakSelf = self;
    LTPlaylistSelectViewController *picker =
        [[LTPlaylistSelectViewController alloc] initWithPlaylists:eligible
                                                       completion:^(NSArray *identifiers, BOOL cancelled) {
        LTSettingsViewController *strongSelf = weakSelf;
        [strongSelf dismissViewControllerAnimated:YES completion:NULL];
        if (!strongSelf || cancelled) return;
        [strongSelf startWebExportWithPlaylists:identifiers];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [LTCardNavBar applyModernStyleToNavigationBar:nav.navigationBar];
    [self presentViewController:nav animated:YES completion:NULL];
}

- (void)startWebExportWithPlaylists:(NSArray *)identifiers {
    UIAlertView *progress = [[UIAlertView alloc] initWithTitle:@"Creating AN Mini"
                                                       message:@"Downloading missing artwork, then packaging your tracks…"
                                                      delegate:nil
                                             cancelButtonTitle:nil
                                             otherButtonTitles:nil];
    [progress show];
    self.progressAlert = progress;

    __unsafe_unretained LTSettingsViewController *weakSelf = self;
    [[LTWebExporter sharedExporter] exportWithSelectedPlaylists:identifiers
        completion:^(NSString *outDir, NSError *error) {
            LTSettingsViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.progressAlert dismissWithClickedButtonIndex:0 animated:NO];
            strongSelf.progressAlert = nil;
            NSString *title;
            NSString *message;
            if (outDir) {
                title = @"AN Mini Created";
                message = [NSString stringWithFormat:@"Your audioNINJA Mini was written to:\n%@\n\nCopy that folder to any computer or phone, then open its index.html to listen. It works fully offline.", outDir];
            } else {
                title = @"Create Failed";
                message = error.localizedDescription ?: @"Something went wrong while creating your AN Mini.";
            }
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                            message:message
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        }];
}

#pragma mark - UIAlertViewDelegate

- (void)presentIconPicker {
    UIAlertView *sheet = [[UIAlertView alloc] initWithTitle:@"App Icon"
                                                   message:@"Pick which icon revision shows on the Home Screen. iOS will confirm the change."
                                                  delegate:self
                                         cancelButtonTitle:@"Cancel"
                                         otherButtonTitles:@"Classic", @"Rounded", @"Modern", nil];
    sheet.tag = 950;
    [sheet show];
}

- (NSString *)lyricsOffsetLabel {
    double seconds = LTLyricsOffset();
    if (fabs(seconds) < 0.05) return @"Synced";
    return [NSString stringWithFormat:@"%+.1fs", seconds];
}

- (NSString *)sleepTimerLabel {
    NSInteger left = [[LTSleepTimer shared] remainingMinutes];
    if (left <= 0) return @"Off";
    return [NSString stringWithFormat:@"%ld min left", (long)left];
}

- (void)presentSleepTimerPicker {
    NSInteger left = [[LTSleepTimer shared] remainingMinutes];
    UIAlertView *sheet = [[UIAlertView alloc] initWithTitle:@"Sleep Timer"
                                                   message:@"Playback will pause when the timer runs out."
                                                  delegate:self
                                         cancelButtonTitle:@"Cancel"
                                         otherButtonTitles:@"Off", @"15 min", @"30 min", @"45 min", @"60 min", @"90 min", nil];
    sheet.tag = 951;
    (void)left;
    [sheet show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 951) {
        // Buttons: 0 Cancel, then Off / 15 / 30 / 45 / 60 / 90 minutes.
        static const NSInteger minutes[] = {0, 15, 30, 45, 60, 90};
        if (buttonIndex >= 1 && buttonIndex <= 6) {
            [[LTSleepTimer shared] startWithMinutes:minutes[buttonIndex - 1]];
            [self.tableView reloadData];
        }
        return;
    }
    if (alertView.tag == 950) {
        NSString *name = nil;
        if (buttonIndex == 1) name = [LTAppIcon classicIconName];
        else if (buttonIndex == 2) name = [LTAppIcon roundedIconName];
        else if (buttonIndex == 3) name = [LTAppIcon modernIconName];
        if (buttonIndex >= 1) {
            [LTAppIcon applyIconNamed:name];
            [self.tableView reloadData];
        }
        return;
    }
    if (alertView.tag == 900 && buttonIndex == 1) {
        [self clearOfflineFiles];
    }
    if (alertView.tag == 901 && buttonIndex == 1) {
        [self startMetadataRefresh];
    }
    if (alertView.tag == 902 && buttonIndex == 1) {
        [self resetListeningStats];
    }
    if (alertView.tag == 903 && buttonIndex == 1) {
        [[LTPlaylistStore sharedStore] clearSearchHistory];
        [self.tableView reloadData];
    }
    if (alertView.tag == 904 && buttonIndex == 1) {
        [[LTPlaylistStore sharedStore] clearRecents];
        [self.tableView reloadData];
    }

}

- (NSString *)speedLabel {
    CGFloat multiplier = [LTTransitionSettings speedMultiplier];
    return [NSString stringWithFormat:@"%.1fx", multiplier];
}

- (NSString *)tileSizeLabel {
    CGFloat width = [[NSUserDefaults standardUserDefaults] floatForKey:@"LTHomeTileSize"];
    if (width < kHomeTileMinWidth || width > kHomeTileMaxWidth) {
        width = kHomeTileMinWidth;
    }
    return [NSString stringWithFormat:@"%.0f pt", width];
}

- (void)handleVersionTap {
    self.versionTapCount++;
    if (self.versionTapCount >= 5) {
        self.versionTapCount = 0;
        LTDebugMenuViewController *vc = [[LTDebugMenuViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.currentTab == LTSettingsTabData) return 2;
    return 1;
}

// The icon picker is appended after whatever the last appearance row happens to
// be, so it never shifts the indices of the existing rows. The theme row sits
// after it, and the accent row after that, for the same reason.
- (BOOL)hasAccentRow {
    // The accent only applies to the Modern themes, so its row is hidden while
    // Native is selected (and on iOS versions that cannot run Modern at all).
    return [LTTheme isModern];
}

// iPod Mode is a full-screen replacement UI that is only useful on the newer
// systems. On iOS 5 and earlier it cannot be entered, so do not offer it.
- (BOOL)hasIpodRow {
    NSInteger major = [[[UIDevice currentDevice] systemVersion] integerValue];
    return major > 5;
}

- (NSInteger)appearanceRowCount {
    NSInteger count = 4;  // art bg, animations, transition speed, recents tile size
    if ([self hasIpodRow]) count += 1;
    if ([LTOneHandedMode isSupported]) count += 1;
    if ([LTAppIcon isPickerSupported]) count += 1;
    // The theme row only exists where a modern theme can actually run.
    if ([LTTheme supportsModernThemes]) count += 1;
    if ([self hasAccentRow]) count += 1;
    return count;
}

// Fixed rows shift up when iPod Mode is hidden, so work out their indices
// instead of hard-coding them.
- (NSInteger)ipodRowIndex {
    return [self hasIpodRow] ? 3 : -1;
}

- (NSInteger)recentsTileRowIndex {
    return [self hasIpodRow] ? 4 : 3;
}

- (NSInteger)oneHandedRowIndex {
    if (![LTOneHandedMode isSupported]) return -1;
    return [self hasIpodRow] ? 5 : 4;
}

// Index of the accent row, or -1 when it is hidden.
- (NSInteger)accentRowIndex {
    if (![self hasAccentRow]) return -1;
    return [self appearanceRowCount] - 1;
}

// Index of the theme row, when there is one. -1 otherwise, which never matches
// a real row.
- (NSInteger)themeRowIndex {
    if (![LTTheme supportsModernThemes]) return -1;
    return [self appearanceRowCount] - 1 - ([self hasAccentRow] ? 1 : 0);
}

// Index of the app icon row, just above the theme row. -1 when the picker is
// not available, which never matches a real row.
- (NSInteger)appIconRowIndex {
    if (![LTAppIcon isPickerSupported]) return -1;
    NSInteger index = [self appearanceRowCount] - 1;
    if ([LTTheme supportsModernThemes]) index -= 1;
    if ([self hasAccentRow]) index -= 1;
    return index;
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
    switch (self.currentTab) {
        case LTSettingsTabPlayback: return @"Playback options";
        case LTSettingsTabAppearance: return @"Appearance options";
        case LTSettingsTabLibrary: return @"Library";
        case LTSettingsTabData: return (section == 1) ? @"Connections" : @"Data";
        case LTSettingsTabAbout: return @"About";
        default: return @"";
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.currentTab) {
        case LTSettingsTabPlayback: return 5;
        case LTSettingsTabAppearance: return [self appearanceRowCount];
        case LTSettingsTabLibrary: return LTSmartPlaylistsSupported() ? 3 : 2;
        case LTSettingsTabData: return (section == 1) ? 4 : 6;
        case LTSettingsTabAbout: return 4;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellId];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [LTTheme text];
    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = [LTTheme secondaryText];

    switch (self.currentTab) {
        case LTSettingsTabPlayback: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Keep Screen Awake";
                cell.accessoryView = (UIView *)self.awakeSwitch;
                LTLog(@"SETTINGS awake switch %@ frame=%@", NSStringFromClass([self.awakeSwitch class]), NSStringFromCGRect(((UIView *)self.awakeSwitch).frame));
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Show kbps Counter";
                cell.accessoryView = (UIView *)self.kbpsSwitch;
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"Sleep Timer";
                cell.detailTextLabel.text = [self sleepTimerLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 3) {
                cell.textLabel.text = @"Lyrics Offset";
                cell.detailTextLabel.text = [self lyricsOffsetLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else {
                cell.textLabel.text = @"Haptic Strength";
                cell.detailTextLabel.text = [LTHaptics currentStrengthLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsTabAppearance: {
            if (indexPath.row == [self accentRowIndex]) {
                cell.textLabel.text = @"Accent Color";
                cell.detailTextLabel.text = [LTTheme currentAccentLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == [self themeRowIndex]) {
                cell.textLabel.text = @"Theme";
                cell.detailTextLabel.text = [LTTheme nameForTheme:[LTTheme currentTheme]];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == [self appIconRowIndex]) {
                cell.textLabel.text = @"App Icon";
                cell.detailTextLabel.text = [LTAppIcon currentIconLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 0) {
                cell.textLabel.text = @"Album Art Background";
                cell.detailTextLabel.text = @"";
                cell.accessoryView = (UIView *)self.bgSwitch;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Enable Animations";
                cell.detailTextLabel.text = @"";
                cell.accessoryView = (UIView *)self.animSwitch;
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"Transition Speed";
                cell.detailTextLabel.text = [self speedLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == [self ipodRowIndex]) {
                cell.textLabel.text = @"iPod Mode";
                cell.detailTextLabel.text = @"";
                cell.accessoryView = (UIView *)self.ipodSwitch;
            } else if (indexPath.row == [self recentsTileRowIndex]) {
                cell.textLabel.text = @"Recents Tile Size";
                cell.detailTextLabel.text = [self tileSizeLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == [self oneHandedRowIndex]) {
                cell.textLabel.text = @"One-Handed Mode";
                cell.detailTextLabel.text = [LTOneHandedMode currentLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsTabLibrary: {
            // On iOS 5 and below the smart-playlist row is gone, so the two
            // remaining rows shift up rather than leaving a blank gap.
            NSInteger row = indexPath.row + (LTSmartPlaylistsSupported() ? 0 : 1);
            if (row == 0) {
                cell.textLabel.text = @"Smart Playlists";
                cell.detailTextLabel.text = @"";
                cell.accessoryView = (UIView *)self.smartPlaylistsSwitch;
            } else if (row == 1) {
                cell.textLabel.text = @"Refresh Metadata & Artwork";
                cell.detailTextLabel.text = @"";
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else {
                cell.textLabel.text = @"Create AN Mini Instance (BETA)";
                cell.detailTextLabel.text = @"";
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsTabData: {
            if (indexPath.section == 1) {
                LTListenBrainzScrobbler *lb = [LTListenBrainzScrobbler sharedScrobbler];
                if (indexPath.row == 0) {
                    cell.textLabel.text = @"Sync with Another Device";
                    cell.detailTextLabel.text = @"";
                    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
                } else if (indexPath.row == 1) {
                    cell.textLabel.text = @"Import from Spotify (BETA)";
                    cell.detailTextLabel.text = @"Playlists";
                    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                } else if (indexPath.row == 2) {
                    cell.textLabel.text = @"ListenBrainz Status";
                    cell.detailTextLabel.text = lb.isConnected ? (lb.username.length ? lb.username : @"Connected") : @"Not connected";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                } else {
                    cell.textLabel.text = lb.isConnected ? @"Disconnect ListenBrainz" : @"Connect ListenBrainz";
                    cell.textLabel.textColor = lb.isConnected ? [UIColor redColor] : [LTTheme text];
                    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
                }
                break;
            }
            LTPlaylistStore *store = [LTPlaylistStore sharedStore];
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Download Queue";
                NSInteger pending = [store pendingDownloadCount];
                cell.detailTextLabel.text = pending ? [NSString stringWithFormat:@"%d waiting", (int)pending] : @"Empty";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Offline Downloads";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%d files", (int)[store offlineFileCount]];
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"Clear Offline Downloads";
                cell.textLabel.textColor = [UIColor redColor];
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 3) {
                cell.textLabel.text = @"Clear Recently Played";
                cell.textLabel.textColor = [UIColor redColor];
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 4) {
                cell.textLabel.text = @"Clear Search History";
                cell.textLabel.textColor = [UIColor redColor];
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else {
                cell.textLabel.text = @"Reset Listening Stats";
                cell.textLabel.textColor = [UIColor redColor];
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsTabAbout: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"App";
                cell.detailTextLabel.text = @"audioNINJA mobile";
                cell.accessoryView = nil;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Version";
                NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
                cell.detailTextLabel.text = version.length ? version : @"0.1.0";
                cell.accessoryView = nil;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"SuperYosh23";
                cell.detailTextLabel.text = @"App concept and design";
                cell.accessoryView = nil;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.detailTextLabel.textColor = [LTTheme secondaryText];
            } else {
                cell.textLabel.text = @"OpenCode";
                cell.detailTextLabel.text = @"AI Coding Agent";
                cell.accessoryView = nil;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.detailTextLabel.textColor = [LTTheme secondaryText];
            }
            break;
        }
        default:
            break;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.currentTab == LTSettingsTabPlayback && indexPath.row == 2) {
        [self presentSleepTimerPicker];
        return;
    }
    if (self.currentTab == LTSettingsTabPlayback && indexPath.row == 3) {
        [self.navigationController pushViewController:[[LTLyricsOffsetViewController alloc] init] animated:YES];
        return;
    }
    if (self.currentTab == LTSettingsTabPlayback && indexPath.row == 4) {
        [self.navigationController pushViewController:[[LTHapticStrengthViewController alloc] init] animated:YES];
        return;
    }
    if (self.currentTab == LTSettingsTabAbout) {
        if (indexPath.row == 1) {
            [self handleVersionTap];
            return;
        }
        return;
    }
    if (self.currentTab == LTSettingsTabAppearance) {
        if (indexPath.row == [self accentRowIndex]) {
            LTAccentPickerViewController *vc = [[LTAccentPickerViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == [self themeRowIndex]) {
            LTThemePickerViewController *vc = [[LTThemePickerViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == [self appIconRowIndex]) {
            [self presentIconPicker];
        } else if (indexPath.row == 2) {
            LTTransitionSpeedViewController *vc = [[LTTransitionSpeedViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == [self recentsTileRowIndex]) {
            LTRecentsTileSizeViewController *vc = [[LTRecentsTileSizeViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == [self oneHandedRowIndex]) {
            LTOneHandedModeViewController *vc = [[LTOneHandedModeViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
        return;
    }
    if (self.currentTab == LTSettingsTabLibrary) {
        NSInteger row = indexPath.row + (LTSmartPlaylistsSupported() ? 0 : 1);
        if (row == 1) {
            [self refreshMetadataTapped];
        } else if (row == 2) {
            [self exportToWebTapped];
        }
        return;
    }
    if (self.currentTab == LTSettingsTabData) {
        if (indexPath.section == 1) {
            if (indexPath.row == 0) {
                [LTP2PSync beginFromViewController:self];
            } else if (indexPath.row == 1) {
                LTSpotifyImportViewController *vc = [[LTSpotifyImportViewController alloc] init];
                [self.navigationController pushViewController:vc animated:YES];
            } else if (indexPath.row == 3) {
                LTListenBrainzScrobbler *lb = [LTListenBrainzScrobbler sharedScrobbler];
                if (lb.isConnected) {
                    [lb disconnect];
                    [self.tableView reloadData];
                } else {
                    [self listenBrainzConnectTapped];
                }
            }
            return;
        }
        if (indexPath.row == 0) {
            LTDownloadQueueViewController *queue = [[LTDownloadQueueViewController alloc] init];
            [self.navigationController pushViewController:queue animated:YES];
        } else if (indexPath.row == 2) {
            [self clearDownloadsTapped];
        } else if (indexPath.row == 3) {
            [self clearRecentsTapped];
        } else if (indexPath.row == 4) {
            [self clearSearchHistoryTapped];
        } else if (indexPath.row == 5) {
            [self resetStatsTapped];
        }
        return;
    }
}


#pragma mark - ListenBrainz

- (void)listenBrainzConnectTapped {
    LTListenBrainzScrobbler *lb = [LTListenBrainzScrobbler sharedScrobbler];
    [lb requestTokenWithCompletion:^(NSString *token, NSError *error) {
        if (error || !token.length) {
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"ListenBrainz"
                                                        message:error.localizedDescription ?: @"Could not get a request token"
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
            [a show];
            return;
        }
        NSURL *url = [lb authorizationURLForToken:token];
        [[NSUserDefaults standardUserDefaults] setObject:token forKey:@"LTListenBrainzPendingToken"];
        LTListenBrainzAuthViewController *vc = [[LTListenBrainzAuthViewController alloc] initWithAuthURL:url token:token];
        // presentViewController:animated:completion: is iOS 5+.
        if ([self respondsToSelector:@selector(presentViewController:animated:completion:)]) {
            [self presentViewController:vc animated:YES completion:nil];
        } else {
            [self presentModalViewController:vc animated:YES];
        }
    }];
}

@end
