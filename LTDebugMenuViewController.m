#import "LTDebugMenuViewController.h"
#import "LTAppDelegate.h"
#import "LTDebugSettings.h"
#import "LTTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "LTThemedTableView.h"

// Not declared in these SDKs; the call site is guarded by respondsToSelector:.
@interface CADisplayLink (LTFPS)
- (void)setPreferredFramesPerSecond:(NSInteger)framesPerSecond;
@end

typedef NS_ENUM(NSInteger, LTDebugSection) {
    LTDebugSectionDisplay = 0,
    LTDebugSectionDiagnostics,
};

@interface LTDebugMenuViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *nonWideSwitch;
@property (nonatomic, strong) UISwitch *wideSwitch;
// Frame counting. 3GS-class hardware is where every regression in this app has
// shown up, and until now the only way to catch one was to notice stutter by
// hand. preferredFramesPerSecond is not declared in these SDKs, so it is set
// reflectively.
@property (nonatomic, strong) CADisplayLink *fpsLink;
@property (nonatomic, assign) NSInteger fpsFrames;
@property (nonatomic, strong) NSDate *fpsStart;
@property (nonatomic, assign) CGFloat fpsValue;
@end

@implementation LTDebugMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = @"Debug";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    [self startFpsCounting];

    CGRect bounds = self.view.bounds;
    self.tableView = [[LTThemedTableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
                                                  style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (UISwitch *)nonWideSwitch {
    if (!_nonWideSwitch) {
        _nonWideSwitch = [[UISwitch alloc] init];
        _nonWideSwitch.on = [LTDebugSettings forceNonWidescreen];
        [_nonWideSwitch addTarget:self action:@selector(nonWideChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _nonWideSwitch;
}

- (void)nonWideChanged:(id)sender {
    [LTDebugSettings setForceNonWidescreen:self.nonWideSwitch.on];
    self.wideSwitch.on = [LTDebugSettings forceWidescreen];
    [LTAppDelegate applyDisplayModeAnimated:YES];
}

- (UISwitch *)wideSwitch {
    if (!_wideSwitch) {
        _wideSwitch = [[UISwitch alloc] init];
        _wideSwitch.on = [LTDebugSettings forceWidescreen];
        [_wideSwitch addTarget:self action:@selector(wideChanged:) forControlEvents:UIControlEventValueChanged];
    }
    return _wideSwitch;
}

- (void)wideChanged:(id)sender {
    [LTDebugSettings setForceWidescreen:self.wideSwitch.on];
    self.nonWideSwitch.on = [LTDebugSettings forceNonWidescreen];
    [LTAppDelegate applyDisplayModeAnimated:YES];
}

#pragma mark - UITableViewDataSource

- (void)startFpsCounting {
    self.fpsLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(fpsTick:)];
    if ([self.fpsLink respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        [self.fpsLink setPreferredFramesPerSecond:60];
    }
    [self.fpsLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.fpsStart = [NSDate date];
}

- (void)fpsTick:(CADisplayLink *)link {
    self.fpsFrames++;
    NSTimeInterval elapsed = -[self.fpsStart timeIntervalSinceNow];
    // Sample over a second so the number is readable rather than jittery.
    if (elapsed < 1.0) return;
    self.fpsValue = (CGFloat)((double)self.fpsFrames / elapsed);
    self.fpsFrames = 0;
    self.fpsStart = [NSDate date];
    [self.tableView reloadData];
}

- (void)dealloc {
    [self.fpsLink invalidate];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == LTDebugSectionDisplay) return @"Display";
    if (section == LTDebugSectionDiagnostics) return @"Diagnostics";
    return @"";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != LTDebugSectionDisplay) return @"";
    UIWindow *win = self.view.window;
    if (!win) win = [(LTAppDelegate *)[[UIApplication sharedApplication] delegate] window];
    UIScreen *scr = [UIScreen mainScreen];
    CGSize native = CGSizeZero;
    if ([scr respondsToSelector:@selector(nativeBounds)]) { NSValue *v = [scr valueForKey:@"nativeBounds"]; native = [v CGRectValue].size; }
    UIEdgeInsets ins = UIEdgeInsetsZero;
#if defined(__IPHONE_11_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if ([win respondsToSelector:@selector(safeAreaInsets)]) ins = win.safeAreaInsets;
#endif
    CGRect wf = win ? win.frame : CGRectZero;
    CGRect rf = win.rootViewController.view.frame;
    CGFloat scale = 0.0f;
    if ([scr respondsToSelector:@selector(scale)]) scale = scr.scale;
    return [NSString stringWithFormat:
            @"Letterboxes the app and switches the Now Playing layout. All debug settings reset to default when the app is relaunched.\n\n"
            @"screen %.0fx%.0f  native %.0fx%.0f  scale %.2f\n"
            @"window %.0fx%.0f @ (%.0f, %.0f)\n"
            @"root %.0fx%.0f\n"
            @"insets T%.0f L%.0f B%.0f R%.0f",
            scr.bounds.size.width, scr.bounds.size.height, native.width, native.height, scale,
            wf.size.width, wf.size.height, wf.origin.x, wf.origin.y,
            rf.size.width, rf.size.height,
            ins.top, ins.left, ins.bottom, ins.right];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == LTDebugSectionDisplay) return 2;
    if (section == LTDebugSectionDiagnostics) return 1;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTDebugCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellId];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = [LTTheme text];
    if (indexPath.section == LTDebugSectionDiagnostics) {
        cell.textLabel.text = @"Frame Rate";
        cell.detailTextLabel.text = self.fpsLink
            ? [NSString stringWithFormat:@"%.0f fps", self.fpsValue]
            : @"paused";
    } else if (indexPath.section == LTDebugSectionDisplay && indexPath.row == 0) {
        cell.textLabel.text = @"Force Non-Widescreen Mode";
        cell.accessoryView = [self nonWideSwitch];
    } else if (indexPath.section == LTDebugSectionDisplay && indexPath.row == 1) {
        cell.textLabel.text = @"Force Widescreen Mode";
        cell.accessoryView = [self wideSwitch];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end