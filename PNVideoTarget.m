#import "PNVideoTarget.h"
#import <string.h>
#import <limits.h>
#import <stdlib.h>

id PNReadValue(id object, NSString *key) {
    if (!object || object == NSNull.null) return nil;
    if ([object isKindOfClass:NSDictionary.class]) return object[key];
    SEL selector = NSSelectorFromString(key);
    @try {
        if (![object respondsToSelector:selector]) return nil;
        NSMethodSignature *signature = [object methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2) return nil;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = selector;
        [invocation invokeWithTarget:object];
        const char *type = signature.methodReturnType;
        while (*type && strchr("rnNoORV", *type)) type++;
        switch (*type) {
            case '@': { __unsafe_unretained id value = nil; [invocation getReturnValue:&value]; return value; }
#define PN_BOX(code, ctype) case code: { ctype value = 0; [invocation getReturnValue:&value]; return @(value); }
            PN_BOX('q', long long)
            PN_BOX('Q', unsigned long long)
            PN_BOX('i', int)
            PN_BOX('I', unsigned int)
            PN_BOX('l', long)
            PN_BOX('L', unsigned long)
            PN_BOX('s', short)
            PN_BOX('S', unsigned short)
            PN_BOX('c', char)
            PN_BOX('C', unsigned char)
            PN_BOX('B', BOOL)
#undef PN_BOX
            default: return nil;
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *PNPositiveInteger(id value) {
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) return nil;
    NSString *text = [value description];
    if (text.length == 0 || text.length > 19) return nil;
    NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    if ([text rangeOfCharacterFromSet:nonDigits].location != NSNotFound || text.longLongValue <= 0) return nil;
    // Bilibili IDs and Dart's int on iOS fit in a signed 64-bit integer.
    unsigned long long number = strtoull(text.UTF8String, NULL, 10);
    if (number > LLONG_MAX) return nil;
    return [NSString stringWithFormat:@"%llu", number];
}

@implementation PNVideoTarget
+ (instancetype)targetWithPlayerItem:(id)item {
    // BBPlayerPlayItem.oid is the AV id; cid identifies the actual current P.
    NSString *videoID = PNPositiveInteger(PNReadValue(item, @"oid"));
    if (!videoID) videoID = PNPositiveInteger(PNReadValue(item, @"aid"));
    if (!videoID) {
        id bvid = PNReadValue(item, @"bvid");
        if ([bvid isKindOfClass:NSString.class] && [bvid length] == 12 && [bvid hasPrefix:@"BV"] &&
            [bvid rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"] invertedSet]].location == NSNotFound) {
            videoID = bvid;
        }
    }
    NSString *cid = PNPositiveInteger(PNReadValue(item, @"cid"));
    if (!videoID || !cid) return nil;
    PNVideoTarget *target = [self new];
    target->_videoID = [videoID copy];
    target->_cid = [cid copy];
    return target;
}
- (NSURL *)URL {
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"pilinara";
    components.host = @"video";
    components.path = [@"/" stringByAppendingString:self.videoID];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"cid" value:self.cid]];
    return components.URL;
}
@end
