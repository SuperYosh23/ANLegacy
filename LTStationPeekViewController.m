#import "LTStationPeekViewController.h"
#import "LTTheme.h"
#import <QuartzCore/QuartzCore.h>
#import "LTGraphics.h"
#import "LTModel.h"
#import "LTYouTubeClient.h"

static const NSUInteger kLTPeekMaxRows = 9;
static const CGFloat kLTPeekRowHeight = 24.0f;
static const CGFloat kLTPeekCoverSide = 84.0f;
static const CGFloat kLTPeekHeaderHeight = 128.0f;
static const CGFloat kLTPeekHintHeight = 26.0f;
static const CGFloat kLTPeekSideMargin = 16.0f;

@interface LTStationPeekViewController ()
@property (nonatomic, strong) LTStation *station;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIView *seedList;
@property (nonatomic, strong) UIView *hintView;
@end

@implementation LTStationPeekViewController

@synthesize station = _station;

- (instancetype)initWithStation:(LTStation *)station {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _station = station;
    }
    return self;
}

- (NSUInteger)peekRowCount {
    NSUInteger count = self.station.seeds.count;
    NSUInteger rows = count < kLTPeekMaxRows ? count : kLTPeekMaxRows;
    return count > rows ? rows + 1 : rows;
}

- (CGSize)preferredContentSize {
    CGFloat height = kLTPeekHeaderHeight + (CGFloat)[self peekRowCount] * kLTPeekRowHeight + kLTPeekHintHeight;
    return CGSizeMake(0.0f, height);
}

- (NSString *)seedTitle:(LTStationSeed *)seed {
    if ([seed.type isEqualToString:@"track"]) return seed.title.length ? seed.title : seed.videoId;
    if ([seed.type isEqualToString:@"artist"]) return seed.artist.length ? seed.artist : @"Artist";
    if ([seed.type isEqualToString:@"album"]) return seed.album.length ? seed.album : @"Album";
    return @"Seed";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [LTTheme background];

    self.coverView = [[UIImageView alloc] initWithFrame:CGRectMake(kLTPeekSideMargin, kLTPeekSideMargin,
                                                                   kLTPeekCoverSide, kLTPeekCoverSide)];
    self.coverView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverView.clipsToBounds = YES;
    self.coverView.layer.cornerRadius = 4.0f;
    self.coverView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];

    if (self.station.coverPath.length) {
        UIImage *cover = [UIImage imageWithContentsOfFile:self.station.coverPath];
        if (cover) self.coverView.image = cover;
    } else if (self.station.seeds.count) {
        LTStationSeed *seed = [self.station.seeds objectAtIndex:0];
        if (seed.thumbnailURL.length) {
            __unsafe_unretained typeof(self) weakSelf = self;
            NSString *stationPath = [[NSBundle mainBundle] pathForResource:@"station" ofType:@"png"];
            UIImage *stationBase = [UIImage imageWithContentsOfFile:stationPath];
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:seed.thumbnailURL];
            [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *seedImage) {
                if (!seedImage) {
                    weakSelf.coverView.image = stationBase ?: [LTGraphics musicIcon];
                    return;
                }
                CGSize size = CGSizeMake(kLTPeekCoverSide, kLTPeekCoverSide);
                UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
                if (stationBase) [stationBase drawInRect:CGRectMake(0, 0, size.width, size.height)];
                CGFloat insetX = size.width * 23.0f / 44.0f;
                CGFloat insetY = size.height * 21.0f / 44.0f;
                CGFloat ow = size.width * 9.0f / 44.0f;
                CGFloat oh = size.height * 9.0f / 44.0f;
                CGRect seedRect = CGRectMake(insetX, insetY, ow, oh);
                CGContextRef ctx = UIGraphicsGetCurrentContext();
                CGContextSaveGState(ctx);
                UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:seedRect];
                [circle addClip];
                [seedImage drawInRect:seedRect];
                CGContextRestoreGState(ctx);
                UIImage *composite = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                if (composite) weakSelf.coverView.image = composite;
            }];
        } else {
            NSString *stationPath = [[NSBundle mainBundle] pathForResource:@"station" ofType:@"png"];
            UIImage *stationBase = [UIImage imageWithContentsOfFile:stationPath];
            self.coverView.image = stationBase ?: [LTGraphics musicIcon];
        }
    } else {
        NSString *stationPath = [[NSBundle mainBundle] pathForResource:@"station" ofType:@"png"];
        UIImage *stationBase = [UIImage imageWithContentsOfFile:stationPath];
        self.coverView.image = stationBase ?: [LTGraphics musicIcon];
    }
    [self.view addSubview:self.coverView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = self.station.name.length ? self.station.name : @"Station";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.textColor = [LTTheme text];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:self.titleLabel];

    NSUInteger count = self.station.seeds.count;
    self.countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.countLabel.text = [NSString stringWithFormat:@"%lu seed%@", (unsigned long)count, count == 1 ? @"" : @"s"];
    self.countLabel.font = [UIFont systemFontOfSize:13];
    self.countLabel.textColor = [LTTheme secondaryText];
    self.countLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.countLabel];

    self.seedList = [[UIView alloc] initWithFrame:CGRectMake(kLTPeekSideMargin, kLTPeekHeaderHeight,
                                                             10.0f, (CGFloat)[self peekRowCount] * kLTPeekRowHeight)];
    self.seedList.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.seedList];

    NSUInteger seedCount = self.station.seeds.count;
    CGFloat width = MAX(self.seedList.bounds.size.width, 10.0f);
    NSUInteger drawn = seedCount < kLTPeekMaxRows ? seedCount : kLTPeekMaxRows;
    for (NSUInteger i = 0; i < drawn; i++) {
        LTStationSeed *seed = [self.station.seeds objectAtIndex:i];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, (CGFloat)i * kLTPeekRowHeight, width, kLTPeekRowHeight)];
        label.text = [self seedTitle:seed];
        label.font = [UIFont systemFontOfSize:13];
        label.textColor = [LTTheme text];
        label.backgroundColor = [UIColor clearColor];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.seedList addSubview:label];
    }
    if (seedCount > drawn) {
        UILabel *more = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, (CGFloat)drawn * kLTPeekRowHeight, width, kLTPeekRowHeight)];
        more.text = [NSString stringWithFormat:@"+%lu more", (unsigned long)(seedCount - drawn)];
        more.font = [UIFont italicSystemFontOfSize:13];
        more.textColor = [LTTheme secondaryText];
        more.backgroundColor = [UIColor clearColor];
        [self.seedList addSubview:more];
    }

    self.hintView = [[UIView alloc] initWithFrame:CGRectZero];
    self.hintView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.hintView];
    UILabel *hintLabel = [[UILabel alloc] initWithFrame:self.hintView.bounds];
    hintLabel.text = @"press harder to open";
    hintLabel.font = [UIFont systemFontOfSize:12];
    hintLabel.textColor = [LTTheme secondaryText];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.backgroundColor = [UIColor clearColor];
    hintLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.hintView addSubview:hintLabel];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat titleX = kLTPeekSideMargin + kLTPeekCoverSide + 12.0f;
    CGFloat titleWidth = width - titleX - kLTPeekSideMargin;
    self.titleLabel.frame = CGRectMake(titleX, kLTPeekSideMargin + 4.0f, titleWidth, 22.0f);
    self.countLabel.frame = CGRectMake(titleX, kLTPeekSideMargin + 28.0f, titleWidth, 18.0f);

    CGFloat listWidth = width - kLTPeekSideMargin * 2.0f;
    self.seedList.frame = CGRectMake(kLTPeekSideMargin, kLTPeekHeaderHeight, listWidth, (CGFloat)[self peekRowCount] * kLTPeekRowHeight);
    for (UIView *v in self.seedList.subviews) {
        if ([v isKindOfClass:[UILabel class]]) {
            v.frame = CGRectMake(0.0f, v.frame.origin.y, listWidth, v.frame.size.height);
        }
    }
    self.hintView.frame = CGRectMake(0.0f, self.view.bounds.size.height - kLTPeekHintHeight, width, kLTPeekHintHeight);
}

@end
