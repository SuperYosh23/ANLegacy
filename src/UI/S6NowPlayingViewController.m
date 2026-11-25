#import "S6NowPlayingViewController.h"
#import "S6Player.h"
#import "S6Router.h"
#import "S6Cells.h"
#import "S6Theme.h"
#import "S6Models.h"
#import "S6Catalog.h"
#import "S6SpClient.h"
#import "S6ImageLoader.h"
#import "S6Utils.h"
#import "S6Modern.h"
#import "S6Common.h"
#import "S6Settings.h"
#import <MediaPlayer/MediaPlayer.h>

#pragma mark - Lyrics

@interface S6LyricsViewController : UITableViewController
@property (nonatomic, copy) NSString *trackId;
@property (nonatomic, strong) NSArray *lines;       // NSDictionary {ms, text}
@property (nonatomic) BOOL synced;
@property (nonatomic) NSInteger currentLine;
@property (nonatomic, copy) NSString *message;
- (void)showTrack:(S6Track *)track;
- (void)tick;
@end

@implementation S6LyricsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    // (exact row heights: iOS 11 and newer estimate them, and a line far down would land ~100 points off the middle)
    if ([self.tableView respondsToSelector:@selector(setEstimatedRowHeight:)]) [self.tableView setValue:@0 forKey:@"estimatedRowHeight"];
    self.currentLine = -1;
}

// Room above the first line and below the last one, so that the line being sung can always stand a little above the
// middle (the panel is only ~180 points tall on a 3.5" iPhone)
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat h = self.tableView.bounds.size.height;
    UIEdgeInsets inset = UIEdgeInsetsMake(floorf(h * 0.4f), 0, ceilf(h * 0.6f), 0);
    if (h > 0 && !UIEdgeInsetsEqualToEdgeInsets(inset, self.tableView.contentInset)) {
        self.tableView.contentInset = inset;
        [self scrollToCurrentAnimated:NO];
    }
}

- (void)scrollToCurrentAnimated:(BOOL)animated
{
    UITableView *t = self.tableView;
    if (self.message || self.currentLine < 0 || self.currentLine >= (NSInteger)self.lines.count) {
        [t setContentOffset:CGPointMake(0, -t.contentInset.top) animated:animated];
        return;
    }
    CGRect r = [t rectForRowAtIndexPath:[NSIndexPath indexPathForRow:self.currentLine inSection:0]];
    [t setContentOffset:CGPointMake(0, floorf(CGRectGetMidY(r) - t.bounds.size.height * 0.4f)) animated:animated];
}

- (void)showTrack:(S6Track *)track
{
    if ([track.trackId isEqualToString:self.trackId]) return;
    self.trackId = track.trackId;
    self.lines = [NSArray array];
    self.currentLine = -1;
    self.message = L(@"Loading lyrics…");
    [self.tableView reloadData];
    if (!track.trackId.length || track.isEpisode) { self.message = L(@"No lyrics for this song."); [self.tableView reloadData]; return; }
    NSString *tid = track.trackId;
    [S6SpClient lyricsForTrack:tid completion:^(NSDictionary *json, NSError *error) {
        if (![tid isEqualToString:self.trackId]) return;
        NSDictionary *lyrics = S6Dict([json objectForKey:@"lyrics"]);
        NSMutableArray *lines = [NSMutableArray array];
        for (id l in S6Arr([lyrics objectForKey:@"lines"])) {
            NSDictionary *d = S6Dict(l);
            NSString *words = S6Str([d objectForKey:@"words"]) ?: @"";
            if ([words isEqualToString:@"♪"]) words = @"♪";
            [lines addObject:@{ @"ms": @(S6Int([d objectForKey:@"startTimeMs"])), @"text": [S6Utils displayText:words] ?: @"" }];
        }
        self.synced = [S6Str([lyrics objectForKey:@"syncType"]) isEqualToString:@"LINE_SYNCED"];
        self.lines = lines;
        self.message = lines.count ? nil : (error.code == 404 || !error ? L(@"No lyrics for this song.") : error.localizedDescription);
        [self.tableView reloadData];
        [self scrollToCurrentAnimated:NO];
        [self tick];
    }];
}

- (void)tick
{
    if (!self.synced || !self.lines.count) return;
    NSInteger ms = [S6Player shared].positionMs + 300;
    NSInteger line = -1;
    for (NSUInteger i = 0; i < self.lines.count; i++) {
        if ([self.lines[[i] objectForKey:@"ms"] integerValue] <= ms) line = (NSInteger)i; else break;
    }
    if (line == self.currentLine) return;
    NSInteger old = self.currentLine;
    self.currentLine = line;
    NSMutableArray *rows = [NSMutableArray array];
    if (old >= 0 && old < (NSInteger)self.lines.count) [rows addObject:[NSIndexPath indexPathForRow:old inSection:0]];
    if (line >= 0) [rows addObject:[NSIndexPath indexPathForRow:line inSection:0]];
    [self.tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
    if (!self.tableView.isDragging && !self.tableView.isDecelerating) [self scrollToCurrentAnimated:YES];
}

// (smaller on a 3.5" screen: more of the song fits in the little panel)
- (UIFont *)lineFont
{
    CGFloat size = S6IsPad() ? 24 : ([UIScreen mainScreen].bounds.size.height < 500 ? 17 : 19);
    return [UIFont fontWithName:@"HelveticaNeue-Bold" size:size] ?: [UIFont boldSystemFontOfSize:size];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.message ? 1 : (NSInteger)self.lines.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.message) return 80;
    NSString *text = self.lines[[(NSUInteger)indexPath.row] objectForKey:@"text"];
    CGSize s = [text.length ? text : @" " sizeWithFont:[self lineFont] constrainedToSize:CGSizeMake(tableView.bounds.size.width - 40, 400) lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(s.height) + 12;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"line"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"line"];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [self lineFont];
    if (self.message) {
        cell.textLabel.text = self.message;
        cell.textLabel.textColor = [[S6Theme shared] secondaryTextColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        return cell;
    }
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.text = self.lines[[(NSUInteger)indexPath.row] objectForKey:@"text"];
    BOOL current = indexPath.row == self.currentLine;
    BOOL past = self.synced && indexPath.row < self.currentLine;
    cell.textLabel.textColor = current ? [UIColor whiteColor] : (past ? [UIColor colorWithWhite:1 alpha:0.55] : [UIColor colorWithWhite:1 alpha:self.synced ? 0.3 : 0.85]);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.synced || self.message) return;
    [[S6Player shared] seekToMs:[self.lines[[(NSUInteger)indexPath.row] objectForKey:@"ms"] integerValue]];
}

@end

#pragma mark - Queue

enum { S6QueueNow, S6QueueUser, S6QueueNext, S6QueueSectionCount };

@interface S6QueueViewController ()
@property (nonatomic, strong) NSArray *upcoming;
@property (nonatomic, strong) UIButton *editButton;
- (void)refresh;
@end

@implementation S6QueueViewController

- (instancetype)init
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) self.title = L(@"Queue");
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.tableView.rowHeight = 56;
    [self.tableView registerClass:[S6TrackCell class] forCellReuseIdentifier:@"track"];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 40)];
    self.editButton = [[S6Theme shared] outlineButtonWithTitle:L(@"Edit")];
    self.editButton.frame = CGRectMake(320 - 96, 6, 86, 28);
    self.editButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.editButton addTarget:self action:@selector(toggleEditing) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:self.editButton];
    self.tableView.tableHeaderView = header;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:S6PlayerDidChangeNotification object:nil];
    [self refresh];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)toggleEditing
{
    [self.tableView setEditing:!self.tableView.editing animated:YES];
    [self.editButton setTitle:[(self.tableView.editing ? L(@"Done") : L(@"Edit")) uppercaseString] forState:UIControlStateNormal];
}

- (void)refresh
{
    if (self.tableView.editing) return;   // (the rows stay while they are moved)
    self.upcoming = [[S6Player shared] upcomingTracks:100];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return S6QueueSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    S6Player *p = [S6Player shared];
    if (section == S6QueueNow) return p.currentTrack ? 1 : 0;
    if (section == S6QueueUser) return (NSInteger)p.userQueue.count;
    return (NSInteger)self.upcoming.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (![self tableView:tableView numberOfRowsInSection:section]) return nil;
    NSString *title = section == S6QueueNow ? L(@"Now playing") : section == S6QueueUser ? L(@"Next in queue") :
                      [NSString stringWithFormat:L(@"Next from: %@"), [S6Player shared].contextName ?: @""];
    return S6SectionHeader(title, tableView.bounds.size.width);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [self tableView:tableView numberOfRowsInSection:section] ? 26 : 0;
}

- (S6Track *)trackAt:(NSIndexPath *)ip
{
    S6Player *p = [S6Player shared];
    if (ip.section == S6QueueNow) return p.currentTrack;
    if (ip.section == S6QueueUser) return p.userQueue[(NSUInteger)ip.row];
    return self.upcoming[(NSUInteger)ip.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6TrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"track" forIndexPath:indexPath];
    cell.showsArt = YES;
    [cell showTrack:[self trackAt:indexPath] number:0];
    cell.moreButton.hidden = YES;
    cell.showsReorderControl = YES;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section != S6QueueNow; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section != S6QueueNow; }

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to
{
    // (a song moves within its own part of the queue)
    if (to.section == from.section) return to;
    NSInteger rows = [self tableView:tableView numberOfRowsInSection:from.section];
    return [NSIndexPath indexPathForRow:to.section < from.section ? 0 : MAX(0, rows - 1) inSection:from.section];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to
{
    S6Player *p = [S6Player shared];
    if (from.section == S6QueueUser) [p moveQueueItemFrom:(NSUInteger)from.row to:(NSUInteger)to.row];
    else if (from.section == S6QueueNext) {
        [p moveUpcomingFrom:(NSUInteger)from.row to:(NSUInteger)to.row];
        NSMutableArray *u = [self.upcoming mutableCopy];
        id x = u[(NSUInteger)from.row];
        [u removeObjectAtIndex:(NSUInteger)from.row];
        [u insertObject:x atIndex:(NSUInteger)to.row];
        self.upcoming = u;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    S6Player *p = [S6Player shared];
    if (indexPath.section == S6QueueUser) [p removeFromQueueAtIndex:(NSUInteger)indexPath.row];
    else if (indexPath.section == S6QueueNext) {
        [p removeUpcomingAtIndex:(NSUInteger)indexPath.row];
        NSMutableArray *u = [self.upcoming mutableCopy];
        [u removeObjectAtIndex:(NSUInteger)indexPath.row];
        self.upcoming = u;
    }
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationFade];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath { return L(@"Remove"); }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end

#pragma mark - Now playing

@interface S6NowPlayingViewController ()
@property (nonatomic, strong) UIImageView *backdrop;
@property (nonatomic, strong) UIView *dim;
@property (nonatomic, strong) UIImageView *topBar;
@property (nonatomic, strong) UIImageView *bottomDock;
@property (nonatomic, strong) UIView *artContainer;
@property (nonatomic, strong) S6ImageView *art;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UILabel *contextLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *artistButton;
@property (nonatomic, strong) UIButton *heartButton;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UILabel *formatLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIButton *lyricsButton;
@property (nonatomic, strong) UIButton *queueButton;
@property (nonatomic, strong) UIButton *sleepButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) MPVolumeView *volume;
@property (nonatomic, strong) S6LyricsViewController *lyrics;
@property (nonatomic, strong) S6QueueViewController *queue;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL scrubbing;
@property (nonatomic) BOOL liked;
@property (nonatomic, copy) NSString *shownURI;
@property (nonatomic, copy) NSString *backdropURL;
@end

@implementation S6NowPlayingViewController

- (UIButton *)button:(S6Icon)icon size:(CGFloat)size action:(SEL)action
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:[[S6Theme shared] icon:icon size:size] forState:UIControlStateNormal];
    b.showsTouchWhenHighlighted = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
    l.shadowOffset = CGSizeMake(0, 1);
    [self.view addSubview:l];
    return l;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    S6Theme *theme = [S6Theme shared];
    self.view.backgroundColor = [theme plainBackgroundColor];
    self.backdrop = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backdrop.contentMode = UIViewContentModeScaleAspectFill;
    self.backdrop.clipsToBounds = YES;
    self.backdrop.alpha = 0.35;
    [self.view addSubview:self.backdrop];
    self.dim = [[UIView alloc] initWithFrame:self.view.bounds];
    self.dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    [self.view addSubview:self.dim];

    self.topBar = [[UIImageView alloc] initWithImage:[theme navigationBarImage]];
    self.topBar.userInteractionEnabled = NO;
    [self.view addSubview:self.topBar];

    self.bottomDock = [[UIImageView alloc] initWithImage:[theme playerBarImage]];
    self.bottomDock.userInteractionEnabled = NO;
    [self.view addSubview:self.bottomDock];

    self.artContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.artContainer.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.artContainer];

    self.art = [[S6ImageView alloc] initWithFrame:CGRectZero];
    self.art.contentMode = UIViewContentModeScaleAspectFill;
    self.art.clipsToBounds = YES;
    self.art.maxPixels = 1024;
    self.art.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.artContainer addSubview:self.art];

    // Containment is iOS 5+; on iOS 4 the child views still work as plain
    // subviews, so only call the containment methods the runtime understands.
    BOOL canContain = [self respondsToSelector:@selector(addChildViewController:)]
        && [UIViewController instancesRespondToSelector:@selector(didMoveToParentViewController:)];
    self.lyrics = [[S6LyricsViewController alloc] initWithStyle:UITableViewStylePlain];
    if (canContain) [self addChildViewController:self.lyrics];
    [self.view addSubview:self.lyrics.view];
    if (canContain) [self.lyrics didMoveToParentViewController:self];
    self.queue = [[S6QueueViewController alloc] init];
    if (canContain) [self addChildViewController:self.queue];
    [self.view addSubview:self.queue.view];
    if (canContain) [self.queue didMoveToParentViewController:self];

    self.closeButton = [self button:S6IconChevronDown size:24 action:@selector(close)];
    self.closeButton.accessibilityLabel = L(@"Close");
    self.moreButton = [self button:S6IconMore size:22 action:@selector(more)];
    self.sleepButton = [self button:S6IconMoon size:20 action:@selector(sleepTimer)];
    self.sleepButton.accessibilityLabel = L(@"Sleep timer");
    self.contextLabel = [self label:[theme sectionFont] color:[theme secondaryTextColor]];
    self.contextLabel.numberOfLines = 2;
    self.titleLabel = [self label:[UIFont fontWithName:@"HelveticaNeue-Bold" size:S6IsPad() ? 24 : 19] ?: [UIFont boldSystemFontOfSize:20] color:[UIColor whiteColor]];
    self.artistButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.artistButton.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:S6IsPad() ? 17 : 15] ?: [UIFont systemFontOfSize:16];
    [self.artistButton setTitleColor:[theme secondaryTextColor] forState:UIControlStateNormal];
    [self.artistButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [self.artistButton addTarget:self action:@selector(openArtist) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.artistButton];
    self.heartButton = [self button:S6IconHeart size:24 action:@selector(toggleLike)];
    self.progress = [[UISlider alloc] initWithFrame:CGRectZero];
    [self.progress addTarget:self action:@selector(scrubStarted) forControlEvents:UIControlEventTouchDown];
    [self.progress addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.progress addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.progress];
    self.elapsedLabel = [self label:[UIFont fontWithName:@"HelveticaNeue" size:12] ?: [UIFont systemFontOfSize:12] color:[theme secondaryTextColor]];
    self.elapsedLabel.textAlignment = NSTextAlignmentLeft;
    self.remainingLabel = [self label:[UIFont fontWithName:@"HelveticaNeue" size:12] ?: [UIFont systemFontOfSize:12] color:[theme secondaryTextColor]];
    self.remainingLabel.textAlignment = NSTextAlignmentRight;
    self.formatLabel = [self label:[UIFont fontWithName:@"HelveticaNeue" size:11] ?: [UIFont systemFontOfSize:11] color:[theme tertiaryTextColor]];
    self.playButton = [self button:S6IconPlay size:54 action:@selector(togglePlay)];
    self.previousButton = [self button:S6IconPrevious size:30 action:@selector(previous)];
    self.nextButton = [self button:S6IconNext size:30 action:@selector(next)];
    self.shuffleButton = [self button:S6IconShuffle size:24 action:@selector(toggleShuffle)];
    self.repeatButton = [self button:S6IconRepeat size:24 action:@selector(cycleRepeat)];
    self.lyricsButton = [self button:S6IconLyrics size:24 action:@selector(toggleLyrics)];
    self.queueButton = [self button:S6IconQueue size:24 action:@selector(toggleQueue)];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    self.volume = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    [self.volume setMinimumVolumeSliderImage:[theme sliderTrackImageFilled:YES] forState:UIControlStateNormal];
    [self.volume setMaximumVolumeSliderImage:[theme sliderTrackImageFilled:NO] forState:UIControlStateNormal];
    [self.volume setVolumeThumbImage:[theme sliderThumbImage] forState:UIControlStateNormal];
    [self.view addSubview:self.volume];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update) name:S6PlayerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:S6LibraryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyThemeMode) name:S6SettingsDidChangeNotification object:nil];
    [self applyThemeMode];
    [self update];
}

- (void)applyThemeMode
{
    BOOL classic = [S6Settings classicPlayer];
    S6Theme *theme = [S6Theme shared];
    if (classic) {
        self.view.backgroundColor = [theme backgroundColor];
        self.backdrop.hidden = YES;
        self.dim.hidden = YES;
        self.topBar.hidden = NO;
        self.bottomDock.hidden = NO;

        self.artContainer.layer.shadowColor = [UIColor blackColor].CGColor;
        self.artContainer.layer.shadowOffset = CGSizeMake(0, 4);
        self.artContainer.layer.shadowOpacity = 0.75f;
        self.artContainer.layer.shadowRadius = 8.0f;
        self.artContainer.layer.borderWidth = 1.0f;
        self.artContainer.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;

        [self.closeButton setImage:nil forState:UIControlStateNormal];
        [self.closeButton setBackgroundImage:[theme darkButtonImageHighlighted:NO] forState:UIControlStateNormal];
        [self.closeButton setBackgroundImage:[theme darkButtonImageHighlighted:YES] forState:UIControlStateHighlighted];
        [self.closeButton setTitle:L(@"Done") forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButton.titleLabel.font = [theme boldBodyFont];
        self.closeButton.titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.75];
        self.closeButton.titleLabel.shadowOffset = CGSizeMake(0, -1);

        [self.moreButton setBackgroundImage:[theme darkButtonImageHighlighted:NO] forState:UIControlStateNormal];
        [self.moreButton setBackgroundImage:[theme darkButtonImageHighlighted:YES] forState:UIControlStateHighlighted];
        [self.sleepButton setBackgroundImage:[theme darkButtonImageHighlighted:NO] forState:UIControlStateNormal];
        [self.sleepButton setBackgroundImage:[theme darkButtonImageHighlighted:YES] forState:UIControlStateHighlighted];

        self.contextLabel.font = [theme boldBodyFont];
        self.contextLabel.textColor = [UIColor whiteColor];
        self.contextLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.75];
        self.contextLabel.shadowOffset = CGSizeMake(0, -1);
        self.contextLabel.numberOfLines = 1;

        self.titleLabel.shadowOffset = CGSizeMake(0, -1);
    } else {
        self.view.backgroundColor = [theme plainBackgroundColor];
        self.backdrop.hidden = NO;
        self.dim.hidden = NO;
        self.topBar.hidden = YES;
        self.bottomDock.hidden = YES;

        self.artContainer.layer.shadowOpacity = 0;
        self.artContainer.layer.borderWidth = 0;

        [self.closeButton setTitle:nil forState:UIControlStateNormal];
        [self.closeButton setBackgroundImage:nil forState:UIControlStateNormal];
        [self.closeButton setBackgroundImage:nil forState:UIControlStateHighlighted];
        [self.closeButton setImage:[theme icon:S6IconChevronDown size:24] forState:UIControlStateNormal];

        [self.moreButton setBackgroundImage:nil forState:UIControlStateNormal];
        [self.moreButton setBackgroundImage:nil forState:UIControlStateHighlighted];
        [self.sleepButton setBackgroundImage:nil forState:UIControlStateNormal];
        [self.sleepButton setBackgroundImage:nil forState:UIControlStateHighlighted];

        self.contextLabel.font = [theme sectionFont];
        self.contextLabel.textColor = [theme secondaryTextColor];
        self.contextLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
        self.contextLabel.shadowOffset = CGSizeMake(0, 1);
        self.contextLabel.numberOfLines = 2;

        self.titleLabel.shadowOffset = CGSizeMake(0, 1);
    }
    if (self.isViewLoaded) {
        [self.view setNeedsLayout];
    }
}

- (void)libraryChanged
{
    self.shownURI = nil;
    [self update];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyThemeMode];
    [self.timer invalidate];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self showPanel];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return S6IsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize s = self.view.bounds.size;
    BOOL landscape = s.width > s.height;
    // iOS 6 puts the view under the status bar; from iOS 7 on it lies behind it (hidden here), and iOS 11+ has the notch
    CGFloat top = S6ModernTopInset(self.view, 0);
    if (top < 20 && S6ModernIOS()) top = 20;

    if ([S6Settings classicPlayer]) {
        [self layoutClassicInSize:s top:top landscape:landscape];
    } else {
        [self layoutModernInSize:s top:top landscape:landscape];
    }
}

- (void)layoutModernInSize:(CGSize)s top:(CGFloat)top landscape:(BOOL)landscape
{
    self.topBar.hidden = YES;
    self.bottomDock.hidden = YES;
    self.closeButton.frame = CGRectMake(8, top + 4, 44, 44);
    self.moreButton.frame = CGRectMake(s.width - 52, top + 4, 44, 44);
    self.sleepButton.frame = CGRectMake(s.width - 96, top + 4, 44, 44);
    self.contextLabel.frame = CGRectMake(104, top + 6, s.width - 208, 36);
    CGFloat controlsH = S6IsPad() ? 250 : 210;
    if (landscape && S6IsPad()) {
        // the cover (or lyrics/queue) on the left, everything else on the right
        CGFloat side = MIN(s.height - 120, s.width / 2 - 40);
        CGRect panel = CGRectMake(40, (s.height - side) / 2 + 10, side, side);
        self.artContainer.frame = panel;
        self.lyrics.view.frame = panel;
        self.queue.view.frame = panel;
        CGFloat x = 40 + side + 40, w = s.width - x - 40;
        [self layoutControlsInRect:CGRectMake(x, (s.height - controlsH) / 2, w, controlsH)];
    } else {
        CGFloat side = MIN(s.width - (S6IsPad() ? 140 : 40), s.height - controlsH - 110);
        CGRect panel = CGRectMake((s.width - side) / 2, top + 60, side, side);
        self.artContainer.frame = panel;
        self.lyrics.view.frame = CGRectMake(20, top + 50, s.width - 40, side + 20);
        self.queue.view.frame = CGRectMake(0, top + 50, s.width, side + 20);
        CGFloat w = MIN(s.width - 40, 560);
        [self layoutControlsInRect:CGRectMake((s.width - w) / 2, CGRectGetMaxY(panel) + 18, w, controlsH)];
    }
}

- (void)layoutClassicInSize:(CGSize)s top:(CGFloat)top landscape:(BOOL)landscape
{
    self.topBar.hidden = NO;
    self.bottomDock.hidden = NO;
    CGFloat bottom = S6SafeAreaInsets(self.view).bottom;
    CGFloat barH = 44.0f;
    self.topBar.frame = CGRectMake(0, 0, s.width, top + barH);

    CGFloat doneW = MAX(56.0f, [self.closeButton.titleLabel.text sizeWithFont:[[S6Theme shared] boldBodyFont]].width + 20.0f);
    self.closeButton.frame = CGRectMake(8, top + 7, doneW, 30);
    self.moreButton.frame = CGRectMake(s.width - 40, top + 7, 32, 30);
    self.sleepButton.frame = CGRectMake(s.width - 78, top + 7, 32, 30);
    CGFloat titleLeft = CGRectGetMaxX(self.closeButton.frame) + 8;
    CGFloat titleRight = self.sleepButton.frame.origin.x - 8;
    self.contextLabel.frame = CGRectMake(titleLeft, top + 7, MAX(0, titleRight - titleLeft), 30);

    if (landscape && S6IsPad()) {
        CGFloat availY = top + barH;
        CGFloat availH = s.height - availY - bottom;
        CGFloat side = MIN(availH - 40, s.width / 2 - 60);
        CGRect panel = CGRectMake(50, availY + (availH - side) / 2, side, side);
        self.artContainer.frame = panel;
        self.lyrics.view.frame = panel;
        self.queue.view.frame = panel;

        CGFloat rx = 50 + side + 40;
        CGFloat rw = s.width - rx - 50;
        CGFloat rightCenterY = availY + availH / 2;
        CGFloat infoY = rightCenterY - 130;
        self.titleLabel.frame = CGRectMake(rx + 36, infoY, rw - 72, 28);
        self.heartButton.frame = CGRectMake(rx + rw - 36, infoY - 6, 36, 36);
        self.artistButton.frame = CGRectMake(rx + 36, infoY + 28, rw - 72, 22);

        self.progress.frame = CGRectMake(rx, infoY + 58, rw, 22);
        self.elapsedLabel.frame = CGRectMake(rx, infoY + 80, 60, 16);
        self.remainingLabel.frame = CGRectMake(rx + rw - 60, infoY + 80, 60, 16);
        self.formatLabel.frame = CGRectMake(rx + 60, infoY + 80, rw - 120, 16);

        CGFloat dockY = infoY + 104;
        CGFloat dockH = 114;
        self.bottomDock.frame = CGRectMake(rx, dockY, rw, dockH);
        self.bottomDock.layer.cornerRadius = 6;
        self.bottomDock.clipsToBounds = YES;

        CGFloat cx = rx + rw / 2;
        self.playButton.frame = CGRectMake(cx - 30, dockY + 6, 60, 48);
        self.spinner.center = self.playButton.center;
        self.previousButton.frame = CGRectMake(cx - 96, dockY + 10, 48, 40);
        self.nextButton.frame = CGRectMake(cx + 48, dockY + 10, 48, 40);
        self.shuffleButton.frame = CGRectMake(rx + 10, dockY + 12, 36, 36);
        self.repeatButton.frame = CGRectMake(rx + rw - 46, dockY + 12, 36, 36);

        CGFloat r2Y = dockY + 60;
        self.lyricsButton.frame = CGRectMake(rx + 10, r2Y - 2, 36, 36);
        self.queueButton.frame = CGRectMake(rx + rw - 46, r2Y - 2, 36, 36);
        self.volume.frame = CGRectMake(rx + 56, r2Y + 4, rw - 112, 22);
    } else {
        self.bottomDock.layer.cornerRadius = 0;
        self.bottomDock.clipsToBounds = NO;
        CGFloat dockContentH = (s.height < 500) ? 94.0f : 106.0f;
        CGFloat dockH = dockContentH + bottom;
        self.bottomDock.frame = CGRectMake(0, s.height - dockH, s.width, dockH);

        CGFloat startY = top + barH;
        CGFloat availableH = (s.height - dockH) - startY;
        CGFloat infoH = (s.height < 500) ? 72.0f : 86.0f;
        CGFloat maxSideH = availableH - infoH - ((s.height < 500) ? 14.0f : 24.0f);
        CGFloat side = MIN(s.width - (S6IsPad() ? 140 : 40), maxSideH);
        if (side < 120) side = 120;
        CGFloat panelY = startY + (availableH - infoH - side) / 2;
        if (panelY < startY + 6) panelY = startY + 6;

        self.artContainer.frame = CGRectMake((s.width - side) / 2, panelY, side, side);
        self.lyrics.view.frame = CGRectMake(20, panelY - 4, s.width - 40, side + 8);
        self.queue.view.frame = CGRectMake(0, panelY - 4, s.width, side + 8);

        CGFloat infoY = CGRectGetMaxY(self.artContainer.frame) + ((s.height < 500) ? 6.0f : 12.0f);
        CGFloat infoW = MIN(s.width - 32, 540);
        CGFloat infoX = (s.width - infoW) / 2;

        CGFloat titleH = (s.height < 500) ? 22.0f : 26.0f;
        CGFloat artistH = (s.height < 500) ? 18.0f : 20.0f;
        self.titleLabel.frame = CGRectMake(infoX + 36, infoY, infoW - 72, titleH);
        self.heartButton.frame = CGRectMake(infoX + infoW - 36, infoY - 4, 36, 36);
        self.artistButton.frame = CGRectMake(infoX + 36, infoY + titleH, infoW - 72, artistH);

        CGFloat progY = infoY + titleH + artistH + ((s.height < 500) ? 2.0f : 6.0f);
        self.progress.frame = CGRectMake(infoX, progY, infoW, 20);
        self.elapsedLabel.frame = CGRectMake(infoX, progY + 18, 56, 14);
        self.remainingLabel.frame = CGRectMake(infoX + infoW - 56, progY + 18, 56, 14);
        self.formatLabel.frame = CGRectMake(infoX + 56, progY + 18, infoW - 112, 14);

        CGFloat dockY = self.bottomDock.frame.origin.y;
        CGFloat dockW = MIN(s.width - 20, 540);
        CGFloat dockX = (s.width - dockW) / 2;
        CGFloat cx = s.width / 2;

        CGFloat btnY = dockY + ((s.height < 500) ? 4.0f : 8.0f);
        CGFloat playBtnH = (s.height < 500) ? 44.0f : 50.0f;
        self.playButton.frame = CGRectMake(cx - 30, btnY, 60, playBtnH);
        self.spinner.center = self.playButton.center;
        self.previousButton.frame = CGRectMake(cx - 96, btnY + 2, 48, 40);
        self.nextButton.frame = CGRectMake(cx + 48, btnY + 2, 48, 40);
        self.shuffleButton.frame = CGRectMake(dockX + 6, btnY + 4, 36, 36);
        self.repeatButton.frame = CGRectMake(dockX + dockW - 42, btnY + 4, 36, 36);

        CGFloat r2Y = btnY + playBtnH + ((s.height < 500) ? 2.0f : 6.0f);
        self.lyricsButton.frame = CGRectMake(dockX + 6, r2Y - 2, 36, 36);
        self.queueButton.frame = CGRectMake(dockX + dockW - 42, r2Y - 2, 36, 36);
        self.volume.frame = CGRectMake(dockX + 50, r2Y + 4, dockW - 100, 22);
    }
}

- (void)layoutControlsInRect:(CGRect)r
{
    CGFloat x = r.origin.x, w = r.size.width, y = r.origin.y;
    self.titleLabel.frame = CGRectMake(x + 40, y, w - 80, 28);
    self.heartButton.frame = CGRectMake(x + w - 40, y - 6, 40, 40);
    self.artistButton.frame = CGRectMake(x + 40, y + 28, w - 80, 24);
    y += 64;
    self.progress.frame = CGRectMake(x, y, w, 22);
    self.elapsedLabel.frame = CGRectMake(x, y + 22, 60, 16);
    self.remainingLabel.frame = CGRectMake(x + w - 60, y + 22, 60, 16);
    self.formatLabel.frame = CGRectMake(x + 60, y + 22, w - 120, 16);
    y += 48;
    CGFloat cx = x + w / 2;
    self.playButton.frame = CGRectMake(cx - 36, y, 72, 64);
    self.spinner.center = self.playButton.center;
    self.previousButton.frame = CGRectMake(cx - 110, y + 8, 56, 48);
    self.nextButton.frame = CGRectMake(cx + 54, y + 8, 56, 48);
    self.shuffleButton.frame = CGRectMake(x, y + 10, 44, 44);
    self.repeatButton.frame = CGRectMake(x + w - 44, y + 10, 44, 44);
    y += 74;
    self.lyricsButton.frame = CGRectMake(x, y, 44, 44);
    self.queueButton.frame = CGRectMake(x + w - 44, y, 44, 44);
    self.volume.frame = CGRectMake(x + 60, y + 12, w - 120, 22);
}

- (void)showPanel
{
    self.artContainer.hidden = self.panel != S6NowPlayingArt;
    self.lyrics.view.hidden = self.panel != S6NowPlayingLyrics;
    self.queue.view.hidden = self.panel != S6NowPlayingQueue;
    S6Theme *theme = [S6Theme shared];
    [self.lyricsButton setImage:[theme icon:S6IconLyrics size:24 color:self.panel == S6NowPlayingLyrics ? [theme accentColor] : [UIColor whiteColor]] forState:UIControlStateNormal];
    [self.queueButton setImage:[theme icon:S6IconQueue size:24 color:self.panel == S6NowPlayingQueue ? [theme accentColor] : [UIColor whiteColor]] forState:UIControlStateNormal];
    if (self.panel == S6NowPlayingLyrics) [self.lyrics showTrack:[S6Player shared].currentTrack];
    if (self.panel == S6NowPlayingQueue) [self.queue refresh];
}

- (void)setPanel:(S6NowPlayingPanel)panel
{
    _panel = panel;
    if (self.isViewLoaded) [self showPanel];
}

#pragma mark - State

- (void)update
{
    S6Player *player = [S6Player shared];
    S6Theme *theme = [S6Theme shared];
    S6Track *t = player.currentTrack;
    if (!t) { [self close]; return; }
    self.titleLabel.text = [S6Utils displayText:t.name];
    [self.artistButton setTitle:[S6Utils displayText:[t artistNames]] forState:UIControlStateNormal];
    NSString *context = player.contextName.length ? player.contextName : t.album.name;
    if ([S6Settings classicPlayer]) {
        self.contextLabel.text = context.length ? context : L(@"Now playing");
    } else {
        self.contextLabel.text = context.length ? [NSString stringWithFormat:@"%@\n%@", [L(@"Playing from") uppercaseString], context] : @"";
    }
    NSString *url = [t imageURLForSize:640];
    [self.art setImageURL:url placeholder:[theme artPlaceholderWithSize:300]];
    if (url && ![url isEqualToString:self.backdropURL]) {
        self.backdropURL = url;
        __unsafe_unretained S6NowPlayingViewController *weakSelf = self;
        [[S6ImageLoader shared] loadImage:url maxPixels:200 completion:^(UIImage *image) {
            if ([weakSelf.backdropURL isEqualToString:url]) weakSelf.backdrop.image = image;
        }];
    }
    [self.playButton setImage:[theme icon:player.playing ? S6IconPause : S6IconPlay size:54] forState:UIControlStateNormal];
    UIColor *on = [theme accentColor], *off = [UIColor whiteColor];
    [self.shuffleButton setImage:[theme icon:S6IconShuffle size:24 color:player.shuffle ? on : off] forState:UIControlStateNormal];
    [self.repeatButton setImage:[theme icon:player.repeat == S6RepeatOne ? S6IconRepeatOne : S6IconRepeat size:24 color:player.repeat != S6RepeatOff ? on : off] forState:UIControlStateNormal];
    if (![t.uri isEqualToString:self.shownURI]) {
        self.shownURI = t.uri;
        self.liked = NO;
        [self showLiked];
        NSString *uri = t.uri;
        if (t.trackId.length && !t.isEpisode) {
            [S6Catalog areSaved:@[ t.uri ] completion:^(NSArray *savedList, NSError *savedError) {
                BOOL saved = [savedList.firstObject boolValue];
                if (![uri isEqualToString:self.shownURI]) return;
                self.liked = saved;
                [self showLiked];
            }];
        }
        if (self.panel == S6NowPlayingLyrics) [self.lyrics showTrack:t];
    }
    [self tick];
}

- (void)showLiked
{
    S6Theme *theme = [S6Theme shared];
    [self.heartButton setImage:[theme icon:self.liked ? S6IconHeartFilled : S6IconHeart size:24 color:self.liked ? [theme accentColor] : [UIColor whiteColor]] forState:UIControlStateNormal];
}

- (void)tick
{
    S6Player *player = [S6Player shared];
    NSInteger duration = player.durationMs, position = player.positionMs;
    if (!self.scrubbing) {
        self.progress.value = duration > 0 ? (float)position / (float)duration : 0;
        self.elapsedLabel.text = S6FormatDurationMs(position);
        self.remainingLabel.text = duration > 0 ? [@"-" stringByAppendingString:S6FormatDurationMs(MAX(0, duration - position))] : @"";
    }
    NSString *format = player.formatName ?: @"";
    NSString *sleep = nil;
    if (player.sleepAtEndOfSong) sleep = L(@"Sleep: end of song");
    else if (player.sleepAt) sleep = [NSString stringWithFormat:L(@"Sleep: %@"), S6FormatDurationMs((NSInteger)MAX(0, [player.sleepAt timeIntervalSinceNow] * 1000))];
    self.formatLabel.text = sleep ? (format.length ? [NSString stringWithFormat:@"%@ • %@", format, sleep] : sleep) : format;
    BOOL sleeping = sleep != nil;
    if (sleeping != self.sleepButton.selected) {
        self.sleepButton.selected = sleeping;
        S6Theme *theme = [S6Theme shared];
        UIImage *moon = [theme icon:S6IconMoon size:20 color:sleeping ? [theme accentColor] : [UIColor whiteColor]];
        [self.sleepButton setImage:moon forState:UIControlStateNormal];
        [self.sleepButton setImage:moon forState:UIControlStateSelected];
    }
    if (player.buffering && player.playing) { [self.spinner startAnimating]; self.playButton.alpha = 0.15; }
    else { [self.spinner stopAnimating]; self.playButton.alpha = 1; }
    if (self.panel == S6NowPlayingLyrics) [self.lyrics tick];
}

#pragma mark - Actions

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)togglePlay { [[S6Player shared] togglePlay]; }
- (void)next { [[S6Player shared] next]; }
- (void)previous { [[S6Player shared] previous]; }
- (void)toggleShuffle { S6Player *p = [S6Player shared]; p.shuffle = !p.shuffle; }

- (void)cycleRepeat
{
    S6Player *p = [S6Player shared];
    p.repeat = p.repeat == S6RepeatOff ? S6RepeatAll : p.repeat == S6RepeatAll ? S6RepeatOne : S6RepeatOff;
}

- (void)toggleLyrics { self.panel = self.panel == S6NowPlayingLyrics ? S6NowPlayingArt : S6NowPlayingLyrics; }
- (void)toggleQueue { self.panel = self.panel == S6NowPlayingQueue ? S6NowPlayingArt : S6NowPlayingQueue; }

- (void)toggleLike
{
    S6Track *t = [S6Player shared].currentTrack;
    if (!t.trackId.length || t.isEpisode) return;
    BOOL like = !self.liked;
    self.liked = like;
    [self showLiked];
    [S6Catalog setSaved:like uris:@[ t.uri ] completion:^(NSError *error) {
        if (error) { self.liked = !like; [self showLiked]; [S6Router toast:error.localizedDescription]; }
    }];
}

- (void)openArtist
{
    S6Artist *a = [S6Player shared].currentTrack.artists.firstObject;
    if (!a.artistId.length) return;
    [self dismissViewControllerAnimated:YES completion:^{ [S6Router openArtist:a]; }];
}

- (void)more
{
    S6Track *t = [S6Player shared].currentTrack;
    if (t) [S6Router showActionsForTrack:t fromView:self.moreButton inController:self playlist:nil];
}

- (void)sleepTimer { [S6Router showSleepTimerFromView:self.sleepButton inController:self]; }

- (void)scrubStarted { self.scrubbing = YES; }

- (void)scrubMoved
{
    NSInteger duration = [S6Player shared].durationMs;
    NSInteger at = (NSInteger)(self.progress.value * duration);
    self.elapsedLabel.text = S6FormatDurationMs(at);
    self.remainingLabel.text = [@"-" stringByAppendingString:S6FormatDurationMs(MAX(0, duration - at))];
}

- (void)scrubEnded
{
    NSInteger duration = [S6Player shared].durationMs;
    if (duration > 0) [[S6Player shared] seekToMs:(NSInteger)(self.progress.value * duration)];
    self.scrubbing = NO;
}

@end
