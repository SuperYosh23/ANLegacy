#import "LTSettingsViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTWirelessSync.h"
#import "LTP2PSync.h"
#import "LTTransitionSettings.h"
#import "LTTransitionSpeedViewController.h"
#import "LTRecentsTileSizeViewController.h"
#import "LTWebExporter.h"
#import "LTPlaylistSelectViewController.h"
#import "LTHomeViewController.h"
#import "LTDebugMenuViewController.h"
#import "LTLog.h"

typedef NS_ENUM(NSInteger, LTSettingsSection) {
    LTSettingsSectionPlayback = 0,
    LTSettingsSectionAppearance,
    LTSettingsSectionData,
    LTSettingsSectionAbout,
};

@interface LTSettingsViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *awakeSwitch;
@property (nonatomic, strong) UISwitch *kbpsSwitch;
@property (nonatomic, strong) UISwitch *bgSwitch;
@property (nonatomic, strong) UISwitch *animSwitch;
@property (nonatomic, strong) UIAlertView *progressAlert;
@property (nonatomic, assign) BOOL refreshingMetadata;
@property (nonatomic, assign) NSInteger versionTapCount;
@end

@implementation LTSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Settings";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    CGRect bounds = self.view.bounds;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                                  style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - Controls

- (UISwitch *)awakeSwitch {
    if (!_awakeSwitch) {
        _awakeSwitch = [[UISwitch alloc] init];
        _awakeSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTKeepAwake"];
        [_awakeSwitch addTarget:self action:@selector(awakeChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _awakeSwitch;
}

- (void)awakeChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.awakeSwitch.on forKey:@"LTKeepAwake"];
    BOOL playing = [[LTPlayerController sharedController] isPlaying];
    [[UIApplication sharedApplication] setIdleTimerDisabled:(self.awakeSwitch.on && playing)];
}

- (UISwitch *)kbpsSwitch {
    if (!_kbpsSwitch) {
        _kbpsSwitch = [[UISwitch alloc] init];
        _kbpsSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTShowKbpsCounter"];
        [_kbpsSwitch addTarget:self action:@selector(kbpsChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _kbpsSwitch;
}

- (void)kbpsChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.kbpsSwitch.on forKey:@"LTShowKbpsCounter"];
}

- (UISwitch *)bgSwitch {
    if (!_bgSwitch) {
        _bgSwitch = [[UISwitch alloc] init];
        _bgSwitch.on = [self artworkBackgroundEnabled];
        [_bgSwitch addTarget:self action:@selector(bgChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _bgSwitch;
}

- (void)bgChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.bgSwitch.on forKey:@"LTPlayerArtworkBackground"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)artworkBackgroundEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"LTPlayerArtworkBackground"] == nil) {
        BOOL modern = ([UIDevice currentDevice].systemVersion.intValue >= 7);
        [defaults setBool:modern forKey:@"LTPlayerArtworkBackground"];
        [defaults synchronize];
        return modern;
    }
    return [defaults boolForKey:@"LTPlayerArtworkBackground"];
}

- (UISwitch *)animSwitch {
    if (!_animSwitch) {
        _animSwitch = [[UISwitch alloc] init];
        _animSwitch.on = [LTTransitionSettings animationsEnabled];
        [_animSwitch addTarget:self action:@selector(animChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _animSwitch;
}

- (void)animChanged:(id)sender {
    [LTTransitionSettings setAnimationsEnabled:self.animSwitch.on];
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

- (void)resetStatsTapped {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Reset Listening Stats"
                                                    message:@"This clears the Stats screen, the most-played list, the listening counter, any stats synced from other phones, and listening history. This cannot be undone."
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
    __weak LTSettingsViewController *weakSelf = self;
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

    __weak LTSettingsViewController *weakSelf = self;
    LTPlaylistSelectViewController *picker =
        [[LTPlaylistSelectViewController alloc] initWithPlaylists:eligible
                                                       completion:^(NSArray *identifiers, BOOL cancelled) {
        LTSettingsViewController *strongSelf = weakSelf;
        [strongSelf dismissViewControllerAnimated:YES completion:NULL];
        if (!strongSelf || cancelled) return;
        [strongSelf startWebExportWithPlaylists:identifiers];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
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

    __weak LTSettingsViewController *weakSelf = self;
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

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 900 && buttonIndex == 1) {
        [self clearOfflineFiles];
    }
    if (alertView.tag == 901 && buttonIndex == 1) {
        [self startMetadataRefresh];
    }
    if (alertView.tag == 902 && buttonIndex == 1) {
        [self resetListeningStats];
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
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case LTSettingsSectionPlayback: return @"Playback options";
        case LTSettingsSectionAppearance: return @"Appearance options";
        case LTSettingsSectionData: return @"Data management";
        case LTSettingsSectionAbout: return @"About";
        default: return @"";
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case LTSettingsSectionPlayback: return 2;
        case LTSettingsSectionAppearance: return 4;
        case LTSettingsSectionData: return 6;
        case LTSettingsSectionAbout: return 2;
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
    cell.textLabel.textColor = [UIColor blackColor];

    switch (indexPath.section) {
        case LTSettingsSectionPlayback: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Keep Screen Awake";
                cell.accessoryView = [self awakeSwitch];
            } else {
                cell.textLabel.text = @"Show kbps Counter";
                cell.accessoryView = [self kbpsSwitch];
            }
            break;
        }
        case LTSettingsSectionAppearance: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Album Art Background";
                cell.detailTextLabel.text = @"";
                cell.accessoryView = [self bgSwitch];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Enable Animations";
                cell.detailTextLabel.text = @"";
                cell.accessoryView = [self animSwitch];
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"Transition Speed";
                cell.detailTextLabel.text = [self speedLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else {
                cell.textLabel.text = @"Recents Tile Size";
                cell.detailTextLabel.text = [self tileSizeLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsSectionData: {
            LTPlaylistStore *store = [LTPlaylistStore sharedStore];
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Offline Downloads";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%d files", (int)[store offlineFileCount]];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Sync with Another Phone";
                cell.detailTextLabel.text = @"";
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 2) {
                cell.textLabel.text = @"Refresh Metadata & Artwork";
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 3) {
                cell.textLabel.text = @"Create AN Mini Instance (BETA)";
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 4) {
                cell.textLabel.text = @"Clear Offline Downloads";
                cell.textLabel.textColor = [UIColor redColor];
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else {
                cell.textLabel.text = @"Reset Listening Stats";
                cell.textLabel.textColor = [UIColor redColor];
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsSectionAbout: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"App";
                cell.detailTextLabel.text = @"audioNINJA Legacy";
            } else {
                cell.textLabel.text = @"Version";
                NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
                cell.detailTextLabel.text = version.length ? version : @"0.1.0";
            }
            cell.accessoryView = nil;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
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
    if (indexPath.section == LTSettingsSectionAbout && indexPath.row == 1) {
        [self handleVersionTap];
        return;
    }
    if (indexPath.section == LTSettingsSectionAppearance) {
        if (indexPath.row == 2) {
            LTTransitionSpeedViewController *vc = [[LTTransitionSpeedViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == 3) {
            LTRecentsTileSizeViewController *vc = [[LTRecentsTileSizeViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
        return;
    }
    if (indexPath.section == LTSettingsSectionData) {
        if (indexPath.row == 1) {
            [LTP2PSync beginFromViewController:self];
        } else if (indexPath.row == 2) {
            [self refreshMetadataTapped];
        } else if (indexPath.row == 3) {
            [self exportToWebTapped];
        } else if (indexPath.row == 4) {
            [self clearDownloadsTapped];
        } else if (indexPath.row == 5) {
            [self resetStatsTapped];
        }
        return;
    }
}

@end
