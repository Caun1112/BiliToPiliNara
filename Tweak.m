#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CydiaSubstrate/CydiaSubstrate.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#import <string.h>
#import "PNVideoTarget.h"

// Only weak references to players; never retain a previous video's identifiers.
static NSHashTable *PNPlaybacks;
static NSLock *PNPlaybackLock;
static char PNButtonKey;
static char PNObservedKey;

@interface PNJumpButton : UIButton
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic) BOOL opening;
@end

static void PNObservePlayback(id playback) {
    if (!playback || objc_getAssociatedObject(playback, &PNObservedKey)) return;
    [PNPlaybackLock lock];
    [PNPlaybacks addObject:playback];
    [PNPlaybackLock unlock];
    objc_setAssociatedObject(playback, &PNObservedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL PNVisibleInOwner(UIView *render, UIView *owner) {
    if (!render.window || render.window != owner.window || ![render isDescendantOfView:owner]) return NO;
    for (UIView *view = render; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.01) return NO;
        if (view == owner) return YES;
    }
    return NO;
}

static id PNCurrentPlayback(UIViewController *owner) {
    [PNPlaybackLock lock];
    NSArray *players = PNPlaybacks.allObjects;
    [PNPlaybackLock unlock];
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableArray *focused = [NSMutableArray array];
    for (id player in players) {
        id render = PNReadValue(player, @"view");
        if (![render isKindOfClass:UIView.class] || !PNVisibleInOwner(render, owner.view)) continue;
        id item = PNReadValue(player, @"currentItem");
        if (![PNVideoTarget targetWithPlayerItem:item]) continue;
        [visible addObject:player];
        if ([PNReadValue(player, @"isGetFocus") boolValue]) [focused addObject:player];
    }
    // Refuse ambiguous players (e.g. transition/preload); do not guess a video.
    if (focused.count == 1) return focused.firstObject;
    return focused.count == 0 && visible.count == 1 ? visible.firstObject : nil;
}

static void PNShowMessage(UIViewController *owner, NSString *message) {
    if (!owner.view.window || owner.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"在 PiliNara 打开"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}

@implementation PNJumpButton
- (void)openCurrentVideo {
    UIViewController *owner = self.owner;
    if (self.opening || !owner.view.window) return;
    id player = PNCurrentPlayback(owner);
    PNVideoTarget *target = [PNVideoTarget targetWithPlayerItem:PNReadValue(player, @"currentItem")];
    if (!target) {
        PNShowMessage(owner, @"尚未读取到当前视频和分 P。请让视频开始播放后重试。若仍失败，可能需要适配当前哔哩哔哩版本。");
        return;
    }
    self.opening = YES;
    self.enabled = NO;
    // Do not call canOpenURL: the host App has no pilinara scheme whitelist.
    [UIApplication.sharedApplication openURL:target.URL options:@{} completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.opening = NO;
            self.enabled = YES;
            if (!success) PNShowMessage(owner, @"无法打开 PiliNara。请安装支持 pilinara:// 的版本（2026-10-13 的“B站打开”版或更新版本）。");
        });
    }];
}
@end

static void PNInstallButton(UIViewController *owner) {
    if (!owner.isViewLoaded) return;
    PNJumpButton *button = objc_getAssociatedObject(owner, &PNButtonKey);
    if (!button) {
        button = [PNJumpButton buttonWithType:UIButtonTypeCustom];
        button.owner = owner;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.backgroundColor = [UIColor colorWithRed:0.91 green:0.27 blue:0.48 alpha:0.96];
        button.layer.cornerRadius = 21;
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.18;
        button.layer.shadowRadius = 6;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [button setTitle:@"PiliNara ↗" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.accessibilityIdentifier = @"com.caun.bilitopilinara.open";
        button.accessibilityLabel = @"在 PiliNara 打开当前视频";
        button.accessibilityHint = @"跳转到当前视频的同一分 P";
        [button addTarget:button action:@selector(openCurrentVideo) forControlEvents:UIControlEventTouchUpInside];
        [owner.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:owner.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
            [button.bottomAnchor constraintEqualToAnchor:owner.view.safeAreaLayoutGuide.bottomAnchor constant:-88],
            [button.widthAnchor constraintEqualToConstant:112],
            [button.heightAnchor constraintEqualToConstant:44],
        ]];
        objc_setAssociatedObject(owner, &PNButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The control belongs to the details page; keep landscape video unobstructed.
    button.hidden = CGRectGetWidth(owner.view.bounds) > CGRectGetHeight(owner.view.bounds);
    [owner.view bringSubviewToFront:button];
}

static void (*PNOriginalAppear)(UIViewController *, SEL, BOOL);
static void PNAppear(UIViewController *owner, SEL selector, BOOL animated) {
    PNOriginalAppear(owner, selector, animated);
    PNInstallButton(owner);
}
static void (*PNOriginalLayout)(UIViewController *, SEL);
static void PNLayout(UIViewController *owner, SEL selector) {
    PNOriginalLayout(owner, selector);
    PNInstallButton(owner);
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
        _dyld_register_func_for_add_image(PNImageAdded);
    }
}
