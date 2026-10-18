#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CydiaSubstrate/CydiaSubstrate.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#import <string.h>
#import "PNVideoTarget.h"
#import "PNButtonLayout.h"

// Only weak references to players; never retain a previous video's identifiers.
static NSHashTable *PNPlaybacks;
static NSLock *PNPlaybackLock;
static NSHashTable *PNButtons;
static dispatch_source_t PNRefreshTimer;
static char PNButtonKey;
static char PNObservedKey;

@interface PNJumpButton : UIButton
@property(nonatomic) BOOL opening;
@end

static void PNObservePlayback(id playback) {
    if (!playback || objc_getAssociatedObject(playback, &PNObservedKey)) return;
    [PNPlaybackLock lock];
    [PNPlaybacks addObject:playback];
    [PNPlaybackLock unlock];
    objc_setAssociatedObject(playback, &PNObservedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL PNVisibleInScope(UIView *render, UIView *scope) {
    UIWindow *window = [scope isKindOfClass:UIWindow.class] ? (UIWindow *)scope : scope.window;
    if (!render.window || render.window != window || ![render isDescendantOfView:scope]) return NO;
    CGRect visible = [render convertRect:render.bounds toView:scope];
    if (CGRectIsEmpty(CGRectIntersection(visible, scope.bounds))) return NO;
    for (UIView *view = render; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.01) return NO;
        if (view.clipsToBounds) {
            visible = CGRectIntersection(visible, [view convertRect:view.bounds toView:scope]);
            if (CGRectIsEmpty(visible)) return NO;
        }
        if (view == scope) return YES;
    }
    return NO;
}

static id PNCurrentPlayback(UIView *scope) {
    [PNPlaybackLock lock];
    NSArray *players = PNPlaybacks.allObjects;
    [PNPlaybackLock unlock];
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableArray *focused = [NSMutableArray array];
    for (id player in players) {
        id render = PNReadValue(player, @"view");
        if (![render isKindOfClass:UIView.class] || !PNVisibleInScope(render, scope)) continue;
        id item = PNReadValue(player, @"currentItem");
        if (![PNVideoTarget targetWithPlayerItem:item]) continue;
        [visible addObject:player];
        if ([PNReadValue(player, @"isGetFocus") boolValue]) [focused addObject:player];
    }
    // Refuse ambiguous players (e.g. transition/preload); do not guess a video.
    if (focused.count == 1) return focused.firstObject;
    return focused.count == 0 && visible.count == 1 ? visible.firstObject : nil;
}

static UIViewController *PNFrontController(UIViewController *controller);
static id PNVideoPlaybackInWindow(UIWindow *window);

static void PNShowMessage(UIWindow *window, NSString *message) {
    UIViewController *presenter = PNFrontController(window.rootViewController);
    if (!presenter.isViewLoaded || !presenter.view.window ||
        [presenter isKindOfClass:UIAlertController.class] || presenter.isBeingDismissed) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"在 PiliNara 打开"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@implementation PNJumpButton
- (void)openCurrentVideo {
    UIWindow *window = self.window;
    if (self.opening || !window || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    // Re-read the focused player in this window, even when a comment sheet is on top.
    id player = PNVideoPlaybackInWindow(window);
    PNVideoTarget *target = [PNVideoTarget targetWithPlayerItem:PNReadValue(player, @"currentItem")];
    if (!target) {
        PNShowMessage(window, @"尚未读取到当前视频和分 P。请让视频开始播放后重试。若仍失败，可能需要适配当前哔哩哔哩版本。");
        return;
    }
    NSURLComponents *download = [NSURLComponents componentsWithURL:target.downloadURL resolvingAgainstBaseURL:NO];
    download.queryItems = [download.queryItems arrayByAddingObject:
        [NSURLQueryItem queryItemWithName:@"request_id" value:NSUUID.UUID.UUIDString]];
    self.opening = YES;
    self.enabled = NO;
    // Do not call canOpenURL: the host App has no pilinara scheme whitelist.
    [UIApplication.sharedApplication openURL:download.URL options:@{} completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.opening = NO;
            self.enabled = YES;
            if (!success) PNShowMessage(window, @"无法打开 PiliNara。请安装支持一键480P下载的新版 PiliNara。");
        });
    }];
}
@end

static PNJumpButton *PNInstallButton(UIWindow *window) {
    PNJumpButton *button = objc_getAssociatedObject(window, &PNButtonKey);
    if (!button) {
        button = [PNJumpButton buttonWithType:UIButtonTypeCustom];
        button.backgroundColor = [UIColor colorWithRed:0.91 green:0.27 blue:0.48 alpha:1];
        button.alpha = 0.5;
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.18;
        button.layer.shadowRadius = 6;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        [button setTitle:@"P↗" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.accessibilityIdentifier = @"com.caun.bilitopilinara.open";
        button.accessibilityLabel = @"在 PiliNara 下载当前视频（480P）";
        button.accessibilityHint = @"下载当前分P，完成后弹出分享或保存面板";
        [button addTarget:button action:@selector(openCurrentVideo) forControlEvents:UIControlEventTouchUpInside];
        // A single small window subview leaves all other touches with Bilibili.
        [window addSubview:button];
        objc_setAssociatedObject(window, &PNButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [PNButtons addObject:button];
    }
    // Only the actual app window defines placement. Page, sheet, player and
    // keyboard layouts must never become the button's coordinate system.
    CGRect bounds = window.bounds;
    CGRect safe = UIEdgeInsetsInsetRect(bounds, window.safeAreaInsets);
    CGRect frame = PNJumpButtonFrame(bounds, safe);
    if (!CGRectEqualToRect(button.frame, frame)) button.frame = frame;
    button.layer.cornerRadius = CGRectGetWidth(button.bounds) / 2;
    button.hidden = CGRectIsEmpty(button.frame);
    if (window.subviews.lastObject != button) [window bringSubviewToFront:button];
    return button;
}

static UIViewController *PNFrontController(UIViewController *controller) {
    for (NSUInteger depth = 0; controller && depth < 20; depth++) {
        UIViewController *next = nil;
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
            next = controller.presentedViewController;
        } else if ([controller isKindOfClass:UINavigationController.class]) {
            next = ((UINavigationController *)controller).visibleViewController;
        } else if ([controller isKindOfClass:UITabBarController.class]) {
            next = ((UITabBarController *)controller).selectedViewController;
        }
        if (!next || next == controller) return controller;
        controller = next;
    }
    return controller;
}

static BOOL PNLikeName(NSString *name) {
    if (!name.length) return NO;
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"dislike"] || [lower containsString:@"不喜欢"] || [lower containsString:@"点踩"]) return NO;
    return [lower containsString:@"点赞"] || [lower isEqualToString:@"赞"] ||
        [lower containsString:@"like"] || [lower containsString:@"thumbup"] ||
        [lower containsString:@"thumbsup"];
}

// Recognize a portrait video context only; controls never influence placement.
static BOOL PNHasVideoActions(UIView *root) {
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (pending.count && visited++ < 1800) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (view.hidden || view.alpha < 0.01 || [view isKindOfClass:PNJumpButton.class]) continue;
        CGRect rect = [view convertRect:view.bounds toView:root];
        if (!PNVisibleInScope(view, root)) continue;
        [pending addObjectsFromArray:view.subviews];
        CGFloat width = CGRectGetWidth(rect), height = CGRectGetHeight(rect);
        CGFloat x = CGRectGetMidX(rect), y = CGRectGetMidY(rect);
        if (x < CGRectGetMinX(root.bounds) + CGRectGetWidth(root.bounds) * 0.78 ||
            y < CGRectGetMinY(root.bounds) + CGRectGetHeight(root.bounds) * 0.2 ||
            y > CGRectGetMinY(root.bounds) + CGRectGetHeight(root.bounds) * 0.86 ||
            width < 16 || width > 100 || height < 16 || height > 110 ||
            !CGRectContainsRect(root.bounds, rect)) continue;
        BOOL named = PNLikeName(view.accessibilityLabel) || PNLikeName(view.accessibilityIdentifier) ||
            PNLikeName(NSStringFromClass(view.class));
        if ([view isKindOfClass:UIControl.class]) {
            UIControl *control = (UIControl *)view;
            for (id target in control.allTargets) {
                for (NSString *action in [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]) {
                    named |= PNLikeName(action);
                }
            }
        }
        if (named) return YES;
    }
    return NO;
}

static UIViewController *PNDetailOwner(UIView *render) {
    Class detail = NSClassFromString(@"BBVDDetailVC");
    for (UIResponder *responder = render; responder; responder = responder.nextResponder) {
        if (detail && [responder isKindOfClass:detail]) return (UIViewController *)responder;
        if ([responder isKindOfClass:UIViewController.class]) {
            for (UIViewController *parent = ((UIViewController *)responder).parentViewController;
                 parent; parent = parent.parentViewController) {
                if (detail && [parent isKindOfClass:detail]) return parent;
            }
        }
    }
    return nil;
}

static id PNVideoPlaybackInWindow(UIWindow *window) {
    id player = PNCurrentPlayback(window);
    UIView *render = PNReadValue(player, @"view");
    if (![render isKindOfClass:UIView.class]) return nil;
    if (PNDetailOwner(render)) return player;
    CGRect bounds = window.bounds;
    if (CGRectIsEmpty(bounds)) return nil;
    CGRect playerRect = [render convertRect:render.bounds toView:window];
    BOOL fullPlayer = CGRectGetWidth(playerRect) >= CGRectGetWidth(bounds) * 0.7 &&
        CGRectGetHeight(playerRect) >= CGRectGetHeight(bounds) * 0.65;
    if (fullPlayer) return player;
    BOOL portrait = CGRectGetHeight(bounds) > CGRectGetWidth(bounds);
    return portrait && PNHasVideoActions(window) ? player : nil;
}

static void PNRefreshButtons(void) {
    static BOOL refreshing;
    if (refreshing) return;
    refreshing = YES;
    NSMutableSet *activeButtons = [NSMutableSet set];
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                // Text entry may change the key window. Match the content window
                // by its current video instead of moving into an input window.
                if (window.hidden || window.alpha < 0.01 || !window.rootViewController.isViewLoaded) continue;
                if (!PNVideoPlaybackInWindow(window)) continue;
                [activeButtons addObject:PNInstallButton(window)];
            }
        }
    }
    for (PNJumpButton *button in PNButtons.allObjects) {
        if (![activeButtons containsObject:button]) button.hidden = YES;
    }
    refreshing = NO;
}

static void (*PNOriginalAppear)(UIViewController *, SEL, BOOL);
static void PNAppear(UIViewController *owner, SEL selector, BOOL animated) {
    PNOriginalAppear(owner, selector, animated);
    PNRefreshButtons();
}
static void (*PNOriginalLayout)(UIViewController *, SEL);
static void PNLayout(UIViewController *owner, SEL selector) {
    PNOriginalLayout(owner, selector);
    PNRefreshButtons();
}
static void (*PNOriginalSetItem)(id, SEL, id);
static void PNSetItem(id player, SEL selector, id item) {
    PNOriginalSetItem(player, selector, item);
    PNObservePlayback(player);
}
static double (*PNOriginalTime)(id, SEL);
static double PNCurrentTime(id player, SEL selector) {
    PNObservePlayback(player);
    return PNOriginalTime(player, selector);
}

static BOOL PNHasSignature(Class cls, SEL selector, const char *returnType, NSUInteger arguments) {
    NSMethodSignature *signature = [cls instanceMethodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == arguments &&
        strcmp(signature.methodReturnType, returnType) == 0;
}

static void PNInstallHooks(void) {
    static BOOL detailInstalled, playbackInstalled, timeInstalled;
    Class detail = NSClassFromString(@"BBVDDetailVC");
    if (!detailInstalled && detail && [detail isSubclassOfClass:UIViewController.class]) {
        MSHookMessageEx(detail, @selector(viewDidAppear:), (IMP)PNAppear, (IMP *)&PNOriginalAppear);
        MSHookMessageEx(detail, @selector(viewDidLayoutSubviews), (IMP)PNLayout, (IMP *)&PNOriginalLayout);
        detailInstalled = YES;
        NSLog(@"[BiliToPiliNara] Detail button hook installed (Bilibili %@)", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    }
    Class playback = NSClassFromString(@"BBPlayerPlayback");
    SEL setter = NSSelectorFromString(@"setCurrentItem:");
    if (!playbackInstalled && PNHasSignature(playback, setter, "v", 3)) {
        NSMethodSignature *signature = [playback instanceMethodSignatureForSelector:setter];
        if ([signature getArgumentTypeAtIndex:2][0] == '@') {
            MSHookMessageEx(playback, setter, (IMP)PNSetItem, (IMP *)&PNOriginalSetItem);
            playbackInstalled = YES;
        }
    }
    // Covers a restored player that set its item before our deferred installation.
    SEL currentTime = NSSelectorFromString(@"currentTime");
    if (!timeInstalled && PNHasSignature(playback, currentTime, "d", 2)) {
        MSHookMessageEx(playback, currentTime, (IMP)PNCurrentTime, (IMP *)&PNOriginalTime);
        timeInstalled = YES;
    }
}

static atomic_bool PNInstallScheduled;
static void PNImageAdded(__unused const struct mach_header *header, __unused intptr_t slide) {
    // App modules may be loaded after launch. Coalesce callbacks outside dyld's lock.
    if (atomic_exchange(&PNInstallScheduled, true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&PNInstallScheduled, false);
        PNInstallHooks();
    });
}

__attribute__((constructor)) static void PNInitialize(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"tv.danmaku.bilianime"]) return;
        PNPlaybacks = [NSHashTable weakObjectsHashTable];
        PNPlaybackLock = [NSLock new];
        PNButtons = [NSHashTable weakObjectsHashTable];
        dispatch_async(dispatch_get_main_queue(), ^{
            PNRefreshTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(PNRefreshTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2),
                NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
            dispatch_source_set_event_handler(PNRefreshTimer, ^{ PNRefreshButtons(); });
            dispatch_resume(PNRefreshTimer);
        });
        _dyld_register_func_for_add_image(PNImageAdded);
    }
}
