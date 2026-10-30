#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NativePage : NSObject
@property(nonatomic, strong, readonly) NSMutableArray *items;
- (instancetype)initWithItems:(NSArray *)items;
@end

@interface NativeGroup : NSObject
@property(nonatomic, copy, readonly) NSString *id;
@property(nonatomic, copy, nullable) NSString *title;
@property(nonatomic, strong, readonly) NSMutableArray<NativePage *> *items;
- (instancetype)initWithID:(NSString *)id title:(nullable NSString *)title pages:(NSArray<NativePage *> *)pages;
@end

@interface NativeLayout : NSObject
@property(nonatomic, strong, readonly) NSMutableArray<NativePage *> *pages;
+ (NSURL *)fileURL;
- (nullable instancetype)initWithApps:(NSArray<NSURL *> *)apps
                             fileURL:(nullable NSURL *)fileURL
                               error:(NSError * _Nullable * _Nullable)error;
- (nullable NativePage *)pageContainingItem:(id)item;
- (BOOL)save:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
