#import "LTOneHandedModeViewController.h"
#import "LTOneHandedMode.h"
#import "LTAppDelegate.h"
#import "LTTheme.h"

@interface LTOneHandedModeViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation LTOneHandedModeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"One-Handed Mode";
    self.view.backgroundColor = [LTTheme groupedBackground];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme groupedBackground];
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Shrinks the app to the classic screen size and pins it to a bottom corner so it is easier to reach with one hand.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTOneHandedCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
    }
    LTOneHandedCorner mode = (LTOneHandedCorner)indexPath.row;
    cell.textLabel.textColor = [LTTheme text];
    cell.textLabel.text = [LTOneHandedMode labelForMode:mode];
    cell.accessoryType = ([LTOneHandedMode mode] == mode) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [LTOneHandedMode setMode:(LTOneHandedCorner)indexPath.row];
    [tableView reloadData];
    [LTAppDelegate applyDisplayModeAnimated:YES];
}

@end
