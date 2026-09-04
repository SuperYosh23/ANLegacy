#import "LTLocalPlaylistDetailViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTYouTubeClient.h"
#import "LTMediaCell.h"
#import "LTCustomActionSheet.h"
#import "LTGraphics.h"
#import "LTSpinnerView.h"
#import "LTLog.h"

#define kHeaderHeight 96.0f
#define kArtworkSize 80.0f
#define kButtonHeight 36.0f

@interface LTLocalPlaylistDetailViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, LTCustomActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) LTLocalPlaylist *playlist;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *artworkImageView;
@property (nonatomic, strong) UILabel *playlistNameLabel;
@property (nonatomic, strong) UILabel *trackCountLabel;
@property (nonatomic, strong) UIButton *playAllButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UIButton *renameButton;
@property (nonatomic, strong) LTSpinnerView *downloadSpinner;
@property (nonatomic, assign) NSInteger downloadFailures;
@property (nonatomic, assign) NSInteger pendingRemoveRow;
@property (nonatomic, assign) BOOL playlistFullyDownloaded;
@property (nonatomic, strong) UIAlertView *renameAlert;
@end

@implementation LTLocalPlaylistDetailViewController

- (id)initWithPlaylist:(LTLocalPlaylist *)playlist {
    self = [super init];
    if (self) {
        _playlist = playlist;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = self.playlist.name;
    self.view.backgroundColor = [UIColor whiteColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)]) {
        self.tableView.separatorInset = UIEdgeInsetsMake(0, 60, 0, 0);
    }
    [self.view addSubview:self.tableView];

    [self buildHeaderView];
    [self refreshHeader];
    [self loadArtwork];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(trackDidChange:)
                                                 name:LTPlaylistTrackDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadProgress:)
                                                 name:LTPlaylistDownloadProgressNotification
                                               object:nil];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Header

- (void)buildHeaderView {
    CGFloat w = self.view.bounds.size.width;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, kHeaderHeight)];
    container.backgroundColor = [UIColor whiteColor];

    CGFloat pad = 12.0f;

    // Artwork (left side, square)
    _artworkImageView = [[UIImageView alloc] initWithFrame:CGRectMake(pad, pad, kArtworkSize, kArtworkSize)];
    _artworkImageView.backgroundColor = [UIColor colorWithWhite:0.92f alpha:1.0f];
    _artworkImageView.contentMode = UIViewContentModeScaleAspectFill;
    _artworkImageView.clipsToBounds = YES;
    _artworkImageView.layer.cornerRadius = 6.0f;
    _artworkImageView.userInteractionEnabled = YES;
    UITapGestureRecognizer *artTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(artworkTapped:)];
    [_artworkImageView addGestureRecognizer:artTap];
    [container addSubview:_artworkImageView];

    CGFloat textX = pad + kArtworkSize + 10.0f;
    CGFloat textW = w - textX - pad;
    CGFloat y = pad;

    // Playlist name
    _playlistNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, y, textW, 20)];
    _playlistNameLabel.font = [UIFont boldSystemFontOfSize:16];
    _playlistNameLabel.text = self.playlist.name;
    [container addSubview:_playlistNameLabel];

    y += 22.0f;

    // Track count
    _trackCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, y, textW, 16)];
    _trackCountLabel.font = [UIFont systemFontOfSize:12];
    _trackCountLabel.textColor = [UIColor grayColor];
    [container addSubview:_trackCountLabel];

    y += 20.0f;

    // Buttons row (next to artwork, left aligned like the playlist name)
    CGFloat btnY = y + 4.0f;
    CGFloat smallGap = 6.0f;
    CGFloat smallBtn = 34.0f;
    CGFloat smallH = 32.0f;

    _playAllButton = [self headerButtonWithIcon:[LTGraphics playIcon] frame:CGRectMake(textX, btnY, smallBtn, smallH)];
    [_playAllButton addTarget:self action:@selector(playAllTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_playAllButton];

    _shuffleButton = [self headerButtonWithIcon:[LTGraphics shuffleIcon] frame:CGRectMake(textX + (smallBtn + smallGap), btnY, smallBtn, smallH)];
    [_shuffleButton addTarget:self action:@selector(shuffleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_shuffleButton];

    _downloadButton = [self headerButtonWithIcon:[LTGraphics downloadIcon] frame:CGRectMake(textX + (smallBtn + smallGap) * 2, btnY, smallBtn, smallH)];
    [_downloadButton addTarget:self action:@selector(downloadTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_downloadButton];

    _renameButton = [self headerButtonWithIcon:[LTGraphics renameIcon] frame:CGRectMake(textX + (smallBtn + smallGap) * 3, btnY, smallBtn, smallH)];
    [_renameButton addTarget:self action:@selector(renamePlaylistTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_renameButton];

    // Download spinner
    _downloadSpinner = [[LTSpinnerView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
    _downloadSpinner.center = CGPointMake(textX + smallBtn / 2.0f, btnY + smallH / 2.0f);
    _downloadSpinner.hidesWhenStopped = YES;
    _downloadSpinner.hidden = YES;
    [container addSubview:_downloadSpinner];

    self.tableView.tableHeaderView = container;
}

- (UIButton *)headerButtonWithIcon:(UIImage *)icon frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = frame;
    [button setImage:[self scaledIcon:icon] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
    button.layer.cornerRadius = 6.0f;
    button.clipsToBounds = YES;
    return button;
}

- (UIImage *)scaledIcon:(UIImage *)image {
    if (!image) return nil;
    CGSize target = CGSizeMake(22.0f, 22.0f);
    UIGraphicsBeginImageContextWithOptions(target, NO, image.scale);
    CGFloat scale = MIN(target.width / image.size.width, target.height / image.size.height);
    CGFloat dw = image.size.width * scale;
    CGFloat dh = image.size.height * scale;
    CGRect rect = CGRectMake((target.width - dw) / 2.0f, (target.height - dh) / 2.0f, dw, dh);
    [image drawInRect:rect];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled;
}

- (void)refreshHeader {
    NSUInteger count = self.playlist.tracks.count;
    self.trackCountLabel.text = [NSString stringWithFormat:@"%lu track%@",
                                 (unsigned long)count, count == 1 ? @"" : @"s"];

    BOOL hasTracks = count > 0;
    self.playAllButton.enabled = hasTracks;
    self.shuffleButton.enabled = hasTracks;
    self.downloadButton.enabled = hasTracks;
    self.playAllButton.alpha = hasTracks ? 1.0f : 0.4f;
    self.shuffleButton.alpha = hasTracks ? 1.0f : 0.4f;
    self.downloadButton.alpha = hasTracks ? 1.0f : 0.4f;

    BOOL fullyDownloaded = hasTracks;
    if (fullyDownloaded) {
        LTPlaylistStore *store = [LTPlaylistStore sharedStore];
        for (LTTrack *track in self.playlist.tracks) {
            if (![store isTrackDownloaded:track]) { fullyDownloaded = NO; break; }
        }
    }
    self.playlistFullyDownloaded = fullyDownloaded;
    [self.downloadButton setImage:[self scaledIcon:fullyDownloaded ? [LTGraphics checkmarkIcon] : [LTGraphics downloadIcon]]
                        forState:UIControlStateNormal];
}

- (void)loadArtwork {
    // Custom cover takes priority
    if (self.playlist.coverPath.length) {
        UIImage *cover = [UIImage imageWithContentsOfFile:self.playlist.coverPath];
        if (cover) {
            self.artworkImageView.image = cover;
            return;
        }
    }
    // Fall back to first track thumbnail
    if (self.playlist.tracks.count > 0) {
        LTTrack *first = self.playlist.tracks[0];
        if (first.thumbnailURL.length) {
            __weak typeof(self) weakSelf = self;
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
            [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                weakSelf.artworkImageView.image = image;
            }];
        }
    }
}

#pragma mark - Actions

- (void)artworkTapped:(id)sender {
    LTCustomActionSheet *sheet = [[LTCustomActionSheet alloc] initWithTitle:@"Playlist Cover"
                                                              buttonTitles:@[@"Choose from Library", @"Remove Cover"]
                                                           destructiveIndex:1];
    sheet.delegate = self;
    [sheet show];
}

- (void)playAllTapped:(id)sender {
    if (!self.playlist.tracks.count) return;
    [LTPlayerController sharedController].queueSourceName = self.playlist.name;
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks atIndex:0];
    [LTPlayerController sharedController].repeatMode = LTRepeatModeAll;
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)shuffleTapped:(id)sender {
    if (!self.playlist.tracks.count) return;
    [LTPlayerController sharedController].queueSourceName = self.playlist.name;
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks shuffle:YES];
    [LTPlayerController sharedController].repeatMode = LTRepeatModeAll;
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (void)downloadTapped:(id)sender {
    if ([[LTPlaylistStore sharedStore] isDownloading]) return;

    BOOL allDownloaded = self.playlistFullyDownloaded;
    if (allDownloaded) {
        NSInteger count = self.playlist.tracks.count;
        self.pendingRemoveRow = -1;
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove Downloads"
                                                        message:[NSString stringWithFormat:@"Remove all %d downloaded track%@ from this playlist? They will no longer be available offline.", (int)count, count == 1 ? @"" : @"s"]
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Remove", nil];
        alert.tag = 951;
        [alert show];
        return;
    }

    NSMutableArray *missing = [NSMutableArray array];
    for (LTTrack *track in self.playlist.tracks) {
        if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
            [missing addObject:track];
        }
    }
    if (!missing.count) {
        return;
    }
    LTLog(@"PLAYLIST download %d tracks", (int)missing.count);
    self.downloadFailures = 0;
    [self setDownloadingUI:YES];
    [[LTPlaylistStore sharedStore] downloadTracks:missing completion:^{
        [self setDownloadingUI:NO];
        if (self.downloadFailures > 0) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Download Failed"
                                                            message:[NSString stringWithFormat:@"%d track(s) could not be downloaded.\nCheck your connection and try again.", (int)self.downloadFailures]
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        }
    }];
}

- (void)renamePlaylistTapped:(id)sender {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Rename Playlist"
                                                    message:nil
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Save", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.text = self.playlist.name;
    field.placeholder = @"Playlist name";
    self.renameAlert = alert;
    [alert show];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 950 && buttonIndex == 1) {
        NSInteger row = self.pendingRemoveRow;
        self.pendingRemoveRow = -1;
        if (row >= 0 && row < (NSInteger)self.playlist.tracks.count) {
            LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)row];
            LTLog(@"ROW remove download %@ title=%@", track.videoId, track.title);
            [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[track]];
        }
        return;
    }
    if (alertView.tag == 951 && buttonIndex == 1) {
        LTLog(@"PLAYLIST remove all downloads count=%lu", (unsigned long)self.playlist.tracks.count);
        [[LTPlaylistStore sharedStore] removeDownloadsForTracks:self.playlist.tracks];
        return;
    }
    if (alertView == self.renameAlert && buttonIndex == 1) {
        UITextField *field = [alertView textFieldAtIndex:0];
        NSString *name = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) {
            [[LTPlaylistStore sharedStore] renamePlaylist:self.playlist name:name];
            self.title = name;
            self.playlistNameLabel.text = name;
        }
    }
}

- (void)customActionSheet:(id)sheet tappedButtonAtIndex:(NSInteger)index {
    if (index == 0) {
        // Choose from Library - use native picker
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.delegate = self;
            picker.allowsEditing = YES;
            [self presentViewController:picker animated:YES completion:nil];
        }
    } else if (index == 1) {
        // Remove Cover
        [[LTPlaylistStore sharedStore] setCoverImage:nil forPlaylist:self.playlist];
        [self loadArtwork];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
    if (!image) image = [info objectForKey:UIImagePickerControllerOriginalImage];
    if (image) {
        [[LTPlaylistStore sharedStore] setCoverImage:image forPlaylist:self.playlist];
        [self loadArtwork];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)setDownloadingUI:(BOOL)downloading {
    if (downloading) {
        self.downloadButton.hidden = YES;
        self.renameButton.hidden = YES;
        [self.downloadSpinner startAnimating];
    } else {
        [self.downloadSpinner stopAnimating];
        self.downloadButton.hidden = NO;
        self.renameButton.hidden = NO;
        [self refreshHeader];
        [self.tableView reloadData];
    }
}

#pragma mark - Notifications

- (void)storeDidChange:(NSNotification *)notification {
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)trackDidChange:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)downloadProgress:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    NSString *status = info[@"status"];
    if ([status isEqualToString:@"error"]) {
        self.downloadFailures += 1;
    }
    NSInteger index = [info[@"index"] integerValue];
    NSInteger total = [info[@"total"] integerValue];
    if (total > 0 && index < total) {
        self.trackCountLabel.text = [NSString stringWithFormat:@"Downloading %d of %d...", (int)index + 1, (int)total];
    } else {
        [self refreshHeader];
    }
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.playlist.tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTPlaylistTrackCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%d. %@", (int)indexPath.row + 1, track.title];

    NSMutableString *detail = [NSMutableString string];
    if (track.artist.length) [detail appendString:track.artist];
    if (track.duration > 0) {
        if (detail.length) [detail appendString:@"   "];
        [detail appendString:[self formatDuration:track.duration]];
    }
    cell.detailTextLabel.text = detail;
    if (track.thumbnailURL.length) {
        [cell setImageFromURL:track.thumbnailURL];
    } else {
        cell.imageView.image = nil;
        [[LTPlaylistStore sharedStore] resolveThumbnailForTrack:track completion:^(NSString *thumbnailURL) {
            if (thumbnailURL.length) {
                [cell setImageFromURL:thumbnailURL];
            }
        }];
    }
    if ([[LTPlaylistStore sharedStore] isTrackDownloading:track]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self rowSpinnerForRow:indexPath.row];
    } else if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self rowRemoveButtonForRow:indexPath.row];
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self rowDownloadButtonForRow:indexPath.row];
    }
    return cell;
}

- (UIView *)rowSpinnerForRow:(NSInteger)row {
    LTSpinnerView *spinner = [[LTSpinnerView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
    [spinner startAnimating];
    return spinner;
}

- (UIButton *)rowRemoveButtonForRow:(NSInteger)row {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 32);
    [button setImage:[self scaledIcon:[LTGraphics checkmarkIcon]] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.tag = row;
    [button addTarget:self action:@selector(rowRemoveTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)rowRemoveTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.playlist.tracks.count) return;
    LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)row];
    if (![[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    self.pendingRemoveRow = row;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Remove Download"
                                                    message:[NSString stringWithFormat:@"Remove \"%@\" from your offline downloads?", track.title]
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Remove", nil];
    alert.tag = 950;
    [alert show];
}

- (UIButton *)rowDownloadButtonForRow:(NSInteger)row {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 40, 32);
    [button setImage:[self scaledIcon:[LTGraphics downloadIcon]] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.tag = row;
    [button addTarget:self action:@selector(rowDownloadTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)rowDownloadTapped:(id)sender {
    UIButton *button = (UIButton *)sender;
    NSInteger row = button.tag;
    if (row < 0 || row >= (NSInteger)self.playlist.tracks.count) return;
    if ([[LTPlaylistStore sharedStore] isDownloading]) return;
    LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)row];
    if ([[LTPlaylistStore sharedStore] isTrackDownloaded:track]) return;
    LTLog(@"ROW download %@ title=%@", track.videoId, track.title);
    self.downloadFailures = 0;
    [[LTPlaylistStore sharedStore] downloadTracks:@[track] completion:^{
        if (self.downloadFailures > 0) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Download Failed"
                                                            message:@"That track could not be downloaded.\nCheck your connection and try again."
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        }
    }];
}

- (NSString *)formatDuration:(NSTimeInterval)duration {
    NSInteger seconds = (NSInteger)duration;
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 54.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [LTPlayerController sharedController].queueSourceName = self.playlist.name;
    [[LTPlayerController sharedController] playQueue:self.playlist.tracks atIndex:indexPath.row];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        LTTrack *track = [self.playlist.tracks objectAtIndex:(NSUInteger)indexPath.row];
        LTLog(@"PLAYLIST remove track %@ title=%@", track.videoId, track.title);
        [[LTPlaylistStore sharedStore] removeTrackAtIndex:indexPath.row fromPlaylist:self.playlist];
    }
}

@end
