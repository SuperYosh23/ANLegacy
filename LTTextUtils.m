#import "LTTextUtils.h"

const CGFloat LTListTitleWidthFraction = 0.85f;

NSString *LTTruncatedTextToWidth(NSString *text, UIFont *font, CGFloat maxWidth) {
    if (!text.length || !font || maxWidth <= 0.0f) return text;
    if ([text sizeWithFont:font].width <= maxWidth) return text;
    NSString *ellipsis = @"...";
    CGFloat ellipsisWidth = [ellipsis sizeWithFont:font].width;
    NSRange prefix = NSMakeRange(0, text.length);
    while (prefix.length > 0) {
        prefix.length -= 1;
        NSRange safe = [text rangeOfComposedCharacterSequencesForRange:prefix];
        NSString *candidate = [text substringWithRange:safe];
        if ([candidate sizeWithFont:font].width + ellipsisWidth <= maxWidth) {
            return [candidate stringByAppendingString:ellipsis];
        }
    }
    return ellipsis;
}
