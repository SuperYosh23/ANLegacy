#import "LTPlaylistPicker.h"
#import "LTLog.h"
#import <objc/runtime.h>

static LTPlaylistPicker *activePicker = nil;

@interface LTPlaylistPicker ()
@property (nonatomic, copy) void (^onPicked)(LTLocalPlaylist *playlist);
@property (nonatomic, copy) void (^onCreateNew)(NSString *name);
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UIScrollView *rowsView;
@end

@implementation LTPlaylistPicker

+ (void)presentFromViewController:(UIViewController *)viewController
                       panelTitle:(NSString *)panelTitle
                        onPicked:(void (^)(LTLocalPlaylist *playlist))picked
                     onCreateNew:(void (^)(NSString *name))createNew {
    if (activePicker) return;
    LTPlaylistPicker *picker = [[LTPlaylistPicker alloc] init];
    picker.onPicked = picked;
    picker.onCreateNew = createNew;

    UIViewController *host = viewController;
    while (host.parentViewController) host = host.parentViewController;
    [host addChildViewController:picker];
    [host.view addSubview:picker.view];
    [picker didMoveToParentViewController:host];

    picker.view.frame = host.view.bounds;
    [picker buildPanelWithTitle:panelTitle];
    picker.view.alpha = 0.0f;
    [UIView animateWithDuration:0.18 animations:^{ picker.view.alpha = 1.0f; }];
}

- (void)buildPanelWithTitle:(NSString *)title {
    CGRect bounds = self.view.bounds;
    CGFloat screenH = bounds.size.height;

    UIView *dim = [[UIView alloc] initWithFrame:bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.45f];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [dim addGestureRecognizer:tap];
    [self.view addSubview:dim];

    NSArray *playlists = [[LTPlaylistStore sharedStore] playlists];
    CGFloat panelWidth = MIN(300.0f, bounds.size.width - 24.0f);
    CGFloat listHeight = (playlists.count + 1) * 44.0f;
    CGFloat maxList = screenH * 0.5f;
    if (listHeight > maxList) listHeight = maxList;
    CGFloat panelHeight = 54.0f + listHeight + 48.0f;

    self.panelView = [[UIView alloc] initWithFrame:CGRectMake((bounds.size.width - panelWidth) / 2.0f,
                                                              screenH - panelHeight - 12.0f,
                                                              panelWidth, panelHeight)];
    self.panelView.backgroundColor = [UIColor colorWithWhite:0.11f alpha:1.0f];
    self.panelView.layer.cornerRadius = 12.0f;
    self.panelView.clipsToBounds = YES;
    self.panelView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                      UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.panelView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 8, panelWidth - 16, 18)];
    titleLabel.text = @"Add to Playlist";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.backgroundColor = [UIColor clearColor];
    [self.panelView addSubview:titleLabel];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 28, panelWidth - 24, 16)];
    subtitle.text = title.length ? title : @"";
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.45f];
    subtitle.font = [UIFont systemFontOfSize:12];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
    subtitle.backgroundColor = [UIColor clearColor];
    [self.panelView addSubview:subtitle];

    self.rowsView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 54, panelWidth, listHeight)];
    self.rowsView.showsVerticalScrollIndicator = YES;
    self.rowsView.alwaysBounceVertical = YES;
    self.rowsView.backgroundColor = [UIColor clearColor];
    [self.panelView addSubview:self.rowsView];

    CGFloat y = 0;
    __weak LTPlaylistPicker *weakSelf = self;
    y = [self addRowWithTitle:@"+ New Playlist…"
                       accent:YES
                      yOffset:y
                        block:^{ [weakSelf promptForName]; }];
    for (LTLocalPlaylist *playlist in playlists) {
        y = [weakSelf addRowWithTitle:playlist.name playlist:playlist yOffset:y];
    }
    self.rowsView.contentSize = CGSizeMake(panelWidth, y);

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 54 + listHeight, panelWidth, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08f];
    sep.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.panelView addSubview:sep];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake(0, 54 + listHeight + 1, panelWidth, 47);
    cancel.backgroundColor = [UIColor colorWithWhite:0.16f alpha:1.0f];
    cancel.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    cancel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.panelView addSubview:cancel];
}

- (CGFloat)addRowWithTitle:(NSString *)title
                  playlist:(LTLocalPlaylist *)playlist
                   yOffset:(CGFloat)y {
    __weak LTPlaylistPicker *weakSelf = self;
    return [self addRowWithTitle:title accent:NO yOffset:y block:^{
        LTPlaylistPicker *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.onPicked) strongSelf.onPicked(playlist);
        [strongSelf dismiss];
    }];
}

- (CGFloat)addRowWithTitle:(NSString *)title
                    accent:(BOOL)accent
                   yOffset:(CGFloat)y
                     block:(void (^)(void))block {
    CGFloat width = self.rowsView.bounds.size.width;
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, y, width, 44);
    row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    row.titleEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    row.titleLabel.font = [UIFont systemFontOfSize:15];
    row.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [row setTitleColor:(accent ? [UIColor colorWithRed:0.35f green:0.65f blue:1.0f alpha:1.0f]
                               : [UIColor whiteColor])
              forState:UIControlStateNormal];
    [row setTitle:title forState:UIControlStateNormal];
    [row addTarget:self action:@selector(rowTouchDown:) forControlEvents:UIControlEventTouchDown];
    [row addTarget:self action:@selector(rowTouchUp:) forControlEvents:UIControlEventTouchUpInside |
         UIControlEventTouchUpOutside];
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(row, "block", block, OBJC_ASSOCIATION_COPY_NONATOMIC);

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, y + 43, width, 0.5)];
    line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06f];
    [self.rowsView addSubview:line];
    [self.rowsView addSubview:row];
    return y + 44;
}

- (void)rowTouchDown:(UIButton *)sender {
    sender.backgroundColor = [UIColor colorWithWhite:1 alpha:0.09f];
}

- (void)rowTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.12 animations:^{ sender.backgroundColor = [UIColor clearColor]; }];
}

- (void)rowTapped:(UIButton *)sender {
    void (^block)(void) = objc_getAssociatedObject(sender, "block");
    if (block) block();
}

- (void)dismiss {
    [UIView animateWithDuration:0.15 animations:^{ self.view.alpha = 0.0f; }
                     completion:^(BOOL finished) {
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
        activePicker = nil;
    }];
}

#pragma mark - New playlist name prompt

- (void)promptForName {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"New Playlist"
                                                    message:@"Enter a name for the playlist."
                                                   delegate:self
                                         cancelButtonTitle:@"Cancel"
                                         otherButtonTitles:@"Create", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        NSString *name = [[alertView textFieldAtIndex:0] text];
        if (name.length && self.onCreateNew) {
            self.onCreateNew(name);
            [self dismiss];
        }
    }
}

@end
