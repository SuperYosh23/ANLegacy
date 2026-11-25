#import "S6ArtistViewController.h"
#import "S6TrackListViewController.h"
#import "S6Cells.h"
#import "S6Router.h"
#import "S6Theme.h"
#import "S6Models.h"
#import "S6Catalog.h"
#import "S6Player.h"
#import "S6ImageLoader.h"
#import "S6Utils.h"
#import "S6Common.h"

enum { S6ArtistPopular, S6ArtistAlbums, S6ArtistSingles, S6ArtistAppears, S6ArtistPlaylists, S6ArtistRelated, S6ArtistSectionCount };

@interface S6ArtistViewController ()
@property (nonatomic, strong) S6Artist *artist;
@property (nonatomic, strong) NSArray *topTracks;
@property (nonatomic, strong) NSArray *albums;
@property (nonatomic, strong) NSArray *singles;
@property (nonatomic, strong) NSArray *appearsOn;
@property (nonatomic, strong) NSArray *playlists;
@property (nonatomic, strong) NSArray *related;
@property (nonatomic) BOOL showAllPopular;
@property (nonatomic) BOOL following;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) S6ImageView *picture;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *followButton;
@end

@implementation S6ArtistViewController

- (instancetype)initWithArtist:(S6Artist *)artist
{
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _artist = artist;
        _topTracks = [NSArray array];
        _albums = [NSArray array];
        _singles = [NSArray array];
        _appearsOn = [NSArray array];
        _playlists = [NSArray array];
        _related = [NSArray array];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.artist.name;
    [self.tableView registerClass:[S6TrackCell class] forCellReuseIdentifier:@"track"];
    [self.tableView registerClass:[S6MediaCell class] forCellReuseIdentifier:@"media"];
    [self.tableView registerClass:[S6ShelfCell class] forCellReuseIdentifier:@"shelf"];
    S6Theme *theme = [S6Theme shared];
    self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10)];
    self.picture = [[S6ImageView alloc] initWithFrame:CGRectZero];
    self.picture.contentMode = UIViewContentModeScaleAspectFill;
    self.picture.clipsToBounds = YES;
    [self.header addSubview:self.picture];
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.font = [theme headerFont];
    self.nameLabel.textColor = [theme primaryTextColor];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.6;
    [self.header addSubview:self.nameLabel];
    self.infoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.infoLabel.font = [theme smallFont];
    self.infoLabel.textColor = [theme secondaryTextColor];
    self.infoLabel.backgroundColor = [UIColor clearColor];
    [self.header addSubview:self.infoLabel];
    self.playButton = [theme greenButtonWithTitle:L(@"Play")];
    [self.playButton addTarget:self action:@selector(playTop) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.playButton];
    self.followButton = [theme outlineButtonWithTitle:L(@"Follow")];
    [self.followButton addTarget:self action:@selector(toggleFollow) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.followButton];
    [self showHeader];
}

- (void)showHeader
{
    S6Theme *theme = [S6Theme shared];
    self.title = self.artist.name;
    self.nameLabel.text = [S6Utils displayText:self.artist.name];
    NSMutableArray *bits = [NSMutableArray array];
    if (self.artist.monthlyListeners) [bits addObject:[NSString stringWithFormat:L(@"%@ monthly listeners"), [S6Utils formatCount:self.artist.monthlyListeners]]];
    if (self.artist.followers) [bits addObject:[NSString stringWithFormat:L(@"%@ followers"), [S6Utils formatCount:self.artist.followers]]];
    self.infoLabel.text = [bits componentsJoinedByString:@" · "];
    [self.picture setImageURL:[self.artist imageURLForSize:400] placeholder:[theme artistPlaceholderWithSize:150]];
    [self.followButton setTitle:[(self.following ? L(@"Following") : L(@"Follow")) uppercaseString] forState:UIControlStateNormal];
    CGFloat w = self.tableView.bounds.size.width;
    BOOL wide = w > 500;
    CGFloat side = wide ? 150 : 110, pad = wide ? 24 : 14;
    self.picture.frame = CGRectMake(pad, pad, side, side);
    self.picture.layer.cornerRadius = side / 2;
    CGFloat x = pad + side + 20;
    self.nameLabel.frame = CGRectMake(x, pad + side / 2 - 48, w - x - pad, 40);
    self.infoLabel.frame = CGRectMake(x, pad + side / 2 - 6, w - x - pad, 18);
    CGFloat pw = [theme widthForButton:self.playButton minimum:100];
    self.playButton.frame = CGRectMake(x, pad + side / 2 + 20, pw, 32);
    self.followButton.frame = CGRectMake(x + pw + 10, pad + side / 2 + 20, [theme widthForButton:self.followButton minimum:110], 32);
    self.header.frame = CGRectMake(0, 0, w, side + pad * 2);
    self.tableView.tableHeaderView = self.header;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (fabs(self.header.bounds.size.width - self.tableView.bounds.size.width) > 1) [self showHeader];
}

- (void)load
{
    [self startLoading];
    __unsafe_unretained S6ArtistViewController *weakSelf = self;
    [S6Catalog artist:self.artist.uri completion:^(S6ArtistPage *page, NSError *error) {
        S6ArtistViewController *me = weakSelf;
        if (!me) return;
        if (page) {
            me.artist = page.artist;
            me.following = page.artist.saved;
            me.topTracks = page.topTracks ?: [NSArray array];
            me.albums = [(page.albums ?: [NSArray array]) arrayByAddingObjectsFromArray:page.compilations ?: [NSArray array]];
            me.singles = page.singles ?: [NSArray array];
            me.appearsOn = page.appearsOn ?: [NSArray array];
            me.playlists = page.playlists ?: [NSArray array];
            me.related = page.related ?: [NSArray array];
        }
        BOOL empty = !me.topTracks.count && !me.albums.count && !me.singles.count;
        [me finishLoadingWithError:empty ? error : nil empty:empty emptyMessage:L(@"Nothing here.")];
        [me showHeader];
    }];
}

- (void)playTop
{
    if (self.topTracks.count) [[S6Player shared] playTracks:self.topTracks startingAt:0 contextURI:self.artist.uri contextName:self.artist.name];
}

- (void)toggleFollow
{
    BOOL follow = !self.following;
    self.following = follow;
    [self showHeader];
    __unsafe_unretained S6ArtistViewController *weakSelf = self;
    [S6Catalog setSaved:follow uris:@[ self.artist.uri ?: @"" ] completion:^(NSError *error) {
        if (!error) return;
        [S6Router toast:error.localizedDescription];
        weakSelf.following = !follow;
        [weakSelf showHeader];
    }];
}

#pragma mark - Table

- (NSArray *)albumsIn:(NSInteger)section
{
    if (section == S6ArtistAlbums) return self.albums;
    if (section == S6ArtistSingles) return self.singles;
    if (section == S6ArtistAppears) return self.appearsOn;
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return S6ArtistSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case S6ArtistPopular: {
            NSInteger n = (NSInteger)self.topTracks.count;
            if (!self.showAllPopular && n > 5) return 6;   // five and "See more"
            return n;
        }
        case S6ArtistRelated: return self.related.count ? 1 : 0;
        case S6ArtistPlaylists: return self.playlists.count ? 1 : 0;
        default: return (NSInteger)MIN((NSUInteger)20, [self albumsIn:section].count);
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == S6ArtistRelated || indexPath.section == S6ArtistPlaylists) return [S6ShelfCell heightForCardWidth:S6IsPad() ? 130 : 100];
    if (indexPath.section == S6ArtistPopular) return 56;
    return 68;
}

- (NSString *)titleFor:(NSInteger)section
{
    switch (section) {
        case S6ArtistPopular: return L(@"Popular");
        case S6ArtistAlbums: return L(@"Albums");
        case S6ArtistSingles: return L(@"Singles and EPs");
        case S6ArtistAppears: return L(@"Appears on");
        case S6ArtistPlaylists: return L(@"Featuring");
        default: return L(@"Fans also like");
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (![self tableView:tableView numberOfRowsInSection:section]) return nil;
    return S6SectionHeader([self titleFor:section], tableView.bounds.size.width);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [self tableView:tableView numberOfRowsInSection:section] ? 26 : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    S6Theme *theme = [S6Theme shared];
    if (indexPath.section == S6ArtistPopular) {
        if (!self.showAllPopular && indexPath.row == 5) {
            UITableViewCell *more = [tableView dequeueReusableCellWithIdentifier:@"more"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"more"];
            [theme styleCell:more];
            more.textLabel.text = L(@"See more");
            more.textLabel.font = [theme boldBodyFont];
            more.textLabel.textColor = [theme secondaryTextColor];
            return more;
        }
        S6TrackCell *cell = [tableView dequeueReusableCellWithIdentifier:@"track" forIndexPath:indexPath];
        cell.showsArt = YES;
        [cell showTrack:self.topTracks[(NSUInteger)indexPath.row] number:indexPath.row + 1];
        [cell.moreButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [cell.moreButton addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
        cell.moreButton.tag = indexPath.row;
        return cell;
    }
    if (indexPath.section == S6ArtistRelated || indexPath.section == S6ArtistPlaylists) {
        S6ShelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"shelf" forIndexPath:indexPath];
        NSMutableArray *items = [NSMutableArray array];
        for (id x in indexPath.section == S6ArtistRelated ? self.related : self.playlists) {
            NSDictionary *card = S6CardFor(x);
            if (card) [items addObject:card];
        }
        [cell showItems:items cardWidth:S6IsPad() ? 130 : 100];
        cell.onSelect = ^(id item) { [S6Router openItem:item]; };
        return cell;
    }
    S6MediaCell *cell = [tableView dequeueReusableCellWithIdentifier:@"media" forIndexPath:indexPath];
    S6Album *a = [self albumsIn:indexPath.section][(NSUInteger)indexPath.row];
    cell.round = NO;
    NSString *count = a.totalTracks == 1 ? L(@"Single") : a.totalTracks ? [NSString stringWithFormat:L(@"%lu songs"), (unsigned long)a.totalTracks] : @"";
    NSString *sub = indexPath.section == S6ArtistAppears ? [NSString stringWithFormat:@"%@ · %@", [a year], [a artistNames]] :
                    count.length ? [NSString stringWithFormat:@"%@ · %@", [a year], count] : [a year];
    [cell showTitle:a.name subtitle:sub imageURL:[a imageURLForSize:120]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == S6ArtistPopular) {
        if (!self.showAllPopular && indexPath.row == 5) {
            self.showAllPopular = YES;
            [tableView reloadSections:[NSIndexSet indexSetWithIndex:S6ArtistPopular] withRowAnimation:UITableViewRowAnimationFade];
            return;
        }
        [[S6Player shared] playTracks:self.topTracks startingAt:(NSUInteger)indexPath.row contextURI:self.artist.uri contextName:self.artist.name];
        return;
    }
    NSArray *albums = [self albumsIn:indexPath.section];
    if ((NSUInteger)indexPath.row < albums.count) [S6Router openAlbum:albums[(NSUInteger)indexPath.row]];
}

- (void)moreTapped:(UIButton *)sender
{
    if (sender.tag < (NSInteger)self.topTracks.count) [S6Router showActionsForTrack:self.topTracks[(NSUInteger)sender.tag] fromView:sender inController:self playlist:nil];
}

@end
