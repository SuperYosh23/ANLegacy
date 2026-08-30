#import "LTCoverPickerViewController.h"
#import "LTLog.h"
#import <AssetsLibrary/AssetsLibrary.h>

#define kCellIdentifier @"AlbumCell"
#define kGridCellIdentifier @"PhotoCell"
#define kThumbSize 80.0f
#define kThumbSpacing 2.0f

#pragma mark - Album Model

@interface LTAlbumEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, strong) ALAssetsGroup *group;
@end

@implementation LTAlbumEntry
@end

#pragma mark - Photo Grid (forward declaration)

@interface LTCoverPickerGrid : UIViewController
@property (nonatomic, weak) id<LTCoverPickerDelegate> delegate;
@property (nonatomic, strong) ALAssetsGroup *group;
@end

#pragma mark - Album List

@interface LTCoverPickerAlbumList : UITableViewController
@property (nonatomic, weak) id<LTCoverPickerDelegate> delegate;
@property (nonatomic, strong) ALAssetsLibrary *library;
@property (nonatomic, strong) NSMutableArray *albums;
@end

@implementation LTCoverPickerAlbumList

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Albums";
    self.view.backgroundColor = [UIColor colorWithRed:0.11f green:0.11f blue:0.11f alpha:1.0f];

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(cancelTapped:)];
    self.navigationItem.rightBarButtonItem = cancel;

    self.tableView.separatorColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.tableView.rowHeight = 56.0f;

    self.library = [[ALAssetsLibrary alloc] init];
    self.albums = [NSMutableArray array];
    [self loadAlbums];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)loadAlbums {
    __weak LTCoverPickerAlbumList *weakSelf = self;
    // Photos album
    [self.library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                                usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (!group) return;
        NSString *name = [group valueForProperty:ALAssetsGroupPropertyName];
        NSInteger count = [group numberOfAssets];
        if (count <= 0) return;
        LTAlbumEntry *entry = [[LTAlbumEntry alloc] init];
        entry.name = name;
        entry.count = count;
        entry.group = group;
        [weakSelf.albums addObject:entry];
        [weakSelf.tableView reloadData];
    } failureBlock:^(NSError *error) {
        LTLog(@"COVER PICKER album load error: %@", error);
    }];
}

- (void)cancelTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
    if ([self.delegate respondsToSelector:@selector(coverPickerDidCancel:)]) {
        [self.delegate coverPickerDidCancel:self];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.albums.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kCellIdentifier];
        cell.backgroundColor = [UIColor colorWithRed:0.15f green:0.15f blue:0.15f alpha:1.0f];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        UIView *bg = [[UIView alloc] init];
        bg.backgroundColor = [UIColor colorWithRed:0.25f green:0.25f blue:0.25f alpha:1.0f];
        cell.selectedBackgroundView = bg;
    }
    LTAlbumEntry *entry = [self.albums objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = entry.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%d photos", (int)entry.count];

    // Album thumbnail
    CGImageRef thumb = [entry.group posterImage];
    cell.imageView.image = thumb ? [UIImage imageWithCGImage:thumb] : nil;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LTAlbumEntry *entry = [self.albums objectAtIndex:(NSUInteger)indexPath.row];

    LTCoverPickerGrid *grid = [[LTCoverPickerGrid alloc] init];
    grid.delegate = self.delegate;
    grid.group = entry.group;
    grid.title = entry.name;
    [self.navigationController pushViewController:grid animated:YES];
}

@end

#pragma mark - Photo Grid

@interface LTCoverPickerGrid ()
@property (nonatomic, strong) NSMutableArray *assets;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation LTCoverPickerGrid

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.11f green:0.11f blue:0.11f alpha:1.0f];

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(cancelTapped:)];
    self.navigationItem.rightBarButtonItem = cancel;

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.scrollView];

    self.assets = [NSMutableArray array];
    [self loadPhotos];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.loaded) [self layoutGrid];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)loadPhotos {
    __weak LTCoverPickerGrid *weakSelf = self;
    [self.group enumerateAssetsWithOptions:NSEnumerationReverse
                                usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
        if (!result) return;
        NSString *type = [result valueForProperty:ALAssetPropertyType];
        if (![type isEqualToString:ALAssetTypePhoto]) return;
        [weakSelf.assets addObject:result];
    }];
    self.loaded = YES;
    [self layoutGrid];
}

- (void)layoutGrid {
    CGFloat w = self.view.bounds.size.width;
    CGFloat padding = kThumbSpacing;
    NSInteger cols = (NSInteger)((w - padding) / (kThumbSize + padding));
    if (cols < 1) cols = 1;
    CGFloat totalW = cols * kThumbSize + (cols - 1) * padding;
    CGFloat offsetX = (w - totalW) / 2.0f;

    // Remove old subviews
    for (UIView *v in [self.scrollView subviews]) {
        [v removeFromSuperview];
    }

    NSInteger count = (NSInteger)self.assets.count;
    NSInteger rows = (count + cols - 1) / cols;
    CGFloat contentH = rows * kThumbSize + (rows > 0 ? (rows - 1) * padding : 0) + padding;
    self.scrollView.contentSize = CGSizeMake(w, contentH);

    for (NSInteger i = 0; i < count; i++) {
        ALAsset *asset = [self.assets objectAtIndex:(NSUInteger)i];
        CGImageRef thumbRef = [asset aspectRatioThumbnail];
        if (!thumbRef) continue;

        NSInteger row = i / cols;
        NSInteger col = i % cols;
        CGFloat x = offsetX + col * (kThumbSize + padding);
        CGFloat y = padding + row * (kThumbSize + padding);

        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(x, y, kThumbSize, kThumbSize)];
        iv.image = [UIImage imageWithCGImage:thumbRef];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 4.0f;
        iv.userInteractionEnabled = YES;
        iv.tag = i;

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(photoTapped:)];
        [iv addGestureRecognizer:tap];

        [self.scrollView addSubview:iv];
    }
}

- (void)photoTapped:(UITapGestureRecognizer *)gesture {
    NSInteger idx = gesture.view.tag;
    if (idx < 0 || idx >= (NSInteger)self.assets.count) return;

    ALAsset *asset = [self.assets objectAtIndex:(NSUInteger)idx];
    ALAssetRepresentation *rep = [asset defaultRepresentation];
    if (!rep) return;

    CGImageRef fullRef = [rep fullScreenImage];
    UIImage *fullImage = fullRef ? [UIImage imageWithCGImage:fullRef] : nil;
    if (!fullImage) return;

    [self dismissViewControllerAnimated:YES completion:nil];
    if ([self.delegate respondsToSelector:@selector(coverPicker:didSelectImage:)]) {
        [self.delegate coverPicker:self didSelectImage:fullImage];
    }
}

- (void)cancelTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
    if ([self.delegate respondsToSelector:@selector(coverPickerDidCancel:)]) {
        [self.delegate coverPickerDidCancel:self];
    }
}

@end

#pragma mark - Public Entry Point

@implementation LTCoverPickerViewController

+ (void)presentFromViewController:(UIViewController *)viewController delegate:(id<LTCoverPickerDelegate>)delegate {
    LTCoverPickerAlbumList *albumList = [[LTCoverPickerAlbumList alloc] initWithStyle:UITableViewStylePlain];
    albumList.delegate = delegate;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:albumList];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    nav.navigationBar.translucent = NO;
    nav.navigationBar.barTintColor = [UIColor colorWithRed:0.11f green:0.11f blue:0.11f alpha:1.0f];
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f];
    nav.navigationBar.titleTextAttributes = @{UITextAttributeTextColor: [UIColor whiteColor]};
    [viewController presentViewController:nav animated:YES completion:nil];
}

@end
