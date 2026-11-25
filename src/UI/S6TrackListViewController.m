#import "S6TrackListViewController.h"
#import "S6Cells.h"
#import "S6Router.h"
#import "S6Theme.h"
#import "S6Models.h"
#import "S6Catalog.h"
#import "S6Player.h"
#import "S6Session.h"
#import "S6ImageLoader.h"
#import "S6Utils.h"
#import "S6ExternalOpen.h"
#import "S6Common.h"

typedef NS_ENUM(NSInteger, S6ListKind) { S6ListAlbum, S6ListPlaylist, S6ListLiked, S6ListShow, S6ListTracks };

static NSString * const S6TrackCellId = @"track";

@interface S6TrackListViewController ()
@property (nonatomic) S6ListKind kind;
@property (nonatomic, strong) S6Album *album;
@property (nonatomic, strong) S6Playlist *playlist;
@property (nonatomic, strong) S6Show *show;
@property (nonatomic, copy) NSString *contextURI;
@property (nonatomic, copy) NSString *listTitle;
@property (nonatomic, strong) NSArray *tracks;
@property (nonatomic) NSUInteger generation;    // a newer load makes the answers of an older one go unused
@property (nonatomic) BOOL saved;               // the album saved / the playlist or podcast followed
@property (nonatomic) NSInteger total;
// header
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) S6ImageView *cover;
@property (nonatomic, strong) UILabel *typeLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) NSArray *descriptionLinks;   // the web links in the description (a tap on it opens them)
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *saveButton;
@end

@implementation S6TrackListViewController

- (instancetype)initWithKind:(S6ListKind)kind
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _kind = kind;
        _tracks = [NSArray array];
    }
    return self;
}

- (instancetype)initWithAlbum:(S6Album *)album
{
    if ((self = [self initWithKind:S6ListAlbum])) {
        _album = album;
        _contextURI = album.uri;
        _listTitle = album.name;
    }
    return self;
}

- (instancetype)initWithPlaylist:(S6Playlist *)playlist
{
    if ((self = [self initWithKind:S6ListPlaylist])) {
        _playlist = playlist;
        _contextURI = playlist.uri;
        _listTitle = playlist.name;
    }
    return self;
}

- (instancetype)initWithShow:(S6Show *)show
{
    if ((self = [self initWithKind:S6ListShow])) {
        _show = show;
        _contextURI = show.uri;
        _listTitle = show.name;
    }
    return self;
}

- (instancetype)initLikedSongs
{
    if ((self = [self initWithKind:S6ListLiked])) {
        _listTitle = L(@"Liked Songs");
        _contextURI = [NSString stringWithFormat:@"spotify:user:%@:collection", [S6Session shared].username ?: @""];
    }
    return self;
}

- (instancetype)initWithTracks:(NSArray *)tracks title:(NSString *)title contextURI:(NSString *)uri
{
    if ((self = [self initWithKind:S6ListTracks])) {
        _tracks = [tracks copy];
        _listTitle = title;
        _contextURI = uri;
        self.refreshable = NO;
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - View

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.listTitle;
    self.tableView.rowHeight = 56;
    [self.tableView registerClass:[S6TrackCell class] forCellReuseIdentifier:S6TrackCellId];
    [self buildHeader];
    [self showHeader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:S6LibraryDidChangeNotification object:nil];
}

- (void)libraryChanged
{
    if (self.kind == S6ListLiked || self.kind == S6ListPlaylist) [self reload];
}

- (UILabel *)headerLabel:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    [self.header addSubview:l];
    return l;
}

- (void)buildHeader
{
    S6Theme *theme = [S6Theme shared];
    self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10)];
    self.header.backgroundColor = [UIColor clearColor];
    self.cover = [[S6ImageView alloc] initWithFrame:CGRectZero];
    self.cover.contentMode = UIViewContentModeScaleAspectFill;
    self.cover.clipsToBounds = YES;
    self.cover.layer.shadowOpacity = 0.6;
    [self.header addSubview:self.cover];
    self.typeLabel = [self headerLabel:[theme sectionFont] color:[theme secondaryTextColor]];
    self.titleLabel = [self headerLabel:[theme headerFont] color:[theme primaryTextColor]];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.6;
    self.infoLabel = [self headerLabel:[theme smallFont] color:[theme secondaryTextColor]];
    self.infoLabel.numberOfLines = 2;
    self.descriptionLabel = [self headerLabel:[theme smallFont] color:[theme tertiaryTextColor]];
    self.descriptionLabel.numberOfLines = 2;
    self.descriptionLabel.userInteractionEnabled = YES;
    [self.descriptionLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(descriptionTapped)]];
    self.playButton = [theme greenButtonWithTitle:L(@"Play")];
    [self.playButton addTarget:self action:@selector(playAll) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.playButton];
    self.shuffleButton = [theme outlineButtonWithTitle:L(@"Shuffle")];
    [self.shuffleButton addTarget:self action:@selector(shuffleAll) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.shuffleButton];
    self.saveButton = [theme outlineButtonWithTitle:L(@"Save")];
    [self.saveButton addTarget:self action:@selector(toggleSaved) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.saveButton];
}

// A tap on the description opens the links in it (one at once, several listed first)
- (void)descriptionTapped
{
    [S6ExternalOpen presentLinkChooserForURLs:self.descriptionLinks from:self anchor:self.descriptionLabel];
}

- (NSString *)imageURL
{
    switch (self.kind) {
        case S6ListAlbum: return [self.album imageURLForSize:400];
        case S6ListPlaylist: return [self.playlist imageURLForSize:400];
        case S6ListShow: return [self.show imageURLForSize:400];
        default: return [(S6Track *)self.tracks.firstObject imageURLForSize:400];
    }
}

- (void)showHeader
{
    S6Theme *theme = [S6Theme shared];
    NSString *type = @"", *info = @"", *description = nil;
    switch (self.kind) {
        case S6ListAlbum: {
            type = [self.album.albumType isEqualToString:@"single"] ? L(@"Single") : [self.album.albumType isEqualToString:@"compilation"] ? L(@"Compilation") : L(@"Album");
            NSMutableArray *bits = [NSMutableArray array];
            if ([self.album artistNames].length) [bits addObject:[self.album artistNames]];
            if ([self.album year].length) [bits addObject:[self.album year]];
            if (self.tracks.count) [bits addObject:[NSString stringWithFormat:L(@"%lu songs"), (unsigned long)self.tracks.count]];
            info = [bits componentsJoinedByString:@" · "];
            break;
        }
        case S6ListPlaylist: {
            type = L(@"Playlist");
            NSMutableArray *bits = [NSMutableArray array];
            if (self.playlist.ownerName.length) [bits addObject:[NSString stringWithFormat:L(@"by %@"), self.playlist.ownerName]];
            if (self.playlist.followers) [bits addObject:[NSString stringWithFormat:L(@"%@ likes"), [S6Utils formatCount:self.playlist.followers]]];
            NSInteger n = self.playlist.totalTracks ?: (NSInteger)self.tracks.count;
            if (n) [bits addObject:[NSString stringWithFormat:L(@"%lu songs"), (unsigned long)n]];
            info = [bits componentsJoinedByString:@" · "];
            description = S6PlainText(self.playlist.descriptionText);
            break;
        }
        case S6ListLiked:
            type = L(@"Playlist");
            info = [NSString stringWithFormat:L(@"%lu songs"), (unsigned long)(self.total ?: (NSInteger)self.tracks.count)];
            break;
        case S6ListShow:
            type = L(@"Podcast");
            info = self.show.publisher ?: @"";
            description = S6PlainText(self.show.descriptionText);
            break;
        case S6ListTracks:
            info = [NSString stringWithFormat:L(@"%lu songs"), (unsigned long)self.tracks.count];
            break;
    }
    self.typeLabel.text = [type uppercaseString];
    self.titleLabel.text = [S6Utils displayText:self.listTitle];
    self.infoLabel.text = [S6Utils displayText:info];
    self.descriptionLabel.text = [S6Utils displayText:description];
    self.descriptionLinks = [S6ExternalOpen linksInText:description];
    if (self.kind == S6ListLiked) {
        self.cover.image = [self likedArtwork];
    } else {
        [self.cover setImageURL:[self imageURL] placeholder:[theme artPlaceholderWithSize:160]];
    }
    BOOL canSave = self.kind == S6ListAlbum || self.kind == S6ListShow ||
                   (self.kind == S6ListPlaylist && ![self.playlist.ownerId isEqualToString:[S6Session shared].username]);
    self.saveButton.hidden = !canSave;
    NSString *saveTitle = self.kind == S6ListAlbum ? (self.saved ? L(@"Saved") : L(@"Save")) : (self.saved ? L(@"Following") : L(@"Follow"));
    [self.saveButton setTitle:[saveTitle uppercaseString] forState:UIControlStateNormal];
    self.title = self.listTitle;
    [self layoutHeader];
}

- (UIImage *)likedArtwork
{
    S6Theme *theme = [S6Theme shared];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(160, 160), YES, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (id)[UIColor colorWithRed:0.29 green:0.18 blue:0.75 alpha:1].CGColor, (id)[UIColor colorWithRed:0.52 green:0.62 blue:0.85 alpha:1].CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(ctx, g, CGPointMake(0, 0), CGPointMake(160, 160), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
    [[theme icon:S6IconHeartFilled size:64] drawAtPoint:CGPointMake(48, 48)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)layoutHeader
{
    CGFloat w = self.tableView.bounds.size.width;
    BOOL wide = w > 500;
    CGFloat art = wide ? 180 : 120, pad = wide ? 24 : 14;
    self.cover.frame = CGRectMake(pad, pad, art, art);
    self.cover.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.cover.bounds].CGPath;
    CGFloat x = pad + art + 18, textW = w - x - pad;
    CGFloat y = pad + (wide ? 8 : 0);
    self.typeLabel.frame = CGRectMake(x, y, textW, 16);
    y += 18;
    CGSize t = [self.titleLabel.text sizeWithFont:self.titleLabel.font constrainedToSize:CGSizeMake(textW, wide ? 72 : 54) lineBreakMode:NSLineBreakByTruncatingTail];
    self.titleLabel.frame = CGRectMake(x, y, textW, MAX(ceilf(t.height), 26));
    y += MAX(ceilf(t.height), 26) + 4;
    self.infoLabel.frame = CGRectMake(x, y, textW, 34);
    [self.infoLabel sizeToFit];
    CGRect f = self.infoLabel.frame;
    f.size.width = textW;
    self.infoLabel.frame = f;
    y += f.size.height + 4;
    if (self.descriptionLabel.text.length) {
        self.descriptionLabel.frame = CGRectMake(x, y, textW, 34);
        y += 36;
    } else {
        self.descriptionLabel.frame = CGRectZero;
    }
    CGFloat by = MAX(y + 8, pad + art - 32);
    CGFloat bx = wide ? x : pad;
    if (!wide) by = pad + art + 14;
    S6Theme *theme = [S6Theme shared];
    CGFloat pw = [theme widthForButton:self.playButton minimum:100], sw = [theme widthForButton:self.shuffleButton minimum:100];
    self.playButton.frame = CGRectMake(bx, by, pw, 32);
    self.shuffleButton.frame = CGRectMake(bx + pw + 10, by, sw, 32);
    self.saveButton.frame = CGRectMake(bx + pw + sw + 20, by, [theme widthForButton:self.saveButton minimum:100], 32);
    CGFloat height = MAX(by + 32, pad + art) + pad;
    self.header.frame = CGRectMake(0, 0, w, height);
    self.tableView.tableHeaderView = self.header;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (fabs(self.header.bounds.size.width - self.tableView.bounds.size.width) > 1) [self layoutHeader];
}

#pragma mark - Loading

- (void)load
{
    if (self.kind == S6ListTracks) {
        [self finishLoadingWithError:nil empty:!self.tracks.count emptyMessage:L(@"Nothing here.")];
        [self showHeader];
        return;
    }
    [self startLoading];
    NSUInteger generation = ++self.generation;
    __unsafe_unretained S6TrackListViewController *weakSelf = self;
    // (if/else, not a switch: blocks in case labels without braces are a compile error under ARC)
    if (self.kind == S6ListAlbum) {
        [S6Catalog album:self.album.uri completion:^(S6Album *album, NSError *error) {
            S6TrackListViewController *me = weakSelf;
            if (!me || generation != me.generation) return;
            if (album) {
                me.album = album;
                me.listTitle = album.name;
                me.contextURI = album.uri;
                me.saved = album.saved;
            }
            me.tracks = album.tracks ?: [NSArray array];
            [me finishLoadingWithError:me.tracks.count ? nil : error empty:!me.tracks.count emptyMessage:L(@"Nothing here.")];
            [me showHeader];
        }];
        return;
    }
    if (self.kind == S6ListShow) {
        [S6Catalog show:self.show.uri completion:^(S6Show *show, NSError *error) {
            S6TrackListViewController *me = weakSelf;
            if (!me || generation != me.generation || !show) return;
            me.show = show;
            me.listTitle = show.name;
            me.saved = show.saved;
            [me showHeader];
        }];
    }
    [self loadFrom:0 into:[NSMutableArray array] generation:generation];
}

// Playlists, Liked Songs and a show's episodes come page after page; the list grows as they arrive
- (void)loadFrom:(NSInteger)offset into:(NSMutableArray *)all generation:(NSUInteger)generation
{
    __unsafe_unretained S6TrackListViewController *weakSelf = self;
    S6ListKind kind = self.kind;
    NSInteger max = kind == S6ListShow ? 300 : 3000;
    void (^page)(NSArray *, NSInteger, NSError *) = [^(NSArray *tracks, NSInteger total, NSError *error) {
        S6TrackListViewController *me = weakSelf;
        if (!me || generation != me.generation) return;
        [all addObjectsFromArray:tracks ?: [NSArray array]];
        me.tracks = [all copy];
        me.total = total;
        if (!error && tracks.count && (NSInteger)all.count < MIN(total, max)) {
            [me.tableView reloadData];
            [me showHeader];
            [me loadFrom:offset + (NSInteger)tracks.count into:all generation:generation];
            return;
        }
        [me finishLoadingWithError:all.count ? nil : error empty:!all.count
                      emptyMessage:kind == S6ListLiked ? L(@"Songs you like show up here. Tap the heart.") : L(@"Nothing here.")];
        [me showHeader];
    } copy];
    if (kind == S6ListPlaylist) {
        [S6Catalog playlist:self.playlist.uri offset:offset limit:100 completion:^(S6Playlist *playlist, NSArray *tracks, NSInteger total, NSError *error) {
            S6TrackListViewController *me = weakSelf;
            if (playlist && offset == 0 && me && generation == me.generation) {
                me.playlist = playlist;
                me.listTitle = playlist.name;
                me.contextURI = playlist.uri;
                me.saved = playlist.saved;
            }
            page(tracks, total, error);
        }];
    } else if (kind == S6ListLiked) {
        [S6Catalog likedSongsOffset:offset limit:100 completion:page];
    } else if (kind == S6ListShow) {
        [S6Catalog showEpisodes:self.show.uri offset:offset limit:50 completion:page];
    }
}

#pragma mark - Actions

- (void)playAll
{
    if (!self.tracks.count) return;
    [S6Player shared].shuffle = NO;
    [[S6Player shared] playTracks:self.tracks startingAt:0 contextURI:self.contextURI contextName:self.listTitle];
}

- (void)shuffleAll
{
    [[S6Player shared] playTracksShuffled:self.tracks contextURI:self.contextURI contextName:self.listTitle];
}

- (void)toggleSaved
{
    NSString *uri = self.kind == S6ListAlbum ? self.album.uri : self.kind == S6ListPlaylist ? self.playlist.uri : self.show.uri;
    if (!uri.length) return;
    BOOL saved = !self.saved;
    self.saved = saved;
    [self showHeader];
    __unsafe_unretained S6TrackListViewController *weakSelf = self;
    [S6Catalog setSaved:saved uris:@[ uri ] completion:^(NSError *error) {
        if (!error) return;
        [S6Router toast:error.localizedDescription];
        weakSelf.saved = !saved;
        [weakSelf showHeader];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.tracks.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6TrackCell *cell = [tableView dequeueReusableCellWithIdentifier:S6TrackCellId forIndexPath:indexPath];
    S6Track *t = self.tracks[(NSUInteger)indexPath.row];
    cell.showsArt = self.kind != S6ListAlbum;
    [cell showTrack:t number:self.kind == S6ListAlbum ? (t.trackNumber ?: indexPath.row + 1) : 0];
    [cell.moreButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.moreButton addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.moreButton.tag = indexPath.row;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    S6Track *t = self.tracks[(NSUInteger)indexPath.row];
    if (!t.playable) { [S6Router toast:L(@"This song is not available.")]; return; }
    S6Track *current = [S6Player shared].currentTrack;
    if (current && [current.uri isEqualToString:t.uri]) { [S6Router showNowPlaying]; return; }
    [[S6Player shared] playTracks:self.tracks startingAt:(NSUInteger)indexPath.row contextURI:self.contextURI contextName:self.listTitle];
}

- (void)moreTapped:(UIButton *)sender
{
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.tracks.count) return;
    S6Track *t = self.tracks[(NSUInteger)sender.tag];
    BOOL editable = self.kind == S6ListPlaylist && self.playlist.editable;
    [S6Router showActionsForTrack:t fromView:sender inController:self playlist:editable ? self.playlist : nil];
}

@end
