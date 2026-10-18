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

CGRect PNJumpButtonFrame(CGRect windowBounds, CGRect safeBounds) {
    if (!PNUsableRect(windowBounds)) return CGRectZero;

    CGFloat safeMinX = CGRectGetMinX(windowBounds);
    CGFloat safeMaxX = CGRectGetMaxX(windowBounds);
    // Use only physical side insets. Sheet or keyboard-related vertical changes
    // must never turn the fixed window position into a content-relative one.
    if (isfinite(safeBounds.origin.x) && isfinite(safeBounds.size.width) &&
        safeBounds.size.width > 0 && isfinite(CGRectGetMaxX(safeBounds))) {
        CGFloat intersectionMin = MAX(safeMinX, CGRectGetMinX(safeBounds));
        CGFloat intersectionMax = MIN(safeMaxX, CGRectGetMaxX(safeBounds));
        if (intersectionMax > intersectionMin) {
            safeMinX = intersectionMin;
            safeMaxX = intersectionMax;
        }
    }

    const CGFloat margin = 8;
    if (safeMaxX - safeMinX <= 2 * margin || windowBounds.size.height <= 2 * margin) return CGRectZero;
    CGRect available = CGRectMake(safeMinX + margin, CGRectGetMinY(windowBounds) + margin,
        safeMaxX - safeMinX - 2 * margin, CGRectGetHeight(windowBounds) - 2 * margin);
    CGFloat diameter = MIN(PNJumpButtonDiameter, MIN(available.size.width, available.size.height));

    CGFloat x = safeMaxX - 12 - diameter;
    CGFloat y = CGRectGetMinY(windowBounds) + 0.60 * CGRectGetHeight(windowBounds) - diameter / 2;

    x = PNClamp(x, CGRectGetMinX(available), CGRectGetMaxX(available) - diameter);
    y = PNClamp(y, CGRectGetMinY(available), CGRectGetMaxY(available) - diameter);
    return CGRectMake(x, y, diameter, diameter);
}
