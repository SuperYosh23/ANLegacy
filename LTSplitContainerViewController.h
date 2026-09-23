#import <UIKit/UIKit.h>

@class LTTabBarController;

// Root container used on iPad only. In portrait it shows the regular tab bar;
// in landscape it swaps that for a left sidebar listing the five destinations.
// The tab bar controller owns all of the child navigation controllers in both
// layouts so the sidebar just switches its selectedIndex.
@interface LTSplitContainerViewController : UIViewController

@property (nonatomic, strong, readonly) LTTabBarController *tabController;

+ (BOOL)isSupported;

- (instancetype)initWithTabController:(LTTabBarController *)tabController;

@end