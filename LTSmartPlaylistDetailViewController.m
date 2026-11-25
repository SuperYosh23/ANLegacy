#import "LTSmartPlaylistDetailViewController.h"
#import "LTPlaylistStore.h"
#import "LTYouTubeClient.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTMediaCell.h"
#import "LTSpinnerView.h"
#import "LTTheme.h"
#import "LTLog.h"
#import "LTThemedTableView.h"

#define kHeaderHeight 104.0f

@interface LTSmartPlaylistDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *smartName;
@property (nonatomic, assign) NSInteger smartIndex;
@property (nonatomic, strong) NSArray *tracks;       // fetched recommendations
@property (nonatomic, strong) NSArray *seedTracks;   // seeds used
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *trackCountLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *saveBtn;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation LTSmartPlaylistDetailViewController

- (id)initWithSmartIndex:(NSInteger)index name:(NSString *)name {
    if ((self = [super init])) {
        _smartIndex = index;
        _smartName = name;
        _tracks = [NSArray array];
        _seedTracks = [NSArray array];
    }
    return self;
}

- (id)initWithName:(NSString *)name tracks:(NSArray *)tracks {
    if ((self = [super init])) {
        _smartName = name;
        _smartIndex = -1;
        _tracks = [NSArray array];
        _seedTracks = tracks ?: [NSArray array];
        // map legacy name to index
        NSArray *names = [LTSmartPlaylistDetailViewController smartPlaylistNames];
        _smartIndex = [names indexOfObject:name];
        if (_smartIndex == NSNotFound) _smartIndex = 0;
    }
    return self;
}

+ (NSArray *)smartPlaylistNames {
    return @[@"For You Mix", @"Top Artists Mix", @"Fresh Picks"];
}

+ (NSString *)smartPlaylistDescriptionForIndex:(NSInteger)index {
    if (index == 0) return @"Radio from your most-played songs";
    if (index == 1) return @"Radio from your top artists";
    return @"New finds from what you played recently";
}

- (NSArray *)seedTracksForIndex:(NSInteger)index {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    if (index == 0) {
        NSArray *seeds = [store topPlayedTracks:5];
        if (!seeds.count) seeds = [store recentTracks];
        return seeds ?: [NSArray array];
    }
    if (index == 2) {
        NSArray *seeds = [store recentlyPlayedTracks:8];
        if (!seeds.count) seeds = [store topPlayedTracks:5];
        return seeds ?: [NSArray array];
    }
    // index 1 is artist-based, handled separately
    return [NSArray array];
}

- (NSArray *)artistNamesForIndex:(NSInteger)index {
    if (index != 1) return [NSArray array];
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSArray *artists = [store topArtists];
    NSMutableArray *names = [NSMutableArray array];
    for (id row in artists) {
        if ((NSInteger)names.count >= 3) break;
        if ([row isKindOfClass:[NSDictionary class]]) {
            NSString *n = [(NSDictionary *)row objectForKey:@"name"];
            if (n.length && ![n isEqualToString:@"Unknown Artist"]) [names addObject:n];
        }
    }
    return names ?: [NSArray array];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.smartName;
    self.view.backgroundColor = [LTTheme background];

    self.tableView = [[LTThemedTableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [LTTheme background];
    [self.view addSubview:self.tableView];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width, kHeaderHeight)];
    header.backgroundColor = [LTTheme background];

    UILabel *count = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, self.view.bounds.size.width-24, 18)];
    count.font = [UIFont systemFontOfSize:13];
    count.textColor = [LTTheme secondaryText];
    count.text = @"Finding songs like yours…";
    [header addSubview:count];
    self.trackCountLabel = count;

    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(12, 28, self.view.bounds.size.width-24, 16)];
    detail.font = [UIFont systemFontOfSize:11];
    detail.textColor = [LTTheme secondaryText];
    detail.text = [LTSmartPlaylistDetailViewController smartPlaylistDescriptionForIndex:self.smartIndex];
    [header addSubview:detail];
    self.detailLabel = detail;

    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    saveBtn.frame = CGRectMake(12, 50, self.view.bounds.size.width-24, 36);
    [saveBtn setTitle:@"Save to Library" forState:UIControlStateNormal];
    saveBtn.backgroundColor = [LTTheme fill];
    [saveBtn setTitleColor:[LTTheme text] forState:UIControlStateNormal];
    saveBtn.layer.cornerRadius = 6.0f;
    saveBtn.clipsToBounds = YES;
    saveBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [saveBtn addTarget:self action:@selector(saveTapped:) forControlEvents:UIControlEventTouchUpInside];
    saveBtn.enabled = NO;
    saveBtn.alpha = 0.4f;
    [header addSubview:saveBtn];
    self.saveBtn = saveBtn;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.center = CGPointMake(self.view.bounds.size.width/2.0f, self.view.bounds.size.height/2.0f);
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.tableView.tableHeaderView = header;

    [self fetchRecommendations];
}

- (void)shuffleArray:(NSMutableArray *)arr {
    NSUInteger n = [arr count];
    if (n < 2) return;
    for (NSUInteger i = n - 1; i > 0; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)(i+1));
        [arr exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
}

- (NSArray *)dedupedTracks:(NSArray *)tracks excludingVideoIds:(NSSet *)excluded {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    if (excluded) [seen unionSet:excluded];
    for (id obj in tracks) {
        if (![obj isKindOfClass:[LTTrack class]]) continue;
        LTTrack *t = (LTTrack *)obj;
        if (!t.videoId.length) continue;
        if ([seen containsObject:t.videoId]) continue;
        [seen addObject:t.videoId];
        [out addObject:t];
    }
    return out;
}

- (void)fetchRecommendations {
    self.isLoading = YES;
    [self.spinner startAnimating];
    self.trackCountLabel.text = @"Finding songs like yours…";
    self.saveBtn.enabled = NO;
    self.saveBtn.alpha = 0.4f;

    if (self.smartIndex == 1) {
        // Top Artists Mix — artist radio
        NSArray *artistNames = [self artistNamesForIndex:1];
        if (!artistNames.count) {
            [self finishLoadingWithTracks:[self seedTracksForIndex:0] fallback:YES];
            return;
        }
        NSMutableArray *all = [NSMutableArray array];
        __block NSInteger done = 0;
        NSInteger total = [artistNames count];
        // copy for block capture
        NSArray *names = [artistNames copy];
        for (NSString *artistName in names) {
            NSString *an = [artistName copy];
            [[LTYouTubeClient sharedClient] fetchRadioForArtist:an completion:^(NSArray *tracks, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (tracks.count) {
                        @synchronized(all) { [all addObjectsFromArray:tracks]; }
                    }
                    done++;
                    if (done >= total) {
                        NSArray *deduped = [self dedupedTracks:all excludingVideoIds:nil];
                        [self shuffleArray:[deduped mutableCopy]];
                        // re-shuffle properly
                        NSMutableArray *shuffled = [deduped mutableCopy];
                        [self shuffleArray:shuffled];
                        NSArray *final = shuffled;
                        if (final.count > 50) final = [final subarrayWithRange:NSMakeRange(0, 50)];
                        if (final.count) {
                            [self finishLoadingWithTracks:final fallback:NO];
                        } else {
                            [self finishLoadingWithTracks:[self seedTracksForIndex:0] fallback:YES];
                        }
                    }
                });
            }];
        }
        return;
    }

    // Track-seed based (0 and 2)
    NSArray *seeds = [self seedTracksForIndex:self.smartIndex];
    if (!seeds.count) {
        [self finishLoadingWithTracks:[NSArray array] fallback:NO];
        return;
    }
    self.seedTracks = seeds;

    NSSet *excluded = nil;
    if (self.smartIndex == 2) {
        // Fresh Picks: exclude top played + seeds themselves
        NSMutableSet *ex = [NSMutableSet set];
        for (id t in [[LTPlaylistStore sharedStore] topPlayedTracks:30]) {
            if ([t isKindOfClass:[LTTrack class]]) {
                NSString *vid = [(LTTrack *)t videoId];
                if (vid.length) [ex addObject:vid];
            }
        }
        for (id t in seeds) {
            if ([t isKindOfClass:[LTTrack class]]) {
                NSString *vid = [(LTTrack *)t videoId];
                if (vid.length) [ex addObject:vid];
            }
        }
        excluded = ex;
    }

    NSMutableArray *all = [NSMutableArray array];
    __block NSInteger done = 0;
    NSInteger total = [seeds count];
    NSArray *seedsCopy = [seeds copy];
    for (id seedObj in seedsCopy) {
        if (![seedObj isKindOfClass:[LTTrack class]]) {
            done++;
            if (done >= total) {
                // finalize below in final block
            }
            continue;
        }
        LTTrack *seed = (LTTrack *)seedObj;
        [[LTYouTubeClient sharedClient] fetchRadioForTrack:seed completion:^(NSArray *tracks, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (tracks.count) {
                    @synchronized(all) { [all addObjectsFromArray:tracks]; }
                }
                done++;
                if (done >= total) {
                    NSArray *deduped = [self dedupedTracks:all excludingVideoIds:excluded];
                    NSMutableArray *shuffled = [deduped mutableCopy];
                    [self shuffleArray:shuffled];
                    NSArray *final = shuffled;
                    if (final.count > 50) final = [final subarrayWithRange:NSMakeRange(0, 50)];
                    if (final.count) {
                        [self finishLoadingWithTracks:final fallback:NO];
                    } else {
                        // fallback to seeds themselves (history)
                        NSArray *fallback = [self seedTracksForIndex:self.smartIndex];
                        if (!fallback.count) fallback = [[LTPlaylistStore sharedStore] topPlayedTracks:50];
                        [self finishLoadingWithTracks:fallback fallback:YES];
                    }
                }
            });
        }];
    }
    // handle case where seeds contain non-track (should not happen)
    if (total == 0) {
        [self finishLoadingWithTracks:[NSArray array] fallback:NO];
    }
}

- (void)finishLoadingWithTracks:(NSArray *)tracks fallback:(BOOL)fallback {
    self.isLoading = NO;
    [self.spinner stopAnimating];
    self.tracks = tracks ?: [NSArray array];
    if (self.tracks.count) {
        self.trackCountLabel.text = [NSString stringWithFormat:@"%@ • %lu tracks",
                                     fallback ? @"From your history" : @"Recommendations",
                                     (unsigned long)self.tracks.count];
        self.saveBtn.enabled = YES;
        self.saveBtn.alpha = 1.0f;
    } else {
        self.trackCountLabel.text = @"No recommendations yet";
        self.detailLabel.text = @"Listen to some music first — Smart Playlists are built from your history.";
        self.saveBtn.enabled = NO;
        self.saveBtn.alpha = 0.4f;
    }
    [self.tableView reloadData];
    LTLog(@"SMART %@ fetched %lu tracks (fallback=%d)", self.smartName, (unsigned long)self.tracks.count, fallback ? 1 : 0);
}

- (void)saveTapped:(id)sender {
    if (self.tracks.count == 0) return;
    LTLocalPlaylist *pl = [[LTPlaylistStore sharedStore] createPlaylistWithName:self.smartName];
    if (!pl) return;
    for (LTTrack *t in self.tracks) {
        [[LTPlaylistStore sharedStore] addTrack:t toPlaylist:pl];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:[LTPlaylistStore sharedStore]];
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Saved"
                                                message:[NSString stringWithFormat:@"Added %@ to your playlists", self.smartName]
                                               delegate:nil
                                      cancelButtonTitle:@"OK"
                                      otherButtonTitles:nil];
    [a show];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)idx {
    static NSString *CellId = @"SmartTrackCell";
    LTMediaCell *cell = [tv dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [LTTheme secondaryText];
    }
    LTTrack *t = [self.tracks objectAtIndex:(NSUInteger)idx.row];
    cell.textLabel.text = t.title;
    cell.detailTextLabel.text = t.artist;
    [cell setImageFromURL:t.thumbnailURL];
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)idx {
    [tv deselectRowAtIndexPath:idx animated:YES];
    if (!self.tracks.count) return;
    LTPlayerController *pc = [LTPlayerController sharedController];
    pc.queueSourceName = self.smartName;
    [pc playQueue:self.tracks atIndex:idx.row];
    pc.radioEnabled = YES;
    LTTrack *first = [self.tracks objectAtIndex:0];
    if (first.videoId.length) pc.radioSeedVideoId = first.videoId;
    [pc extendRadio];
    [(LTTabBarController *)self.tabBarController showNowPlaying];
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)idx { return 54.0f; }

@end
