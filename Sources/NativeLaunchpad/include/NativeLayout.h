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

@interface NativeSavedPreset : NSObject
@property(nonatomic, copy, readonly) NSString *id;
@property(nonatomic, copy, readonly) NSString *title;
- (instancetype)initWithID:(NSString *)id title:(NSString *)title;
@end

@interface NativeLayout : NSObject <NSCopying>
@property(nonatomic, strong, readonly) NSMutableArray<NativePage *> *pages;
@property(nonatomic, strong, readonly, nullable) NSURL *destination;
@property(nonatomic, copy, nullable) NSString *title;
+ (NSURL *)fileURL;
+ (BOOL)isSavedPreset:(NSString *)preset;
- (nullable instancetype)initWithApps:(NSArray<NSURL *> *)apps
                             fileURL:(nullable NSURL *)fileURL
                               error:(NSError * _Nullable * _Nullable)error;
- (nullable NativePage *)pageContainingItem:(id)item;
- (BOOL)flattenGroup:(NativeGroup *)group;
- (NativeLayout *)copyToURL:(NSURL *)destination NS_SWIFT_NAME(copy(to:));
- (BOOL)save:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
