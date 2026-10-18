#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

FOUNDATION_EXPORT const CGFloat PNJumpButtonDiameter;

/// Return a circular control frame in window coordinates. Keep its right edge
/// 12 points inside the horizontal safe edge and its center at 60% of the window
/// height. Clamp horizontally to the safe interval and vertically to the window,
/// with an 8 point margin. The safe bounds' vertical inset never moves the button.
FOUNDATION_EXPORT CGRect PNJumpButtonFrame(CGRect windowBounds, CGRect safeBounds);
