#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NativeLayout, NativeSavedPreset;
NS_SWIFT_UI_ACTOR
@interface NativeHost : NSObject <NSApplicationDelegate, NSMenuItemValidation>
@property(nonatomic, strong) NSArray<NSURL *> *items;
@property(nonatomic) BOOL verifying;
@property(nonatomic) BOOL automatedVerification;
@property(nonatomic) BOOL showOnlyOnMainScreen;
@property(nonatomic, copy, nullable) void (^iconDidLoad)(NSURL *item);
@property(nonatomic, readonly) NSWindow *window;
@property(nonatomic, readonly) BOOL wantsLauncherVisible;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (void)showLauncher;
- (void)hideLauncher;
- (void)hideLauncherImmediately;
- (void)toggleLauncher;
- (void)reloadItems:(NSArray<NSURL *> *)items;
- (BOOL)canMoveItemToTrash:(NSURL *)item;
- (void)authorizeDesktopImage:(id)sender;
- (void)showSettings:(id)sender;
- (void)autoArrange:(id)sender;
- (BOOL)arrangeItems:(BOOL (^)(NativeLayout *layout))changes
          forPreset:(NSString *)preset
              error:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<NativeSavedPreset *> *)savedPresets:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)saveCurrentLayoutAs:(NSString *)title
                                    error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(saveCurrentLayoutAs(_:));
- (void)refreshBackground;
- (void)applyAnimationSettings;
- (NSImage *)iconForItem:(NSURL *)item;
- (void)handleControllerKey:(unsigned short)keyCode pressed:(BOOL)pressed repeated:(BOOL)repeated;
@end
NS_ASSUME_NONNULL_END
