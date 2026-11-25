#import "LTHapticStrengthViewController.h"
#import "LTTraitCompat.h"
#import "LTHaptics.h"
#import "LTTheme.h"
#import "LTThemedTableView.h"

@interface LTHapticStrengthViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation LTHapticStrengthViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = @"Haptic Strength";
    self.view.backgroundColor = [LTTheme groupedBackground];

    self.tableView = [[LTThemedTableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
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

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme groupedBackground];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return LTHapticStrengthCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Controls how hard the vibration motor taps on transport keys, the iPod click wheel, and menu presses.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTHapticStrengthCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
    }
    // Rows are the enum ordinals: the enum runs weakest-first from 0, which is
    // also the order you want to read them in.
    LTHapticStrength strength = (LTHapticStrength)indexPath.row;
    cell.textLabel.textColor = [LTTheme text];
    cell.textLabel.text = [LTHaptics labelForStrength:strength];
    cell.accessoryType = ([LTHaptics strength] == strength) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [LTHaptics setStrength:(LTHapticStrength)indexPath.row];
    [tableView reloadData];
    // Fire the new strength immediately so the choice is felt, not guessed at.
    [LTHaptics pulse];
}

@end
