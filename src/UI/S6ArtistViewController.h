#import "S6ListViewController.h"

@class S6Artist;

// An artist: the picture, followers, Play and Follow, the popular songs, the albums, singles and EPs, what they appear
// on, and the artists their fans also like
@interface S6ArtistViewController : S6ListViewController
- (instancetype)initWithArtist:(S6Artist *)artist;
@end
