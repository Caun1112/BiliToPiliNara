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

int main(void) {
    @autoreleasepool {
        PNMockItem *item = [PNMockItem new];
        item.oid = 170001;
        item.cid = 9223372036854770000LL;
        item.isGetFocus = YES;
        PNVideoTarget *target = [PNVideoTarget targetWithPlayerItem:item];
        Check([target.URL.absoluteString isEqual:@"pilinara://video/170001?cid=9223372036854770000"], @"typed int64 getters preserve IDs without float truncation");
        Check([PNReadValue(item, @"isGetFocus") boolValue], @"BOOL focus getter is boxed");
        item.cid = 279786;
        Check([[PNVideoTarget targetWithPlayerItem:item].URL.absoluteString isEqual:@"pilinara://video/170001?cid=279786"], @"current P is re-read after switching P");
        item.oid = 455017605;
        Check([[PNVideoTarget targetWithPlayerItem:item].videoID isEqual:@"455017605"], @"video replacement does not reuse old AV");
        target = [PNVideoTarget targetWithPlayerItem:@{@"bvid": @"BV1xx411c7mD", @"cid": @279786}];
        Check([target.URL.absoluteString isEqual:@"pilinara://video/BV1xx411c7mD?cid=279786"], @"BV fallback is accepted");
        target = [PNVideoTarget targetWithPlayerItem:@{@"aid": @170001, @"cid": @279786}];
        Check([target.videoID isEqual:@"170001"], @"aid fallback works");
        target = [PNVideoTarget targetWithPlayerItem:@{@"oid": @"000170001", @"cid": @"000279786"}];
        Check([target.URL.absoluteString isEqual:@"pilinara://video/170001?cid=279786"], @"numeric string getters normalize without an av prefix");
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
