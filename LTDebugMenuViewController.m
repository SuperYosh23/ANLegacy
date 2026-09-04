#import "LTDebugMenuViewController.h"
#import "LTAppDelegate.h"
#import "LTDebugSettings.h"

typedef NS_ENUM(NSInteger, LTDebugSection) {
    LTDebugSectionDisplay = 0,
};

@interface LTDebugMenuViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *nonWideSwitch;
@property (nonatomic, strong) UISwitch *wideSwitch;
@end

@implementation LTDebugMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Debug";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    CGRect bounds = self.view.bounds;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height)
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == LTDebugSectionDisplay) return @"Display";
    return @"";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == LTDebugSectionDisplay) {
        return @"Letterboxes the app and switches the Now Playing layout. Widescreen forces the 4-inch layout, Non-Widescreen forces the 3.5-inch one. All debug settings reset to default when the app is relaunched.";
    }
    return @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == LTDebugSectionDisplay) return 2;
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
    cell.textLabel.textColor = [UIColor blackColor];
    if (indexPath.section == LTDebugSectionDisplay && indexPath.row == 0) {
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