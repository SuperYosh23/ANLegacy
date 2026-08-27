#import "LTSettingsViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTWirelessSync.h"
#import "LTTransitionSettings.h"
#import "LTTransitionSpeedViewController.h"
#import "LTLog.h"

typedef NS_ENUM(NSInteger, LTSettingsSection) {
    LTSettingsSectionPlayback = 0,
    LTSettingsSectionStorage,
    LTSettingsSectionAbout,
};

@interface LTSettingsViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *awakeSwitch;
@property (nonatomic, strong) UIAlertView *progressAlert;
@property (nonatomic, assign) BOOL refreshingMetadata;
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

- (void)showQualityPicker:(id)sender {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Streaming Quality"
                                                      delegate:self
                                             cancelButtonTitle:@"Cancel"
                                        destructiveButtonTitle:nil
                                             otherButtonTitles:@"Low", @"Normal", @"High", nil];
    sheet.tag = 800;
    [sheet showInView:self.view];
}

- (void)awakeChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.awakeSwitch.on forKey:@"LTKeepAwake"];
    BOOL playing = [[LTPlayerController sharedController] isPlaying];
    [[UIApplication sharedApplication] setIdleTimerDisabled:(self.awakeSwitch.on && playing)];
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

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 900 && buttonIndex == 1) {
        [self clearOfflineFiles];
    }
    if (alertView.tag == 901 && buttonIndex == 1) {
        [self startMetadataRefresh];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == 800 && buttonIndex >= 0 && buttonIndex <= 2) {
        [[NSUserDefaults standardUserDefaults] setInteger:buttonIndex forKey:@"LTStreamingQuality"];
        [self.tableView reloadData];
    }
}

- (NSString *)qualityLabel {
    NSInteger quality = [[NSUserDefaults standardUserDefaults] integerForKey:@"LTStreamingQuality"];
    if (quality < 0 || quality > 2) quality = 2;
    switch (quality) {
        case 0: return @"Low";
        case 1: return @"Normal";
        default: return @"High";
    }
}

- (NSString *)speedLabel {
    CGFloat multiplier = [LTTransitionSettings speedMultiplier];
    return [NSString stringWithFormat:@"%.1fx", multiplier];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case LTSettingsSectionPlayback: return @"Playback";
        case LTSettingsSectionStorage: return @"Storage";
        case LTSettingsSectionAbout: return @"About";
        default: return @"";
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case LTSettingsSectionPlayback: return 3;
        case LTSettingsSectionStorage: return 3;
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
                cell.textLabel.text = @"Streaming Quality";
                cell.detailTextLabel.text = [self qualityLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Keep Screen Awake";
                cell.accessoryView = [self awakeSwitch];
            } else {
                cell.textLabel.text = @"Transition Speed";
                cell.detailTextLabel.text = [self speedLabel];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsSectionStorage: {
            LTPlaylistStore *store = [LTPlaylistStore sharedStore];
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Offline Downloads";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%d files", (int)[store offlineFileCount]];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Refresh Metadata & Artwork";
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            } else {
                cell.textLabel.text = @"Clear Offline Downloads";
                cell.textLabel.textColor = [UIColor redColor];
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            }
            break;
        }
        case LTSettingsSectionAbout: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"App";
                cell.detailTextLabel.text = @"LegacyMusic";
            } else {
                cell.textLabel.text = @"Version";
                NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
                cell.detailTextLabel.text = version.length ? version : @"0.1.0";
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
    if (indexPath.section == LTSettingsSectionPlayback) {
        if (indexPath.row == 0) {
            [self showQualityPicker:nil];
        } else if (indexPath.row == 2) {
            LTTransitionSpeedViewController *vc = [[LTTransitionSpeedViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
        return;
    }
    if (indexPath.section == LTSettingsSectionStorage) {
        if (indexPath.row == 1) {
            [self refreshMetadataTapped];
        } else if (indexPath.row == 2) {
            [self clearDownloadsTapped];
        }
        return;
    }
}

@end
