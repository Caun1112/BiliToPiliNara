#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

FOUNDATION_EXPORT const CGFloat PNJumpButtonDiameter;

/// Return a circular control frame in window coordinates. Keep its right edge
/// 12 points inside the horizontal safe edge and its center at 60% of the window
/// height. Clamp horizontally to the safe interval and vertically to the window,
/// with an 8 point margin. The safe bounds' vertical inset never moves the button.
FOUNDATION_EXPORT CGRect PNJumpButtonFrame(CGRect windowBounds, CGRect safeBounds);

typedef NS_ENUM(NSUInteger, PNPortraitActionKind) {
    PNPortraitActionUnknown,
    PNPortraitActionLike,
    PNPortraitActionComment,
    PNPortraitActionCoin,
    PNPortraitActionFavorite,
    PNPortraitActionShare,
};

typedef struct {
    CGRect frame;
    PNPortraitActionKind kind;
    uintptr_t column;
} PNPortraitActionAnchor;

typedef struct {
    CGRect like;
    CGRect comment;
} PNPortraitActionRail;

FOUNDATION_EXPORT const CGFloat PNPortraitJumpButtonHeight;
/// Stable portrait fallback when private native controls cannot be identified.
/// Match the supplied portrait viewport: glyph center at 49% of window height,
/// 27 points from the right edge; vertical safe-area/keyboard changes are ignored.
FOUNDATION_EXPORT CGRect PNPortraitFallbackJumpButtonFrame(CGRect windowBounds, CGRect safeBounds);
/// Require aligned, regularly spaced native actions, rather than a comment vote.
FOUNDATION_EXPORT BOOL PNFindPortraitActionRail(const PNPortraitActionAnchor *anchors,
    NSUInteger count, CGRect windowBounds, BOOL allowUngroupedFallback, PNPortraitActionRail *rail);
/// Native-style icon + caption, above Like and centered on the action column.
FOUNDATION_EXPORT CGRect PNPortraitJumpButtonFrame(CGRect windowBounds, CGRect safeBounds,
    PNPortraitActionRail rail);
