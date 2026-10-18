#import <Foundation/Foundation.h>
#import "PNVideoTarget.h"

@interface PNMockItem : NSObject
@property(nonatomic) long long oid;
@property(nonatomic) long long cid;
@property(nonatomic) BOOL isGetFocus;
@end
@implementation PNMockItem
@end

@interface PNThrowingItem : NSObject
@end
@implementation PNThrowingItem
- (id)oid { [NSException raise:@"Unavailable" format:@"simulate changed private API"]; return nil; }
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void CheckDownloadURL(PNVideoTarget *target, NSString *videoID, NSString *cid) {
    NSString *pureURL = target.URL.absoluteString;
    NSURL *downloadURL = target.downloadURL;
    NSURLComponents *components = [NSURLComponents componentsWithURL:downloadURL resolvingAgainstBaseURL:NO];
    Check([components.scheme isEqual:@"pilinara"], @"download uses the PiliNara scheme");
    Check([components.host isEqual:@"video"], @"download targets the video route");
    Check([components.path isEqual:[@"/" stringByAppendingString:videoID]], @"download retains the exact source video ID path");
    Check(components.fragment == nil && components.user == nil && components.password == nil && components.port == nil,
        @"download does not add unrelated URL components");
    NSDictionary<NSString *, NSString *> *expected = @{
        @"cid": cid, @"action": @"download", @"quality": @"32", @"share": @"1",
    };
    Check(components.queryItems.count == expected.count, @"download contains exactly four query items");
    for (NSString *name in expected) {
        NSUInteger count = 0;
        for (NSURLQueryItem *item in components.queryItems) {
            if (![item.name isEqual:name]) continue;
            count++;
            Check([item.value isEqual:expected[name]], @"download query preserves its exact semantic value");
        }
        Check(count == 1, @"download contains exactly one value for each requested query key");
    }
    Check([target.downloadURL.absoluteString isEqual:downloadURL.absoluteString], @"repeated download URL reads do not append duplicate actions");
    Check([target.URL.absoluteString isEqual:pureURL], @"reading download URL leaves the existing jump URL unchanged");
    NSURLComponents *pureComponents = [NSURLComponents componentsWithURL:target.URL resolvingAgainstBaseURL:NO];
    Check(pureComponents.queryItems.count == 1 && [pureComponents.queryItems.firstObject.name isEqual:@"cid"] &&
        [pureComponents.queryItems.firstObject.value isEqual:cid], @"pure jump URL still contains only its source CID");
}

int main(void) {
    @autoreleasepool {
        PNMockItem *item = [PNMockItem new];
        item.oid = 170001;
        item.cid = 9223372036854770000LL;
        item.isGetFocus = YES;
        PNVideoTarget *target = [PNVideoTarget targetWithPlayerItem:item];
        Check([target.URL.absoluteString isEqual:@"pilinara://video/170001?cid=9223372036854770000"], @"typed int64 getters preserve IDs without float truncation");
        CheckDownloadURL(target, @"170001", @"9223372036854770000");
        Check([PNReadValue(item, @"isGetFocus") boolValue], @"BOOL focus getter is boxed");
        item.cid = 279786;
        Check([[PNVideoTarget targetWithPlayerItem:item].URL.absoluteString isEqual:@"pilinara://video/170001?cid=279786"], @"current P is re-read after switching P");
        CheckDownloadURL([PNVideoTarget targetWithPlayerItem:item], @"170001", @"279786");
        Check([target.cid isEqual:@"9223372036854770000"], @"existing metadata remains an immutable snapshot when the player changes P");
        item.oid = 455017605;
        Check([[PNVideoTarget targetWithPlayerItem:item].videoID isEqual:@"455017605"], @"video replacement does not reuse old AV");
        CheckDownloadURL([PNVideoTarget targetWithPlayerItem:item], @"455017605", @"279786");
        target = [PNVideoTarget targetWithPlayerItem:@{@"bvid": @"BV1xx411c7mD", @"cid": @279786}];
        Check([target.URL.absoluteString isEqual:@"pilinara://video/BV1xx411c7mD?cid=279786"], @"BV fallback is accepted");
        CheckDownloadURL(target, @"BV1xx411c7mD", @"279786");
        target = [PNVideoTarget targetWithPlayerItem:@{@"aid": @170001, @"cid": @279786}];
        Check([target.videoID isEqual:@"170001"], @"aid fallback works");
        CheckDownloadURL(target, @"170001", @"279786");
        target = [PNVideoTarget targetWithPlayerItem:@{@"oid": @"000170001", @"cid": @"000279786"}];
        Check([target.URL.absoluteString isEqual:@"pilinara://video/170001?cid=279786"], @"numeric string getters normalize without an av prefix");
        CheckDownloadURL(target, @"170001", @"279786");
        target = [PNVideoTarget targetWithPlayerItem:@{@"oid": @9007199254740993LL, @"cid": @9223372036854770000LL}];
        CheckDownloadURL(target, @"9007199254740993", @"9223372036854770000");
        NSArray *badItems = @[
            @{}, @{@"oid": @170001}, @{@"cid": @279786},
            @{@"oid": @170001, @"cid": @0},
            @{@"oid": @0, @"cid": @279786},
            @{@"oid": @(-1), @"cid": @279786},
            @{@"oid": @170001, @"cid": @(-1)},
            @{@"oid": @"170001&x=1", @"cid": @279786},
            @{@"oid": @"av170001", @"cid": @279786},
            @{@"oid": @170001, @"cid": @"2.5"},
            @{@"oid": @"9223372036854775808", @"cid": @279786},
            @{@"oid": NSNull.null, @"cid": @279786},
            @{@"oid": @170001, @"cid": NSNull.null},
            @{@"bvid": @"BV1xx411c7mD?bad", @"cid": @279786},
            @{@"bvid": @"BV1xx411c7m中", @"cid": @279786},
            NSNull.null, [PNThrowingItem new],
        ];
        for (id invalid in badItems) Check([PNVideoTarget targetWithPlayerItem:invalid] == nil, @"invalid/incomplete data must not open a wrong video");
        Check([PNVideoTarget targetWithPlayerItem:nil] == nil, @"nil player safely fails");
        Check(PNReadValue(item, @"missingPrivateGetter") == nil, @"changed API safely fails");
        Check(PNReadValue(item, @"setOid:") == nil, @"never invokes getters requiring arguments");
        NSLog(@"PASS: %lu video target checks", (unsigned long)checks);
    }
    return 0;
}
