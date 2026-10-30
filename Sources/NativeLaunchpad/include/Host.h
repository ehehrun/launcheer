#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
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
- (void)refreshBackground;
- (void)applyAnimationSettings;
- (NSImage *)iconForItem:(NSURL *)item;
- (void)handleControllerKey:(unsigned short)keyCode pressed:(BOOL)pressed repeated:(BOOL)repeated;
@end
NS_ASSUME_NONNULL_END
