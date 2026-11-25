#import "LTThemedTableView.h"
#import <objc/message.h>
#import "LTTheme.h"
#import "LTLog.h"
#import <objc/runtime.h>

// Horizontal inset of a card from the edge of the table. Material 3 uses 16pt
// of side padding on a phone, and the gutter on the leading edge is where a
// row's indicator goes - the queue's play glyph, marking the track that is
// playing - so it is wide enough for one.
static const CGFloat LTCardInset = 20.0f;
// Space above and below each card, so they read as separate surfaces.
static const CGFloat LTCardGap = 6.0f;
// The artwork's size in a list row.
static const CGFloat LTArtworkSize = 44.0f;
// The padding inside a card, between its edge and its text.
static const CGFloat LTCardPadding = 12.0f;
// The gap between an indicator in the margin and the card beside it.
static const CGFloat LTIndicatorGap = 8.0f;

// One row of the list, drawn by us.
//
// The content is taken from the cell the table view handed us - the title, the
// subtitle, the artwork and the accessory - so the screens do not have to
// change at all. What changes is that none of the platform's own chrome is
// used: no cell background, no grouped corners, no separator, no selection
// highlight.
@interface LTCardRowView : UIView

// The content, copied from the cell.
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong) UIImage *artwork;
@property (nonatomic, strong) UIImage *accessoryImage;
// A live control the screen put in the cell's accessory slot - a switch, a
// button, a spinner. The platform lays those out against the cell's own edge,
// which is outside the card, so the themed table moves them into the card and
// places them by hand.
@property (nonatomic, strong) UIView *accessoryControl;
// Where the cell's content view is, in the row's own coordinates. The
// platform moves it aside when the cell is in editing mode, and the row's
// contents follow it so they clear the editing controls.
@property (nonatomic, assign) CGRect contentRect;
// Where the card's edge goes, for a table whose rows have to clear something
// on the left. Zero leaves the card at its usual margin.
@property (nonatomic, assign) CGFloat leadingRowInset;
@property (nonatomic, assign) BOOL selected;

@end

@implementation LTCardRowView {
    BOOL _loggedHit;
    BOOL _loggedLayout;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    [self setNeedsDisplay];
}

- (void)setSubtitle:(NSString *)subtitle {
    _subtitle = [subtitle copy];
    [self setNeedsDisplay];
}

- (void)setArtwork:(UIImage *)artwork {
    _artwork = artwork;
    [self setNeedsDisplay];
}

- (void)setAccessoryImage:(UIImage *)accessoryImage {
    _accessoryImage = accessoryImage;
    [self setNeedsDisplay];
}

- (void)setAccessoryControl:(UIView *)accessoryControl {
    if (_accessoryControl == accessoryControl) {
        // Something took the control out of the row - emptying the cell's
        // accessory view does exactly that - so it goes back in.
        if (accessoryControl && accessoryControl.superview != self) {
            [self addSubview:accessoryControl];
            [self setNeedsLayout];
        }
        return;
    }
    [_accessoryControl removeFromSuperview];
    _accessoryControl = accessoryControl;
    if (_accessoryControl) [self addSubview:_accessoryControl];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    [self setNeedsDisplay];
}

// The card's own rect: the row's margin, moved in when the cell's content
// view has been moved aside.
//
// The platform moves that view to make room for the cell's accessories, and
// in editing mode - the queue is always in editing mode, so its reorder
// handles are always there - it moves it a good way in. The card follows it
// in, so the controls are not drawn over the card.
//
// Only the leading edge follows: the content view is also narrower than the
// cell, because the platform made room for the accessory, and clipping the
// card to that would leave every row short.
- (CGRect)cardRect {
    // The card is the row's usual margin on each side. What the platform
    // moves aside - the cell's content view, for the editing controls - moves
    // the contents rather than the card, the same way it moves the platform's
    // own labels and leaves the cell's background where it was.
    return CGRectMake(LTCardInset, LTCardGap,
                      CGRectGetWidth(self.bounds) - LTCardInset * 2.0f,
                      CGRectGetHeight(self.bounds) - LTCardGap);
}

// The area the row's contents live in: the card, clipped to the cell's
// content view, so the text clears the accessory on the right and the
// editing controls on the left.
- (CGRect)contentArea {
    CGRect card = [self cardRect];
    CGFloat left = CGRectGetMinX(card);
    CGFloat right = CGRectGetMaxX(card);
    // The row may be told to keep its contents clear of something on the left.
    if (self.leadingRowInset > left) left = self.leadingRowInset;
    if (!CGRectIsEmpty(self.contentRect)) {
        // The cell's content view has been moved in to make room for the
        // editing controls, and the contents move in with it.
        CGFloat origin = CGRectGetMinX(self.contentRect);
        if (origin > left) left = origin;
    }
    // The right edge is the card's own, and deliberately not the content
    // view's. The platform narrows the content view to make room for the
    // cell's accessory, and widens it again once the accessory is gone -
    // which is what happens here, because the themed table takes the
    // accessory away. Using the content view's edge would make the text
    // jump about as the cell is laid out again, which is what the switches
    // in Settings were doing after a trip to another tab and back.
    return CGRectMake(left, CGRectGetMinY(card), right - left, CGRectGetHeight(card));
}

// The control is placed against the contents' own right edge, with the same
// padding the text has.
- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *control = self.accessoryControl;
    if (!control) return;
    if (control.superview != self) {
        // Another row has taken it - the screen's accessory is shared between
        // cells, and a cell that is reused hands it on.
        self.accessoryControl = nil;
        return;
    }
    CGRect frame = control.frame;
    if (CGRectGetWidth(frame) <= 0.0f) {
        [control sizeToFit];
        frame = control.frame;
    }
    if (CGRectGetWidth(frame) <= 0.0f) frame = CGRectMake(0, 0, 22.0f, 22.0f);
    CGRect card = [self cardRect];
    frame.origin.x = CGRectGetMaxX(card) - 12.0f - CGRectGetWidth(frame);
    frame.origin.y = CGRectGetMidY(card) - CGRectGetHeight(frame) / 2.0f;
    control.frame = frame;

    if (!_loggedLayout) {
        _loggedLayout = YES;
        LTLog(@"LAYOUT row=%@ control=%@ container=%@ containerFrame=%@",
              NSStringFromCGRect(self.frame), NSStringFromCGRect(control.frame),
              NSStringFromClass([self.superview class]),
              NSStringFromCGRect(self.superview.frame));
    }

    // The platform narrows the cell's content view to make room for an
    // accessory view, and it does not widen it again once the accessory has
    // gone. The switch is in the row, against the card's edge, which is past
    // the narrow content view - so the switch could be seen but not touched.
    // The content view is put back to the cell's width.
    UIView *container = self.superview;
    if (container && CGRectGetWidth(container.bounds) < CGRectGetWidth(self.bounds)) {
        CGRect containerFrame = container.frame;
        containerFrame.size.width = CGRectGetWidth(self.bounds);
        container.frame = containerFrame;
    }
}

// The row is drawn over the cell, so it must not swallow the touches that
// select it. Only the accessory control is interactive.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *control = self.accessoryControl;
    if (control) {
        CGPoint local = [self convertPoint:point toView:control];
        BOOL inside = [control pointInside:local withEvent:event];
        if (!_loggedHit) {
            _loggedHit = YES;
            LTLog(@"HIT row=%@ point=%@ control=%@ local=%@ inside=%d superview=%@ container=%@",
                  NSStringFromCGRect(self.frame), NSStringFromCGPoint(point),
                  NSStringFromCGRect(control.frame), NSStringFromCGPoint(local),
                  inside ? 1 : 0,
                  NSStringFromClass([control.superview class]),
                  NSStringFromCGRect(self.superview.bounds));
        }
        if (inside) return control;
    }
    return nil;
}

- (void)drawRect:(CGRect)rect {
    CGFloat radius = [LTTheme cornerRadius];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    // The row covers the whole cell, so the card is inset inside it. The gap
    // to the left of the card is where a row's indicator goes.
    CGRect cardRect = [self cardRect];

    // An image smaller than the artwork slot is an indicator, not artwork: the
    // queue puts its little play glyph there to mark the track that is
    // playing. An indicator belongs in the gutter to the left of the card,
    // flush against the edge of the screen, where it is clear of the card.
    UIImage *artwork = self.artwork;
    CGSize natural = artwork ? artwork.size : CGSizeZero;
    BOOL isIndicator = artwork && natural.width < LTArtworkSize && natural.height < LTArtworkSize;
    // The indicator is drawn with the card's contents, below.

    // Everything else is drawn in the card's own coordinates, so the card can
    // be moved without its contents being left behind.
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, cardRect.origin.x, cardRect.origin.y);
    CGRect inner = CGRectMake(0.0f, 0.0f, CGRectGetWidth(cardRect), CGRectGetHeight(cardRect));

    // The card. A selected row is filled with the theme's accent container, the
    // way Material 3 marks a selected list item.
    UIBezierPath *card = [UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:radius];
    if (self.selected) {
        [[LTTheme accent] setFill];
        [card fill];
    } else {
        [[LTTheme cellBackground] setFill];
        [card fill];
    }

    CGFloat pad = LTCardPadding;
    // The contents sit inside the card, and inside the cell's content view.
    CGRect content = CGRectOffset([self contentArea], -cardRect.origin.x, -cardRect.origin.y);
    CGFloat textX = CGRectGetMinX(content);
    CGFloat textRight = CGRectGetMaxX(content);

    // An indicator is an indicator, not artwork: the queue puts its little play
    // glyph at the card's left edge to mark the track that is playing, and the
    // text follows it.
    if (isIndicator) {
        CGRect spot = CGRectMake(textX,
                                 CGRectGetMidY(inner) - natural.height / 2.0f,
                                 natural.width, natural.height);
        [artwork drawInRect:spot];
        textX += natural.width + LTIndicatorGap;
    } else {
        textX += pad;
    }
    textRight -= pad;

    CGFloat textWidth = textRight - textX;
    // The accessory takes its space off the end of the text.
    CGFloat accessoryWidth = 0.0f;
    if (self.accessoryControl) {
        accessoryWidth = CGRectGetWidth(self.accessoryControl.frame) + 8.0f;
        textWidth -= accessoryWidth;
    }
    if (textWidth < 20.0f) textWidth = 20.0f;

    // The artwork, with Material 3's rounded shape.
    if (artwork && !isIndicator) {
        CGRect slot = CGRectMake(textX, (CGRectGetHeight(inner) - LTArtworkSize) / 2.0f,
                                 LTArtworkSize, LTArtworkSize);
        UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:slot
                                                          cornerRadius:[LTTheme largeCornerRadius]];
        CGContextSaveGState(ctx);
        [clip addClip];
        [artwork drawInRect:slot];
        CGContextRestoreGState(ctx);
        textX = CGRectGetMaxX(slot) + pad;
        textWidth = CGRectGetWidth(inner) - textX - pad - accessoryWidth;
    }

    // The trailing accessory, if the screen set one.
    if (self.accessoryImage) {
        CGFloat size = 22.0f;
        CGRect art = CGRectMake(textRight - size,
                                CGRectGetMidY(inner) - size / 2.0f, size, size);
        [self.accessoryImage drawInRect:art];
    }

    // The text. Material 3's list uses a 16pt title and a 14pt supporting
    // label, in the on-surface and on-surface-variant colours.
    BOOL hasSubtitle = self.subtitle.length > 0;
    UIColor *titleColor = self.selected ? [UIColor colorWithWhite:1.0f alpha:0.95f] : [LTTheme text];
    UIColor *subtitleColor = self.selected ? [UIColor colorWithWhite:1.0f alpha:0.8f] : [LTTheme secondaryText];

    UIFont *titleFont = [UIFont systemFontOfSize:16.0f];
    CGFloat titleHeight = 20.0f;
    CGFloat subtitleHeight = 16.0f;
    CGFloat totalHeight = titleHeight + (hasSubtitle ? subtitleHeight : 0.0f);
    CGFloat titleY = CGRectGetMidY(inner) - totalHeight / 2.0f;

    // The title is drawn with attributes rather than withFont:, so the colour
    // can be the theme's.
    if (self.title.length) {
        CGRect titleRect = CGRectMake(textX, titleY, textWidth, titleHeight);
        if ([self.title respondsToSelector:@selector(drawInRect:withAttributes:)]) {
            NSDictionary *attributes = @{ NSFontAttributeName: titleFont, NSForegroundColorAttributeName: titleColor };
            ((void(*)(id,SEL,CGRect,id))objc_msgSend)(self.title, @selector(drawInRect:withAttributes:), titleRect, attributes);
        } else {
            [titleColor set];
            [self.title drawInRect:titleRect withFont:titleFont lineBreakMode:NSLineBreakByTruncatingTail alignment:NSTextAlignmentLeft];
        }
    }

    if (hasSubtitle) {
        UIFont *subtitleFont = [UIFont systemFontOfSize:13.0f];
        CGRect subRect = CGRectMake(textX, titleY + titleHeight, textWidth, subtitleHeight);
        if ([self.subtitle respondsToSelector:@selector(drawInRect:withAttributes:)]) {
            NSDictionary *attributes = @{ NSFontAttributeName: subtitleFont, NSForegroundColorAttributeName: subtitleColor };
            ((void(*)(id,SEL,CGRect,id))objc_msgSend)(self.subtitle, @selector(drawInRect:withAttributes:), subRect, attributes);
        } else {
            [subtitleColor set];
            [self.subtitle drawInRect:subRect withFont:subtitleFont lineBreakMode:NSLineBreakByTruncatingTail alignment:NSTextAlignmentLeft];
        }
    }

    CGContextRestoreGState(ctx);
}

@end

// The cell's original background colour, kept so Native can put it back
// untouched.
static const void *kLTCellOriginalBackgroundKey = &kLTCellOriginalBackgroundKey;
// The cell's own accessory type, so it can be put back.
static const void *kLTCellAccessoryTypeKey = &kLTCellAccessoryTypeKey;
// The accessory the screen last set, and the one we have taken into the card.
static const void *kLTAccessoryWantedKey = &kLTAccessoryWantedKey;
static const void *kLTAccessoryHeldKey = &kLTAccessoryHeldKey;
// Set while we are taking the accessory for ourselves, so that our own
// change is not mistaken for the screen's.
static const void *kLTAccessoryTakingKey = &kLTAccessoryTakingKey;

// The screen sets the cell's accessory view in -tableView:cellForRowAtIndexPath:,
// and the themed table takes it into the card afterwards. Once the table has
// taken it the cell's own accessory view is empty, so the two can no longer be
// told apart by looking at the cell - the screen's choice has to be recorded
// as it is made.
@interface UITableViewCell (LTAccessoryRecording)
- (void)lt_setAccessoryView:(UIView *)accessoryView;
@end

@implementation UITableViewCell (LTAccessoryRecording)

- (void)lt_setAccessoryView:(UIView *)accessoryView {
    if (!objc_getAssociatedObject(self, kLTAccessoryTakingKey)) {
        objc_setAssociatedObject(self, kLTAccessoryWantedKey, accessoryView,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self lt_setAccessoryView:accessoryView];
}

@end

static void LTSwizzleAccessoryRecording(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class cell = [UITableViewCell class];
    Method original = class_getInstanceMethod(cell, @selector(setAccessoryView:));
    Method replacement = class_getInstanceMethod(cell, @selector(lt_setAccessoryView:));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

@implementation LTThemedTableView {
    BOOL _loggedGeometry;
}

- (id)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    self = (self = [super initWithFrame:frame style:style]) ? self : nil;
    if (self) {
        LTSwizzleAccessoryRecording();
        [self applySeparatorStyle];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applySeparatorStyle];
    if (![LTTheme isModern]) {
        [self restoreNativeCells];
        return;
    }
    [self applyModernRows];
}

// Turns the platform's separators off.
//
// The inset trick only moves a separator drawn at a cell's edge, and it does
// nothing for the lines a grouped table draws under a section - which is where
// the ones in the empty space below the last item came from. The separator
// style is the setting that actually controls all of them.
- (void)applySeparatorStyle {
    if ([LTTheme isModern]) {
        if (self.separatorStyle == UITableViewCellSeparatorStyleNone) return;
        self.separatorStyle = UITableViewCellSeparatorStyleNone;
        // Changing the style does not redraw the separators on cells that are
        // already on screen - they keep theirs until the table reloads. That is
        // why the lines only went away after visiting another tab and coming
        // back: the table had been reloaded by then.
        [self reloadData];
    } else if (self.separatorStyle != UITableViewCellSeparatorStyleSingleLine) {
        self.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        [self reloadData];
    }
}

// Puts our own row behind each visible cell, and hides the cell's own chrome.
- (void)applyModernRows {
    for (UITableViewCell *cell in self.visibleCells) {
        NSIndexPath *indexPath = [self indexPathForCell:cell];
        if (!indexPath) continue;

        LTCardRowView *row = [self rowViewForCell:cell];
        row.title = cell.textLabel.text;
        row.subtitle = cell.detailTextLabel.text;
        row.artwork = cell.imageView.image;
        row.selected = cell.selected;
        if ([cell.accessoryView isKindOfClass:[UIImageView class]]) {
            row.accessoryImage = [(UIImageView *)cell.accessoryView image];
            ((UIImageView *)cell.accessoryView).hidden = YES;
        } else {
            row.accessoryImage = nil;
        }
        [self takeAccessoryFromCell:cell intoRow:row];
        [row setNeedsDisplay];

        // The row covers the whole cell rather than just the card, so that it
        // can draw in the gutter to the left of the card. The card itself is
        // inset inside it: it starts below the top of the cell, for the gap,
        // and runs all the way to the bottom. The platform draws its separator
        // at the very bottom edge of the cell, so the card covers it.
        //
        // The row lives in the cell's content view, and that is moved aside
        // when the cell is in editing mode - the queue is always in editing
        // mode, so its reorder handles are always there. The row makes up for
        // that, so the card still spans the cell and the indicator still sits
        // against the edge of the screen.
        UIView *container = cell.contentView ?: cell;
        CGRect frame = cell.bounds;
        frame.origin.x = -container.frame.origin.x;
        frame.origin.y = -container.frame.origin.y;
        row.frame = frame;
        row.contentRect = CGRectOffset(container.bounds, -frame.origin.x, -frame.origin.y);
        row.leadingRowInset = self.leadingRowInset;

        if (!self->_loggedGeometry) {
            self->_loggedGeometry = YES;
            LTLog(@"THEME row theme=%@ table=%@ editing=%d inset=%.0f cell=%@ content=%@ row=%@ card=%@ area=%@ artwork=%@ accessory=%@",
                  [LTTheme nameForTheme:[LTTheme currentTheme]],
                  NSStringFromCGRect(self.frame), self.isEditing, self.leadingRowInset,
                  NSStringFromCGRect(cell.bounds), NSStringFromCGRect(container.frame),
                  NSStringFromCGRect(row.frame),
                  NSStringFromCGRect([row cardRect]), NSStringFromCGRect([row contentArea]),
                  row.artwork ? NSStringFromCGSize(row.artwork.size) : @"none",
                  cell.accessoryView ? NSStringFromCGSize(cell.accessoryView.frame.size) : @"none");
            if (row.accessoryControl) {
                LTLog(@"THEME control %@ at %@", NSStringFromClass([row.accessoryControl class]),
                      NSStringFromCGRect(row.accessoryControl.frame));
            }
        }

        // The cell's own chrome is what makes this still look like an iOS
        // list, so it goes: no background, no background view, no separator,
        // and no selection highlight.
        // The cell's own content views have to go, or the platform's text layout
    // and artwork are drawn on top of ours and the row still reads as an iOS
    // cell. The cell's content view is where our row goes: at index 0 of the
    // cell's own subviews it would sit *behind* the content view and never be
    // seen at all.
    cell.textLabel.hidden = YES;
    cell.detailTextLabel.hidden = YES;
    cell.imageView.hidden = YES;
    cell.contentView.backgroundColor = [UIColor clearColor];
    // The row is the cell's width wide, so that the card spans the cell
    // rather than only the part of the content view that is left after the
    // editing controls. Without this the card is chopped off at the content
    // view's edge, so indenting it only makes it narrower.
    cell.contentView.clipsToBounds = NO;
    cell.clipsToBounds = NO;

    if (cell.backgroundView != nil) cell.backgroundView = nil;
        UIColor *original = objc_getAssociatedObject(cell, kLTCellOriginalBackgroundKey);
        if (original == nil) {
            objc_setAssociatedObject(cell, kLTCellOriginalBackgroundKey,
                                     cell.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        // The platform's separator line. Insetting it by the full width pushes
        // it off the edge of the cell, which is the only way to hide it: there
        // is no "no separator" setting.
        // Insetting the left edge by the cell's full width moves the
        // separator's start past the cell's right edge, so it is not drawn.
        // (Insetting both sides by the width overflows and is clamped, which
        // does not work.)
        //
        // -separatorInset arrived in iOS 7 and the 3GS runs 6.1.6, where
        // sending it is an unrecognised selector and a crash on launch.
        if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
            UIEdgeInsets insets = UIEdgeInsetsMake(0, CGRectGetWidth(cell.bounds), 0, 0);
            ((void(*)(id,SEL,UIEdgeInsets))objc_msgSend)(cell, @selector(setSeparatorInset:), insets);
        }

        // And its disclosure indicator, which is drawn by the cell itself and
        // would otherwise sit on top of our row.
        if (cell.accessoryType != UITableViewCellAccessoryNone) {
            NSNumber *saved = [NSNumber numberWithInteger:cell.accessoryType];
            objc_setAssociatedObject(cell, kLTCellAccessoryTypeKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }
}

// Moves the cell's accessory into the card.
//
// The platform lays the accessory out against the cell's own edge, which is
// outside the card, so the control is taken out of the cell and placed
// against the card's edge instead. The cell's accessory view is left empty so
// that the platform does not move it again.
//
// The screen's choice is compared with the one we are holding, so that a row
// which gains, loses or changes its accessory is picked up.
- (void)takeAccessoryFromCell:(UITableViewCell *)cell intoRow:(LTCardRowView *)row {
    // The cell must not keep the accessory, whatever it was set to. The
    // platform lays an accessory out against the cell's own edge, which is
    // outside the card, and it narrows the cell's content view to make room
    // for it - so the text would jump about as the cell is laid out again.
    //
    // This has to be done even when the accessory has not changed: the
    // screen can hand the same accessory back to the same cell, and the cell
    // would then be holding it again without the table noticing.
    //
    // It has to be done before the accessory is put in the row: emptying the
    // cell's accessory view takes the view out of whatever it is in, and by
    // then it is in the row.
    if (cell.accessoryView) {
        // Emptying the cell's accessory view is our own change, not the
        // screen's.
        objc_setAssociatedObject(cell, kLTAccessoryTakingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.accessoryView = nil;
        objc_setAssociatedObject(cell, kLTAccessoryTakingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIView *wanted = objc_getAssociatedObject(cell, kLTAccessoryWantedKey);
    UIView *held = objc_getAssociatedObject(cell, kLTAccessoryHeldKey);
    if (wanted != held) {
        objc_setAssociatedObject(cell, kLTAccessoryHeldKey, wanted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (wanted) [self themeAccessory:wanted];
    }
    // The control has to be in the row, whatever happened above: emptying the
    // cell's accessory view takes the view out of the row, and nothing puts
    // it back unless the row is told to.
    row.accessoryControl = wanted;
}

// Gives the accessory the theme's colours.
- (void)themeAccessory:(UIView *)accessory {
    if ([accessory isKindOfClass:[UISwitch class]]) {
        UISwitch *toggle = (UISwitch *)accessory;
        // -onTintColor arrived in iOS 7, and the 3GS runs 6.1.6.
        if ([toggle respondsToSelector:@selector(setOnTintColor:)]) {
            [toggle setOnTintColor:[LTTheme accent]];
        }
        if ([toggle respondsToSelector:@selector(setThumbTintColor:)]) {
            [toggle setThumbTintColor:[UIColor whiteColor]];
        }
    } else if ([accessory isKindOfClass:[UIButton class]]) {
        // The add buttons are drawn in the accent colour rather than blue.
        [LTTheme setTintColor:[LTTheme accent] onView:accessory];
    }
}

// Puts the cells back exactly as they were before.
- (void)restoreNativeCells {
    for (UITableViewCell *cell in self.visibleCells) {
        LTCardRowView *row = [self existingRowViewForCell:cell];
        if (row) {
            row.accessoryControl = nil;
            [row removeFromSuperview];
        }

        // The content views come back, and so does the content view's own
        // background.
        cell.textLabel.hidden = NO;
        cell.detailTextLabel.hidden = NO;
        cell.imageView.hidden = NO;
        cell.contentView.clipsToBounds = YES;
        cell.clipsToBounds = YES;
        // The modern theme widens the content view to reach the card's edge.
        cell.contentView.frame = cell.bounds;

        UIColor *original = objc_getAssociatedObject(cell, kLTCellOriginalBackgroundKey);
        if (original) {
            cell.backgroundColor = original;
            objc_setAssociatedObject(cell, kLTCellOriginalBackgroundKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
#else
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
#endif
        if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
            ((void(*)(id,SEL,UIEdgeInsets))objc_msgSend)(cell, @selector(setSeparatorInset:), UIEdgeInsetsZero);
        }

        NSNumber *savedType = objc_getAssociatedObject(cell, kLTCellAccessoryTypeKey);
        if (savedType) {
            cell.accessoryType = (UITableViewCellAccessoryType)[savedType integerValue];
            objc_setAssociatedObject(cell, kLTCellAccessoryTypeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        // The accessory goes back to the cell, which lays it out again.
        UIView *held = objc_getAssociatedObject(cell, kLTAccessoryHeldKey);
        if (held) {
            cell.accessoryView = held;
            objc_setAssociatedObject(cell, kLTAccessoryHeldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

- (LTCardRowView *)existingRowViewForCell:(UITableViewCell *)cell {
    UIView *container = cell.contentView ?: cell;
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[LTCardRowView class]]) return (LTCardRowView *)subview;
    }
    return nil;
}

- (LTCardRowView *)rowViewForCell:(UITableViewCell *)cell {
    LTCardRowView *existing = [self existingRowViewForCell:cell];
    if (existing) return existing;
    UIView *container = cell.contentView ?: cell;
    LTCardRowView *row = [[LTCardRowView alloc] initWithFrame:container.bounds];
    row.backgroundColor = [UIColor clearColor];
    row.opaque = NO;
    // The row has to be interactive so that the accessory control inside it
    // can be touched. Its own hit testing passes everything else through to
    // the cell, so the row still selects.
    row.userInteractionEnabled = YES;
    [container insertSubview:row atIndex:0];
    return row;
}

@end
