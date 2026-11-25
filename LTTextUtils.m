#import "LTTextUtils.h"

const CGFloat LTListTitleWidthFraction = 0.85f;

// Truncates text to fit maxWidth, appending an ellipsis.
//
// The original shortened the candidate string one character at a time and
// re-measured the whole thing on every step, so a 40-character title cost ~40
// full font measurements. That runs in every cell dequeue and, in the iPod
// search view, once per visible row from inside -drawRect:.
//
// Binary search over the prefix length finds the same answer in about
// log2(n) measurements. The rangeOfComposedCharacterSequencesForRange: hop is
// kept so the cut never lands mid-cluster: a Japanese title or an emoji grapheme
// would otherwise be sliced in half.
NSString *LTTruncatedTextToWidth(NSString *text, UIFont *font, CGFloat maxWidth) {
    if (!text.length || !font || maxWidth <= 0.0f) return text;
    if ([text sizeWithFont:font].width <= maxWidth) return text;

    NSString *ellipsis = @"...";
    CGFloat ellipsisWidth = [ellipsis sizeWithFont:font].width;
    CGFloat budget = maxWidth - ellipsisWidth;
    if (budget <= 0.0f) return ellipsis;

    NSUInteger textLength = text.length;
    NSUInteger lo = 0;
    NSUInteger hi = textLength;
    NSUInteger best = 0;
    while (lo <= hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        NSRange candidate = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, mid)];
        CGFloat width = [[text substringWithRange:candidate] sizeWithFont:font].width;
        if (width <= budget) {
            best = candidate.length;
            lo = candidate.length + 1;
        } else {
            if (mid == 0) break;
            hi = mid - 1;
        }
    }
    if (best == 0) return ellipsis;
    return [[text substringToIndex:best] stringByAppendingString:ellipsis];
}
