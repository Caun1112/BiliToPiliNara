#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#import "PNButtonLayout.h"

static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static PNPortraitActionAnchor Anchor(CGFloat y, PNPortraitActionKind kind, uintptr_t column) {
    return (PNPortraitActionAnchor){CGRectMake(385, y, 36, 38), kind, column};
}

int main(void) {
    @autoreleasepool {
        CGRect window = CGRectMake(0, 0, 430, 932);
        CGRect safe = CGRectMake(0, 59, 430, 839);
        PNPortraitActionRail rail;
        PNPortraitActionAnchor native[] = {
            Anchor(508, PNPortraitActionLike, 1),
            Anchor(578, PNPortraitActionComment, 1),
            Anchor(648, PNPortraitActionCoin, 1),
            Anchor(718, PNPortraitActionFavorite, 1),
            Anchor(788, PNPortraitActionShare, 1),
        };
        Check(PNFindPortraitActionRail(native, 5, window, NO, &rail), @"native vertical action rail is recognized");
        Check(CGRectEqualToRect(rail.like, native[0].frame), @"like is the first native action");
        Check(CGRectEqualToRect(rail.comment, native[1].frame), @"comment determines the native row spacing");
        CGRect frame = PNPortraitJumpButtonFrame(window, safe, rail);
        Check(!CGRectIsNull(frame), @"native caption control fits above like");
        Check(frame.size.width == 44 && frame.size.height == 60, @"44 point touch width with icon and caption");
        Check(fabs(CGRectGetMidX(frame) - CGRectGetMidX(native[0].frame)) < 0.01, @"native column centers align");
        Check(CGRectGetMaxY(frame) <= CGRectGetMinY(native[0].frame) - 8, @"caption and touch frame never overlap like");
        Check(fabs((frame.origin.y + 18) - (CGRectGetMidY(native[0].frame) - 70)) < 4,
            @"download glyph follows native row rhythm");

        CGRect keyboardSafe = CGRectMake(0, 500, 430, 100);
        Check(CGRectEqualToRect(frame, PNPortraitJumpButtonFrame(window, keyboardSafe, rail)),
            @"keyboard vertical insets do not move the rail control");
        PNPortraitActionRail invalid = {CGRectNull, CGRectNull};
        Check(CGRectIsNull(PNPortraitJumpButtonFrame(window, safe, invalid)), @"missing anchors do not invent a rail position");
        invalid = (PNPortraitActionRail){CGRectMake(385, 30, 36, 38), CGRectMake(385, 100, 36, 38)};
        Check(CGRectIsNull(PNPortraitJumpButtonFrame(window, safe, invalid)), @"insufficient space above like fails safely");

        PNPortraitActionAnchor commentVotes[5];
        for (NSUInteger i = 0; i < 5; i++) commentVotes[i] = Anchor(508 + 70 * i, PNPortraitActionLike, 0);
        Check(!PNFindPortraitActionRail(commentVotes, 5, window, YES, &rail),
            @"five comment vote buttons are not a native action rail");
        Check(!PNFindPortraitActionRail(native, 2, window, YES, &rail),
            @"a lone like and reply pair cannot reposition the control");
        PNPortraitActionAnchor horizontal[] = {
            {CGRectMake(40, 508, 36, 38), PNPortraitActionLike, 1},
            {CGRectMake(120, 508, 36, 38), PNPortraitActionComment, 1},
            {CGRectMake(200, 508, 36, 38), PNPortraitActionCoin, 1},
        };
        Check(!PNFindPortraitActionRail(horizontal, 3, window, YES, &rail),
            @"ordinary detail action row retains the fixed window placement");

        PNPortraitActionAnchor unnamed[5];
        for (NSUInteger i = 0; i < 5; i++) unnamed[i] = Anchor(508 + 70 * i, PNPortraitActionUnknown, 8);
        Check(PNFindPortraitActionRail(unnamed, 5, window, NO, &rail),
            @"a complete unlabeled native sidebar can use its common narrow parent");
        for (NSUInteger i = 0; i < 5; i++) unnamed[i].column = 0;
        Check(!PNFindPortraitActionRail(unnamed, 5, window, NO, &rail),
            @"unrelated unlabeled controls are insufficient outside immersive playback");
        Check(PNFindPortraitActionRail(unnamed, 5, window, YES, &rail),
            @"immersive playback can recognize a full five-action column");
        unnamed[3].frame.origin.x -= 70;
        Check(!PNFindPortraitActionRail(unnamed, 5, window, YES, &rail), @"misaligned controls are not a sidebar");

        PNPortraitActionAnchor avatarAndActions[6];
        for (NSUInteger i = 0; i < 6; i++) avatarAndActions[i] = Anchor(438 + 70 * i, PNPortraitActionUnknown, 8);
        Check(PNFindPortraitActionRail(avatarAndActions, 6, window, NO, &rail), @"avatar plus native actions is recognized");
        Check(CGRectEqualToRect(rail.like, avatarAndActions[1].frame),
            @"an unlabeled avatar above the actions is not mistaken for like");

        PNPortraitActionAnchor sparse[] = {native[0], native[1], native[4]};
        Check(PNFindPortraitActionRail(sparse, 3, window, NO, &rail),
            @"three known semantic actions suffice when optional rows are hidden");
        Check(CGRectEqualToRect(rail.like, native[0].frame), @"hidden rows do not shift the like anchor");

        PNPortraitActionAnchor mixed[10];
        for (NSUInteger i = 0; i < 5; i++) {
            mixed[i] = commentVotes[i];
            mixed[i + 5] = native[i];
        }
        Check(PNFindPortraitActionRail(mixed, 10, window, NO, &rail), @"native actions win over comment votes");
        Check(CGRectEqualToRect(rail.comment, native[1].frame), @"comment votes cannot supply the native comment row");
        Check(!PNFindPortraitActionRail(native, 5, CGRectMake(0, 0, 932, 430), YES, &rail),
            @"landscape uses the existing fixed window layout");
        Check(!PNFindPortraitActionRail(NULL, 0, window, YES, &rail), @"empty view tree is safe");
        Check(!PNFindPortraitActionRail(native, 5, window, YES, NULL), @"missing output is safe");

        for (NSUInteger i = 0; i < 5; i++) {
            PNPortraitActionAnchor moved[5];
            for (NSUInteger j = 0; j < 5; j++) moved[j] = native[j];
            moved[i].frame.origin.y = NAN;
            BOOL found = PNFindPortraitActionRail(moved, 5, window, YES, &rail);
            if (i <= 1) Check(!found, @"invalid mandatory anchors cannot position the button");
            else Check(found, @"an invalid optional row does not erase a verified semantic rail");
        }
        NSLog(@"PASS: %lu portrait action rail checks", (unsigned long)checks);
    }
    return 0;
}
