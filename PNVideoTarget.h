#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads only a named, zero-argument getter, boxing scalar return values safely.
FOUNDATION_EXPORT id _Nullable PNReadValue(id _Nullable object, NSString *key);

@interface PNVideoTarget : NSObject
@property(nonatomic, copy, readonly) NSString *videoID;
@property(nonatomic, copy, readonly) NSString *cid;
@property(nonatomic, readonly) NSURL *URL;
@property(nonatomic, readonly) NSURL *downloadURL;
+ (nullable instancetype)targetWithPlayerItem:(id _Nullable)item;
@end

NS_ASSUME_NONNULL_END
