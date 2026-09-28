#import "LTLucideIcons.h"

// ---------------------------------------------------------------------------
// Icon geometry, copied verbatim from lucide-react (the desktop app's icon set).
// Each icon is an array of element dictionaries:
//   { @"t": @"path",   @"d": <svg path data> }
//   { @"t": @"circle", @"cx":.., @"cy":.., @"r":.. }
//   { @"t": @"rect",   @"x":.., @"y":.., @"w":.., @"h":.., @"rx":.. }
// ---------------------------------------------------------------------------
static NSDictionary *LTLucideIconDefinitions(void) {
    static NSDictionary *defs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"play"] = @[@{@"t": @"path", @"d": @"M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"}];
        d[@"pause"] = @[@{@"t": @"rect", @"x": @14, @"y": @3, @"w": @5, @"h": @18, @"rx": @1},
                        @{@"t": @"rect", @"x": @5,  @"y": @3, @"w": @5, @"h": @18, @"rx": @1}];
        d[@"rewind"] = @[@{@"t": @"path", @"d": @"M12 6a2 2 0 0 0-3.414-1.414l-6 6a2 2 0 0 0 0 2.828l6 6A2 2 0 0 0 12 18z"},
                        @{@"t": @"path", @"d": @"M22 6a2 2 0 0 0-3.414-1.414l-6 6a2 2 0 0 0 0 2.828l6 6A2 2 0 0 0 22 18z"}];
        d[@"fast-forward"] = @[@{@"t": @"path", @"d": @"M12 6a2 2 0 0 1 3.414-1.414l6 6a2 2 0 0 1 0 2.828l-6 6A2 2 0 0 1 12 18z"},
                               @{@"t": @"path", @"d": @"M2 6a2 2 0 0 1 3.414-1.414l6 6a2 2 0 0 1 0 2.828l-6 6A2 2 0 0 1 2 18z"}];
        d[@"skip-back"] = @[@{@"t": @"path", @"d": @"M17.971 4.285A2 2 0 0 1 21 6v12a2 2 0 0 1-3.029 1.715l-9.997-5.998a2 2 0 0 1-.003-3.432z"}];
        d[@"skip-forward"] = @[@{@"t": @"path", @"d": @"M6.029 4.285A2 2 0 0 0 3 6v12a2 2 0 0 0 3.029 1.715l9.997-5.998a2 2 0 0 0 .003-3.432z"}];
        d[@"shuffle"] = @[@{@"t": @"path", @"d": @"m18 14 4 4-4 4"},
                          @{@"t": @"path", @"d": @"m18 2 4 4-4 4"},
                          @{@"t": @"path", @"d": @"M2 18h1.973a4 4 0 0 0 3.3-1.7l5.454-8.6a4 4 0 0 1 3.3-1.7H22"},
                          @{@"t": @"path", @"d": @"M2 6h1.972a4 4 0 0 1 3.6 2.2"},
                          @{@"t": @"path", @"d": @"M22 18h-6.041a4 4 0 0 1-3.3-1.8l-.359-.45"}];
        d[@"repeat"] = @[@{@"t": @"path", @"d": @"m17 2 4 4-4 4"},
                         @{@"t": @"path", @"d": @"M3 11v-1a4 4 0 0 1 4-4h14"},
                         @{@"t": @"path", @"d": @"m7 22-4-4 4-4"},
                         @{@"t": @"path", @"d": @"M21 13v1a4 4 0 0 1-4 4H3"}];
        d[@"repeat-1"] = @[@{@"t": @"path", @"d": @"m17 2 4 4-4 4"},
                           @{@"t": @"path", @"d": @"M3 11v-1a4 4 0 0 1 4-4h14"},
                           @{@"t": @"path", @"d": @"m7 22-4-4 4-4"},
                           @{@"t": @"path", @"d": @"M21 13v1a4 4 0 0 1-4 4H3"},
                           @{@"t": @"path", @"d": @"M11 10h1v4"}];
        d[@"download"] = @[@{@"t": @"path", @"d": @"M12 15V3"},
                            @{@"t": @"path", @"d": @"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"},
                            @{@"t": @"path", @"d": @"m7 10 5 5 5-5"}];
        d[@"check"] = @[@{@"t": @"path", @"d": @"M20 6 9 17l-5-5"}];
        d[@"pen"] = @[@{@"t": @"path", @"d": @"M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"}];
        d[@"house"] = @[@{@"t": @"path", @"d": @"M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"}];
        d[@"search"] = @[@{@"t": @"path", @"d": @"m21 21-4.34-4.34"},
                         @{@"t": @"circle", @"cx": @11, @"cy": @11, @"r": @8}];
        d[@"settings"] = @[@{@"t": @"path", @"d": @"M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"},
                           @{@"t": @"circle", @"cx": @12, @"cy": @12, @"r": @3}];
        d[@"library"] = @[@{@"t": @"path", @"d": @"m16 6 4 14"},
                          @{@"t": @"path", @"d": @"M12 6v14"},
                          @{@"t": @"path", @"d": @"M8 8v12"},
                          @{@"t": @"path", @"d": @"M4 4v16"}];
        d[@"trending-up"] = @[@{@"t": @"path", @"d": @"M16 7h6v6"},
                              @{@"t": @"path", @"d": @"m22 7-8.5 8.5-5-5L2 17"}];
        // Extra icons used across the app.
        d[@"x"] = @[@{@"t": @"path", @"d": @"M18 6 6 18"}, @{@"t": @"path", @"d": @"m6 6 12 12"}];
        d[@"plus"] = @[@{@"t": @"path", @"d": @"M5 12h14"}, @{@"t": @"path", @"d": @"M12 5v14"}];
        d[@"minus"] = @[@{@"t": @"path", @"d": @"M5 12h14"}];
        d[@"chevron-left"] = @[@{@"t": @"path", @"d": @"m15 18-6-6 6-6"}];
        d[@"chevron-right"] = @[@{@"t": @"path", @"d": @"m9 18 6-6-6-6"}];
        d[@"chevron-up"] = @[@{@"t": @"path", @"d": @"m18 15-6-6-6 6"}];
        d[@"chevron-down"] = @[@{@"t": @"path", @"d": @"m6 9 6 6 6-6"}];
        d[@"arrow-left"] = @[@{@"t": @"path", @"d": @"m12 19-7-7 7-7"}, @{@"t": @"path", @"d": @"M19 12H5"}];
        d[@"trash-2"] = @[@{@"t": @"path", @"d": @"M3 6h18"}, @{@"t": @"path", @"d": @"M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"},
                          @{@"t": @"path", @"d": @"M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"}];
        d[@"music"] = @[@{@"t": @"path", @"d": @"M9 18V5l12-2v13"},
                         @{@"t": @"circle", @"cx": @6, @"cy": @18, @"r": @3},
                         @{@"t": @"circle", @"cx": @18, @"cy": @16, @"r": @3}];
        d[@"list-music"] = @[@{@"t": @"path", @"d": @"M16 5H3"}, @{@"t": @"path", @"d": @"M11 12H3"},
                             @{@"t": @"path", @"d": @"M11 19H3"}, @{@"t": @"path", @"d": @"M21 16V5"},
                             @{@"t": @"circle", @"cx": @18, @"cy": @16, @"r": @3}];
        d[@"sliders-horizontal"] = @[@{@"t": @"path", @"d": @"M21 4h-7"}, @{@"t": @"path", @"d": @"M10 4H3"},
                                      @{@"t": @"path", @"d": @"M21 12h-9"}, @{@"t": @"path", @"d": @"M8 12H3"},
                                      @{@"t": @"path", @"d": @"M21 20h-5"}, @{@"t": @"path", @"d": @"M12 20H3"},
                                      @{@"t": @"path", @"d": @"M14 2v4"}, @{@"t": @"path", @"d": @"M8 10v4"},
                                      @{@"t": @"path", @"d": @"M16 18v4"}];
        d[@"clock"] = @[@{@"t": @"circle", @"cx": @12, @"cy": @12, @"r": @10},
                        @{@"t": @"path", @"d": @"M12 6v6l4 2"}];
        d[@"mic-vocal"] = @[@{@"t": @"path", @"d": @"M2 10v3"},
                             @{@"t": @"path", @"d": @"M14 2v3"},
                             @{@"t": @"path", @"d": @"M20 10v3"},
                             @{@"t": @"path", @"d": @"M22 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"},
                             @{@"t": @"path", @"d": @"M12 2a2 2 0 0 0-2 2c0 1.02-.1 1.99-.26 2.9"},
                             @{@"t": @"path", @"d": @"M14 2a2 2 0 0 1 2 2c0 1.02.1 1.99.26 2.9"},
                             @{@"t": @"path", @"d": @"M18 10v3"},
                             @{@"t": @"path", @"d": @"M6 10v3"},
                             @{@"t": @"circle", @"cx": @12, @"cy": @12, @"r": @2},
                             @{@"t": @"path", @"d": @"M12 18a6 6 0 0 0 6-6"}];
        d[@"square"] = @[@{@"t": @"rect", @"x": @3, @"y": @3, @"w": @18, @"h": @18, @"rx": @2}];
        d[@"grip-vertical"] = @[@{@"t": @"path", @"d": @"M9 5h.01"}, @{@"t": @"path", @"d": @"M9 12h.01"},
                                 @{@"t": @"path", @"d": @"M9 19h.01"}, @{@"t": @"path", @"d": @"M15 5h.01"},
                                 @{@"t": @"path", @"d": @"M15 12h.01"}, @{@"t": @"path", @"d": @"M15 19h.01"}];
        defs = d;
    });
    return defs;
}

@implementation LTLucideIcons

// --- Minimal SVG path-data parser (M L H V C S Q T A Z, absolute+relative) ---
typedef struct { double x, y; } LTPoint;

static BOOL LTScanNumber(NSString *s, NSUInteger *idx, double *out) {
    NSUInteger i = *idx, n = s.length;
    while (i < n && ([s characterAtIndex:i] == ' ' || [s characterAtIndex:i] == ',')) i++;
    NSUInteger start = i;
    if (i < n && ([s characterAtIndex:i] == '+' || [s characterAtIndex:i] == '-')) i++;
    while (i < n && [s characterAtIndex:i] >= '0' && [s characterAtIndex:i] <= '9') i++;
    if (i < n && [s characterAtIndex:i] == '.') { i++; while (i < n && [s characterAtIndex:i] >= '0' && [s characterAtIndex:i] <= '9') i++; }
    if (i < n && ([s characterAtIndex:i] == 'e' || [s characterAtIndex:i] == 'E')) {
        i++;
        if (i < n && ([s characterAtIndex:i] == '+' || [s characterAtIndex:i] == '-')) i++;
        while (i < n && [s characterAtIndex:i] >= '0' && [s characterAtIndex:i] <= '9') i++;
    }
    if (i == start) return NO;
    NSString *num = [s substringWithRange:NSMakeRange(start, i - start)];
    *out = [num doubleValue];
    *idx = i;
    return YES;
}

static BOOL LTScanFlag(NSString *s, NSUInteger *idx, BOOL *out) {
    NSUInteger i = *idx;
    while (i < s.length && ([s characterAtIndex:i] == ' ' || [s characterAtIndex:i] == ',')) i++;
    if (i >= s.length) return NO;
    unichar c = [s characterAtIndex:i];
    if (c == '0' || c == '1') { *out = (c == '1'); *idx = i + 1; return YES; }
    return NO;
}

// Appends an SVG elliptical arc to `path` (current point = p0, endpoint = p2).
// Follows the SVG spec F.6.5 endpoint->center conversion, then emits circular
// arc segments via UIBezierPath (all Lucide arcs are rx==ry circles).
static void LTAppendArc(UIBezierPath *path, LTPoint p0, double rx, double ry,
                        double xRotDeg, BOOL largeArc, BOOL sweep, LTPoint p2) {
    if (rx == 0 || ry == 0) { [path addLineToPoint:CGPointMake(p2.x, p2.y)]; return; }
    rx = fabs(rx); ry = fabs(ry);
    double phi = xRotDeg * M_PI / 180.0;
    double dx2 = (p0.x - p2.x) / 2.0, dy2 = (p0.y - p2.y) / 2.0;
    double x1 =  cos(phi) * dx2 + sin(phi) * dy2;
    double y1 = -sin(phi) * dx2 + cos(phi) * dy2;

    double lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry);
    if (lambda > 1.0) { double s = sqrt(lambda); rx *= s; ry *= s; }

    double sign = (largeArc != sweep) ? 1.0 : -1.0;
    double num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1;
    double den = rx * rx * y1 * y1 + ry * ry * x1 * x1;
    if (den <= 0) den = 1e-12;
    double co = (num < 0 ? 0 : num / den);
    // The SVG coefficient is a signed multiplier that is routinely larger than
    // 1, so only the radicand is clamped (never the coefficient itself).
    if (co < 0) co = 0;
    co = sign * sqrt(co);
    double cxp =  co * (rx * y1 / ry);
    double cyp = -co * (ry * x1 / rx);
    double cx = cos(phi) * cxp - sin(phi) * cyp + (p0.x + p2.x) / 2.0;
    double cy = sin(phi) * cxp + cos(phi) * cyp + (p0.y + p2.y) / 2.0;

    double ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry;
    double vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry;
    double theta1 = atan2(uy, ux);
    double dtheta = atan2(vy, vx) - theta1;
    if (!sweep && dtheta > 0) dtheta -= 2 * M_PI;
    else if (sweep && dtheta < 0) dtheta += 2 * M_PI;

    // For circular arcs (rx==ry) draw exactly with addArcWithCenter; otherwise
    // fall back to the centre with the mean radius (rare in Lucide).
    BOOL circular = fabs(rx - ry) < 1e-6;
    if (circular) {
        CGPoint center = CGPointMake(cx, cy);
        [path addArcWithCenter:center radius:rx startAngle:(CGFloat)theta1 endAngle:(CGFloat)(theta1 + dtheta) clockwise:dtheta >= 0];
    } else {
        double rr = (rx + ry) / 2.0;
        [path addArcWithCenter:CGPointMake(cx, cy) radius:rr startAngle:(CGFloat)theta1 endAngle:(CGFloat)(theta1 + dtheta) clockwise:dtheta >= 0];
    }
}

static UIBezierPath *LTPathFromSVGPathData(NSString *d) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    NSUInteger i = 0, n = d.length;
    LTPoint cur = {0, 0}, startPt = {0, 0}, lastCubicCtrl = {0, 0}, lastQuadCtrl = {0, 0};
    unichar prevCmd = 0;
    BOOL haveCubicCtrl = NO, haveQuadCtrl = NO;

    while (i < n) {
        unichar c = [d characterAtIndex:i];
        if (c == ' ' || c == ',') { i++; continue; }
        unichar cmd = c;
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
            i++;
        } else {
            // implicit repeat of previous command
            cmd = prevCmd;
            if (cmd == 'M') cmd = 'L';
            else if (cmd == 'm') cmd = 'l';
        }
        BOOL rel = (cmd >= 'a' && cmd <= 'z');
        unichar op = rel ? (unichar)(cmd - 'a' + 'A') : cmd;

        switch (op) {
            case 'M': case 'L': case 'T': {
                double a, b;
                if (!LTScanNumber(d, &i, &a) || !LTScanNumber(d, &i, &b)) return path;
                LTPoint p = rel ? (LTPoint){cur.x + a, cur.y + b} : (LTPoint){a, b};
                if (op == 'M') { [path moveToPoint:CGPointMake(p.x, p.y)]; startPt = p; haveCubicCtrl = haveQuadCtrl = NO; }
                else if (op == 'L') { [path addLineToPoint:CGPointMake(p.x, p.y)]; haveCubicCtrl = haveQuadCtrl = NO; }
                else { // smooth quadratic
                    LTPoint ctrl;
                    if (haveQuadCtrl) { ctrl.x = 2 * cur.x - lastQuadCtrl.x; ctrl.y = 2 * cur.y - lastQuadCtrl.y; }
                    else { ctrl = cur; }
                    // elevate quad to cubic
                    CGPoint c1 = CGPointMake(cur.x + 2.0 / 3.0 * (ctrl.x - cur.x), cur.y + 2.0 / 3.0 * (ctrl.y - cur.y));
                    CGPoint c2 = CGPointMake(p.x + 2.0 / 3.0 * (ctrl.x - p.x), p.y + 2.0 / 3.0 * (ctrl.y - p.y));
                    [path addCurveToPoint:CGPointMake(p.x, p.y) controlPoint1:c1 controlPoint2:c2];
                    lastQuadCtrl = ctrl; haveQuadCtrl = YES; haveCubicCtrl = NO;
                }
                cur = p;
                break;
            }
            case 'H': {
                double a; if (!LTScanNumber(d, &i, &a)) return path;
                cur.x = rel ? cur.x + a : a;
                [path addLineToPoint:CGPointMake(cur.x, cur.y)]; haveCubicCtrl = haveQuadCtrl = NO;
                break;
            }
            case 'V': {
                double a; if (!LTScanNumber(d, &i, &a)) return path;
                cur.y = rel ? cur.y + a : a;
                [path addLineToPoint:CGPointMake(cur.x, cur.y)]; haveCubicCtrl = haveQuadCtrl = NO;
                break;
            }
            case 'C': {
                double a, b, cc, dd, e, f;
                if (!LTScanNumber(d, &i, &a) || !LTScanNumber(d, &i, &b) || !LTScanNumber(d, &i, &cc) ||
                    !LTScanNumber(d, &i, &dd) || !LTScanNumber(d, &i, &e) || !LTScanNumber(d, &i, &f)) return path;
                LTPoint c1 = rel ? (LTPoint){cur.x + a, cur.y + b} : (LTPoint){a, b};
                LTPoint c2 = rel ? (LTPoint){cur.x + cc, cur.y + dd} : (LTPoint){cc, dd};
                LTPoint p = rel ? (LTPoint){cur.x + e, cur.y + f} : (LTPoint){e, f};
                [path addCurveToPoint:CGPointMake(p.x, p.y) controlPoint1:CGPointMake(c1.x, c1.y) controlPoint2:CGPointMake(c2.x, c2.y)];
                lastCubicCtrl = c2; haveCubicCtrl = YES; haveQuadCtrl = NO; cur = p;
                break;
            }
            case 'S': {
                double a, b, e, f;
                if (!LTScanNumber(d, &i, &a) || !LTScanNumber(d, &i, &b) || !LTScanNumber(d, &i, &e) || !LTScanNumber(d, &i, &f)) return path;
                LTPoint c1;
                if (haveCubicCtrl) { c1.x = 2 * cur.x - lastCubicCtrl.x; c1.y = 2 * cur.y - lastCubicCtrl.y; }
                else { c1 = cur; }
                LTPoint c2 = rel ? (LTPoint){cur.x + a, cur.y + b} : (LTPoint){a, b};
                LTPoint p = rel ? (LTPoint){cur.x + e, cur.y + f} : (LTPoint){e, f};
                [path addCurveToPoint:CGPointMake(p.x, p.y) controlPoint1:CGPointMake(c1.x, c1.y) controlPoint2:CGPointMake(c2.x, c2.y)];
                lastCubicCtrl = c2; haveCubicCtrl = YES; haveQuadCtrl = NO; cur = p;
                break;
            }
            case 'Q': {
                double a, b, e, f;
                if (!LTScanNumber(d, &i, &a) || !LTScanNumber(d, &i, &b) || !LTScanNumber(d, &i, &e) || !LTScanNumber(d, &i, &f)) return path;
                LTPoint ctrl = rel ? (LTPoint){cur.x + a, cur.y + b} : (LTPoint){a, b};
                LTPoint p = rel ? (LTPoint){cur.x + e, cur.y + f} : (LTPoint){e, f};
                CGPoint c1 = CGPointMake(cur.x + 2.0 / 3.0 * (ctrl.x - cur.x), cur.y + 2.0 / 3.0 * (ctrl.y - cur.y));
                CGPoint c2 = CGPointMake(p.x + 2.0 / 3.0 * (ctrl.x - p.x), p.y + 2.0 / 3.0 * (ctrl.y - p.y));
                [path addCurveToPoint:CGPointMake(p.x, p.y) controlPoint1:c1 controlPoint2:c2];
                lastQuadCtrl = ctrl; haveQuadCtrl = YES; haveCubicCtrl = NO; cur = p;
                break;
            }
            case 'A': {
                double rx, ry, rot, x, y; BOOL la, sw;
                if (!LTScanNumber(d, &i, &rx) || !LTScanNumber(d, &i, &ry) || !LTScanNumber(d, &i, &rot) ||
                    !LTScanFlag(d, &i, &la) || !LTScanFlag(d, &i, &sw) ||
                    !LTScanNumber(d, &i, &x) || !LTScanNumber(d, &i, &y)) return path;
                LTPoint p = rel ? (LTPoint){cur.x + x, cur.y + y} : (LTPoint){x, y};
                LTAppendArc(path, cur, rx, ry, rot, la, sw, p);
                haveCubicCtrl = haveQuadCtrl = NO; cur = p;
                break;
            }
            case 'Z': {
                [path closePath];
                cur = startPt; haveCubicCtrl = haveQuadCtrl = NO;
                break;
            }
            default:
                return path; // unknown command: stop
        }
        prevCmd = cmd;
    }
    return path;
}

#pragma mark - Rendering

+ (UIImage *)iconNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color {
    if (name.length == 0 || size <= 0.0) return nil;
    NSArray *elements = LTLucideIconDefinitions()[name];
    if (!elements.count) return nil;
    UIColor *tint = color ?: [UIColor whiteColor];

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGFloat s = size / 24.0;
        CGContextSaveGState(ctx);
        CGContextSetLineCap(ctx, kCGLineCapRound);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        CGContextSetLineWidth(ctx, 2.0 * s);
        CGContextSetStrokeColorWithColor(ctx, tint.CGColor);
        for (NSDictionary *el in elements) {
            UIBezierPath *p = nil;
            NSString *type = el[@"t"];
            if ([type isEqualToString:@"path"]) {
                p = LTPathFromSVGPathData(el[@"d"]);
            } else if ([type isEqualToString:@"circle"]) {
                CGFloat r = [el[@"r"] doubleValue];
                p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake([el[@"cx"] doubleValue] - r, [el[@"cy"] doubleValue] - r, r * 2, r * 2)];
            } else if ([type isEqualToString:@"rect"]) {
                CGFloat rx = el[@"rx"] ? [el[@"rx"] doubleValue] : 0;
                p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake([el[@"x"] doubleValue], [el[@"y"] doubleValue], [el[@"w"] doubleValue], [el[@"h"] doubleValue]) cornerRadius:rx];
            }
            if (!p) continue;
            [p applyTransform:CGAffineTransformMakeScale(s, s)];
            CGContextAddPath(ctx, p.CGPath);
        }
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
