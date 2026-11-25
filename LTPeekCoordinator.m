#import "LTPeekCoordinator.h"
#import "LTLog.h"
#import "LTModel.h"
#import "LTArtworkPeekViewController.h"
#import <objc/message.h>

@interface LTPeekCoordinator ()
@property (nonatomic, unsafe_unretained) UIViewController *owner;
@property (nonatomic, unsafe_unretained) UIView *sourceView;
@property (nonatomic, copy) LTPeekProviderBlock provider;
@property (nonatomic, copy) LTPeekCommitBlock commit;
@end

@implementation LTPeekCoordinator

- (instancetype)initWithOwner:(UIViewController *)owner
                    sourceView:(UIView *)sourceView
                 peekProvider:(LTPeekProviderBlock)provider
                       commit:(LTPeekCommitBlock)commit {
    if ((self = [super init])) {
        _owner = owner;
        _sourceView = sourceView;
        _provider = [provider copy];
        _commit = [commit copy];
    }
    return self;
}

- (void)registerPreview {
    UIViewController *owner = self.owner;
    UIView *source = self.sourceView;
    if (!owner || !source) return;

    // Available from iOS 9; the app still supports iOS 6, where this selector is
    // absent and peek is simply unavailable.
    SEL selector = @selector(registerForPreviewingWithDelegate:sourceView:);
    if (![owner respondsToSelector:selector]) {
        LTLog(@"PEEK unavailable on this OS");
        return;
    }
    // Sent through objc_msgSend so the iOS 9-only selector is not called directly
    // against an iOS 6 deployment target.
    id (*send)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
    id context = send(owner, selector, (id)self, source);
    LTLog(@"PEEK registered on %@ ctx=%@", NSStringFromClass([source class]), context ? @"yes" : @"no");
}

#pragma mark - UIViewControllerPreviewingDelegate

// iOS 9.0 through 10.x. The inSourceView: argument below did not exist yet, and
// UIKit looks for this exact selector, so it has to be implemented separately
// from the newer variant.
- (UIViewController *)previewingContext:(id)previewingContext
                  viewControllerForLocation:(CGPoint)location {
    return [self peekViewControllerForLocation:location];
}

// iOS 11 and later.
- (UIViewController *)previewingContext:(id)previewingContext
                  viewControllerForLocation:(CGPoint)location
                          inSourceView:(UIView *)sourceView {
    return [self peekViewControllerForLocation:location];
}

- (void)previewingContext:(id)previewingContext
    commitViewController:(UIViewController *)viewControllerToCommit {
    if (!self.commit) return;   // nothing to open; UIKit dismisses the peek
    self.commit(viewControllerToCommit);
}

- (UIViewController *)peekViewControllerForLocation:(CGPoint)location {
    UIViewController *peek = self.provider ? self.provider(location) : nil;
    LTLog(@"PEEK %@ at %.0f,%.0f", peek ? @"hit" : @"miss", location.x, location.y);
    return peek;
}

@end
@implementation LTPeekCoordinator (Songs)

+ (UIImage *)artworkForRowAtIndexPath:(NSIndexPath *)indexPath inTableView:(UITableView *)tableView {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if ([cell.imageView isKindOfClass:[UIImageView class]]) return cell.imageView.image;
    return nil;
}

+ (LTPeekCoordinator *)songArtworkPeekForTableView:(UITableView *)tableView
                                             owner:(UIViewController *)owner
                                   songAtIndexPath:(LTSongAtIndexPathBlock)songAtIndexPath {
    LTPeekCoordinator *coordinator = [[LTPeekCoordinator alloc] initWithOwner:owner
                                                                    sourceView:tableView
                                                                 peekProvider:^UIViewController *(CGPoint location) {
        NSIndexPath *indexPath = [tableView indexPathForRowAtPoint:location];
        if (!indexPath) return nil;
        LTTrack *track = songAtIndexPath(indexPath);
        if (!track) return nil;
        // Reuse what the row already shows, so the peek is never blank while a
        // new image loads.
        UIImage *image = [LTPeekCoordinator artworkForRowAtIndexPath:indexPath inTableView:tableView];
        return [[LTArtworkPeekViewController alloc] initWithTrack:track image:image];
    } commit:nil];

    [coordinator registerPreview];
    return coordinator;
}

@end
