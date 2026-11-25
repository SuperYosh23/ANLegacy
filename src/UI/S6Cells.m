#import "S6Cells.h"
#import "S6Theme.h"
#import "S6ImageLoader.h"
#import "S6Models.h"
#import "S6Player.h"
#import "S6Utils.h"
#import "S6Common.h"

UIView *S6SectionHeader(NSString *title, CGFloat width)
{
    S6Theme *theme = [S6Theme shared];
    UIImageView *bar = [[UIImageView alloc] initWithImage:[theme sectionHeaderImage]];
    bar.frame = CGRectMake(0, 0, width, 26);
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, width - 24, 26)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.backgroundColor = [UIColor clearColor];
    l.font = [theme sectionFont];
    l.textColor = [theme secondaryTextColor];
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
    l.shadowOffset = CGSizeMake(0, -1);
    l.text = [title uppercaseString];
    [bar addSubview:l];
    return bar;
}

@interface S6TrackCell ()
@property (nonatomic, strong) S6ImageView *art;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UILabel *numberLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIImageView *explicitView;
@property (nonatomic, strong) UIImageView *playingView;
@end

@implementation S6TrackCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        S6Theme *theme = [S6Theme shared];
        [theme styleCell:self];
        _showsArt = YES;
        _art = [[S6ImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        _art.contentMode = UIViewContentModeScaleAspectFill;
        _art.clipsToBounds = YES;
        [self.contentView addSubview:_art];
        _numberLabel = [self label:[theme smallFont] color:[theme secondaryTextColor]];
        _numberLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel = [self label:[theme bodyFont] color:[theme primaryTextColor]];
        _subtitleLabel = [self label:[theme smallFont] color:[theme secondaryTextColor]];
        _durationLabel = [self label:[theme smallFont] color:[theme tertiaryTextColor]];
        _durationLabel.textAlignment = NSTextAlignmentRight;
        _explicitView = [[UIImageView alloc] initWithImage:[theme explicitBadge]];
        [self.contentView addSubview:_explicitView];
        _playingView = [[UIImageView alloc] initWithImage:[theme icon:S6IconSpeaker size:16 color:[theme accentColor]]];
        [self.contentView addSubview:_playingView];
        _moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_moreButton setImage:[theme icon:S6IconMore size:18 color:[theme secondaryTextColor]] forState:UIControlStateNormal];
        _moreButton.accessibilityLabel = L(@"More");
        [self.contentView addSubview:_moreButton];
    }
    return self;
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:l];
    return l;
}

- (void)showTrack:(S6Track *)track number:(NSInteger)number
{
    S6Theme *theme = [S6Theme shared];
    S6Track *current = [S6Player shared].currentTrack;
    BOOL playing = current && ([current.uri isEqualToString:track.uri] || (current.trackId.length && [current.trackId isEqualToString:track.trackId]));
    self.titleLabel.text = [S6Utils displayText:track.name];
    self.titleLabel.textColor = playing ? [theme accentTextColor] : (track.playable ? [theme primaryTextColor] : [theme tertiaryTextColor]);
    NSString *sub = [track artistNames];
    if (self.showsArt && track.album.name.length && !track.isEpisode) sub = [NSString stringWithFormat:@"%@ · %@", sub, track.album.name];
    self.subtitleLabel.text = [S6Utils displayText:sub];
    self.durationLabel.text = track.durationMs ? S6FormatDurationMs(track.durationMs) : @"";
    self.numberLabel.text = number > 0 ? [NSString stringWithFormat:@"%ld", (long)number] : @"";
    self.explicitView.hidden = !track.explicitContent;
    self.playingView.hidden = !playing;
    self.art.hidden = !self.showsArt;
    self.numberLabel.hidden = self.showsArt || playing;
    if (self.showsArt) [self.art setImageURL:[track imageURLForSize:80] placeholder:[theme artPlaceholderWithSize:40]];
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.contentView.bounds.size;
    CGFloat x = 10;
    if (self.showsArt) {
        self.art.frame = CGRectMake(x, floorf((s.height - 40) / 2), 40, 40);
        x += 50;
    } else {
        self.numberLabel.frame = CGRectMake(4, 0, 34, s.height);
        x = 42;
    }
    self.playingView.frame = self.showsArt ? CGRectMake(x - 4, floorf((s.height - 16) / 2), 16, 16) : CGRectMake(13, floorf((s.height - 16) / 2), 16, 16);
    if (self.showsArt && !self.playingView.hidden) x += 16;
    self.moreButton.frame = CGRectMake(s.width - 40, 0, 40, s.height);
    CGFloat right = s.width - 40;
    CGSize d = [self.durationLabel.text sizeWithFont:self.durationLabel.font];
    self.durationLabel.frame = CGRectMake(right - ceilf(d.width) - 4, 0, ceilf(d.width), s.height);
    right -= ceilf(d.width) + 12;
    CGFloat textX = x;
    if (!self.explicitView.hidden) {
        self.explicitView.frame = CGRectMake(textX, floorf(s.height / 2) + 4, 14, 14);
        textX += 18;
    }
    self.titleLabel.frame = CGRectMake(x, floorf(s.height / 2) - 19, right - x, 20);
    self.subtitleLabel.frame = CGRectMake(textX, floorf(s.height / 2) + 2, right - textX, 17);
}

@end

@interface S6MediaCell ()
@property (nonatomic, strong) S6ImageView *art;
@end

@implementation S6MediaCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier])) {
        S6Theme *theme = [S6Theme shared];
        [theme styleCell:self];
        self.textLabel.font = [theme boldBodyFont];
        self.detailTextLabel.font = [theme smallFont];
        _art = [[S6ImageView alloc] initWithFrame:CGRectMake(0, 0, 52, 52)];
        _art.contentMode = UIViewContentModeScaleAspectFill;
        _art.clipsToBounds = YES;
        [self.contentView addSubview:_art];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)setRound:(BOOL)round
{
    _round = round;
    self.art.layer.cornerRadius = round ? 26 : 0;
}

- (void)showTitle:(NSString *)title subtitle:(NSString *)subtitle imageURL:(NSString *)url
{
    S6Theme *theme = [S6Theme shared];
    self.textLabel.text = [S6Utils displayText:title];
    self.detailTextLabel.text = [S6Utils displayText:subtitle];
    [self.art setImageURL:url placeholder:self.round ? [theme artistPlaceholderWithSize:52] : [theme artPlaceholderWithSize:52]];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.contentView.bounds.size;
    self.art.frame = CGRectMake(10, floorf((s.height - 52) / 2), 52, 52);
    CGFloat x = 74, w = s.width - x - 6;
    self.textLabel.frame = CGRectMake(x, floorf(s.height / 2) - 20, w, 20);
    self.detailTextLabel.frame = CGRectMake(x, floorf(s.height / 2) + 2, w, 18);
}

@end

@interface S6CardView ()
@property (nonatomic, strong) S6ImageView *art;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation S6CardView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        S6Theme *theme = [S6Theme shared];
        _art = [[S6ImageView alloc] initWithFrame:CGRectZero];
        _art.contentMode = UIViewContentModeScaleAspectFill;
        _art.clipsToBounds = YES;
        _art.userInteractionEnabled = NO;
        [self addSubview:_art];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:13] ?: [UIFont boldSystemFontOfSize:13];
        _titleLabel.textColor = [theme primaryTextColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_titleLabel];
        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:12] ?: [UIFont systemFontOfSize:12];
        _subtitleLabel.textColor = [theme secondaryTextColor];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_subtitleLabel];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    self.art.alpha = highlighted ? 0.6 : 1;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    self.art.frame = CGRectMake(0, 0, w, w);
    self.art.layer.cornerRadius = self.round ? w / 2 : 0;
    self.titleLabel.frame = CGRectMake(0, w + 6, w, 17);
    self.subtitleLabel.frame = CGRectMake(0, w + 23, w, 16);
    self.titleLabel.textAlignment = self.round ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    self.subtitleLabel.textAlignment = self.titleLabel.textAlignment;
}

@end

@interface S6ShelfCell ()
@property (nonatomic, strong) UIScrollView *scroller;
@property (nonatomic, strong) NSMutableArray *cards;
@end

@implementation S6ShelfCell

+ (CGFloat)heightForCardWidth:(CGFloat)width { return width + 58; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _scroller = [[UIScrollView alloc] initWithFrame:self.contentView.bounds];
        _scroller.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroller.showsHorizontalScrollIndicator = NO;
        _scroller.alwaysBounceHorizontal = YES;
        _scroller.scrollsToTop = NO;
        [self.contentView addSubview:_scroller];
        _cards = [NSMutableArray array];
    }
    return self;
}

- (void)showItems:(NSArray *)items cardWidth:(CGFloat)width
{
    S6Theme *theme = [S6Theme shared];
    while (self.cards.count < items.count) {
        S6CardView *card = [[S6CardView alloc] initWithFrame:CGRectZero];
        [card addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroller addSubview:card];
        [self.cards addObject:card];
    }
    CGFloat x = 12, gap = 14;
    for (NSUInteger i = 0; i < self.cards.count; i++) {
        S6CardView *card = self.cards[i];
        card.hidden = i >= items.count;
        if (card.hidden) continue;
        NSDictionary *d = items[i];
        card.round = [[d objectForKey:@"round"] boolValue];
        card.item = [d objectForKey:@"item"];
        card.titleLabel.text = [S6Utils displayText:[d objectForKey:@"title"]];
        card.subtitleLabel.text = [S6Utils displayText:[d objectForKey:@"subtitle"]];
        [card.art setImageURL:[d objectForKey:@"image"] placeholder:card.round ? [theme artistPlaceholderWithSize:width] : [theme artPlaceholderWithSize:width]];
        card.frame = CGRectMake(x, 10, width, width + 44);
        [card setNeedsLayout];
        x += width + gap;
    }
    self.scroller.contentSize = CGSizeMake(x, width + 54);
    self.scroller.contentOffset = CGPointZero;
}

- (void)tapped:(S6CardView *)card
{
    if (self.onSelect && card.item) self.onSelect(card.item);
}

@end

NSDictionary *S6CardFor(id item)
{
    if ([item isKindOfClass:[S6Album class]]) {
        S6Album *a = item;
        NSString *sub = a.year.length ? [NSString stringWithFormat:@"%@ · %@", a.year, [a artistNames]] : [a artistNames];
        return @{ @"title": a.name ?: @"", @"subtitle": sub ?: @"", @"image": [a imageURLForSize:300] ?: @"", @"item": a };
    }
    if ([item isKindOfClass:[S6Playlist class]]) {
        S6Playlist *p = item;
        NSString *sub = p.descriptionText.length ? p.descriptionText : (p.ownerName.length ? [NSString stringWithFormat:L(@"by %@"), p.ownerName] : @"");
        return @{ @"title": p.name ?: @"", @"subtitle": sub, @"image": [p imageURLForSize:300] ?: @"", @"item": p };
    }
    if ([item isKindOfClass:[S6Artist class]]) {
        S6Artist *a = item;
        return @{ @"title": a.name ?: @"", @"subtitle": L(@"Artist"), @"image": [a imageURLForSize:300] ?: @"", @"round": @YES, @"item": a };
    }
    if ([item isKindOfClass:[S6Show class]]) {
        S6Show *s = item;
        return @{ @"title": s.name ?: @"", @"subtitle": s.publisher ?: L(@"Podcast"), @"image": [s imageURLForSize:300] ?: @"", @"item": s };
    }
    if ([item isKindOfClass:[S6Track class]]) {
        S6Track *t = item;
        NSString *sub = t.isEpisode ? t.album.name : [t artistNames];
        return @{ @"title": t.name ?: @"", @"subtitle": sub ?: @"", @"image": [t imageURLForSize:300] ?: @"", @"item": t };
    }
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *c = item;
        return @{ @"title": [c objectForKey:@"title"] ?: @"", @"subtitle": @"", @"image": [c objectForKey:@"image"] ?: @"", @"item": c };
    }
    return nil;
}

#pragma mark - Tiles

@interface S6TileView : UIControl
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) S6ImageView *art;
@property (nonatomic, strong) UIImageView *gloss;
@property (nonatomic, strong) id item;
@end

@implementation S6TileView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 6;
        self.clipsToBounds = YES;
        _art = [[S6ImageView alloc] initWithFrame:CGRectZero];
        _art.contentMode = UIViewContentModeScaleAspectFill;
        _art.clipsToBounds = YES;
        _art.userInteractionEnabled = NO;
        _art.layer.shadowColor = [UIColor blackColor].CGColor;
        [self addSubview:_art];
        _gloss = [[UIImageView alloc] initWithImage:[[S6Theme shared] shadowImageTop:NO]];
        _gloss.alpha = 0.35;
        _gloss.userInteractionEnabled = NO;
        [self addSubview:_gloss];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:S6IsPad() ? 17 : 15] ?: [UIFont boldSystemFontOfSize:16];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
        _titleLabel.shadowOffset = CGSizeMake(0, 1);
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.7 : 1;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    self.gloss.frame = CGRectMake(0, s.height / 2, s.width, s.height / 2);
    self.titleLabel.frame = CGRectMake(10, 8, s.width - 20, 40);
    [self.titleLabel sizeToFit];
    CGRect f = self.titleLabel.frame;
    f.size.width = MIN(f.size.width, s.width - 20);
    self.titleLabel.frame = f;
    // the artwork tilted into the bottom right corner, as Spotify's tiles have it
    CGFloat side = s.height * 0.62;
    self.art.transform = CGAffineTransformIdentity;
    self.art.frame = CGRectMake(0, 0, side, side);
    self.art.center = CGPointMake(s.width - side * 0.32, s.height - side * 0.30);
    self.art.transform = CGAffineTransformMakeRotation((CGFloat)(25.0 * M_PI / 180.0));
}

@end

@interface S6TileRowCell ()
@property (nonatomic, strong) NSMutableArray *tiles;
@end

@implementation S6TileRowCell

+ (CGFloat)heightForWidth:(CGFloat)width columns:(NSInteger)columns
{
    CGFloat tileW = (width - 12 - 12 * (CGFloat)columns) / (CGFloat)MAX(1, columns);
    return floorf(tileW * 0.56f) + 12;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _tiles = [NSMutableArray array];
    }
    return self;
}

- (void)showTiles:(NSArray *)tiles columns:(NSInteger)columns
{
    while (self.tiles.count < (NSUInteger)columns) {
        S6TileView *t = [[S6TileView alloc] initWithFrame:CGRectZero];
        [t addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:t];
        [self.tiles addObject:t];
    }
    for (NSUInteger i = 0; i < self.tiles.count; i++) {
        S6TileView *t = self.tiles[i];
        t.hidden = i >= tiles.count || i >= (NSUInteger)columns;
        if (t.hidden) continue;
        NSDictionary *d = tiles[i];
        t.item = d;
        t.titleLabel.text = [d objectForKey:@"title"];
        t.backgroundColor = [S6Utils colorFromHex:[d objectForKey:@"color"]] ?: [UIColor darkGrayColor];
        [t.art setImageURL:[d objectForKey:@"image"] placeholder:nil];
    }
    self.tag = columns;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    NSInteger columns = MAX(1, self.tag);
    CGSize s = self.contentView.bounds.size;
    CGFloat gap = 12, w = (s.width - gap - gap * (CGFloat)columns) / (CGFloat)columns, h = s.height - gap;
    for (NSUInteger i = 0; i < self.tiles.count; i++) {
        UIView *t = self.tiles[i];
        t.frame = CGRectMake(floorf(gap + (CGFloat)i * (w + gap)), 6, floorf(w), floorf(h));
    }
}

- (void)tapped:(S6TileView *)tile
{
    if (self.onSelect && tile.item) self.onSelect(tile.item);
}

@end
