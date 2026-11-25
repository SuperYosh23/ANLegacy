#import "LTSpotifyConnectViewController.h"
#import "S6Session.h"
#import "S6Zeroconf.h"
#import "LTTheme.h"
#import "LTLog.h"

@interface LTSpotifyConnectViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *instrLabel;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation LTSpotifyConnectViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Connect Spotify";
    self.view.backgroundColor = [LTTheme background];
    self.instrLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 80, self.view.bounds.size.width - 32, 80)];
    self.instrLabel.numberOfLines = 0;
    self.instrLabel.text = @"1. Put this device and your phone on the same Wi-Fi.\n2. Open Spotify on your phone, play something, tap Devices, pick 'LegacyMusic'.\n3. This app logs in automatically.";
    self.instrLabel.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.instrLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 180, self.view.bounds.size.width - 32, 60)];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.view addSubview:self.statusLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stateChanged:) name:S6SessionStateDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(zcChanged:) name:S6ZeroconfDidChangeNotification object:nil];

    [[S6Session shared] start];
    [[S6Zeroconf shared] start];
    [self refresh];
}

- (void)stateChanged:(NSNotification *)n { [self refresh]; }
- (void)zcChanged:(NSNotification *)n { [self refresh]; }

- (void)refresh {
    S6Session *s = [S6Session shared];
    S6Zeroconf *z = [S6Zeroconf shared];
    NSString *state = @"Logged out";
    switch (s.state) {
        case S6SessionStateConnecting: state = @"Connecting..."; break;
        case S6SessionStateReady: state = [NSString stringWithFormat:@"Ready: %@", s.username]; break;
        case S6SessionStateOffline: state = @"Offline"; break;
        case S6SessionStateFailed: state = [NSString stringWithFormat:@"Failed: %@", s.lastError.localizedDescription]; break;
        default: break;
    }
    self.statusLabel.text = [NSString stringWithFormat:@"Session: %@\nZeroconf: %@ (port %d)\nLast: %@", state, z.running ? @"running" : @"stopped", z.port, z.lastEvent ?: @"-"];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end