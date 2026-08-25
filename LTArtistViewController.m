#import "LTArtistViewController.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTMediaCell.h"
#import "LTHeaderView.h"
#import "LTTrackListViewController.h"
#import "LTTabBarController.h"
#import "LTPlayerController.h"

@interface LTArtistViewController ()
@property (nonatomic, copy) NSString *browseId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *topSongs;
@property (nonatomic, strong) NSArray *albums;
@property (nonatomic, strong) NSDictionary *info;
@property (nonatomic, strong) LTHeaderView *headerView;
@end

@implementation LTArtistViewController

- (id)initWithBrowseId:(NSString *)browseId title:(NSString *)title {
    self = [super init];
    if (self) {
        _browseId = [browseId copy];
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.view.backgroundColor = [UIColor whiteColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    self.headerView = [[LTHeaderView alloc] initWithWidth:self.view.bounds.size.width];
    self.tableView.tableHeaderView = self.headerView;

    [self loadContent];
}

- (void)loadContent {
    __weak LTArtistViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] browseArtist:self.browseId completion:^(NSDictionary *info, NSArray *topSongs, NSArray *albums, NSError *error) {
        LTArtistViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Load Failed"
                                                            message:error.localizedDescription
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
            return;
        }
        strongSelf.info = info;
        strongSelf.topSongs = topSongs;
        strongSelf.albums = albums;
        if (info[@"title"]) strongSelf.headerView.titleLabel.text = info[@"title"];
        if (info[@"subtitle"]) strongSelf.headerView.subtitleLabel.text = info[@"subtitle"];
        [strongSelf.headerView setArtworkURL:info[@"thumbnail"]];
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger sections = 0;
    if (self.topSongs.count) sections++;
    if (self.albums.count) sections++;
    return sections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0 && self.topSongs.count) return @"Top Songs";
    return @"Albums";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 && self.topSongs.count) return (NSInteger)self.topSongs.count;
    return (NSInteger)self.albums.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *TrackId = @"LTTrackCell";
    static NSString *AlbumId = @"LTAlbumCell";
    BOOL isSongs = (indexPath.section == 0 && self.topSongs.count);
    NSString *cellId = isSongs ? TrackId : AlbumId;
    LTMediaCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[LTMediaCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    if (isSongs) {
        LTTrack *track = [self.topSongs objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = track.title;
        cell.detailTextLabel.text = track.album;
        cell.accessoryType = UITableViewCellAccessoryNone;
        [cell setImageFromURL:track.thumbnailURL];
    } else {
        LTBrowseItem *album = [self.albums objectAtIndex:(NSUInteger)indexPath.row];
        cell.textLabel.text = album.title;
        cell.detailTextLabel.text = album.subtitle;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [cell setImageFromURL:album.thumbnailURL];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 54.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL isSongs = (indexPath.section == 0 && self.topSongs.count);
    if (isSongs) {
        [[LTPlayerController sharedController] playQueue:self.topSongs atIndex:indexPath.row];
        [(LTTabBarController *)self.tabBarController showNowPlaying];
    } else {
        LTBrowseItem *album = [self.albums objectAtIndex:(NSUInteger)indexPath.row];
        LTTrackListViewController *vc = [[LTTrackListViewController alloc] initWithBrowseId:album.browseId
                                                                                        kind:LTBrowseKindAlbum
                                                                                       title:album.title];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
