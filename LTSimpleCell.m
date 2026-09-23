#import "LTSimpleCell.h"
#import "LTTextUtils.h"

@implementation LTSimpleCell {
    NSString *_fullText;
    CGFloat _maxWidth;
    UIFont *_font;
    NSString *_truncatedText;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *label = self.textLabel;
    if (!label) return;
    NSString *full = label.text;
    if (_fullText.length && [full isEqualToString:_truncatedText]) {
        full = _fullText;
    }
    if (!full.length) return;
    CGFloat maxWidth = self.bounds.size.width * LTListTitleWidthFraction - label.frame.origin.x;
    if (maxWidth <= 0.0f) return;
    UIFont *font = label.font;
    if ([full isEqualToString:_fullText] &&
        maxWidth == _maxWidth &&
        (font == _font || [font isEqual:_font])) {
        if (![label.text isEqualToString:_truncatedText]) {
            label.text = _truncatedText;
        }
        return;
    }
    _fullText = [full copy];
    _maxWidth = maxWidth;
    _font = font;
    _truncatedText = LTTruncatedTextToWidth(full, font, maxWidth);
    label.text = _truncatedText;
}

@end
