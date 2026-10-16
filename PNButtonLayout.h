#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

FOUNDATION_EXPORT const CGFloat PNJumpButtonDiameter;

/// Place a circular jump control in the owner's coordinate system.
/// A visible like frame anchors the control 12 points above it; CGRectNull uses
/// the right safe edge and a center at 60% of the owner's height.
FOUNDATION_EXPORT CGRect PNJumpButtonFrame(CGRect bounds, CGRect safeBounds, CGRect likeFrame);
