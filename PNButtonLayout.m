#import "PNButtonLayout.h"
#import <math.h>

const CGFloat PNJumpButtonDiameter = 44;

static BOOL PNUsableRect(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) &&
        rect.size.width > 0 && rect.size.height > 0 &&
        isfinite(CGRectGetMaxX(rect)) && isfinite(CGRectGetMaxY(rect));
}

static CGFloat PNClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(MAX(value, minimum), maximum);
}

CGRect PNJumpButtonFrame(CGRect bounds, CGRect safeBounds, CGRect likeFrame) {
    if (!PNUsableRect(bounds)) return CGRectZero;

    // A not-yet-laid-out safe area must not hide an otherwise usable control.
    CGRect safe = PNUsableRect(safeBounds) ? CGRectIntersection(bounds, safeBounds) : bounds;
    if (!PNUsableRect(safe)) safe = bounds;

    const CGFloat margin = 8;
    if (safe.size.width <= 2 * margin || safe.size.height <= 2 * margin) return CGRectZero;
    CGRect available = CGRectInset(safe, margin, margin);
    CGFloat diameter = MIN(PNJumpButtonDiameter, MIN(available.size.width, available.size.height));

    CGFloat x = CGRectGetMaxX(safe) - 12 - diameter;
    CGFloat y = CGRectGetMinY(bounds) + 0.60 * CGRectGetHeight(bounds) - diameter / 2;
    if (PNUsableRect(likeFrame) && CGRectContainsRect(bounds, likeFrame)) {
        x = CGRectGetMidX(likeFrame) - diameter / 2;
        y = CGRectGetMinY(likeFrame) - 12 - diameter;
    }

    x = PNClamp(x, CGRectGetMinX(available), CGRectGetMaxX(available) - diameter);
    y = PNClamp(y, CGRectGetMinY(available), CGRectGetMaxY(available) - diameter);
    return CGRectMake(x, y, diameter, diameter);
}
