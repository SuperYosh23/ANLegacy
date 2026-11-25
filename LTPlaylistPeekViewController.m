#import "LTPlaylistPeekViewController.h"
#import "LTTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "LTModel.h"
#import "LTYouTubeClient.h"

// The peek grows with the playlist up to a cap, so a three-track playlist gets a
// short card instead of a mostly-empty tall one. preferredContentSize and the
// layout below both derive from these, so they cannot disagree.
static const NSUInteger kLTPeekMaxRows = 9;
static const CGFloat kLTPeekRowHeight = 24.0f;
static const CGFloat kLTPeekCoverSide = 84.0f;
static const CGFloat kLTPeekHeaderHeight = 128.0f;  // top margin + cover + gap
static const CGFloat kLTPeekHintHeight = 26.0f;
static const CGFloat kLTPeekSideMargin = 16.0f;

@interface LTPlaylistPeekViewController ()
@property (nonatomic, strong) LTLocalPlaylist *playlist;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIView *trackList;
@property (nonatomic, strong) UIView *hintView;
@property (nonatomic, strong) NSArray *trackLabels;
@end

@implementation LTPlaylistPeekViewController

@synthesize playlist = _playlist;

- (instancetype)initWithPlaylist:(LTLocalPlaylist *)playlist {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _playlist = playlist;
    }
    return self;
}

// Rows actually drawn: the track cap, plus one line for the "+N more" overflow.
- (NSUInteger)peekRowCount {
    NSUInteger count = self.playlist.tracks.count;
    NSUInteger rows = count < kLTPeekMaxRows ? count : kLTPeekMaxRows;
    return count > rows ? rows + 1 : rows;
}

// A zero width asks UIKit to pick one that fits rather than pinning the card to
// a fixed width that may be wider than the screen.
- (CGSize)preferredContentSize {
    CGFloat height = kLTPeekHeaderHeight + (CGFloat)[self peekRowCount] * kLTPeekRowHeight + kLTPeekHintHeight;
    return CGSizeMake(0.0f, height);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [LTTheme background];

    // Cover on the left, as in the playlist rows themselves.
    self.coverView = [[UIImageView alloc] initWithFrame:CGRectMake(kLTPeekSideMargin, kLTPeekSideMargin,
                                                                   kLTPeekCoverSide, kLTPeekCoverSide)];
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView.clipsToBounds = YES;
    self.coverView.layer.cornerRadius = 4.0f;
    self.coverView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    if (self.playlist.coverPath.length) {
        UIImage *cover = [UIImage imageWithContentsOfFile:self.playlist.coverPath];
        if (cover) self.coverView.image = cover;
    } else {
        [self loadFallbackArtwork];
    }
    [self.view addSubview:self.coverView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = self.playlist.name.length ? self.playlist.name : @"Untitled Playlist";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.textColor = [LTTheme text];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:self.titleLabel];

    NSUInteger count = self.playlist.tracks.count;
    self.countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.countLabel.text = [NSString stringWithFormat:@"%lu track%@",
                            (unsigned long)count, count == 1 ? @"" : @"s"];
    self.countLabel.font = [UIFont systemFontOfSize:13];
    self.countLabel.textColor = [LTTheme secondaryText];
    self.countLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.countLabel];

    // A short run of track titles: enough to recognise the playlist without
    // turning the peek into the full detail screen.
    self.trackList = [[UIView alloc] initWithFrame:CGRectMake(kLTPeekSideMargin, kLTPeekHeaderHeight,
                                                              10.0f, (CGFloat)[self peekRowCount] * kLTPeekRowHeight)];
    self.trackList.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.trackList];
    self.trackLabels = [self fillTrackList];

    self.hintView = [[UIView alloc] initWithFrame:CGRectZero];
    self.hintView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.hintView];
    UILabel *hintLabel = [[UILabel alloc] initWithFrame:self.hintView.bounds];
    hintLabel.text = @"press harder to open";
    hintLabel.font = [UIFont systemFontOfSize:12];
    hintLabel.textColor = [LTTheme secondaryText];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.backgroundColor = [UIColor clearColor];
    [self.hintView addSubview:hintLabel];
}

// Returns the labels created, so -viewDidLayoutSubviews can resize them.
- (NSArray *)fillTrackList {
    NSMutableArray *labels = [NSMutableArray array];
    NSUInteger count = self.playlist.tracks.count;
    CGFloat width = MAX(self.trackList.bounds.size.width, 10.0f);

    if (count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, width, kLTPeekRowHeight)];
        empty.text = @"No tracks yet";
        empty.font = [UIFont italicSystemFontOfSize:14];
        empty.textColor = [LTTheme secondaryText];
        empty.backgroundColor = [UIColor clearColor];
        [self.trackList addSubview:empty];
        [labels addObject:empty];
        return labels;
    }

    NSUInteger maxRows = kLTPeekMaxRows;
    if (count < maxRows) maxRows = count;
    for (NSUInteger i = 0; i < maxRows; i++) {
        LTTrack *track = [self.playlist.tracks objectAtIndex:i];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, kLTPeekRowHeight * (CGFloat)i,
                                                                   width, kLTPeekRowHeight)];
        label.text = track.title;
        label.font = [UIFont systemFontOfSize:14];
        label.textColor = [LTTheme text];
        label.backgroundColor = [UIColor clearColor];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.trackList addSubview:label];
        [labels addObject:label];
    }
    if (count > kLTPeekMaxRows) {
        UILabel *more = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, kLTPeekRowHeight * (CGFloat)kLTPeekMaxRows,
                                                                  width, kLTPeekRowHeight)];
        more.text = [NSString stringWithFormat:@"+%lu more", (unsigned long)(count - kLTPeekMaxRows)];
        more.font = [UIFont systemFontOfSize:13];
        more.textColor = [LTTheme secondaryText];
        more.backgroundColor = [UIColor clearColor];
        [self.trackList addSubview:more];
        [labels addObject:more];
    }
    return labels;
}

// Same fallback the playlist rows use: with no cover the user set, show the
// album art of the playlist's first track.
- (void)loadFallbackArtwork {
    LTTrack *first = [self.playlist.tracks objectAtIndex:0];
    if (!first.thumbnailURL.length) return;
    NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
    if (!artURL.length) return;
    __unsafe_unretained UIImageView *weakCover = self.coverView;
    [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
        if (image) weakCover.image = image;
    }];
}

// Laid out here rather than in -viewDidLoad because UIKit resizes the peek
// container after loading the view; frames computed against the initial bounds
// would be positioned for a width the card never gets.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    if (width < 1.0f || height < 1.0f) return;

    CGFloat textX = kLTPeekSideMargin + kLTPeekCoverSide + 16.0f;
    CGFloat textW = width - textX - kLTPeekSideMargin;
    if (textW < 40.0f) textW = 40.0f;
    self.titleLabel.frame = CGRectMake(textX, kLTPeekSideMargin + 2.0f, textW, 24.0f);
    self.countLabel.frame = CGRectMake(textX, kLTPeekSideMargin + 26.0f, textW, 18.0f);

    CGFloat listH = (CGFloat)[self peekRowCount] * kLTPeekRowHeight;
    self.trackList.frame = CGRectMake(kLTPeekSideMargin, kLTPeekHeaderHeight,
                                      width - kLTPeekSideMargin * 2.0f, listH);
    for (UIView *label in self.trackLabels) {
        CGRect frame = label.frame;
        frame.origin.x = 0.0f;
        frame.size.width = self.trackList.bounds.size.width;
        label.frame = frame;
    }

    self.hintView.frame = CGRectMake(0.0f, height - kLTPeekHintHeight, width, kLTPeekHintHeight);
    for (UIView *sub in self.hintView.subviews) sub.frame = self.hintView.bounds;
}

@end