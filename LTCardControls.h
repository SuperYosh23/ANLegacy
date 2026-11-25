#import <UIKit/UIKit.h>

// Anything that behaves like a switch.
//
// The settings screen has a switch that is the platform's own in the native
// theme and one of ours in the modern themes. Both have to answer to the same
// code, so both are described by this.
@protocol LTToggleControl <NSObject>

@property (nonatomic, assign, getter=isOn) BOOL on;

@end

// The platform's switch already has an `on` property; this is just so the
// settings screen can hold either kind in one property.
@interface UISwitch (LTToggleControl) <LTToggleControl>
@end

// A Material 3 switch: a track, a thumb, and a check mark in the thumb when it
// is on.
//
// Deliberately NOT a subclass of UISwitch. The platform's switch draws itself
// with private views, and the touch handling lives in those views: the themed
// table moves the accessory out of the cell and into the row it draws, and a
// platform switch that has been re-parented that way stops answering taps
// altogether - the touch lands on it and nothing happens.
//
// So this is a plain control that draws the whole switch and handles its own
// touches, with none of the platform's underneath to fight. The native theme
// keeps the real UISwitch.
@interface LTCardSwitch : UIControl <LTToggleControl>
@end

// A Material 3 segmented control: a rounded track with a pill behind the
// selected item.
//
// Also a plain control, for the same reason.
@interface LTCardSegmented : UIControl

// Built from a list of titles, the way the platform's segmented control is, so
// the screens that create one do not have to care which kind they get.
- (instancetype)initWithItems:(NSArray *)items;

@property (nonatomic, copy) NSArray *items;
@property (nonatomic, assign) NSInteger selectedIndex;

// The screens set the title attributes on the platform's control, so ours has to
// accept them. Only the font is used; the colour comes from the theme.
- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state;

@end

// The native control used on iOS 4-6. The old implementation resets the fonts
// on its private segment labels during layout, so a font set once in
// viewDidLoad is lost by the time the view appears - it only comes back when a
// tap happens to redraw the segment. This subclass re-applies the font after
// every layout pass, which is the only reliable place to do it on iOS 4.
@interface LTCompactSegmentedControl : UISegmentedControl
- (void)setCompactTitleFont:(UIFont *)font;
@end

// A section header drawn by us.
//
// UITableView draws the section title itself, in a colour that cannot be set -
// on every iOS before 13 that is black, which is how "Recently Played" and
// "Your Playlists" ended up black on the modern dark theme.
@interface LTSectionHeaderView : UIView

// The title, drawn in the theme's secondary text colour.
+ (instancetype)headerWithTitle:(NSString *)title;

@end
