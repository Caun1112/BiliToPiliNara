#import "PNButtonLayout.h"
#import <math.h>

const CGFloat PNJumpButtonDiameter = 44;
const CGFloat PNPortraitJumpButtonHeight = 60;

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

CGRect PNPortraitFallbackJumpButtonFrame(CGRect bounds, CGRect safeBounds) {
    if (!PNUsableRect(bounds) || bounds.size.height <= bounds.size.width) return CGRectNull;
    CGRect fixed = PNJumpButtonFrame(bounds, safeBounds);
    if (CGRectIsEmpty(fixed) || bounds.size.height < PNPortraitJumpButtonHeight + 16) return CGRectNull;
    CGFloat maxX = CGRectGetMaxX(bounds);
    if (PNUsableRect(safeBounds)) maxX = MIN(maxX, CGRectGetMaxX(safeBounds));
    CGFloat x = PNClamp(maxX - 27 - PNJumpButtonDiameter / 2,
        CGRectGetMinX(fixed), maxX - 4 - PNJumpButtonDiameter);
    CGFloat y = PNClamp(CGRectGetMinY(bounds) + 0.49 * bounds.size.height - 18,
        CGRectGetMinY(bounds) + 8, CGRectGetMaxY(bounds) - 8 - PNPortraitJumpButtonHeight);
    return CGRectMake(x, y, PNJumpButtonDiameter, PNPortraitJumpButtonHeight);
}

static BOOL PNRailAnchorValid(PNPortraitActionAnchor anchor, CGRect bounds) {
    return PNUsableRect(anchor.frame) && CGRectContainsRect(bounds, anchor.frame) &&
        anchor.frame.size.width >= 16 && anchor.frame.size.width <= 100 &&
        anchor.frame.size.height >= 16 && anchor.frame.size.height <= 110 &&
        CGRectGetMidX(anchor.frame) >= CGRectGetMinX(bounds) + bounds.size.width * 0.78 &&
        CGRectGetMidY(anchor.frame) >= CGRectGetMinY(bounds) + bounds.size.height * 0.20 &&
        CGRectGetMidY(anchor.frame) <= CGRectGetMinY(bounds) + bounds.size.height * 0.93;
}

static BOOL PNAlignedRow(PNPortraitActionAnchor anchor, CGFloat x, CGFloat y, CGFloat stride) {
    return fabs(CGRectGetMidX(anchor.frame) - x) <= 16 &&
        fabs(CGRectGetMidY(anchor.frame) - y) <= MAX(10, stride * 0.22);
}

BOOL PNFindPortraitActionRail(const PNPortraitActionAnchor *anchors, NSUInteger count,
    CGRect bounds, BOOL allowUngroupedFallback, PNPortraitActionRail *rail) {
    if (!anchors || !rail || !PNUsableRect(bounds) || bounds.size.height <= bounds.size.width) return NO;
    BOOL found = NO;
    BOOL foundSemantic = NO;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (NSUInteger i = 0; i < count; i++) {
        PNPortraitActionAnchor like = anchors[i];
        if (!PNRailAnchorValid(like, bounds) ||
            (like.kind != PNPortraitActionLike && like.kind != PNPortraitActionUnknown)) continue;
        for (NSUInteger j = 0; j < count; j++) {
            PNPortraitActionAnchor comment = anchors[j];
            if (!PNRailAnchorValid(comment, bounds) ||
                (comment.kind != PNPortraitActionComment && comment.kind != PNPortraitActionUnknown)) continue;
            CGFloat stride = CGRectGetMidY(comment.frame) - CGRectGetMidY(like.frame);
            CGFloat x = CGRectGetMidX(like.frame);
            if (stride < 48 || stride > 110 || fabs(CGRectGetMidX(comment.frame) - x) > 16) continue;
            NSUInteger semantic = (like.kind == PNPortraitActionLike) + (comment.kind == PNPortraitActionComment);
            NSUInteger rows = 2;
            BOOL grouped = like.column != 0 && like.column == comment.column;
            for (NSUInteger row = 2; row <= 4; row++) {
                PNPortraitActionKind expected = (PNPortraitActionKind)(PNPortraitActionLike + row);
                BOOL rowFound = NO;
                BOOL rowNamed = NO;
                BOOL rowGrouped = NO;
                for (NSUInteger k = 0; k < count; k++) {
                    PNPortraitActionAnchor item = anchors[k];
                    if (!PNRailAnchorValid(item, bounds) ||
                        (item.kind != expected && item.kind != PNPortraitActionUnknown) ||
                        !PNAlignedRow(item, x, CGRectGetMidY(like.frame) + row * stride, stride)) continue;
                    rowFound = YES;
                    rowNamed |= item.kind == expected;
                    rowGrouped |= like.column != 0 && like.column == item.column;
                }
                if (rowFound) rows++;
                if (rowNamed) semantic++;
                grouped &= rowGrouped;
            }
            BOOL namedRail = like.kind == PNPortraitActionLike &&
                comment.kind == PNPortraitActionComment && semantic >= 3;
            BOOL completeColumn = rows == 5 && (grouped || allowUngroupedFallback);
            if (!namedRail && !completeColumn) continue;
            // Semantic actions win. For an unlabeled column with an avatar on
            // top, select the bottom five rows, not the avatar/follow control.
            CGFloat score = semantic * 10000 + rows * 1000 + CGRectGetMidY(like.frame);
            if ((!foundSemantic && namedRail) ||
                (foundSemantic == namedRail && score > bestScore)) {
                rail->like = like.frame;
                rail->comment = comment.frame;
                found = YES;
                foundSemantic = namedRail;
                bestScore = score;
            }
        }
    }
    return found;
}

CGRect PNPortraitJumpButtonFrame(CGRect bounds, CGRect safeBounds, PNPortraitActionRail rail) {
    if (!PNUsableRect(bounds) || !PNUsableRect(rail.like) || !PNUsableRect(rail.comment) ||
        !CGRectContainsRect(bounds, rail.like) || !CGRectContainsRect(bounds, rail.comment)) return CGRectNull;
    CGFloat stride = CGRectGetMidY(rail.comment) - CGRectGetMidY(rail.like);
    if (stride < 48 || stride > 110) return CGRectNull;
    CGFloat minX = CGRectGetMinX(bounds), maxX = CGRectGetMaxX(bounds);
    if (isfinite(safeBounds.origin.x) && isfinite(safeBounds.size.width) && safeBounds.size.width > 0 &&
        isfinite(CGRectGetMaxX(safeBounds))) {
        minX = MAX(minX, CGRectGetMinX(safeBounds));
        maxX = MIN(maxX, CGRectGetMaxX(safeBounds));
    }
    if (maxX - minX < PNJumpButtonDiameter + 8) return CGRectNull;
    CGFloat x = PNClamp(CGRectGetMidX(rail.like) - PNJumpButtonDiameter / 2,
        minX + 4, maxX - 4 - PNJumpButtonDiameter);
    CGFloat y = MIN(CGRectGetMidY(rail.like) - stride - 18,
        CGRectGetMinY(rail.like) - 8 - PNPortraitJumpButtonHeight);
    if (y < CGRectGetMinY(bounds) + 8) return CGRectNull;
    return CGRectMake(x, y, PNJumpButtonDiameter, PNPortraitJumpButtonHeight);
}
