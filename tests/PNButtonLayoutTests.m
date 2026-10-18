#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#import "PNButtonLayout.h"

static NSUInteger checks;

static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void Near(CGFloat actual, CGFloat expected, NSString *message) {
    Check(fabs(actual - expected) < 0.0001,
        [NSString stringWithFormat:@"%@ (actual %.5f, expected %.5f)", message, actual, expected]);
}

static void RectNear(CGRect actual, CGRect expected, NSString *message) {
    Near(actual.origin.x, expected.origin.x, [message stringByAppendingString:@": x"]);
    Near(actual.origin.y, expected.origin.y, [message stringByAppendingString:@": y"]);
    Near(actual.size.width, expected.size.width, [message stringByAppendingString:@": width"]);
    Near(actual.size.height, expected.size.height, [message stringByAppendingString:@": height"]);
}

static void CircleInside(CGRect frame, CGRect window, CGRect horizontalSafe,
    CGFloat diameter, NSString *message) {
    Near(frame.size.width, diameter, [message stringByAppendingString:@": width"]);
    Near(frame.size.height, diameter, [message stringByAppendingString:@": height"]);
    CGRect available = CGRectMake(CGRectGetMinX(horizontalSafe) + 8,
        CGRectGetMinY(window) + 8, CGRectGetWidth(horizontalSafe) - 16,
        CGRectGetHeight(window) - 16);
    Check(CGRectContainsRect(available, frame),
        [message stringByAppendingString:@": respects side-safe and full-window margins"]);
}

// These are geometry contracts for a caller converting a window frame into a
// content view. UIKit integration must separately ensure the caller supplies
// its actual UIWindow, rather than a page or keyboard-adjusted content view.
static void ContentCoordinateContract(NSString *name, CGRect contentBounds,
    CGRect contentSafe, CGAffineTransform contentToWindow) {
    CGRect window = CGRectMake(0, 0, 430, 932);
    CGRect windowSafe = CGRectMake(0, 59, 430, 839);
    CGRect fixedFrame = PNJumpButtonFrame(window, windowSafe);
    CGRect contentFrame = CGRectApplyAffineTransform(fixedFrame,
        CGAffineTransformInvert(contentToWindow));
    CGRect roundTrip = CGRectApplyAffineTransform(contentFrame, contentToWindow);
    RectNear(roundTrip, CGRectMake(374, 537.2, 44, 44),
        [name stringByAppendingString:@": content conversion retains the fixed window position"]);

    // Verify each fixture would catch accidentally substituting content bounds.
    CGRect incorrectContentFrame = PNJumpButtonFrame(contentBounds, contentSafe);
    CGRect incorrectWindowFrame = CGRectApplyAffineTransform(incorrectContentFrame, contentToWindow);
    Check(fabs(CGRectGetMidY(incorrectWindowFrame) - CGRectGetMidY(fixedFrame)) > 1 ||
        fabs(CGRectGetMaxX(incorrectWindowFrame) - CGRectGetMaxX(fixedFrame)) > 1,
        [name stringByAppendingString:@": fixture detects content-relative placement"]);
}

int main(void) {
    @autoreleasepool {
        Near(PNJumpButtonDiameter, 44, @"exported touch target diameter");

        CGRect portrait = CGRectMake(0, 0, 430, 932);
        CGRect portraitSafe = CGRectMake(0, 59, 430, 839);
        CGRect portraitFrame = PNJumpButtonFrame(portrait, portraitSafe);
        CircleInside(portraitFrame, portrait, portraitSafe, 44, @"430 by 932 portrait");
        Near(CGRectGetMaxX(portraitFrame), 418, @"portrait right edge has a 12 point gap");
        Near(CGRectGetMidY(portraitFrame), 559.2, @"portrait center is at 60 percent of the entire window");

        CGRect landscape = CGRectMake(0, 0, 932, 430);
        CGRect landscapeSafe = CGRectMake(59, 0, 814, 409);
        CGRect landscapeFrame = PNJumpButtonFrame(landscape, landscapeSafe);
        CircleInside(landscapeFrame, landscape, landscapeSafe, 44, @"932 by 430 actual landscape");
        Near(CGRectGetMaxX(landscapeFrame), 861, @"landscape gap follows the notch safe edge");
        Near(CGRectGetMidY(landscapeFrame), 258, @"rotation uses the current 430 point window height");
        RectNear(PNJumpButtonFrame(portrait, portraitSafe), portraitFrame,
            @"rotating back restores the portrait frame without accumulated position");

        CGRect shifted = CGRectOffset(portrait, 100, 200);
        CGRect shiftedSafe = CGRectOffset(portraitSafe, 100, 200);
        CGRect frame = PNJumpButtonFrame(shifted, shiftedSafe);
        CircleInside(frame, shifted, shiftedSafe, 44, @"nonzero window bounds origin");
        Near(frame.origin.x, 474, @"nonzero X origin is preserved");
        Near(CGRectGetMidY(frame), 759.2, @"nonzero Y origin participates in center");

        ContentCoordinateContract(@"scrolled comment page", CGRectMake(0, 200, 430, 640),
            CGRectMake(0, 200, 430, 640), CGAffineTransformMakeTranslation(0, -200));
        ContentCoordinateContract(@"bottom sheet", CGRectMake(0, 0, 398, 600),
            CGRectMake(0, 0, 398, 566), CGAffineTransformMakeTranslation(16, 332));
        ContentCoordinateContract(@"keyboard-reduced content", CGRectMake(0, 0, 430, 590),
            CGRectMake(0, 59, 430, 531), CGAffineTransformIdentity);
        ContentCoordinateContract(@"scaled sheet presentation", CGRectMake(0, 0, 430, 740),
            CGRectMake(0, 59, 430, 681), CGAffineTransformMake(0.92, 0, 0, 0.92, 17.2, 205));

        CGRect verticalSafeChanges[] = {
            CGRectMake(0, 59, 430, 531), // Keyboard shrinks the content area.
            CGRectMake(0, 600, 430, 298), // A sheet shifts the apparent safe top.
            CGRectMake(0, 0, 430, 100),
            CGRectMake(0, 1000, 430, 36), // Even vertically disjoint safe bounds.
            CGRectMake(0, 100, 430, 0),
            CGRectMake(0, NAN, 430, INFINITY),
        };
        for (NSUInteger index = 0; index < sizeof(verticalSafeChanges) / sizeof(verticalSafeChanges[0]); index++) {
            RectNear(PNJumpButtonFrame(portrait, verticalSafeChanges[index]), portraitFrame,
                @"vertical safe-area changes never move or shrink the portrait control");
        }
        RectNear(PNJumpButtonFrame(landscape, CGRectMake(59, 0, 814, 110)), landscapeFrame,
            @"landscape keyboard retains physical notch side inset and fixed height");
        RectNear(PNJumpButtonFrame(landscape, CGRectMake(59, 300, 814, 50)), landscapeFrame,
            @"landscape sheet vertical shift leaves the entire frame unchanged");

        CGRect exactSafe = CGRectMake(130, 100, 60, 700);
        frame = PNJumpButtonFrame(portrait, exactSafe);
        CircleInside(frame, portrait, exactSafe, 44, @"44 point circle fits exactly after margins");
        Near(frame.origin.x, 138, @"horizontal clamp respects both safe margins");

        CGRect narrowSafe = CGRectMake(130, 100, 40, 700);
        frame = PNJumpButtonFrame(portrait, narrowSafe);
        CircleInside(frame, portrait, narrowSafe, 24, @"narrow safe interval shrinks both axes equally");
        Near(frame.origin.x, 138, @"narrow safe interval retains both side margins");
        Near(CGRectGetMidY(frame), 559.2, @"shrinking preserves the window center");

        CGRect shortWindow = CGRectMake(0, 100, 430, 36);
        frame = PNJumpButtonFrame(shortWindow, shortWindow);
        CircleInside(frame, shortWindow, shortWindow, 20, @"short window shrinks a circle");
        Near(frame.origin.y, 108, @"short window clamps both top and bottom margins");
        CGRect smallWindow = CGRectMake(0, 100, 430, 60);
        frame = PNJumpButtonFrame(smallWindow, smallWindow);
        CircleInside(frame, smallWindow, smallWindow, 44, @"small window retains the full circle when it fits");
        Near(CGRectGetMaxY(frame), 152, @"small window clamps the 60 percent center to its bottom margin");

        CGRect invalidBounds[] = {
            CGRectZero, CGRectNull, CGRectInfinite,
            CGRectMake(0, 0, 0, 932), CGRectMake(0, 0, 430, 0),
            CGRectMake(0, 0, -430, 932), CGRectMake(NAN, 0, 430, 932),
            CGRectMake(0, 0, INFINITY, 932),
        };
        for (NSUInteger index = 0; index < sizeof(invalidBounds) / sizeof(invalidBounds[0]); index++) {
            Check(CGRectEqualToRect(PNJumpButtonFrame(invalidBounds[index], portraitSafe), CGRectZero),
                @"invalid window bounds return CGRectZero");
        }

        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, CGRectMake(0, 0, 16, 100)), CGRectZero),
            @"no diameter remains when safe width equals both margins");
        Check(CGRectEqualToRect(PNJumpButtonFrame(CGRectMake(0, 0, 430, 15), portraitSafe), CGRectZero),
            @"no diameter remains when window height is smaller than both margins");

        CGRect fallback = PNJumpButtonFrame(portrait, portrait);
        CGRect invalidSafeIntervals[] = {
            CGRectNull, CGRectZero, CGRectMake(500, 0, 100, 100),
            CGRectMake(NAN, 0, 430, 932), CGRectMake(0, 0, INFINITY, 932),
        };
        for (NSUInteger index = 0; index < sizeof(invalidSafeIntervals) / sizeof(invalidSafeIntervals[0]); index++) {
            Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, invalidSafeIntervals[index]), fallback),
                @"unavailable or disjoint safe interval falls back to window bounds");
        }

        CGRect oversizedSafe = CGRectMake(-50, -50, 530, 1032);
        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, oversizedSafe), fallback),
            @"horizontal safe interval is intersected with window bounds");

        NSLog(@"PASS: %lu button layout checks", (unsigned long)checks);
    }
    return 0;
}
