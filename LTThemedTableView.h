#import <UIKit/UIKit.h>

// A list drawn by us, rather than a UITableView with native cells.
//
// WHY: the native table cell cannot be made to look like the desktop app's
// list. Its background, its grouped-style rounded corners at the edges, its
// separator, its selection highlight and its text layout are all the platform's
// own, and none of them can be recoloured on iOS 6 through 11. Bolting a
// rounded shape behind each native cell - which is what this replaces - left
// the native cell's own chrome showing through, so the list still read as an
// iOS list.
//
// So the rows are drawn here: a card, its artwork, its title and subtitle, and
// its trailing accessory, all in the theme's colours. The table view remains
// for scrolling and for hit testing, but it draws nothing of its own.
@interface LTThemedTableView : UITableView

// Where the card's edge goes, in points, for a table whose rows have to clear
// something on the left - the queue's editing controls, which the platform
// only moves in when the table goes into editing mode. The rows are indented
// by this much whether or not it is, so they do not jump when the table is
// put into editing mode. Zero leaves the card at its usual margin.
@property (nonatomic, assign) CGFloat leadingRowInset;

@end
