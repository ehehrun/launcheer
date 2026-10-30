#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface NativeBackdrop : CALayer
@property(nonatomic, readonly) BOOL hasImage;
+ (NSURL * _Nullable)desktopImageURLForScreen:(NSScreen *)screen error:(NSError * _Nullable * _Nullable)error;
- (BOOL)updateForScreen:(NSScreen *)screen error:(NSError * _Nullable * _Nullable)error;
// Completion runs on the main thread; superseded/cancelled requests return NSUserCancelledError.
- (void)updateForScreen:(NSScreen *)screen completion:(void (^)(BOOL success, NSError * _Nullable error))completion;
- (void)cancelPendingUpdate;
- (BOOL)cacheAuthorizedImageAtURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
- (void)useBackgroundColorForScreen:(NSScreen *)screen;
- (void)updateMenuBarCoverLayer:(CALayer *)layer;
@end

NS_ASSUME_NONNULL_END
