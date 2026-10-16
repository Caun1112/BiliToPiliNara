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

static void CircleInside(CGRect frame, CGRect safe, CGFloat diameter, NSString *message) {
    Near(frame.size.width, diameter, [message stringByAppendingString:@": width"]);
    Near(frame.size.height, diameter, [message stringByAppendingString:@": height"]);
    Check(CGRectContainsRect(CGRectInset(safe, 8, 8), frame),
        [message stringByAppendingString:@": respects all safe margins"]);
}

int main(void) {
    @autoreleasepool {
        Near(PNJumpButtonDiameter, 44, @"exported touch target diameter");

        CGRect portrait = CGRectMake(0, 0, 430, 932);
        CGRect portraitSafe = CGRectMake(0, 59, 430, 839);
        CGRect frame = PNJumpButtonFrame(portrait, portraitSafe, CGRectNull);
        CircleInside(frame, portraitSafe, 44, @"430 by 932 portrait");
        Near(CGRectGetMaxX(frame), 418, @"portrait right edge has a 12 point gap");
        Near(CGRectGetMidY(frame), 559.2, @"portrait center is at 60 percent height");

        CGRect landscape = CGRectMake(0, 0, 932, 430);
        CGRect landscapeSafe = CGRectMake(59, 0, 814, 409);
        frame = PNJumpButtonFrame(landscape, landscapeSafe, CGRectNull);
        CircleInside(frame, landscapeSafe, 44, @"932 by 430 actual landscape");
        Near(CGRectGetMaxX(frame), 861, @"landscape gap follows the notch safe edge");
        Near(CGRectGetMidY(frame), 258, @"landscape uses its current 430 point height");

        CGRect shifted = CGRectOffset(portrait, 100, 200);
        CGRect shiftedSafe = CGRectOffset(portraitSafe, 100, 200);
        frame = PNJumpButtonFrame(shifted, shiftedSafe, CGRectNull);
        CircleInside(frame, shiftedSafe, 44, @"nonzero bounds origin");
        Near(frame.origin.x, 474, @"nonzero X origin is preserved");
        Near(CGRectGetMidY(frame), 759.2, @"nonzero Y origin participates in center");

        CGRect like = CGRectMake(370, 700, 36, 44);
        frame = PNJumpButtonFrame(portrait, portraitSafe, like);
        CircleInside(frame, portraitSafe, 44, @"portrait like anchor");
        Near(CGRectGetMidX(frame), CGRectGetMidX(like), @"like anchor aligns horizontal centers");
        Near(CGRectGetMaxY(frame), 688, @"button bottom is 12 points above like top");

        CGRect landscapeLike = CGRectMake(800, 300, 40, 40);
        frame = PNJumpButtonFrame(landscape, landscapeSafe, landscapeLike);
        CircleInside(frame, landscapeSafe, 44, @"landscape like anchor");
        Near(CGRectGetMidX(frame), 820, @"landscape like centers align");
        Near(CGRectGetMaxY(frame), 288, @"landscape like separation is 12 points");

        frame = PNJumpButtonFrame(shifted, shiftedSafe, CGRectOffset(like, 100, 200));
        CircleInside(frame, shiftedSafe, 44, @"shifted like anchor");
        Near(CGRectGetMidX(frame), 488, @"shifted like center aligns");
        Near(CGRectGetMaxY(frame), 888, @"shifted like top separation");

        frame = PNJumpButtonFrame(portrait, portraitSafe, CGRectMake(370, 60, 36, 44));
        CircleInside(frame, portraitSafe, 44, @"top edge clamps like anchor");
        Near(CGRectGetMinY(frame), 67, @"top safe inset is retained");

        frame = PNJumpButtonFrame(portrait, portraitSafe, CGRectMake(400, 700, 22, 44));
        CircleInside(frame, portraitSafe, 44, @"right edge clamps like anchor");
        Near(CGRectGetMaxX(frame), 422, @"right safe inset is retained");

        frame = PNJumpButtonFrame(portrait, portraitSafe, CGRectMake(0, 700, 20, 44));
        CircleInside(frame, portraitSafe, 44, @"left edge clamps like anchor");
        Near(CGRectGetMinX(frame), 8, @"left safe inset is retained");

        CGRect bottomSafe = CGRectMake(0, 0, 430, 100);
        frame = PNJumpButtonFrame(portrait, bottomSafe, CGRectNull);
        CircleInside(frame, bottomSafe, 44, @"short safe area clamps default center");
        Near(CGRectGetMaxY(frame), 92, @"bottom safe inset is retained");

        CGRect exactSafe = CGRectMake(130, 100, 60, 700);
        frame = PNJumpButtonFrame(portrait, exactSafe, CGRectNull);
        CircleInside(frame, exactSafe, 44, @"44 point circle fits exactly after margins");

        CGRect narrowSafe = CGRectMake(130, 100, 40, 700);
        frame = PNJumpButtonFrame(portrait, narrowSafe, CGRectNull);
        CircleInside(frame, narrowSafe, 24, @"narrow safe area shrinks both axes equally");
        Near(frame.origin.x, 138, @"narrow safe area retains both side margins");
        Near(CGRectGetMidY(frame), 559.2, @"shrinking preserves the default center");

        CGRect shortSafe = CGRectMake(0, 100, 430, 36);
        frame = PNJumpButtonFrame(portrait, shortSafe, CGRectNull);
        CircleInside(frame, shortSafe, 20, @"short safe area shrinks a circle");
        Near(frame.origin.y, 108, @"short safe area retains top and bottom margins");

        CGRect defaultFrame = PNJumpButtonFrame(portrait, portraitSafe, CGRectNull);
        CGRect invalidLikes[] = {
            CGRectNull, CGRectZero, CGRectInfinite,
            CGRectMake(1000, 700, 36, 44), CGRectMake(-1, 700, 36, 44),
            CGRectMake(370, 920, 36, 44), CGRectMake(NAN, 700, 36, 44),
            CGRectMake(370, 700, -36, 44),
        };
        for (NSUInteger index = 0; index < sizeof(invalidLikes) / sizeof(invalidLikes[0]); index++) {
            Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, portraitSafe, invalidLikes[index]), defaultFrame),
                @"invalid or offscreen like frame uses the default placement");
        }

        CGRect invalidBounds[] = {
            CGRectZero, CGRectNull, CGRectInfinite,
            CGRectMake(0, 0, 0, 932), CGRectMake(0, 0, 430, 0),
            CGRectMake(0, 0, -430, 932), CGRectMake(NAN, 0, 430, 932),
            CGRectMake(0, 0, INFINITY, 932),
        };
        for (NSUInteger index = 0; index < sizeof(invalidBounds) / sizeof(invalidBounds[0]); index++) {
            Check(CGRectEqualToRect(PNJumpButtonFrame(invalidBounds[index], portraitSafe, like), CGRectZero),
                @"invalid owner bounds return CGRectZero");
        }

        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, CGRectMake(0, 0, 16, 100), CGRectNull), CGRectZero),
            @"no diameter remains when safe width equals both margins");
        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, CGRectMake(0, 0, 100, 15), CGRectNull), CGRectZero),
            @"no diameter remains when safe height is smaller than both margins");

        CGRect fallback = PNJumpButtonFrame(portrait, portrait, CGRectNull);
        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, CGRectNull, CGRectNull), fallback),
            @"unavailable safe area falls back to owner bounds");
        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, CGRectZero, CGRectNull), fallback),
            @"unlaid-out safe area falls back to owner bounds");
        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, CGRectMake(500, 0, 100, 100), CGRectNull), fallback),
            @"disjoint safe area falls back to owner bounds");

        CGRect oversizedSafe = CGRectMake(-50, -50, 530, 1032);
        Check(CGRectEqualToRect(PNJumpButtonFrame(portrait, oversizedSafe, CGRectNull), fallback),
            @"safe area is intersected with owner bounds");

        NSLog(@"PASS: %lu button layout checks", (unsigned long)checks);
    }
    return 0;
}
