#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, S6Icon) {
    S6IconHome = 0,
    S6IconSearch,
    S6IconLibrary,
    S6IconRadio,
    S6IconSettings,
    S6IconBrowse,
    S6IconPlaylist,
    S6IconHeart,
    S6IconHeartFilled,
    S6IconAlbum,
    S6IconArtist,
    S6IconPodcast,
    S6IconPlay,
    S6IconPause,
    S6IconNext,
    S6IconPrevious,
    S6IconShuffle,
    S6IconRepeat,
    S6IconRepeatOne,
    S6IconQueue,
    S6IconLyrics,
    S6IconDevices,
    S6IconMore,
    S6IconPlus,
    S6IconClose,
    S6IconChevronDown,
    S6IconSpeaker,
    S6IconClock,
    S6IconCheck,
    S6IconMoon,              // the sleep timer
};

// The look of Sixify: Spotify's own iPad app of the iOS 6 years - charcoal, textured panels, glossy black bars, the
// green of 2012, artwork drawn in code (no image files). Dark only.
@interface S6Theme : NSObject

+ (instancetype)shared;

// Colours
- (UIColor *)backgroundColor;          // content (textured)
- (UIColor *)plainBackgroundColor;     // the same without texture (cells, labels)
- (UIColor *)panelColor;               // the iPad sidebar
- (UIColor *)rowColor;
- (UIColor *)rowHighlightColor;
- (UIColor *)primaryTextColor;
- (UIColor *)secondaryTextColor;
- (UIColor *)tertiaryTextColor;
- (UIColor *)separatorColor;
- (UIColor *)accentColor;              // Spotify green
- (UIColor *)accentTextColor;          // green readable on dark

// Artwork
- (UIImage *)navigationBarImage;
- (UIImage *)playerBarImage;           // the now-playing strip along the bottom
- (UIImage *)tabBarImage;
- (UIImage *)greenButtonImageHighlighted:(BOOL)highlighted;
- (UIImage *)darkButtonImageHighlighted:(BOOL)highlighted;
- (UIImage *)outlineButtonImageHighlighted:(BOOL)highlighted;
- (UIImage *)searchFieldImage;
- (UIImage *)sidebarSelectionImage;
- (UIImage *)sectionHeaderImage;
- (UIImage *)artPlaceholderWithSize:(CGFloat)size;      // dark square with a note
- (UIImage *)artistPlaceholderWithSize:(CGFloat)size;   // round
- (UIImage *)shadowImageTop:(BOOL)top;                  // black fade (over artwork)
- (UIImage *)sliderTrackImageFilled:(BOOL)filled;
- (UIImage *)sliderThumbImage;
- (UIImage *)explicitBadge;
- (UIImage *)brandMarkWithSize:(CGFloat)size;           // Sixify's mark: a glossy green disc with a white 6

- (UIImage *)icon:(S6Icon)icon size:(CGFloat)size color:(UIColor *)color;
- (UIImage *)icon:(S6Icon)icon size:(CGFloat)size;      // white

// Fonts
- (UIFont *)titleFont;
- (UIFont *)bodyFont;
- (UIFont *)boldBodyFont;
- (UIFont *)smallFont;
- (UIFont *)headerFont;                 // big page titles
- (UIFont *)sectionFont;                // "RECENTLY PLAYED"

// Applying to UIKit
- (void)applyGlobalAppearance;
- (void)applyToNavigationBar:(UINavigationBar *)bar;
- (void)applyToTableView:(UITableView *)tableView;
- (void)styleCell:(UITableViewCell *)cell;
- (void)applyToSearchBar:(UISearchBar *)bar;
- (UIButton *)greenButtonWithTitle:(NSString *)title;
- (UIButton *)outlineButtonWithTitle:(NSString *)title;
- (CGFloat)widthForButton:(UIButton *)button minimum:(CGFloat)minimum;   // its title fits (Czech words are longer)
- (UIActivityIndicatorViewStyle)spinnerStyle;

@end
