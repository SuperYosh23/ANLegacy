#import <UIKit/UIKit.h>

// Builds the view controller to show in the peek card for a press at the given
// point, in the source view's coordinate space. Returning nil cancels the peek.
typedef UIViewController * (^LTPeekProviderBlock)(CGPoint location);

// Called on a full press. The argument is whatever the provider returned, so it
// can be cast back to the peek class to recover the model behind it. A nil
// commit block means a full press simply dismisses the peek.
typedef void (^LTPeekCommitBlock)(UIViewController *peekViewController);


// Owns one UIViewControllerPreviewing registration.
//
// 3D Touch arrived in iOS 8 and peek in iOS 9, so this works on the iPhone 6s
// running iOS 9. The SDK these targets build against (9.3) declares the
// previewing protocols, so they are used directly rather than by duck typing.
//
// -registerPreview is still guarded because the app supports iOS 6, where the
// selector does not exist.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
@interface LTPeekCoordinator : NSObject <UIViewControllerPreviewingDelegate>
#else
@interface LTPeekCoordinator : NSObject
#endif

- (instancetype)initWithOwner:(UIViewController *)owner
                    sourceView:(UIView *)sourceView
                 peekProvider:(LTPeekProviderBlock)provider
                       commit:(LTPeekCommitBlock)commit;

// Does nothing below iOS 9.
- (void)registerPreview;

@end

@class LTTrack;

// Resolves the song shown at a row. Return nil for rows that are not songs,
// which cancels the peek for those rows.
typedef LTTrack * (^LTSongAtIndexPathBlock)(NSIndexPath *indexPath);

@interface LTPeekCoordinator (Songs)

// Registers the large-artwork peek used for song rows. The artwork already
// loaded in the cell is reused so the card appears instantly, and the
// high-resolution copy is only fetched if the cell has none yet.
//
// Nothing is opened on a full press, matching the Now Playing artwork peek.
// The caller must retain the returned coordinator.
+ (LTPeekCoordinator *)songArtworkPeekForTableView:(UITableView *)tableView
                                             owner:(UIViewController *)owner
                                   songAtIndexPath:(LTSongAtIndexPathBlock)songAtIndexPath;

// The artwork a row is already showing, so a peek can reuse it instead of
// starting blank. Returns nil for rows with no image view.
+ (UIImage *)artworkForRowAtIndexPath:(NSIndexPath *)indexPath inTableView:(UITableView *)tableView;

@end
