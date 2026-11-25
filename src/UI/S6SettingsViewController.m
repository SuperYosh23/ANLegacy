#import "S6SettingsViewController.h"
#import "S6ExternalOpen.h"
#import "S6Router.h"
#import "S6Session.h"
#import "S6Zeroconf.h"
#import "S6Connect.h"
#import "S6Settings.h"
#import "S6Player.h"
#import "S6Catalog.h"
#import "S6ImageLoader.h"
#import "S6Utils.h"
#import "S6Theme.h"
#import "S6Common.h"

// The look of a dark grouped table on iOS 6: the rounded cells on charcoal, headers and footers drawn here
// (the system's are dark text on white shadow, made for the pinstripes)
static void S6StyleGroupedCell(UITableViewCell *cell)
{
    S6Theme *theme = [S6Theme shared];
    cell.backgroundColor = [theme panelColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [theme primaryTextColor];
    cell.textLabel.font = [theme boldBodyFont];
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.textColor = [theme secondaryTextColor];
    cell.detailTextLabel.font = [theme bodyFont];
    UIView *selected = [[UIView alloc] init];
    selected.backgroundColor = [theme rowHighlightColor];
    cell.selectedBackgroundView = selected;
}

static UIView *S6GroupedLabel(NSString *text, CGFloat width, BOOL header, CGFloat *height)
{
    S6Theme *theme = [S6Theme shared];
    UIFont *font = header ? [theme boldBodyFont] : [theme smallFont];
    CGFloat inset = S6IsPad() ? 54 : 20;
    CGSize s = [text sizeWithFont:font constrainedToSize:CGSizeMake(width - inset * 2, 400)];
    CGFloat h = ceilf(s.height) + (header ? 22 : 16);
    if (height) *height = h;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, h)];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(inset, header ? 14 : 6, width - inset * 2, ceilf(s.height))];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.text = text;
    l.font = font;
    l.numberOfLines = 0;
    l.textColor = header ? [theme secondaryTextColor] : [theme tertiaryTextColor];
    l.backgroundColor = [UIColor clearColor];
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
    l.shadowOffset = CGSizeMake(0, -1);
    [v addSubview:l];
    return v;
}

static UIImageView *S6CheckView(void)
{
    S6Theme *theme = [S6Theme shared];
    return [[UIImageView alloc] initWithImage:[theme icon:S6IconCheck size:20 color:[theme accentColor]]];
}

#pragma mark - Quality

@interface S6QualityViewController : UITableViewController
@end

@implementation S6QualityViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) self.title = L(@"Streaming quality");
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [[S6Theme shared] backgroundColor];
    self.tableView.separatorColor = [[S6Theme shared] separatorColor];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }

- (NSString *)footerText
{
    return L(@"Higher quality uses more data. Very high (320 kbit/s) needs Premium; songs without it play in the best quality there is.");
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    return S6GroupedLabel([self footerText], tableView.bounds.size.width, NO, NULL);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    CGFloat h = 0;
    S6GroupedLabel([self footerText], tableView.bounds.size.width, NO, &h);
    return h;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    S6StyleGroupedCell(cell);
    NSArray *names = @[ L(@"Normal"), L(@"High"), L(@"Very high") ];
    NSArray *rates = @[ @"96 kbit/s", @"160 kbit/s", @"320 kbit/s" ];
    cell.textLabel.text = names[(NSUInteger)indexPath.row];
    cell.detailTextLabel.text = rates[(NSUInteger)indexPath.row];
    cell.accessoryView = (NSInteger)[S6Settings quality] == indexPath.row ? S6CheckView() : nil;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [S6Settings setQuality:(S6Quality)indexPath.row];
    [tableView reloadData];
}

@end

#pragma mark - Licences

@interface S6LicensesViewController : UIViewController
@end

@implementation S6LicensesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"Open-source software");
    S6Theme *theme = [S6Theme shared];
    self.view.backgroundColor = [theme backgroundColor];
    UITextView *text = [[UITextView alloc] initWithFrame:self.view.bounds];
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    text.editable = NO;
    text.backgroundColor = [UIColor clearColor];
    text.textColor = [theme primaryTextColor];
    text.font = [theme bodyFont];
    text.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    text.text = [NSString stringWithFormat:@"%@\n\n"
                 "stb_vorbis (Sean Barrett)\n%@\n\n"
                 "Mbed TLS (Arm Limited and contributors)\nApache License 2.0\n\n"
                 "librespot (the librespot contributors)\n%@\n\n"
                 "%@",
                 L(@"Sixify is built with these, thank you:"),
                 L(@"Public domain: the Ogg Vorbis decoder."),
                 L(@"MIT License: how Spotify's protocol works was learned from it (no code of it is in the app)."),
                 L(@"Sixify is an unofficial app. It is not made, endorsed or supported by Spotify. Spotify is a trademark of Spotify AB.")];
    [self.view addSubview:text];
}

@end

#pragma mark - Settings

enum { S6SetAccount, S6SetPlayback, S6SetDevice, S6SetStorage, S6SetAbout, S6SetLogout, S6SetCount };

@interface S6SettingsViewController () <UIAlertViewDelegate>
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *cacheSize;
@end

@implementation S6SettingsViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) self.title = L(@"Settings");
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [[S6Theme shared] backgroundColor];
    self.tableView.separatorColor = [[S6Theme shared] separatorColor];
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(reload) name:S6SessionStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(reload) name:S6ZeroconfDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(reload) name:S6SettingsDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(reload) name:S6ConnectDidChangeNotification object:nil];
}

- (void)reload
{
    if ([S6Session shared].state != S6SessionStateReady) self.displayName = nil;
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    [[S6ImageLoader shared] diskUsage:^(unsigned long long bytes) {
        self.cacheSize = [S6Utils formatFileSize:bytes];
        [self.tableView reloadData];
    }];
    if (!self.displayName && [S6Session shared].state == S6SessionStateReady) {
        [S6Catalog profile:^(NSString *name, NSString *imageURL) {
            if (name.length) { self.displayName = [S6Utils displayText:name]; [self.tableView reloadData]; }
        }];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return S6SetCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case S6SetAccount: return 3;
        case S6SetPlayback: return 6;
        case S6SetDevice: return 3;
        case S6SetStorage: return 1;
        case S6SetAbout: return 3;
        case S6SetLogout: return [S6Settings hasAccount] ? 1 : 0;
    }
    return 0;
}

- (NSString *)headerFor:(NSInteger)section
{
    switch (section) {
        case S6SetAccount: return L(@"Account");
        case S6SetPlayback: return L(@"Playback");
        case S6SetDevice: return L(@"This device");
        case S6SetStorage: return L(@"Storage");
        case S6SetAbout: return L(@"About");
    }
    return nil;
}

- (NSString *)footerFor:(NSInteger)section
{
    switch (section) {
        case S6SetPlayback: return L(@"Data saver: on mobile data songs play in Normal quality (96 kbit/s). Crossfade blends the end of a song into the next one. Autoplay: when your music runs out, similar songs keep playing. Classic player: iOS 6 graphite design for Now Playing.");
        case S6SetDevice: return L(@"The name of this device in the Spotify apps of your account: pick it on your phone to log in, to play here, and to control what plays here (Spotify Connect). While Sixify is open, your devices can see it.");
        case S6SetAbout: return L(@"Sixify is an unofficial app. It is not made, endorsed or supported by Spotify.");
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString *t = [self headerFor:section];
    return t ? S6GroupedLabel(t, tableView.bounds.size.width, YES, NULL) : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSString *t = [self headerFor:section];
    if (!t) return 14;
    CGFloat h = 0;
    S6GroupedLabel(t, tableView.bounds.size.width, YES, &h);
    return h;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    NSString *t = [self footerFor:section];
    return t ? S6GroupedLabel(t, tableView.bounds.size.width, NO, NULL) : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    NSString *t = [self footerFor:section];
    if (!t) return 6;
    CGFloat h = 0;
    S6GroupedLabel(t, tableView.bounds.size.width, NO, &h);
    return h;
}

- (UISwitch *)switchOn:(BOOL)on action:(SEL)action
{
    UISwitch *s = [[UISwitch alloc] init];
    s.on = on;
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (NSString *)stateText
{
    switch ([S6Session shared].state) {
        case S6SessionStateConnecting: return L(@"Connecting…");
        case S6SessionStateOffline: return L(@"Offline");
        case S6SessionStateFailed: return L(@"Login refused");
        case S6SessionStateLoggedOut: return L(@"Not logged in");
        case S6SessionStateReady: break;
    }
    return [S6Session shared].premium ? @"Premium" : L(@"Free");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    S6StyleGroupedCell(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    S6Session *session = [S6Session shared];
    NSInteger row = indexPath.row;
    switch (indexPath.section) {
        case S6SetAccount:
            if (row == 0) { cell.textLabel.text = L(@"Logged in as"); cell.detailTextLabel.text = self.displayName ?: session.username ?: [S6Settings username] ?: @"-"; }
            if (row == 1) { cell.textLabel.text = L(@"Plan"); cell.detailTextLabel.text = [self stateText]; }
            if (row == 2) { cell.textLabel.text = L(@"Country"); cell.detailTextLabel.text = session.country ?: @"-"; }
            break;
        case S6SetPlayback:
            if (row == 0) {
                cell.textLabel.text = L(@"Streaming quality");
                NSArray *names = @[ L(@"Normal"), L(@"High"), L(@"Very high") ];
                cell.detailTextLabel.text = names[(NSUInteger)MIN(2, MAX(0, [S6Settings quality]))];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleGray;
            }
            if (row == 1) { cell.textLabel.text = L(@"Data saver"); cell.accessoryView = [self switchOn:[S6Settings dataSaver] action:@selector(dataSaverChanged:)]; }
            if (row == 2) { cell.textLabel.text = L(@"Normalize volume"); cell.accessoryView = [self switchOn:[S6Settings normalize] action:@selector(normalizeChanged:)]; }
            if (row == 3) {
                cell.textLabel.text = L(@"Crossfade");
                NSInteger seconds = [S6Settings crossfadeSeconds];
                cell.detailTextLabel.text = seconds ? [NSString stringWithFormat:L(@"%ld s"), (long)seconds] : L(@"Off");
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleGray;
            }
            if (row == 4) { cell.textLabel.text = L(@"Autoplay"); cell.accessoryView = [self switchOn:[S6Settings autoplay] action:@selector(autoplayChanged:)]; }
            if (row == 5) { cell.textLabel.text = L(@"Classic player"); cell.accessoryView = [self switchOn:[S6Settings classicPlayer] action:@selector(classicPlayerChanged:)]; }
            break;
        case S6SetDevice:
            if (row == 0) {
                cell.textLabel.text = L(@"Device name");
                cell.detailTextLabel.text = [S6Settings deviceName];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleGray;
            }
            if (row == 1) {
                cell.textLabel.text = L(@"Login from the phone");
                cell.detailTextLabel.text = [S6Zeroconf shared].running ? L(@"Visible on Wi-Fi") : L(@"Off");
            }
            if (row == 2) {
                S6Connect *connect = [S6Connect shared];
                cell.textLabel.text = L(@"Spotify Connect");
                cell.detailTextLabel.text = !connect.registered ? L(@"Connecting…") : connect.active ? L(@"Playing here") : L(@"Visible to your devices");
            }
            break;
        case S6SetStorage:
            cell.textLabel.text = L(@"Clear image cache");
            cell.detailTextLabel.text = self.cacheSize ?: @"…";
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            break;
        case S6SetAbout:
            if (row == 0) { cell.textLabel.text = L(@"Version"); cell.detailTextLabel.text = [S6Utils appVersion]; }
            if (row == 1) {
                cell.textLabel.text = L(@"Open-source software");
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleGray;
            }
            if (row == 2) {
                cell.textLabel.text = L(@"Support the development");
                cell.detailTextLabel.text = @"ko-fi.com/samcejko";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleGray;
            }
            break;
        case S6SetLogout:
            cell.textLabel.text = L(@"Log out");
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIColor colorWithRed:1 green:0.42 blue:0.38 alpha:1];
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch (indexPath.section) {
        case S6SetPlayback:
            if (indexPath.row == 0) [self.navigationController pushViewController:[[S6QualityViewController alloc] init] animated:YES];
            if (indexPath.row == 3) {
                S6ActionSheet *sheet = [[S6ActionSheet alloc] initWithTitle:L(@"Crossfade")];
                for (NSNumber *n in @[ @0, @3, @6, @9, @12 ]) {
                    NSInteger seconds = [n integerValue];
                    [sheet addButton:seconds ? [NSString stringWithFormat:L(@"%ld s"), (long)seconds] : L(@"Off") action:^{
                        [S6Settings setCrossfadeSeconds:seconds];
                        [self.tableView reloadData];
                    }];
                }
                [sheet showFromView:[tableView cellForRowAtIndexPath:indexPath] inController:self];
            }
            break;
        case S6SetDevice:
            if (indexPath.row == 0) {
                UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Device name") message:L(@"How this device shows in the Spotify app.")
                                                           delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Save"), nil];
                a.alertViewStyle = UIAlertViewStylePlainTextInput;
                a.tag = 1;
                [a textFieldAtIndex:0].text = [S6Settings deviceName];
                [a show];
            }
            break;
        case S6SetStorage: {
            [[S6ImageLoader shared] clearMemory];
            [[S6ImageLoader shared] clearDiskWithCompletion:^{
                self.cacheSize = [S6Utils formatFileSize:0];
                [self.tableView reloadData];
                [S6Router toast:L(@"Image cache cleared")];
            }];
            break;
        }
        case S6SetAbout:
            if (indexPath.row == 1) [self.navigationController pushViewController:[[S6LicensesViewController alloc] init] animated:YES];
            else if (indexPath.row == 2) [S6ExternalOpen presentOpenInForURL:[NSURL URLWithString:@"https://ko-fi.com/samcejko"] from:self anchor:[tableView cellForRowAtIndexPath:indexPath]];
            break;
        case S6SetLogout: {
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:L(@"Log out?") message:L(@"To log in again, pick this device in the Spotify app on your phone.")
                                                       delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Log out"), nil];
            a.tag = 2;
            [a show];
            break;
        }
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;
    if (alertView.tag == 1) {
        NSString *name = [[alertView textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length || [name isEqualToString:[S6Settings deviceName]]) return;
        [S6Settings setDeviceName:name];
        // announce the new name on the Wi-Fi
        [[S6Zeroconf shared] stop];
        [[S6Zeroconf shared] start];
        [self.tableView reloadData];
    } else if (alertView.tag == 2) {
        [[S6Player shared] pause];
        [[S6Player shared] clearQueue];
        self.displayName = nil;
        [[S6Session shared] logout];
    }
}

- (void)normalizeChanged:(UISwitch *)s { [S6Settings setNormalize:s.on]; }
- (void)dataSaverChanged:(UISwitch *)s { [S6Settings setDataSaver:s.on]; }
- (void)autoplayChanged:(UISwitch *)s { [S6Settings setAutoplay:s.on]; }
- (void)classicPlayerChanged:(UISwitch *)s { [S6Settings setClassicPlayer:s.on]; }

@end
