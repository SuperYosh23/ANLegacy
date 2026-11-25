#import "LTThemePickerViewController.h"
#import "LTTraitCompat.h"
#import "LTTheme.h"
#import "LTThemedTableView.h"
#import <objc/message.h>

// The palette swatch is drawn with plain UIViews and guarded layer calls so the
// same picker code is safe on the old OS versions the app still supports.
static void LTRoundChip(UIView *view, CGFloat radius) {
    if (![view respondsToSelector:@selector(layer)]) return;
    id layer = [view performSelector:@selector(layer)];
    if ([layer respondsToSelector:@selector(setCornerRadius:)]) {
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(layer, @selector(setCornerRadius:), radius);
    }
    if ([layer respondsToSelector:@selector(setMasksToBounds:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, @selector(setMasksToBounds:), YES);
    }
}

@interface LTThemePickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation LTThemePickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Theme";
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"The swatch shows each theme's background, text and accent colour. Accent Color appears in Appearance when a Modern theme is selected.";
}

// A little three-band chip: the theme's background, its text colour, and its
// accent. It makes the difference between the looks obvious at a glance.
- (UIView *)paletteChipForTheme:(LTThemeStyle)theme {
    UIView *chip = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 44.0f, 22.0f)];
    chip.backgroundColor = [LTTheme backgroundForTheme:theme];
    chip.opaque = YES;
    chip.userInteractionEnabled = NO;
    LTRoundChip(chip, 6.0f);

    UIView *textBand = [[UIView alloc] initWithFrame:CGRectMake(4.0f, 4.0f, 36.0f, 5.0f)];
    textBand.backgroundColor = [LTTheme textForTheme:theme];
    textBand.opaque = YES;
    [chip addSubview:textBand];

    UIView *accentBand = [[UIView alloc] initWithFrame:CGRectMake(4.0f, 13.0f, 36.0f, 5.0f)];
    accentBand.backgroundColor = [LTTheme accentForTheme:theme];
    accentBand.opaque = YES;
    LTRoundChip(accentBand, 2.5f);
    [chip addSubview:accentBand];

    // A hairline keeps a light chip visible against a light cell.
    if ([chip respondsToSelector:@selector(layer)]) {
        id layer = [chip performSelector:@selector(layer)];
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTThemeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellId];
    }
    cell.textLabel.textColor = [LTTheme text];
    cell.backgroundColor = [LTTheme cellBackground];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    LTThemeStyle theme = (LTThemeStyle)indexPath.row;
    BOOL selected = ([LTTheme currentTheme] == theme);
    cell.textLabel.text = selected
        ? [NSString stringWithFormat:@"\u2713  %@", [LTTheme nameForTheme:theme]]
        : [LTTheme nameForTheme:theme];
    cell.textLabel.font = selected ? [UIFont boldSystemFontOfSize:16.0f] : [UIFont systemFontOfSize:16.0f];
    cell.accessoryView = [self paletteChipForTheme:theme];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LTThemeStyle theme = (LTThemeStyle)indexPath.row;
    if (theme == [LTTheme currentTheme]) return;

    // The notification makes the app rebuild its UI with the new theme. The
    // picker is popped first so it is not part of what gets rebuilt.
    [self.navigationController popViewControllerAnimated:YES];
    [LTTheme setCurrentTheme:theme];
}

@end
