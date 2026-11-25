#import "LTPlaylistPicker.h"
#import "LTTransitionSettings.h"
#import "LTLog.h"
#import "LTSafeArea.h"
#import <objc/runtime.h>
#import "LTTheme.h"
#import "LTGraphics.h"
#import "LTYouTubeClient.h"

static LTPlaylistPicker *activePicker = nil;

@interface LTPlaylistPicker ()
@property (nonatomic, copy) void (^onPicked)(LTLocalPlaylist *playlist);
@property (nonatomic, copy) void (^onCreateNew)(NSString *name);
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UIScrollView *rowsView;
- (CGFloat)addRowWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                      accent:(BOOL)accent
                       cover:(UIImage *)cover
                     yOffset:(CGFloat)y
                       block:(void (^)(void))block;
@end

#import <QuartzCore/QuartzCore.h>
@implementation LTPlaylistPicker

+ (void)presentFromViewController:(UIViewController *)viewController
                       panelTitle:(NSString *)panelTitle
                        onPicked:(void (^)(LTLocalPlaylist *playlist))picked
                     onCreateNew:(void (^)(NSString *name))createNew {
    if (activePicker) return;
    LTPlaylistPicker *picker = [[LTPlaylistPicker alloc] init];
    // Keep the picker alive for the whole panel lifetime. On iOS 5+ the parent
    // controller also retains it, but on iOS 4 there is no containment, so the
    // static is the only owner and without it the row buttons target a freed
    // object.
    activePicker = picker;
    picker.onPicked = picked;
    picker.onCreateNew = createNew;

    UIViewController *host = viewController;
    while (host.parentViewController) host = host.parentViewController;
    // UIViewController containment is iOS 5+. On iOS 4 the picker only needs to
    // be a view subview: adding the view still loads it and sends its lifecycle
    // callbacks, so skip the containment calls the old runtime does not have.
    BOOL canContain = [host respondsToSelector:@selector(addChildViewController:)]
        && [picker respondsToSelector:@selector(didMoveToParentViewController:)];
    if (canContain) [host addChildViewController:picker];
    [host.view addSubview:picker.view];
    if (canContain) [picker didMoveToParentViewController:host];

    picker.view.frame = host.view.bounds;
    [picker buildPanelWithTitle:panelTitle];
    picker.view.alpha = 0.0f;
    [LTTransitionSettings animateWithDuration:0.18f animations:^{ picker.view.alpha = 1.0f; }];
}

- (void)buildPanelWithTitle:(NSString *)title {
    CGRect bounds = self.view.bounds;
    CGFloat screenH = bounds.size.height;

    UIView *dim = [[UIView alloc] initWithFrame:bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0.0f alpha:[LTTheme isDark] ? 0.6f : 0.45f];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [dim addGestureRecognizer:tap];
    [self.view addSubview:dim];

    NSArray *playlists = [[LTPlaylistStore sharedStore] playlists];
    CGFloat panelWidth = MIN(340.0f, bounds.size.width - 24.0f);
    CGFloat rowHeight = 56.0f;
    CGFloat listHeight = (playlists.count + 1) * rowHeight;
    CGFloat maxList = screenH * 0.5f;
    if (listHeight > maxList) listHeight = maxList;
    CGFloat headerHeight = 62.0f;
    CGFloat panelHeight = headerHeight + listHeight + 52.0f;

    // Overlay sits above the home indicator on notched devices.
    CGFloat bottomInset = LTSafeAreaInsets(self.view.superview ?: self.view).bottom;
    self.panelView = [[UIView alloc] initWithFrame:CGRectMake((bounds.size.width - panelWidth) / 2.0f,
                                                               screenH - panelHeight - 12.0f - bottomInset,
                                                               panelWidth, panelHeight)];
    // A Material 3 dialog: a raised surface, a generous corner radius, and no
    // shadow of its own - the scrim does the separating.
    self.panelView.backgroundColor = [LTTheme cellBackground];
    self.panelView.layer.cornerRadius = [LTTheme isModern] ? 24.0f : [LTTheme largeCornerRadius];
    self.panelView.clipsToBounds = YES;
    self.panelView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                       UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.panelView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, panelWidth - 32, 22)];
    titleLabel.text = @"Add to Playlist";
    titleLabel.textColor = [LTTheme text];
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.backgroundColor = [UIColor clearColor];
    [self.panelView addSubview:titleLabel];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, panelWidth - 32, 16)];
    subtitle.text = title.length ? title : @"";
    subtitle.textColor = [LTTheme secondaryText];
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.lineBreakMode = NSLineBreakByTruncatingTail;
    subtitle.backgroundColor = [UIColor clearColor];
    [self.panelView addSubview:subtitle];

    self.rowsView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, headerHeight, panelWidth, listHeight)];
    self.rowsView.showsVerticalScrollIndicator = YES;
    self.rowsView.alwaysBounceVertical = YES;
    self.rowsView.backgroundColor = [UIColor clearColor];
    [self.panelView addSubview:self.rowsView];

    CGFloat y = 0;
    __unsafe_unretained LTPlaylistPicker *weakSelf = self;
    y = [self addRowWithTitle:@"New Playlist"
                    subtitle:@"Create a new one"
                       accent:YES
                        cover:nil
                      yOffset:y
                        block:^{ [weakSelf promptForName]; }];
    for (LTLocalPlaylist *playlist in playlists) {
        // A stable copy of the loop variable: the block outlives this
        // iteration, and the for-in variable is the same one every time.
        LTLocalPlaylist *item = playlist;
        y = [self addRowWithTitle:item.name
                         subtitle:[self detailTextForPlaylist:item]
                            accent:NO
                             cover:[self coverImageForPlaylist:item]
                           yOffset:y
                             block:^{
            LTPlaylistPicker *strongSelf = weakSelf;
            if (!strongSelf) return;
            if (strongSelf.onPicked) strongSelf.onPicked(item);
            [strongSelf dismiss];
        }];
    }
    self.rowsView.contentSize = CGSizeMake(panelWidth, y);

    // Cancel, as a text button in the accent colour rather than a filled bar.
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake(0, headerHeight + listHeight, panelWidth, 52);
    cancel.backgroundColor = [UIColor clearColor];
    cancel.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [cancel setTitleColor:[LTTheme accent] forState:UIControlStateNormal];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    cancel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    [self.panelView addSubview:cancel];
}

// "12 songs" under a playlist's name.
- (NSString *)detailTextForPlaylist:(LTLocalPlaylist *)playlist {
    NSUInteger count = playlist.tracks.count;
    if (count == 0) return @"Empty";
    if (count == 1) return @"1 song";
    return [NSString stringWithFormat:@"%lu songs", (unsigned long)count];
}

// The playlist's own cover, or the first track's artwork, or nothing.
- (UIImage *)coverImageForPlaylist:(LTLocalPlaylist *)playlist {
    if (playlist.coverPath.length) {
        UIImage *cover = [UIImage imageWithContentsOfFile:playlist.coverPath];
        if (cover) return cover;
    }
    for (LTTrack *track in playlist.tracks) {
        if (!track.thumbnailURL.length) continue;
        UIImage *art = [[LTYouTubeClient sharedClient] cachedArtworkForURL:track.thumbnailURL];
        if (art) return art;
    }
    return nil;
}

- (CGFloat)addRowWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                      accent:(BOOL)accent
                       cover:(UIImage *)cover
                     yOffset:(CGFloat)y
                       block:(void (^)(void))block {
    CGFloat width = self.rowsView.bounds.size.width;
    CGFloat rowHeight = 56.0f;
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, y, width, rowHeight);
    row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    row.titleEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    row.titleLabel.font = [UIFont systemFontOfSize:15];
    row.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [row setTitleColor:(accent ? [LTTheme accent] : [LTTheme text])
               forState:UIControlStateNormal];
    [row setTitle:title forState:UIControlStateNormal];
    [row addTarget:self action:@selector(rowTouchDown:) forControlEvents:UIControlEventTouchDown];
    [row addTarget:self action:@selector(rowTouchUp:) forControlEvents:UIControlEventTouchUpInside |
         UIControlEventTouchUpOutside];
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(row, "block", block, OBJC_ASSOCIATION_COPY_NONATOMIC);

    // The cover, in a rounded square at the row's leading edge. It goes on the
    // row rather than on the scroll view: added to the scroll view, its
    // row-relative frame put every playlist's cover in the same place, piled
    // on top of each other.
    CGFloat coverSize = 40.0f;
    CGFloat coverX = 16.0f;
    CGFloat coverY = (rowHeight - coverSize) / 2.0f;
    UIView *coverBox = [[UIView alloc] initWithFrame:CGRectMake(coverX, coverY, coverSize, coverSize)];
    coverBox.userInteractionEnabled = NO;
    coverBox.backgroundColor = [LTTheme fill];
    coverBox.layer.cornerRadius = 10.0f;
    coverBox.clipsToBounds = YES;
    if (cover) {
        UIImageView *image = [[UIImageView alloc] initWithFrame:coverBox.bounds];
        image.image = cover;
        image.contentMode = UIViewContentModeScaleAspectFill;
        [coverBox addSubview:image];
    } else {
        // A music note for a playlist with no artwork of its own.
        UIImageView *note = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 20, 20)];
        note.image = [LTGraphics musicIcon];
        note.contentMode = UIViewContentModeScaleAspectFit;
        [coverBox addSubview:note];
    }
    [row addSubview:coverBox];

    // The title and its detail line, to the right of the cover.
    CGFloat textX = coverX + coverSize + 12.0f;
    CGFloat textW = width - textX - 16.0f;
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(textX, 12, textW, 20)];
    name.text = title;
    name.font = [UIFont systemFontOfSize:15];
    name.textColor = accent ? [LTTheme accent] : [LTTheme text];
    name.backgroundColor = [UIColor clearColor];
    name.lineBreakMode = NSLineBreakByTruncatingTail;
    [row addSubview:name];

    if (subtitle.length) {
        UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(textX, 31, textW, 16)];
        detail.text = subtitle;
        detail.font = [UIFont systemFontOfSize:12];
        detail.textColor = [LTTheme secondaryText];
        detail.backgroundColor = [UIColor clearColor];
        detail.lineBreakMode = NSLineBreakByTruncatingTail;
        [row addSubview:detail];
    }

    // The row's own title is hidden; the label above draws it in our position.
    [row setTitle:@"" forState:UIControlStateNormal];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(textX, rowHeight - 0.5f, width - textX - 8.0f, 0.5f)];
    line.backgroundColor = [LTTheme separator];
    line.userInteractionEnabled = NO;
    [self.rowsView addSubview:line];
    [self.rowsView addSubview:row];
    return y + rowHeight;
}

- (void)rowTouchDown:(UIButton *)sender {
    sender.backgroundColor = [LTTheme fill];
}

- (void)rowTouchUp:(UIButton *)sender {
    [LTTransitionSettings animateWithDuration:0.12f animations:^{ sender.backgroundColor = [UIColor clearColor]; }];
}

- (void)rowTapped:(UIButton *)sender {
    void (^block)(void) = objc_getAssociatedObject(sender, "block");
    if (block) block();
}

- (void)dismiss {
    [LTTransitionSettings animateWithDuration:0.15f animations:^{ self.view.alpha = 0.0f; }
                     completion:^(BOOL finished) {
        BOOL contained = [self respondsToSelector:@selector(willMoveToParentViewController:)]
            && [self respondsToSelector:@selector(removeFromParentViewController)];
        if (contained) [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        if (contained) [self removeFromParentViewController];
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
