#import "S6ListViewController.h"

// Search: songs, artists, albums, playlists and podcasts as you type; recent searches and the browse categories
// while the field is empty
@interface S6SearchViewController : S6ListViewController
- (void)focusSearchField;
- (void)searchFor:(NSString *)query;
@end

// One browse category's playlists
@interface S6CategoryViewController : S6ListViewController
- (instancetype)initWithCategoryId:(NSString *)categoryId name:(NSString *)name;
@end
