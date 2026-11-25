#import "LTStationDetailViewController.h"
#import "LTTraitCompat.h"
#import "LTSeedSearchViewController.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTYouTubeClient.h"
#import "LTCustomActionSheet.h"
#import "LTGraphics.h"
#import "LTTheme.h"
#import "LTThemedTableView.h"
#import "LTLog.h"
#import "LTMediaCell.h"

#define kHeaderHeight 240.0f
#define kArtworkSize 120.0f
#define kButtonHeight 40.0f

@interface LTStationDetailViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, LTCustomActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, LTSeedSearchViewControllerDelegate>
@property (nonatomic, strong) LTStation *station;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *artworkImageView;
@property (nonatomic, strong) UILabel *stationNameLabel;
@property (nonatomic, strong) UILabel *seedCountLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *renameButton;
@property (nonatomic, strong) UIButton *addSeedButton;
@property (nonatomic, strong) UIAlertView *renameAlert;
@end

@implementation LTStationDetailViewController

- (id)initWithStation:(LTStation *)station {
    self = [super init];
    if (self) {
        _station = station;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = self.station.name;
    self.view.backgroundColor = [LTTheme background];

    [self buildHeaderView];
    [self refreshHeader];
    [self loadArtwork];

    CGFloat headerH = kHeaderHeight;
    self.tableView = [[LTThemedTableView alloc] initWithFrame:CGRectMake(0, headerH, self.view.bounds.size.width, self.view.bounds.size.height - headerH) style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme background];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)traitCollectionDidChange:(id)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.view.backgroundColor = [LTTheme background];
    self.tableView.backgroundColor = [LTTheme background];
    self.tableView.tableHeaderView.backgroundColor = [LTTheme background];
    self.artworkImageView.backgroundColor = [LTTheme placeholder];
    self.seedCountLabel.textColor = [LTTheme secondaryText];
    UIColor *fill = [LTTheme fill];
    self.playButton.backgroundColor = fill;
    self.renameButton.backgroundColor = fill;
    self.addSeedButton.backgroundColor = fill;
    [self.tableView reloadData];
}

#pragma mark - Header

- (void)buildHeaderView {
    CGFloat w = self.view.bounds.size.width;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, kHeaderHeight)];
    container.backgroundColor = [LTTheme background];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:container];

    CGFloat centerX = w / 2.0f;
    
    // Artwork (centered at top)
    _artworkImageView = [[UIImageView alloc] initWithFrame:CGRectMake(centerX - kArtworkSize/2, 16, kArtworkSize, kArtworkSize)];
    _artworkImageView.backgroundColor = [LTTheme placeholder];
    _artworkImageView.contentMode = UIViewContentModeScaleAspectFill;
    _artworkImageView.clipsToBounds = YES;
    _artworkImageView.layer.cornerRadius = 8.0f;
    _artworkImageView.userInteractionEnabled = YES;
    UITapGestureRecognizer *artTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(artworkTapped:)];
    [_artworkImageView addGestureRecognizer:artTap];
    [container addSubview:_artworkImageView];

    CGFloat y = 16 + kArtworkSize + 12.0f;

    // Station name (centered)
    _stationNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 24)];
    _stationNameLabel.font = [UIFont boldSystemFontOfSize:18];
    _stationNameLabel.textColor = [LTTheme text];
    _stationNameLabel.textAlignment = NSTextAlignmentCenter;
    _stationNameLabel.text = self.station.name;
    [container addSubview:_stationNameLabel];

    y += 28.0f;

    // Seed count (centered)
    _seedCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 18)];
    _seedCountLabel.font = [UIFont systemFontOfSize:13];
    _seedCountLabel.textColor = [LTTheme secondaryText];
    _seedCountLabel.textAlignment = NSTextAlignmentCenter;
    [container addSubview:_seedCountLabel];

    y += 24.0f;

    // Buttons row (centered)
    CGFloat btnWidth = 92.0f;
    CGFloat btnHeight = 36.0f;
    CGFloat gap = 12.0f;
    CGFloat totalWidth = (btnWidth * 3) + (gap * 2);
    CGFloat startX = centerX - totalWidth / 2.0f;

    _playButton = [self headerButtonWithIcon:[LTGraphics playIcon] frame:CGRectMake(startX, y, btnWidth, btnHeight)];
    [_playButton setTitle:@"Play" forState:UIControlStateNormal];
    [_playButton addTarget:self action:@selector(playTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_playButton];

    _renameButton = [self headerButtonWithIcon:[LTGraphics renameIcon] frame:CGRectMake(startX + btnWidth + gap, y, btnWidth, btnHeight)];
    [_renameButton setTitle:@"Rename" forState:UIControlStateNormal];
    [_renameButton addTarget:self action:@selector(renameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_renameButton];

    _addSeedButton = [self headerButtonWithIcon:[LTGraphics glyphIcon:'+' size:24 color:[LTGraphics actionIconColor]] frame:CGRectMake(startX + (btnWidth + gap) * 2, y, btnWidth, btnHeight)];
    [_addSeedButton setTitle:@"Add Seed" forState:UIControlStateNormal];
    [_addSeedButton addTarget:self action:@selector(addSeedTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:_addSeedButton];
}

- (UIButton *)headerButtonWithIcon:(UIImage *)icon frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    [button setImage:[self scaledIcon:icon] forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    button.titleLabel.font = [UIFont systemFontOfSize:12];
    [button setTitleColor:[LTTheme text] forState:UIControlStateNormal];
    button.backgroundColor = [LTTheme fill];
    button.layer.cornerRadius = 6.0f;
    button.clipsToBounds = YES;
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 0);
    button.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
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
    NSUInteger count = self.station.seeds.count;
    self.seedCountLabel.text = [NSString stringWithFormat:@"%lu seed%@", (unsigned long)count, count == 1 ? @"" : @"s"];
    self.stationNameLabel.text = self.station.name;
}

- (void)loadArtwork {
    // Custom cover takes priority
    if (self.station.coverPath.length) {
        UIImage *cover = [UIImage imageWithContentsOfFile:self.station.coverPath];
        if (cover) {
            self.artworkImageView.image = cover;
            return;
        }
    }
    
    // Load station.png as base
    NSString *stationPath = [[NSBundle mainBundle] pathForResource:@"station" ofType:@"png"];
    UIImage *stationBase = [UIImage imageWithContentsOfFile:stationPath];
    
    // If no seeds, just show station.png
    if (self.station.seeds.count == 0) {
        self.artworkImageView.image = stationBase ?: [LTGraphics musicIcon];
        return;
    }
    
    // Get first seed thumbnail and overlay on station.png
    LTStationSeed *seed = [self.station.seeds objectAtIndex:0];
    if (seed.thumbnailURL.length) {
        // Strong capture: the detail screen can be popped while the artwork is
        // still loading, and the completion must not touch a freed controller.
        NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:seed.thumbnailURL];
        [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *seedImage) {
            if (!seedImage) {
                self.artworkImageView.image = stationBase ?: [LTGraphics musicIcon];
                return;
            }
            
            // Create composite image: station.png with seed image overlaying the green area
            CGSize size = CGSizeMake(kArtworkSize, kArtworkSize);
            UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
            
            // Draw station.png scaled to fit
            if (stationBase) {
                [stationBase drawInRect:CGRectMake(0, 0, size.width, size.height)];
            }
            
            // Draw seed image in the center (replacing green area) with circular clipping
            // Green circle in 512x512 image is at 108x109+263+238
            // Scaled to 120px: ~25x26 at position ~62,56
            CGFloat insetX = 62.0f;
            CGFloat insetY = 56.0f;
            CGFloat overlayWidth = 25.0f;
            CGFloat overlayHeight = 26.0f;
            CGRect seedRect = CGRectMake(insetX, insetY, overlayWidth, overlayHeight);
            
            // Create circular path for clipping
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSaveGState(context);
            UIBezierPath *circlePath = [UIBezierPath bezierPathWithOvalInRect:seedRect];
            [circlePath addClip];
            
            [seedImage drawInRect:seedRect];
            
            CGContextRestoreGState(context);
            
            UIImage *composite = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            self.artworkImageView.image = composite;
        }];
    } else {
        self.artworkImageView.image = stationBase ?: [LTGraphics musicIcon];
    }
}

#pragma mark - Actions

- (void)artworkTapped:(id)sender {
    LTCustomActionSheet *sheet = [[LTCustomActionSheet alloc] initWithTitle:@"Station Cover"
                                                              buttonTitles:@[@"Choose from Library", @"Remove Cover"]
                                                           destructiveIndex:1];
    sheet.delegate = self;
    [sheet show];
}

- (void)playTapped:(id)sender {
    if (!self.station.seeds.count) return;
    
    UIAlertView *loading = [[UIAlertView alloc] initWithTitle:@"Loading Station"
                                                     message:@"Fetching music..."
                                                    delegate:nil
                                          cancelButtonTitle:nil
                                          otherButtonTitles:nil];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.center = CGPointMake(140.0, 80.0);
    [spinner startAnimating];
    [loading addSubview:spinner];
    [loading show];
#if !__has_feature(objc_arc)
    [spinner release];
#endif

    void (^finish)(void) = ^{
        [loading dismissWithClickedButtonIndex:0 animated:YES];
#if !__has_feature(objc_arc)
        [loading release];
#endif
    };

    // Special case: single artist seed - play catalog directly.
    // Resolve browseId from the artist name if it is missing (e.g. stations
    // created before browseId was persisted, or added from a track result).
    if (self.station.seeds.count == 1) {
        LTStationSeed *seed = [self.station.seeds objectAtIndex:0];
        if ([seed.type isEqualToString:@"artist"] && seed.artist.length) {
            void (^playCatalog)(NSString *) = ^(NSString *resolvedBrowseId) {
                if (resolvedBrowseId.length) {
                    seed.browseId = resolvedBrowseId;
                    [[LTPlaylistStore sharedStore] saveStations];
                    [[LTYouTubeClient sharedClient] browseArtist:resolvedBrowseId
                                                  completion:^(NSDictionary *info, NSArray *topSongs, NSArray *allSongs, NSArray *albums, NSError *error) {
                        if (allSongs.count) {
                            [[LTPlayerController sharedController] playQueue:allSongs shuffle:YES];
                            LTPlayerController *pc = [LTPlayerController sharedController];
                            pc.radioEnabled = YES;
                            LTTrack *firstSeed = [allSongs objectAtIndex:0];
                            if (firstSeed.videoId.length) pc.radioSeedVideoId = firstSeed.videoId;
                            pc.queueSourceName = self.station.name;
                            [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:pc];
                            [pc extendRadio];
                        } else {
                            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Songs"
                                                                             message:@"Could not find songs for this artist."
                                                                            delegate:nil
                                                                   cancelButtonTitle:@"OK"
                                                                   otherButtonTitles:nil];
                            [alert show];
                        }
                        finish();
                        [(LTTabBarController *)self.tabBarController showNowPlaying];
                    } avatarURL:nil];
                } else {
                    // Fallback to name-based radio
                    [[LTYouTubeClient sharedClient] fetchRadioForArtist:seed.artist completion:^(NSArray *tracks, NSError *error) {
                        if (tracks.count) {
                            [[LTPlayerController sharedController] playQueue:tracks shuffle:NO];
                            LTPlayerController *pc = [LTPlayerController sharedController];
                            pc.radioEnabled = YES;
                            pc.queueSourceName = self.station.name;
                            [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:pc];
                        } else {
                            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Music"
                                                                             message:@"Could not find any music for this station."
                                                                            delegate:nil
                                                                   cancelButtonTitle:@"OK"
                                                                   otherButtonTitles:nil];
                            [alert show];
                        }
                        finish();
                        [(LTTabBarController *)self.tabBarController showNowPlaying];
                    }];
                }
            };
            if (seed.browseId.length) {
                playCatalog(seed.browseId);
            } else {
                [[LTYouTubeClient sharedClient] resolveArtistBrowseId:seed.artist completion:playCatalog];
            }
            return;
        }
    }

    // Multi-seed or track-based: use recommendation algorithm
    NSMutableArray *allRecommendations = [NSMutableArray array];
    __block NSInteger completedSeeds = 0;
    NSInteger totalSeeds = self.station.seeds.count;
    
    void (^checkComplete)(void) = ^{
        completedSeeds++;
        if (completedSeeds >= totalSeeds) {
            // All seeds processed, shuffle and play
            if (allRecommendations.count > 0) {
                // Shuffle the recommendations
                for (NSInteger i = allRecommendations.count - 1; i > 0; i--) {
                    NSInteger j = arc4random_uniform((uint32_t)(i + 1));
                    [allRecommendations exchangeObjectAtIndex:i withObjectAtIndex:j];
                }
                [[LTPlayerController sharedController] playQueue:allRecommendations shuffle:NO];
                LTPlayerController *pc = [LTPlayerController sharedController];
                pc.radioEnabled = YES;
                LTTrack *firstRec = [allRecommendations objectAtIndex:0];
                if (firstRec.videoId.length) pc.radioSeedVideoId = firstRec.videoId;
                pc.queueSourceName = self.station.name;
                [pc extendRadio];
                [[NSNotificationCenter defaultCenter] postNotificationName:LTPlayerStateDidChangeNotification object:pc];
            } else {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Music"
                                                                 message:@"Could not find any music for this station."
                                                                delegate:nil
                                                       cancelButtonTitle:@"OK"
                                                       otherButtonTitles:nil];
                [alert show];
            }
            finish();
            [(LTTabBarController *)self.tabBarController showNowPlaying];
        }
    };
    
    for (LTStationSeed *seed in self.station.seeds) {
        if ([seed.type isEqualToString:@"track"] && seed.videoId.length) {
            LTTrack *t = [[LTTrack alloc] init];
            t.videoId = seed.videoId;
            t.title = seed.title;
            t.artist = seed.artist;
            t.album = seed.album;
            t.thumbnailURL = seed.thumbnailURL;
            [[LTYouTubeClient sharedClient] fetchRadioForTrack:t completion:^(NSArray *tracks, NSError *error) {
                if (tracks.count) {
                    @synchronized(allRecommendations) {
                        [allRecommendations addObjectsFromArray:tracks];
                    }
                }
                checkComplete();
            }];
#if !__has_feature(objc_arc)
            [t release];
#endif
        } else if ([seed.type isEqualToString:@"artist"] && seed.artist.length) {
            if (seed.browseId.length) {
                // Get artist's songs, then get radio from multiple songs for diversity
                [[LTYouTubeClient sharedClient] browseArtist:seed.browseId
                                                  completion:^(NSDictionary *info, NSArray *topSongs, NSArray *allSongs, NSArray *albums, NSError *error) {
                    if (allSongs.count > 0) {
                        // Get recommendations from up to 3 different songs
                        NSInteger songsToUse = MIN(3, allSongs.count);
                        __block NSInteger completedRadios = 0;
                        
                        for (NSInteger i = 0; i < songsToUse; i++) {
                            LTTrack *song = [allSongs objectAtIndex:(NSUInteger)i];
                            [[LTYouTubeClient sharedClient] fetchRadioForTrack:song completion:^(NSArray *tracks, NSError *error) {
                                if (tracks.count) {
                                    @synchronized(allRecommendations) {
                                        [allRecommendations addObjectsFromArray:tracks];
                                    }
                                }
                                completedRadios++;
                                if (completedRadios >= songsToUse) {
                                    checkComplete();
                                }
                            }];
                        }
                    } else {
                        checkComplete();
                    }
                } avatarURL:nil];
            } else {
                // Fallback to name-based radio
                [[LTYouTubeClient sharedClient] fetchRadioForArtist:seed.artist completion:^(NSArray *tracks, NSError *error) {
                    if (tracks.count) {
                        @synchronized(allRecommendations) {
                            [allRecommendations addObjectsFromArray:tracks];
                        }
                    }
                    checkComplete();
                }];
            }
        } else if ([seed.type isEqualToString:@"album"] && seed.album.length) {
            if (seed.browseId.length) {
                // Get album tracks, then get radio from multiple songs for diversity
                [[LTYouTubeClient sharedClient] browseAlbum:seed.browseId
                                                completion:^(NSDictionary *info, NSArray *tracks, NSError *error) {
                    if (tracks.count > 0) {
                        // Get recommendations from up to 3 different songs
                        NSInteger songsToUse = MIN(3, tracks.count);
                        __block NSInteger completedRadios = 0;
                        
                        for (NSInteger i = 0; i < songsToUse; i++) {
                            LTTrack *song = [tracks objectAtIndex:(NSUInteger)i];
                            [[LTYouTubeClient sharedClient] fetchRadioForTrack:song completion:^(NSArray *radioTracks, NSError *error) {
                                if (radioTracks.count) {
                                    @synchronized(allRecommendations) {
                                        [allRecommendations addObjectsFromArray:radioTracks];
                                    }
                                }
                                completedRadios++;
                                if (completedRadios >= songsToUse) {
                                    checkComplete();
                                }
                            }];
                        }
                    } else {
                        checkComplete();
                    }
                }];
            } else if (seed.artist.length) {
                // Fallback to artist-based radio
                [[LTYouTubeClient sharedClient] fetchRadioForArtist:seed.artist completion:^(NSArray *tracks, NSError *error) {
                    if (tracks.count) {
                        @synchronized(allRecommendations) {
                            [allRecommendations addObjectsFromArray:tracks];
                        }
                    }
                    checkComplete();
                }];
            } else {
                checkComplete();
            }
        } else {
            checkComplete();
        }
    }
}

- (void)renameTapped:(id)sender {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Rename Station"
                                                    message:nil
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Save", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.text = self.station.name;
    field.placeholder = @"Station name";
    self.renameAlert = alert;
    [alert show];
}

- (void)addSeedTapped:(id)sender {
    LTCustomActionSheet *sheet = [[LTCustomActionSheet alloc] initWithTitle:@"Add Seed"
                                                              buttonTitles:@[@"Add Song", @"Add Artist", @"Add Album"]
                                                           destructiveIndex:-1];
    sheet.delegate = self;
    sheet.tag = 1000;
    [sheet show];
}

#pragma mark - LTSeedSearchViewControllerDelegate

- (void)seedSearchViewController:(LTSeedSearchViewController *)controller didSelectSeed:(LTStationSeed *)seed {
    [self.station.seeds addObject:seed];
    [[LTPlaylistStore sharedStore] saveStations];
    [self refreshHeader];
    [self.tableView reloadData];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView == self.renameAlert && buttonIndex == 1) {
        UITextField *field = [alertView textFieldAtIndex:0];
        NSString *name = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) {
            [[LTPlaylistStore sharedStore] renameStation:self.station name:name];
            self.title = name;
            self.stationNameLabel.text = name;
        }
    }
}

#pragma mark - LTCustomActionSheetDelegate

- (void)customActionSheet:(id)sheet tappedButtonAtIndex:(NSInteger)index {
    if ([sheet isKindOfClass:[LTCustomActionSheet class]] && [sheet tag] == 1000) {
        // Add seed action sheet
        NSString *seedType = nil;
        if (index == 0) {
            seedType = @"track";
        } else if (index == 1) {
            seedType = @"artist";
        } else if (index == 2) {
            seedType = @"album";
        }
        
        if (seedType) {
            LTSeedSearchViewController *searchVC = [[LTSeedSearchViewController alloc] initWithSeedType:seedType];
            searchVC.delegate = self;
            [self.navigationController pushViewController:searchVC animated:YES];
        }
        return;
    }
    
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
        [[LTPlaylistStore sharedStore] setCoverImage:nil forStation:self.station];
        [self loadArtwork];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
    if (!image) image = [info objectForKey:UIImagePickerControllerOriginalImage];
    if (image) {
        [[LTPlaylistStore sharedStore] setCoverImage:image forStation:self.station];
        [self loadArtwork];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Notifications

- (void)storeDidChange:(NSNotification *)notification {
    [self refreshHeader];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.station.seeds.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTStationSeedCell";
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
    }
    
    LTStationSeed *seed = [self.station.seeds objectAtIndex:(NSUInteger)indexPath.row];
    
    if ([seed.type isEqualToString:@"track"]) {
        cell.textLabel.text = seed.title.length ? seed.title : seed.videoId;
        cell.detailTextLabel.text = seed.artist.length ? seed.artist : @"Song";
        [cell setImageFromURL:seed.thumbnailURL];
    } else if ([seed.type isEqualToString:@"artist"]) {
        cell.textLabel.text = seed.artist;
        cell.detailTextLabel.text = @"Artist";
        [cell setImageFromURL:seed.thumbnailURL];
    } else if ([seed.type isEqualToString:@"album"]) {
        cell.textLabel.text = seed.album;
        cell.detailTextLabel.text = seed.artist.length ? seed.artist : @"Album";
        [cell setImageFromURL:seed.thumbnailURL];
    } else {
        cell.textLabel.text = @"Unknown";
        cell.detailTextLabel.text = @"";
        cell.imageView.image = nil;
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 54.0f;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self.station.seeds removeObjectAtIndex:(NSUInteger)indexPath.row];
        [[LTPlaylistStore sharedStore] saveStations];
        [self refreshHeader];
        [self.tableView reloadData];
    }
}

@end
