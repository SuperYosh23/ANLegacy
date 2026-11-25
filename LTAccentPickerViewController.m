#import "LTAccentPickerViewController.h"
#import "LTTraitCompat.h"
#import "LTTheme.h"
#import "LTThemedTableView.h"
#import <objc/message.h>

@interface LTAccentPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation LTAccentPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Accent Color";
    self.view.backgroundColor = [LTTheme groupedBackground];

    self.tableView = [[LTThemedTableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.view addSubview:self.tableView];
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme groupedBackground];
    self.tableView.backgroundColor = [LTTheme groupedBackground];
    [self.tableView reloadData];
}

#pragma mark - Swatch

// A small colour chip shown on the right of each row. layer.cornerRadius is
// guarded because this screen also runs on iOS 4/5, where CALayer exists but
// is not something to assume without checking.
- (UIView *)swatchForIndex:(NSInteger)index {
    UIView *chip = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 20.0f, 20.0f)];
    chip.backgroundColor = [LTTheme accentSwatchForPresetIndex:index];
    chip.opaque = YES;
    chip.userInteractionEnabled = NO;
    if ([chip respondsToSelector:@selector(layer)]) {
        id layer = [chip performSelector:@selector(layer)];
        if ([layer respondsToSelector:@selector(setCornerRadius:)]) {
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(layer, @selector(setCornerRadius:), 10.0f);
        }
        if ([layer respondsToSelector:@selector(setBorderWidth:)] &&
            [layer respondsToSelector:@selector(setBorderColor:)]) {
            ((void (*)(id, SEL, CGFloat))objc_msgSend)(layer, @selector(setBorderWidth:), 1.0f);
            UIColor *border = [LTTheme separator];
            if ([border respondsToSelector:@selector(CGColor)]) {
                CGColorRef borderColor = ((CGColorRef (*)(id, SEL))objc_msgSend)(border, @selector(CGColor));
                ((void (*)(id, SEL, CGColorRef))objc_msgSend)(layer, @selector(setBorderColor:), borderColor);
            }
        }
    }
    return chip;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[LTTheme accentPresetNames] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"The accent colours buttons, switches, icons and highlights in every theme. Theme Default keeps the colour built into the selected theme.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTAccentCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellId];
    }
    cell.textLabel.textColor = [LTTheme text];
    cell.backgroundColor = [LTTheme cellBackground];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    NSString *name = [[LTTheme accentPresetNames] objectAtIndex:indexPath.row];
    BOOL selected = ([LTTheme accentPresetIndex] == indexPath.row);
    cell.textLabel.text = selected ? [NSString stringWithFormat:@"\u2713  %@", name] : name;
    cell.textLabel.font = selected ? [UIFont boldSystemFontOfSize:16.0f] : [UIFont systemFontOfSize:16.0f];
    cell.accessoryView = [self swatchForIndex:indexPath.row];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == [LTTheme accentPresetIndex]) return;

    // Pop first, then change: the accent rebuilds the UI in the same way a
    // theme change does, so this screen should not be part of what is rebuilt.
    [self.navigationController popViewControllerAnimated:YES];
    [LTTheme setAccentPresetIndex:indexPath.row];
}

@end
