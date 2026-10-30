#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <os/log.h>
#import "NativeDock.h"
#import "Host.h"
#import "NativeBackdrop.h"
#import "NativeLayout.h"

static NSString *const HideAnimationKey = @"launcheer.hide";
static NSString *const ShowAnimationKey = @"launcheer.show";
static NSString *const DissolveAnimationKey = @"launcheer.dissolve";
static NSString *const DissolveFilterName = @"launcheerDissolve";
static NSString *const DissolveRadiusKeyPath = @"filters.launcheerDissolve.inputRadius";

@interface NSObject (NativeVisibilityFilter)
+ (id)filterWithType:(NSString *)type;
@end

static void AnimateVisibility(CALayer *layer, BOOL visible, NSTimeInterval duration) {
    CABasicAnimation *active = (CABasicAnimation *)([layer animationForKey:ShowAnimationKey] ?: [layer animationForKey:HideAnimationKey]);
    CALayer *current = active ? layer.presentationLayer : nil;
    CABasicAnimation *change = [CABasicAnimation animationWithKeyPath:@"opacity"];
    change.fromValue = current ? @(current.opacity) : (active ? active.fromValue : @(visible ? 0 : layer.opacity));
    change.toValue = visible ? @(layer.opacity) : @0;
    change.duration = duration;
    change.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    change.fillMode = kCAFillModeBoth;
    change.removedOnCompletion = visible;
    NSString *key = visible ? ShowAnimationKey : HideAnimationKey;
    [layer addAnimation:change forKey:key];
    [layer removeAnimationForKey:visible ? HideAnimationKey : ShowAnimationKey];
}

static void RemoveVisibilityAnimations(CALayer *layer) {
    [layer removeAnimationForKey:HideAnimationKey];
    [layer removeAnimationForKey:ShowAnimationKey];
}

static void Verify(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void StopLayerAnimations(CALayer *layer) {
    [layer removeAllAnimations];
    for (CALayer *child in layer.sublayers) { StopLayerAnimations(child); }
}

static id PlaceholderIcon(void) {
    static id image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = CGBitmapContextCreate(NULL, 256, 256, 8, 0, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        Verify(context != NULL, @"Cannot create the icon placeholder");
        CGPathRef outline = CGPathCreateWithRoundedRect(CGRectMake(18, 18, 220, 220), 46, 46, NULL);
        CGContextSetRGBFillColor(context, 1, 1, 1, 0.06);
        CGContextAddPath(context, outline);
        CGContextFillPath(context);
        const CGFloat dash[] = {14, 10};
        CGContextSetLineDash(context, 0, dash, 2);
        CGContextSetLineWidth(context, 4);
        CGContextSetRGBStrokeColor(context, 1, 1, 1, 0.6);
        CGContextAddPath(context, outline);
        CGContextStrokePath(context);
        image = CFBridgingRelease(CGBitmapContextCreateImage(context));
        CGPathRelease(outline);
        CGContextRelease(context);
        CGColorSpaceRelease(color);
    });
    return image;
}

@interface NativeTextCell : NSTextFieldCell
@end
@implementation NativeTextCell
- (NSText *)setUpFieldEditorAttributes:(NSText *)editor {
    editor = [super setUpFieldEditorAttributes:editor];
    if (editor.isFieldEditor) { [(NSTextView *)editor setInsertionPointColor:NSColor.whiteColor]; }
    return editor;
}
@end
// These signatures were read from this machine's Dock Objective-C metadata.
@interface NSObject (NativeLaunchpadAPI)
- (id)initWithHandler:(id)handler numberOfRowsPerPage:(NSUInteger)rows numberOfColumnsPerPage:(NSUInteger)columns scaleFactor:(float)scale layoutRTL:(BOOL)rtl;
- (id)initWithEvent:(id)event hitLayer:(CALayer *)layer hitWindow:(id)window session:(id)session;
- (CALayer *)layer;
- (CALayer *)searchTextInputLayer;
- (CALayer *)scrollLayer;
- (id)eventDelegate;
- (id)eventHandler;
+ (id)sharedController;
- (void)addHandler:(id)handler externalEventSource:(BOOL)external usingMouseHysteresis:(BOOL)hysteresis;
- (void)removeHandler:(id)handler;
- (void)performMouseUpBlocksWithEvent:(id)event;
- (id)itemForClientItem:(id)item;
- (id)initWithItems:(NSArray *)items;
- (NSArray *)items;
- (NSObject *)currentPage;
- (NSUInteger)numberOfGridItems;
- (id)itemLayer;
- (id)item;
- (id)clientItem;
- (CALayer *)imageLayer;
- (CALayer *)progressLayer;
- (CALayer *)progressLabelLayer;
- (BOOL)filtering;
- (BOOL)dragging;
- (id)dragCapture;
- (id)shownGroup;
- (id)groupPager;
- (BOOL)groupShown;
- (void)setGroupShown:(BOOL)shown;
- (void)setDeleting:(BOOL)deleting;
- (BOOL)deleting;
- (void)cancelDrag:(BOOL)animate;
- (void)setEditing:(BOOL)editing;
- (NSString *)stringValue;
- (void (^)(BOOL))visibleBlock;
- (id)font;
- (CGColorRef)foregroundColor;
- (void)setStringValue:(NSString *)value;
- (void)_updateStringValue:(NSString *)value width:(double)width complete:(BOOL)complete;
- (void)setHasFocus:(BOOL)focus;
- (BOOL)hasFocus;
- (void)setZoomFactor:(double)zoom;
- (float)scaleFactor;
- (void)setScaleFactor:(float)scale;
- (void)setWantsNotificationForMarkedText:(BOOL)wanted;
- (BOOL)gesture:(id)event;
- (BOOL)navigate:(NSInteger)direction withEvent:(id)event;
- (BOOL)leftMouseDown:(id)event;
- (BOOL)leftMouseDragged:(id)event;
- (BOOL)leftMouseUp:(id)event;
- (id)pager;
- (NSArray *)pages;
- (void)setVisible:(BOOL)visible;
- (void)setAllowDragging:(BOOL)allowed;
- (void)setAllowDeleting:(BOOL)allowed;
- (void)setSupportsGroups:(BOOL)supported;
- (void)setCurrentPageIndex:(NSUInteger)index;
- (NSUInteger)currentPageIndex;
- (void)filterUsingItems:(NSArray *)items;
- (void)clearFilteredItems;
- (BOOL)leftMouseDown:(id)event in:(CALayer *)layer;
- (BOOL)leftMouseDragged:(id)event in:(CALayer *)layer;
- (BOOL)leftMouseUp:(id)event in:(CALayer *)layer;
- (BOOL)scrollWheel:(id)event;
- (void)layout;
- (void)invalidate;
- (void)setLeftMargin:(double)value;
- (void)setRightMargin:(double)value;
- (void)setTopMargin:(double)value;
- (void)setBottomMargin:(double)value;
- (void)setValue:(id)value forKey:(NSString *)key ofItem:(id)item;
@end

// Search and folder titles use local AppKit editors instead of Dock XPC mini-views.
@interface NativeHost (LocalTextInput)
- (void)syncGroupEditor;
@end
static __weak NativeHost *localTextInputHost;
static void UseLocalTextInput(id layer, SEL command) {}
static void ActivateLocalTextInput(id layer, SEL command) { [localTextInputHost syncGroupEditor]; }
static void HostNativeTextInput(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"ECTextInputLayer");
        method_setImplementation(class_getInstanceMethod(cls, sel_registerName("_setupConnection")), (IMP)ActivateLocalTextInput);
        method_setImplementation(class_getInstanceMethod(cls, sel_registerName("_sendStringValueMessage")), (IMP)UseLocalTextInput);
    });
}
static NSTextField *LocalTextField(CALayer *layer, id<NSTextFieldDelegate> delegate, NSTextAlignment alignment) {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.cell = [[NativeTextCell alloc] initTextCell:@""];
    field.cell.wraps = NO;
    field.cell.usesSingleLineMode = YES;
    field.cell.backgroundStyle = (NSBackgroundStyle)3;
    [field.cell setWantsNotificationForMarkedText:YES];
    field.editable = YES;
    field.selectable = YES;
    field.bordered = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = (NSFont *)[layer font];
    field.textColor = [NSColor colorWithCGColor:[layer foregroundColor]];
    field.alignment = alignment;
    field.delegate = delegate;
    return field;
}

static NSEvent *NavigationKeyEvent(unsigned short keyCode, BOOL pressed, BOOL repeated) {
    UniChar character;
    switch (keyCode) {
        case 123: character = NSLeftArrowFunctionKey; break;
        case 124: character = NSRightArrowFunctionKey; break;
        case 125: character = NSDownArrowFunctionKey; break;
        case 126: character = NSUpArrowFunctionKey; break;
        case 36: character = 13; break;
        case 76: character = 3; break;
        case 53: character = 27; break;
        default: return nil;
    }
    CGEventRef key = CGEventCreateKeyboardEvent(NULL, keyCode, pressed);
    CGEventSetFlags(key, 0);
    CGEventKeyboardSetUnicodeString(key, 1, &character);
    // ECEvent reads its character from this Dock event field, including for Return.
    CGEventSetIntegerValueField(key, (CGEventField)78, character);
    CGEventSetIntegerValueField(key, kCGKeyboardEventAutorepeat, repeated);
    NSEvent *event = [NSEvent eventWithCGEvent:key];
    CFRelease(key);
    return event;
}

@interface NativeWindow : NSWindow
@end
@implementation NativeWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
- (CALayer *)layer { return self.contentView.layer; }
- (CGPoint)convertPointFromGlobal:(CGPoint)point {
    point.y = NSMaxY(NSScreen.screens.firstObject.frame) - point.y;
    return [self convertPointFromScreen:point];
}
- (CGPoint)convertPointToGlobal:(CGPoint)point {
    point = [self convertPointToScreen:point];
    point.y = NSMaxY(NSScreen.screens.firstObject.frame) - point.y;
    return point;
}
- (CGRect)convertRectToGlobal:(CGRect)rect {
    rect = [self convertRectToScreen:rect];
    rect.origin.y = NSMaxY(NSScreen.screens.firstObject.frame) - CGRectGetMaxY(rect);
    return rect;
}
@end

@protocol NativeKeyInput
- (BOOL)keyDown:(id)event;
- (BOOL)keyUp:(id)event;
@end

@interface NativeMenuBarView : NSView
@property(nonatomic, weak) NativeHost *host;
@end
@implementation NativeMenuBarView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
// Consume the press so the covered system menus cannot receive the click.
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event { [self.host hideLauncher]; }
@end

@class NativeHost;
@interface NativeView : NSView
@property(nonatomic, weak) NativeHost *host;
@property(nonatomic, strong) NativeBackdrop *backdrop;
@property(nonatomic, strong) NSObject *springboard;
@property(nonatomic, strong) CALayer *downLayer;
@property(nonatomic, strong) CALayer *downHitLayer;
@property(nonatomic, strong) id downPage;
@property(nonatomic) BOOL downSearch;
@property(nonatomic) CGRect layoutBounds;
@property(nonatomic) CGRect screenFrame;
@property(nonatomic) CGRect visibleFrame;
@property(nonatomic) CGFloat safeAreaTop;
@property(nonatomic) float layoutScale;
@end

@interface NativeHost () <NSTextFieldDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSWindow *menuBarCoverWindow;
@property(nonatomic, strong) NSVisualEffectView *backgroundView;
@property(nonatomic, strong) NativeView *view;
@property(nonatomic, strong) NSTextField *search;
@property(nonatomic, strong) NSTextField *versionLabel;
@property(nonatomic, strong) NSTextField *groupTitle;
@property(nonatomic, strong) CALayer *groupTextInput;
@property(nonatomic, strong) NSObject *springboard;
@property(nonatomic, strong) NativeLayout *layout;
@property(nonatomic, strong) NSArray *pages;
@property(nonatomic, strong) NSArray *searchPages;
@property(nonatomic, strong) NSMutableDictionary<NSURL *, id> *icons;
@property(nonatomic, strong) NSOperationQueue *iconQueue;
@property(nonatomic) NSUInteger iconGeneration;
@property(nonatomic) NSUInteger iconPixelSize;
@property(nonatomic, strong) NSURL *lastAction;
@property(nonatomic, strong) NSURL *verificationItem;
@property(nonatomic, strong) NSObject *modalSession;
@property(nonatomic, strong) NSArray<NSURL *> *pendingItems;
@property(nonatomic) BOOL layoutDirty;
@property(nonatomic) BOOL layoutSaveScheduled;
@property(nonatomic) BOOL wantsLauncherVisible;
@property(nonatomic, copy) dispatch_block_t hideTask;
@property(nonatomic) NSUInteger hideGeneration;
@property(nonatomic, strong) id dockHiddenGroup;
@property(nonatomic) BOOL dockPresentationActive;
@property(nonatomic) NSApplicationPresentationOptions savedPresentationOptions;
- (void)syncGroupEditor;
- (void)finishGroupEditing;
- (void)cancelNavigation;
- (void)applyPendingItems;
- (void)scheduleLayoutSave;
- (BOOL)persistLayout;
- (BOOL)canMoveItemToTrash:(NSURL *)item;
- (NSMenu *)contextMenuForItem:(NSURL *)item;
- (void)performRemoveActionForItem:(NSURL *)item withEvent:(id)event sender:(id)sender;
- (void)restoreDockPresentation;
- (void)showLauncherOnScreen:(NSScreen *)screen;
- (void)prepareDesktopForScreen:(NSScreen *)screen;
- (void)updateBackgroundMaterial:(NSNotification *)notification;
- (void)updateMenuBarCoverForScreen:(NSScreen *)screen;
- (NSUInteger)iconPixelSizeForScale:(CGFloat)scale;
- (void)prepareIconsForItems:(NSArray<NSURL *> *)items pixelSize:(NSUInteger)pixels;
- (void)cancelIconLoading;
- (void)cancelPendingHide;
- (NSTimeInterval)animateLauncherVisible:(BOOL)visible;
- (void)removeVisibilityAnimations;
- (void)removeDissolveFilter;
@end

@implementation NativeView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)layout {
    [super layout];
    if (!self.window) { return; }
    CGSize size = self.bounds.size;
    CGRect screen = self.window.screen.frame;
    BOOL screenChanged = !CGRectEqualToRect(self.screenFrame, screen);
    if (screenChanged) { self.visibleFrame = self.window.screen.visibleFrame; }
    // Dock presentation changes during native group animations must not resize the grid.
    CGRect visible = self.visibleFrame;
    // The standalone host has no Dock display object to supply the native notch inset.
    CGFloat top = self.window.screen.safeAreaInsets.top;
    float scale = (float)self.window.backingScaleFactor;
    CGFloat left = MAX(0, CGRectGetMinX(visible) - CGRectGetMinX(screen));
    CGFloat right = MAX(0, CGRectGetMaxX(screen) - CGRectGetMaxX(visible));
    CGFloat bottom = MAX(0, CGRectGetMinY(visible) - CGRectGetMinY(screen));
    BOOL sideDock = left > 0 || right > 0;
    CGFloat dock = sideDock ? MAX(left, right) : bottom;
    CGFloat origin = sideDock ? 30 : dock + 30;
    CGFloat effectiveWidth = size.width - (sideDock ? dock : 0);
    CGFloat slot = floor(effectiveWidth / 15);
    CGFloat remaining = floor(size.height - origin - top - (slot + 40) * 5);
    CGFloat horizontal = MAX(90, floor(slot * 0.5));
    if (!CGRectEqualToRect(self.layoutBounds, self.bounds) || screenChanged || self.safeAreaTop != top || self.layoutScale != scale) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.backdrop.frame = self.bounds;
        self.springboard.layer.frame = CGRectMake(0, origin, size.width, size.height - origin - top);
        [self.springboard setLeftMargin:horizontal + left];
        [self.springboard setRightMargin:horizontal + right];
        [self.springboard setTopMargin:MAX(35, floor(remaining * 0.15))];
        [self.springboard setBottomMargin:MAX(35, floor(remaining * 0.25))];
        double zoom = size.width > 1920 ? 0.6 : size.width > 1680 ? 0.3 : size.width > 1440 ? 0.2 : 0;
        if (sideDock && zoom > 0.1) { zoom -= 0.1; }
        [self.springboard setZoomFactor:zoom];
        [self.springboard setScaleFactor:scale];
        [self.springboard layout];
        [CATransaction commit];
        self.layoutBounds = self.bounds;
        self.screenFrame = screen;
        self.safeAreaTop = top;
        self.layoutScale = scale;
    }
    CALayer *searchLayer = [self.springboard.layer searchTextInputLayer];
    [searchLayer layoutIfNeeded];
    CALayer *textLayer = object_getIvar(searchLayer, class_getInstanceVariable(searchLayer.class, "_hostLayer"));
    CGRect textFrame = [searchLayer convertRect:textLayer.frame toLayer:self.layer];
    textFrame.origin.y -= 3;
    self.host.search.frame = textFrame;
    CGRect searchFrame = [searchLayer convertRect:searchLayer.bounds toLayer:self.layer];
    self.host.versionLabel.frame = CGRectMake(CGRectGetMidX(searchFrame) - 180, CGRectGetMinY(searchFrame) - 44, 360, 28);
    if (self.host.groupTextInput) {
        CALayer *input = self.host.groupTextInput;
        CALayer *host = object_getIvar(input, class_getInstanceVariable(input.class, "_hostLayer"));
        CGRect frame = [input convertRect:host.frame toLayer:self.layer];
        frame.origin.y -= 2;
        self.host.groupTitle.frame = frame;
    }
}
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        if (![(id<NativeKeyInput>)self.springboard keyDown:[self nativeEvent:event hitLayer:self.springboard.layer]]) {
            [self.host cancelNavigation];
        }
        [CATransaction flush];
        return;
    }
    if (event.keyCode >= 123 && event.keyCode <= 126) {
        id native = [self nativeEvent:event hitLayer:self.springboard.layer];
        if (![(id<NativeKeyInput>)self.springboard keyDown:native]) {
            static const NSInteger directions[] = {2, 3, 1, 0};
            NSInteger direction = directions[event.keyCode - 123];
            // Keep folder navigation local; only an exhausted root Right turns the page.
            if ([self.springboard groupShown]) {
                if (![self.springboard dragging] && ![[self.springboard.layer searchTextInputLayer] hasFocus] && !self.host.groupTextInput) {
                    NSObject *pager = [self activePager];
                    [[pager currentPage] navigate:direction withEvent:native];
                }
            } else if (![self.springboard navigate:direction withEvent:native] && direction == 3) {
                [self.springboard navigate:4 withEvent:native];
            }
        }
        [CATransaction flush];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        [(id<NativeKeyInput>)self.springboard keyDown:[self nativeEvent:event hitLayer:self.springboard.layer]];
        [CATransaction flush];
        return;
    }
    if (!(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) && event.characters.length) {
        [self.window makeFirstResponder:self.host.search];
        [self.host.search.currentEditor interpretKeyEvents:@[event]];
        return;
    }
    [super keyDown:event];
}
- (void)keyUp:(NSEvent *)event {
    [(id<NativeKeyInput>)self.springboard keyUp:[self nativeEvent:event hitLayer:self.springboard.layer]];
    [CATransaction flush];
}
- (id)nativeEvent:(NSEvent *)event hitLayer:(CALayer *)hitLayer {
    return [[NSClassFromString(@"ECEvent") alloc] initWithEvent:(__bridge id)event.CGEvent hitLayer:hitLayer hitWindow:self.window session:self.host.modalSession];
}
- (id)activePager {
    id group = [[self.springboard pager] shownGroup];
    return group ? [group groupPager] : [self.springboard pager];
}
- (void)scrollGesture:(NSEvent *)event phase:(int64_t)phase {
    CALayer *layer = [[self activePager] layer];
    CGEventRef gesture = CGEventCreateCopy(event.CGEvent);
    CGEventSetType(gesture, (CGEventType)29);
    // Dock receives separate raw scroll-gesture boundaries; AppKit embeds them in scroll phases.
    CGEventSetIntegerValueField(gesture, (CGEventField)110, 6);
    CGEventSetIntegerValueField(gesture, (CGEventField)132, phase);
    id native = [[NSClassFromString(@"ECEvent") alloc] initWithEvent:(__bridge id)gesture hitLayer:layer hitWindow:self.window session:self.host.modalSession];
    [layer gesture:native];
    CFRelease(gesture);
}
- (void)scrollWheel:(NSEvent *)event {
    id pager = [self activePager];
    CALayer *layer = [pager layer];
    if (event.phase & NSEventPhaseBegan) {
        CALayer *scroll = [layer scrollLayer];
        if ([scroll animationForKey:@"bounds"]) {
            CALayer *presentation = scroll.presentationLayer;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            if (presentation) { scroll.bounds = presentation.bounds; }
            [scroll removeAnimationForKey:@"bounds"];
            [CATransaction commit];
        }
        [self scrollGesture:event phase:1];
    }
    [layer scrollWheel:[self nativeEvent:event hitLayer:layer]];
    if (event.phase & NSEventPhaseEnded) { [self scrollGesture:event phase:4]; }
    if (event.phase & NSEventPhaseCancelled) {
        NSUInteger page = [pager currentPageIndex];
        // Native gesture handling has no cancelled phase; end tracking, then restore its page.
        [self scrollGesture:event phase:4];
        [pager setCurrentPageIndex:page];
    }
    // The Dock event controller normally commits these direct layer updates after every event.
    [CATransaction flush];
}
- (void)mouseDown:(NSEvent *)event {
    [self routeMouse:event down:YES];
}
- (void)mouseUp:(NSEvent *)event { [self routeMouse:event down:NO]; }
- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.downLayer || [self.springboard dragging]) { return nil; }
    CALayer *pagerLayer = [[self activePager] layer];
    CGPoint point = [pagerLayer.superlayer convertPoint:[self convertPoint:event.locationInWindow fromView:nil] fromLayer:self.layer];
    // A shown folder leaves root icons behind it; only its active pager owns this menu.
    for (CALayer *layer = [pagerLayer hitTest:point]; layer && layer != pagerLayer.superlayer; layer = layer.superlayer) {
        if (![layer respondsToSelector:@selector(item)]) { continue; }
        id item = [[layer item] clientItem];
        if (![item isKindOfClass:NSURL.class]) { return nil; }
        [self.host finishGroupEditing];
        return [self.host contextMenuForItem:item];
    }
    return nil;
}
- (void)mouseDragged:(NSEvent *)event {
    if (self.downSearch) { return; }
    id native = [self nativeEvent:event hitLayer:self.downHitLayer];
    if (self.downPage) {
        if ([self.downPage respondsToSelector:@selector(leftMouseDragged:in:)]) { [self.downPage leftMouseDragged:native in:self.downLayer]; }
    } else { [self.downLayer leftMouseDragged:native]; }
    [self.host syncGroupEditor];
    [CATransaction flush];
}
- (void)routeMouse:(NSEvent *)event down:(BOOL)down {
    if (down) { [self.host finishGroupEditing]; }
    CGPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CALayer *hit = [self.layer hitTest:point];
    CALayer *nativeSearch = [self.springboard.layer searchTextInputLayer];
    CALayer *searchHit = hit;
    while (searchHit && searchHit != nativeSearch) { searchHit = searchHit.superlayer; }
    if ((down && searchHit) || (!down && self.downSearch)) {
        CALayer *clearLayer = object_getIvar(nativeSearch, class_getInstanceVariable(nativeSearch.class, "_cancelSearchLayer"));
        if (down && hit != clearLayer) { [self.window makeFirstResponder:self.host.search]; return; }
        id native = [self nativeEvent:event hitLayer:hit];
        if (down) { self.downSearch = YES; [nativeSearch leftMouseDown:native]; }
        else {
            [nativeSearch leftMouseUp:native];
            [self.host.modalSession performMouseUpBlocksWithEvent:native];
            self.downSearch = NO;
        }
        return;
    }
    if (down) { [self.window makeFirstResponder:self]; }
    id native = [self nativeEvent:event hitLayer:hit];
    if (down) {
        self.downHitLayer = hit;
        self.downPage = nil;
        self.downLayer = nil;
        for (CALayer *target = hit; target && target != self.layer; target = target.superlayer) {
            id receiver = [target eventDelegate];
            if ([receiver respondsToSelector:@selector(leftMouseDown:in:)] && [receiver leftMouseDown:native in:target]) {
                self.downPage = receiver;
                self.downLayer = target;
                break;
            }
            if ([target respondsToSelector:@selector(leftMouseDown:)] && [target leftMouseDown:native]) {
                self.downLayer = target;
                break;
            }
        }
        // Wallpaper and outside-grid margins still belong to the springboard's background handler.
        if (!self.downLayer) {
            self.downLayer = self.springboard.layer;
            [self.downLayer leftMouseDown:native];
        }
    } else {
        if (self.downPage) { [self.downPage leftMouseUp:native in:self.downLayer]; }
        else { [self.downLayer leftMouseUp:native]; }
        [self.host.modalSession performMouseUpBlocksWithEvent:native];
        self.downPage = nil;
        self.downLayer = nil;
        self.downHitLayer = nil;
        [self.host applyPendingItems];
    }
    [self.host syncGroupEditor];
    [CATransaction flush];
}
@end

@implementation NativeHost
- (instancetype)init {
    if ((self = [super init])) {
        _icons = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    @try {
        CFTimeInterval started = CACurrentMediaTime();
        NSError *nativeError = nil;
        if (!NativeInitializeDock(&nativeError)) {
            @throw [NSException exceptionWithName:@"NativeCompatibilityError" reason:nativeError.localizedDescription userInfo:@{NSUnderlyingErrorKey: nativeError}];
        }
        HostNativeTextInput();
        NSLog(@"Native initialization: %.1f ms", (CACurrentMediaTime() - started) * 1000);
        [self start];
    } @catch (NSException *exception) {
        NSLog(@"Native host failed: %@\n%@", exception, exception.callStackSymbols);
        if (!self.automatedVerification) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Launcheer 无法启动";
            alert.informativeText = exception.reason;
            [alert runModal];
        }
        exit(1);
    }
}
- (void)start {
    CFTimeInterval started = CACurrentMediaTime();
    localTextInputHost = self;
    // Native clientItem is weak; retain concrete NSURL objects from Swift's deferred array bridge.
    NSMutableArray<NSURL *> *items = [NSMutableArray arrayWithCapacity:self.items.count];
    for (NSURL *url in self.items) { [items addObject:url]; }
    self.items = items;
    NSError *layoutError = nil;
    self.layout = [[NativeLayout alloc] initWithApps:items fileURL:self.verifying ? nil : NativeLayout.fileURL error:&layoutError];
    if (!self.layout) { @throw [NSException exceptionWithName:@"NativeLayoutLoadError" reason:layoutError.localizedDescription userInfo:@{NSUnderlyingErrorKey:layoutError}]; }
    self.pages = self.layout.pages;
    CFTimeInterval layoutReady = CACurrentMediaTime();
    CFTimeInterval iconsReady = CACurrentMediaTime();
    self.springboard = [[NSClassFromString(@"ECSBSpringboard") alloc] initWithHandler:self numberOfRowsPerPage:5 numberOfColumnsPerPage:7 scaleFactor:(float)NSScreen.mainScreen.backingScaleFactor layoutRTL:NO];
    [self.springboard setSupportsGroups:YES];
    [[self.springboard eventHandler] setAllowDragging:YES];
    [[self.springboard eventHandler] setAllowDeleting:YES];
    [self.springboard invalidate];
    CFTimeInterval nativeReady = CACurrentMediaTime();
    NSObject *controller = [NSClassFromString(@"ECModalEventController") sharedController];
    [controller addHandler:self externalEventSource:YES usingMouseHysteresis:NO];
    Ivar sessions = class_getInstanceVariable(controller.class, "_eventHandlers");
    self.modalSession = [object_getIvar(controller, sessions) lastObject];
    self.view = [[NativeView alloc] initWithFrame:NSMakeRect(0, 0, NSScreen.mainScreen.frame.size.width, NSScreen.mainScreen.frame.size.height)];
    self.view.host = self;
    self.view.springboard = self.springboard;
    self.view.wantsLayer = YES;
    NativeBackdrop *backdrop = [NativeBackdrop layer];
    // Only the backdrop participates in background opacity; native icons stay in their own layer.
    backdrop.opacity = 0.08f;
    self.view.backdrop = backdrop;
    [self.view.layer addSublayer:backdrop];
    [self.view.layer addSublayer:[self.springboard layer]];
    self.search = LocalTextField([self.springboard.layer searchTextInputLayer], self, NSTextAlignmentNatural);
    [self.view addSubview:self.search];
    self.versionLabel = [NSTextField labelWithString:@""];
    self.versionLabel.font = [NSFont systemFontOfSize:18 weight:NSFontWeightMedium];
    self.versionLabel.textColor = NSColor.whiteColor;
    self.versionLabel.alignment = NSTextAlignmentCenter;
    self.versionLabel.hidden = YES;
    [self.view addSubview:self.versionLabel];
    self.window = [[NativeWindow alloc] initWithContentRect:NSScreen.mainScreen.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed = NO;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.animationBehavior = NSWindowAnimationBehaviorNone;
    self.window.title = @"Launcheer";
    NSView *content = [[NSView alloc] initWithFrame:self.view.frame];
    content.wantsLayer = YES;
    content.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:self.view.frame];
    effect.wantsLayer = YES;
    effect.material = NSVisualEffectMaterialHUDWindow;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.backgroundView = effect;
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    // Keep native icon layers outside the translucent material's view hierarchy.
    [content addSubview:effect];
    [content addSubview:self.view];
    self.window.contentView = content;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.window.level = NSNormalWindowLevel + 1;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshDesktop:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(refreshDesktop:) name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(updateBackgroundMaterial:) name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
    [self showLauncher];
    NSLog(@"Native engine: %s; %lu apps; host PID=%d; layout %.1f ms, native %.1f ms, window %.1f ms; icons loading progressively", class_getImageName([self.springboard class]), (unsigned long)items.count, getpid(), (layoutReady - started) * 1000, (nativeReady - iconsReady) * 1000, (CACurrentMediaTime() - nativeReady) * 1000);
    if (self.automatedVerification) { [self performSelector:@selector(verifyFirstPage) withObject:nil afterDelay:0.6]; }
}
- (void)applicationDidResignActive:(NSNotification *)notification {
    if (!self.automatedVerification) { [self hideLauncherImmediately]; }
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    [self toggleLauncher];
    return NO;
}
- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *settings = [menu addItemWithTitle:@"设置…" action:@selector(showSettings:) keyEquivalent:@""];
    settings.target = self;
    NSMenuItem *wallpaper = [[NSMenuItem alloc] initWithTitle:@"允许读取当前壁纸…" action:@selector(authorizeDesktopImage:) keyEquivalent:@""];
    wallpaper.target = self;
    [menu addItem:wallpaper];
    return menu;
}
- (void)showSettings:(id)sender {
    if (self.verifying) { return; }
    [NSApp sendAction:NSSelectorFromString(@"openSettings:") to:NSApp.delegate from:sender];
}
- (void)refreshBackground {
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    [self prepareDesktopForScreen:screen];
}
- (void)applyAnimationSettings {
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"animations.disabled"]) { return; }
    if (self.hideTask) { [self hideLauncherImmediately]; }
    else { [self removeVisibilityAnimations]; [CATransaction flush]; }
}
- (NSImage *)iconForItem:(NSURL *)item {
    CGImageRef image = (__bridge CGImageRef)(self.icons[item] ?: PlaceholderIcon());
    return [[NSImage alloc] initWithCGImage:image size:NSMakeSize(32, 32)];
}
- (void)toggleLauncher {
    if (self.wantsLauncherVisible) { [self hideLauncher]; }
    else { [self showLauncher]; }
}
- (void)handleControllerKey:(unsigned short)keyCode pressed:(BOOL)pressed repeated:(BOOL)repeated {
    if (pressed && (!self.wantsLauncherVisible || !NSApp.isActive || NSApp.modalWindow)) { return; }
    NSEvent *event = NavigationKeyEvent(keyCode, pressed, repeated);
    if (!event) { return; }
    if (pressed) {
        [self finishGroupEditing];
        [self.window makeFirstResponder:self.view];
        [[self.springboard.layer searchTextInputLayer] setHasFocus:NO];
        [self.view keyDown:event];
    } else { [self.view keyUp:event]; }
    [CATransaction flush];
}
- (void)cancelNavigation {
    if ([self.springboard dragging]) { [self.springboard cancelDrag:YES]; }
    else if ([self.springboard deleting]) { [self.springboard setDeleting:NO]; }
    else if ([self.springboard groupShown]) { [self.springboard setGroupShown:NO]; }
    else if ([self.springboard filtering]) { [[self.springboard.layer searchTextInputLayer] setStringValue:@""]; }
    else { [self hideLauncher]; }
}
- (void)updateBackgroundMaterial:(NSNotification *)notification {
    BOOL hasImage = self.view.backdrop.hasImage;
    CGFloat opacity = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency ? 1 : 0.75;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.backgroundView.hidden = hasImage;
    self.backgroundView.alphaValue = opacity;
    self.view.backdrop.opacity = hasImage ? opacity : 0.08;
    [CATransaction commit];
}
- (void)refreshDesktop:(NSNotification *)notification {
    if (!self.wantsLauncherVisible) { return; }
    NSScreen *screen = self.window.screen;
    if (!screen) { [self hideLauncherImmediately]; return; }
    [self.window setFrame:screen.frame display:NO];
    [self.view setNeedsLayout:YES];
    [self updateBackgroundMaterial:nil];
    [self updateMenuBarCoverForScreen:screen];
    [self.menuBarCoverWindow orderFront:nil];
    NSUInteger pixels = [self iconPixelSizeForScale:screen.backingScaleFactor];
    if (pixels != self.iconPixelSize) { [self prepareIconsForItems:self.items pixelSize:pixels]; }
    [self prepareDesktopForScreen:screen];
}
- (void)prepareDesktopForScreen:(NSScreen *)screen {
    __weak NativeHost *weakSelf = self;
    [self.view.backdrop updateForScreen:screen completion:^(BOOL success, NSError *error) {
        NativeHost *host = weakSelf;
        if (!host) { return; }
        if ([error.domain isEqualToString:NSCocoaErrorDomain] && error.code == NSUserCancelledError) { return; }
        if (!success) {
            os_log_error(OS_LOG_DEFAULT, "Wallpaper unavailable: %{public}@", error);
            [host.view.backdrop useBackgroundColorForScreen:screen];
        }
        if (!host.wantsLauncherVisible) { return; }
        [host updateBackgroundMaterial:nil];
        [host updateMenuBarCoverForScreen:screen];
        [host.menuBarCoverWindow orderFront:nil];
    }];
}
- (void)updateMenuBarCoverForScreen:(NSScreen *)screen {
    if (!self.wantsLauncherVisible) { return; }
    CGFloat height = MAX(NSMaxY(screen.frame) - NSMaxY(screen.visibleFrame), screen.safeAreaInsets.top);
    if (height == 0) { height = NSStatusBar.systemStatusBar.thickness; }
    NSRect frame = NSMakeRect(NSMinX(screen.frame), NSMaxY(screen.frame) - height, screen.frame.size.width, height);
    if (!self.menuBarCoverWindow) {
        NSWindow *cover = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        cover.releasedWhenClosed = NO;
        cover.opaque = NO;
        cover.backgroundColor = NSColor.clearColor;
        cover.hasShadow = NO;
        cover.animationBehavior = NSWindowAnimationBehaviorNone;
        cover.collectionBehavior = self.window.collectionBehavior;
        cover.level = CGWindowLevelForKey(kCGStatusWindowLevelKey) + 1;
        NativeMenuBarView *view = [[NativeMenuBarView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        view.host = self;
        view.wantsLayer = YES;
        cover.contentView = view;
        self.menuBarCoverWindow = cover;
    }
    [self.menuBarCoverWindow setFrame:frame display:NO];
    [self.view layoutSubtreeIfNeeded];
    [self.menuBarCoverWindow.contentView layoutSubtreeIfNeeded];
    [self.view.backdrop updateMenuBarCoverLayer:self.menuBarCoverWindow.contentView.layer];
}
- (void)showLauncher {
    if (self.wantsLauncherVisible) { return; }
    NSScreen *screen = self.showOnlyOnMainScreen ? NSScreen.screens.firstObject : NSScreen.mainScreen;
    if (!self.showOnlyOnMainScreen) {
        for (NSScreen *candidate in NSScreen.screens) {
            if (NSPointInRect(NSEvent.mouseLocation, candidate.frame)) { screen = candidate; break; }
        }
    }
    [self showLauncherOnScreen:screen];
}
- (void)showLauncherOnScreen:(NSScreen *)screen {
    BOOL resuming = self.hideTask != nil;
    [self cancelPendingHide];
    NSUInteger generation = self.hideGeneration;
    self.wantsLauncherVisible = YES;
    if (generation != self.hideGeneration) { return; }
    CGRect visible = screen.visibleFrame;
    if (!resuming && !CGRectEqualToRect(self.view.visibleFrame, visible)) {
        self.view.visibleFrame = visible;
        self.view.layoutBounds = CGRectNull;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.window setFrame:screen.frame display:NO];
    [self.springboard setVisible:YES];
    [self.view setNeedsLayout:YES];
    [CATransaction commit];
    self.window.ignoresMouseEvents = NO;
    self.menuBarCoverWindow.ignoresMouseEvents = NO;
    [self updateBackgroundMaterial:nil];
    [self updateMenuBarCoverForScreen:screen];
    NSTimeInterval duration = 0;
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"animations.disabled"]) { [self removeVisibilityAnimations]; }
    else { duration = [self animateLauncherVisible:YES]; }
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.view];
    [NSApp activateIgnoringOtherApps:YES];
    if (generation != self.hideGeneration) { return; }
    [self.menuBarCoverWindow orderFront:nil];
    [CATransaction flush];
    if ([[self.window.contentView.layer.filters valueForKey:@"name"] containsObject:DissolveFilterName]) {
        __weak NativeHost *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NativeHost *host = weakSelf;
            if (host && generation == host.hideGeneration && host.wantsLauncherVisible) {
                [host removeDissolveFilter];
                [CATransaction flush];
            }
        });
    }
    NSUInteger pixels = [self iconPixelSizeForScale:screen.backingScaleFactor];
    if (pixels != self.iconPixelSize) { [self prepareIconsForItems:self.items pixelSize:pixels]; }
    [self prepareDesktopForScreen:screen];
    [self applyPendingItems];
}
- (NSUInteger)iconPixelSizeForScale:(CGFloat)scale {
    NSObject *pager = [self.view activePager];
    NSObject *page = [pager currentPage];
    NSObject *item = [[[page item] items] firstObject];
    CALayer *layer = [[item itemLayer] imageLayer];
    CGFloat points = MAX(128, CGRectGetHeight(layer.bounds));
    return MIN(512, (NSUInteger)ceil(points * scale));
}
- (void)cancelIconLoading {
    self.iconGeneration += 1;
    [self.iconQueue cancelAllOperations];
}
- (void)prepareIconsForItems:(NSArray<NSURL *> *)items pixelSize:(NSUInteger)pixels {
    [self cancelIconLoading];
    self.iconPixelSize = pixels;
    if (!self.iconQueue) {
        self.iconQueue = [[NSOperationQueue alloc] init];
        self.iconQueue.name = @"vip.kodify.launcheer.icons";
        self.iconQueue.maxConcurrentOperationCount = 2;
        self.iconQueue.qualityOfService = NSQualityOfServiceUtility;
    }
    NSUInteger generation = self.iconGeneration;
    __weak NativeHost *weakSelf = self;
    for (NSURL *url in items) {
        NSBlockOperation *operation = [[NSBlockOperation alloc] init];
        __weak NSBlockOperation *weakOperation = operation;
        [operation addExecutionBlock:^{
            @autoreleasepool {
                NSBlockOperation *work = weakOperation;
                if (work.cancelled) { return; }
                NSImage *source = [[NSWorkspace.sharedWorkspace iconForFile:url.path] copy];
                NSRect rect = NSMakeRect(0, 0, pixels, pixels);
                CGImageRef original = [source CGImageForProposedRect:&rect context:nil hints:@{NSImageHintCTM: [NSAffineTransform transform]}];
                if (!original) {
                    os_log_error(OS_LOG_DEFAULT, "Cannot decode app icon: %{public}@", url.path);
                    return;
                }
                CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                CGContextRef context = CGBitmapContextCreate(NULL, pixels, pixels, 8, 0, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
                CGColorSpaceRelease(color);
                if (!context) {
                    os_log_error(OS_LOG_DEFAULT, "Cannot allocate app icon bitmap: %{public}@", url.path);
                    return;
                }
                CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
                // Materialize IconServices' lazy pixels before handing them to the native layers.
                CGContextDrawImage(context, CGRectMake(0, 0, pixels, pixels), original);
                id image = CFBridgingRelease(CGBitmapContextCreateImage(context));
                CGContextRelease(context);
                if (!image) {
                    os_log_error(OS_LOG_DEFAULT, "Cannot create app icon bitmap: %{public}@", url.path);
                    return;
                }
                if (work.cancelled) { return; }
                dispatch_async(dispatch_get_main_queue(), ^{
                    NativeHost *host = weakSelf;
                    if (!host || work.cancelled || generation != host.iconGeneration) { return; }
                    host.icons[url] = image;
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    [host.springboard setValue:image forKey:@"icon" ofItem:url];
                    [host.springboard setValue:image forKey:@"miniIcon" ofItem:url];
                    [CATransaction commit];
                    [CATransaction flush];
                    if (host.iconDidLoad) { host.iconDidLoad(url); }
                });
            }
        }];
        [self.iconQueue addOperation:operation];
    }
}
- (void)hideLauncher {
    if (!self.wantsLauncherVisible) { return; }
    if (!self.view || [NSUserDefaults.standardUserDefaults boolForKey:@"animations.disabled"]) { [self hideLauncherImmediately]; return; }
    self.hideGeneration += 1;
    NSUInteger generation = self.hideGeneration;
    __weak NativeHost *weakSelf = self;
    dispatch_block_t task = dispatch_block_create(0, ^{
        NativeHost *host = weakSelf;
        if (host && generation == host.hideGeneration) { [host hideLauncherImmediately]; }
    });
    self.hideTask = task;
    self.wantsLauncherVisible = NO;
    if (generation != self.hideGeneration) { return; }
    self.window.ignoresMouseEvents = YES;
    self.menuBarCoverWindow.ignoresMouseEvents = YES;
    [self.window makeFirstResponder:nil];
    [self.springboard cancelDrag:NO];
    self.view.downLayer = nil;
    self.view.downPage = nil;
    self.view.downHitLayer = nil;
    self.view.downSearch = NO;
    if (generation != self.hideGeneration) { return; }
    NSTimeInterval duration = [self animateLauncherVisible:NO];
    [CATransaction flush];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), task);
}
- (NSTimeInterval)animateLauncherVisible:(BOOL)visible {
    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    NSTimeInterval duration = reduceMotion ? 0.16 : 0.36;
    CALayer *layer = self.window.contentView.layer;
    AnimateVisibility(layer, visible, duration);
    AnimateVisibility(self.menuBarCoverWindow.contentView.layer, visible, duration);
    if (reduceMotion) {
        [self removeDissolveFilter];
    } else {
        CABasicAnimation *active = (CABasicAnimation *)[layer animationForKey:DissolveAnimationKey];
        CALayer *current = active ? layer.presentationLayer : nil;
        NSNumber *from = @(visible ? 12 : 0);
        if (active) {
            from = [[current.filters valueForKey:@"name"] containsObject:DissolveFilterName] ? [current valueForKeyPath:DissolveRadiusKeyPath] : active.fromValue;
        }
        if (![[layer.filters valueForKey:@"name"] containsObject:DissolveFilterName]) {
            id blur = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
            [blur setValue:DissolveFilterName forKey:@"name"];
            [blur setValue:@0 forKey:@"inputRadius"];
            [blur setValue:@YES forKey:@"inputHardEdges"];
            NSMutableArray *filters = layer.filters ? [layer.filters mutableCopy] : [NSMutableArray array];
            [filters addObject:blur];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            layer.filters = filters;
            [CATransaction commit];
        }
        CABasicAnimation *blur = [CABasicAnimation animationWithKeyPath:DissolveRadiusKeyPath];
        blur.fromValue = from;
        blur.toValue = @(visible ? 0 : 12);
        blur.duration = duration;
        blur.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        blur.fillMode = kCAFillModeBoth;
        blur.removedOnCompletion = visible;
        [layer addAnimation:blur forKey:DissolveAnimationKey];
    }
    return duration;
}
- (void)removeDissolveFilter {
    CALayer *layer = self.window.contentView.layer;
    [layer removeAnimationForKey:DissolveAnimationKey];
    NSMutableArray *filters = [layer.filters mutableCopy];
    NSUInteger count = filters.count;
    [filters filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id filter, NSDictionary *bindings) {
        return ![[filter valueForKey:@"name"] isEqualToString:DissolveFilterName];
    }]];
    if (filters.count != count) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layer.filters = filters.count ? filters : nil;
        [CATransaction commit];
    }
}
- (void)cancelPendingHide {
    self.hideGeneration += 1;
    if (self.hideTask) { dispatch_block_cancel(self.hideTask); self.hideTask = nil; }
}
- (void)removeVisibilityAnimations {
    if (!self.view) { return; }
    RemoveVisibilityAnimations(self.window.contentView.layer);
    RemoveVisibilityAnimations(self.menuBarCoverWindow.contentView.layer);
    RemoveVisibilityAnimations(self.view.backdrop);
    RemoveVisibilityAnimations(self.backgroundView.layer);
    [self removeDissolveFilter];
}
- (void)hideLauncherImmediately {
    if (!self.wantsLauncherVisible && !self.hideTask) { return; }
    [self cancelPendingHide];
    NSUInteger generation = self.hideGeneration;
    self.wantsLauncherVisible = NO;
    if (generation != self.hideGeneration) { return; }
    self.window.ignoresMouseEvents = YES;
    BOOL wasKey = self.window.isKeyWindow;
    [self.window orderOut:nil];
    [self.menuBarCoverWindow orderOut:nil];
    [self removeVisibilityAnimations];
    [self restoreDockPresentation];
    [self finishGroupEditing];
    [self.springboard cancelDrag:NO];
    self.view.downLayer = nil;
    self.view.downPage = nil;
    self.view.downHitLayer = nil;
    self.view.downSearch = NO;
    id rootPager = [self.springboard pager];
    [rootPager setEditing:NO];
    [rootPager setDeleting:NO];
    id pager = [self.view activePager];
    NSUInteger page = [pager currentPageIndex];
    CGEventRef end = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, 0, 0);
    CGEventSetTimestamp(end, (CGEventTimestamp)(NSProcessInfo.processInfo.systemUptime * 1e9));
    [self.view scrollGesture:[NSEvent eventWithCGEvent:end] phase:4];
    [pager setCurrentPageIndex:page];
    CFRelease(end);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setAnimationDuration:0];
    StopLayerAnimations(self.view.layer);
    [self.springboard setGroupShown:NO];
    StopLayerAnimations(self.view.layer);
    [[self.springboard.layer searchTextInputLayer] setStringValue:@""];
    [[self.springboard.layer searchTextInputLayer] setHasFocus:NO];
    [self.springboard setVisible:NO];
    [CATransaction commit];
    [CATransaction flush];
    // Reload after the native mouse-up callback has unwound.
    if (self.pendingItems) { [self scheduleLayoutSave]; }
    if (wasKey) { [NSApp deactivate]; }
}
- (void)reloadItems:(NSArray<NSURL *> *)items {
    if (self.hideTask || self.view.downLayer || [[[self.springboard eventHandler] dragCapture] dragging]) { self.pendingItems = items; return; }
    [self finishGroupEditing];
    if (![self persistLayout]) { self.pendingItems = items; return; }
    NSMutableArray *retained = [NSMutableArray arrayWithCapacity:items.count];
    for (NSURL *url in items) { [retained addObject:url]; }
    NSError *error = nil;
    NativeLayout *layout = [[NativeLayout alloc] initWithApps:retained fileURL:self.verifying ? nil : NativeLayout.fileURL error:&error];
    if (!layout) { [[NSAlert alertWithError:error] runModal]; return; }
    self.items = retained;
    NSMutableDictionary *icons = [NSMutableDictionary dictionary];
    for (NSURL *url in retained) { if (self.icons[url]) { icons[url] = self.icons[url]; } }
    self.icons = icons;
    self.layout = layout;
    self.pages = layout.pages;
    self.searchPages = nil;
    [[self.springboard.layer searchTextInputLayer] setStringValue:@""];
    [self.springboard invalidate];
    [self prepareIconsForItems:retained pixelSize:self.iconPixelSize];
}
- (void)applyPendingItems {
    if (!self.pendingItems || self.hideTask || self.view.downLayer || [[[self.springboard eventHandler] dragCapture] dragging]) { return; }
    NSArray *items = self.pendingItems;
    self.pendingItems = nil;
    [self reloadItems:items];
}
- (BOOL)persistLayout {
    if (!self.layoutDirty) { return YES; }
    NSError *error = nil;
    if (![self.layout save:&error]) { [[NSAlert alertWithError:error] runModal]; return NO; }
    self.layoutDirty = NO;
    return YES;
}
- (void)scheduleLayoutSave {
    if (self.layoutSaveScheduled) { return; }
    self.layoutSaveScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.layoutSaveScheduled = NO;
        if ([self persistLayout]) { [self applyPendingItems]; }
    });
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self cancelPendingHide];
    self.wantsLauncherVisible = NO;
    [self cancelIconLoading];
    [self.view.backdrop cancelPendingUpdate];
    [self.window orderOut:nil];
    [self.menuBarCoverWindow orderOut:nil];
    [self removeVisibilityAnimations];
    [self restoreDockPresentation];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [[NSClassFromString(@"ECModalEventController") sharedController] removeHandler:self];
    [self.springboard invalidate];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    [self finishGroupEditing];
    return [self persistLayout] ? NSTerminateNow : NSTerminateCancel;
}
- (id)containerWindow { return self.window; }
- (CALayer *)rootLayerForGroups { return self.view.layer; }
- (CALayer *)rootLayerForDragging { return self.view.layer; }
- (NSArray *)pagesForItems:(NSArray *)items {
    NSMutableArray *pages = [NSMutableArray array];
    for (NSUInteger start = 0; start < items.count; start += 35) {
        NSArray *pageItems = [items subarrayWithRange:NSMakeRange(start, MIN(35, items.count - start))];
        [pages addObject:[[NativePage alloc] initWithItems:pageItems]];
    }
    return pages;
}
- (id)valueForKey:(NSString *)key ofItem:(id)item withInfo:(id)info {
    if ([key isEqualToString:@"items"]) {
        if (item) { return [item items]; }
        return self.searchPages ? self.searchPages : self.pages;
    }
    BOOL group = [item isKindOfClass:NativeGroup.class];
    if ([key isEqualToString:@"kind"]) { return group ? @"group" : @"item"; }
    if ([key isEqualToString:@"deletable"]) { return @(!group && [self canMoveItemToTrash:item]); }
    if (group && [key isEqualToString:@"title"]) { return [item title]; }
    if ([key isEqualToString:@"progress"]) { return @{@"progressValue": @(-1.0f), @"progressString": @""}; }
    if (group) { return nil; }
    NSURL *url = item;
    if ([key isEqualToString:@"title"]) { return [[NSFileManager.defaultManager displayNameAtPath:url.path] stringByDeletingPathExtension]; }
    if ([key isEqualToString:@"icon"] || [key isEqualToString:@"miniIcon"]) {
        return self.icons[url] ?: PlaceholderIcon();
    }
    return nil;
}
- (void)setValue:(id)value forKey:(NSString *)key ofItem:(id)item {
    [item setValue:value forKey:key];
    self.layoutDirty = YES;
    [self scheduleLayoutSave];
}
- (void)performChanges:(dispatch_block_t)changes {
    changes();
    [self scheduleLayoutSave];
}
- (void)moveItem:(id)item toIndex:(NSUInteger)index onPage:(NativePage *)page {
    NativePage *source = [self.layout pageContainingItem:item];
    [source.items removeObjectIdenticalTo:item];
    [page.items insertObject:item atIndex:index == NSNotFound ? page.items.count : MIN(index, page.items.count)];
    self.layoutDirty = YES;
}
- (void)removeItem:(id)item onPage:(NativePage *)page {
    [page.items removeObjectIdenticalTo:item];
    self.layoutDirty = YES;
}
- (NativePage *)addPage {
    NativePage *page = [[NativePage alloc] initWithItems:@[]];
    [self.layout.pages addObject:page];
    self.layoutDirty = YES;
    return page;
}
- (void)removePage:(NativePage *)page {
    [self.layout.pages removeObjectIdenticalTo:page];
    self.layoutDirty = YES;
}
- (NativePage *)addPageToGroup:(NativeGroup *)group {
    NativePage *page = [[NativePage alloc] initWithItems:@[]];
    [group.items addObject:page];
    self.layoutDirty = YES;
    return page;
}
- (void)removePage:(NativePage *)page fromGroup:(NativeGroup *)group {
    [group.items removeObjectIdenticalTo:page];
    self.layoutDirty = YES;
}
- (NSArray *)pagesOfGroup:(NativeGroup *)group { return group.items; }
- (BOOL)canMakeGroupUsingItem:(id)item withItem:(id)other {
    return [item isKindOfClass:NSURL.class] && [other isKindOfClass:NSURL.class] && item != other;
}
- (NSString *)nameForGroupUsingItem:(id)item withItem:(id)other {
    NSBundle *dock = [NSBundle bundleWithPath:@"/System/Library/CoreServices/Dock.app"];
    return [dock localizedStringForKey:@"Other" value:@"Other" table:nil];
}
- (NativeGroup *)makeGroupUsingItem:(NSURL *)item withItem:(NSURL *)other atIndex:(NSUInteger)index onPage:(NativePage *)page {
    NativeGroup *group = [[NativeGroup alloc] initWithID:[@"folder-" stringByAppendingString:NSUUID.UUID.UUIDString] title:[self nameForGroupUsingItem:item withItem:other] pages:@[[[NativePage alloc] initWithItems:@[]]]];
    [page.items insertObject:group atIndex:index == NSNotFound ? page.items.count : index];
    [self moveItem:item toIndex:0 onPage:group.items.firstObject];
    [self moveItem:other toIndex:1 onPage:group.items.firstObject];
    return group;
}
- (void)groupShownForItem:(id)item atIndex:(NSUInteger)index {
    if (!self.wantsLauncherVisible) { return; }
    self.dockHiddenGroup = item;
    // Native clientItem is weak; a missing item still requires restoring presentation.
    if (self.dockPresentationActive) { return; }
    self.savedPresentationOptions = NSApp.presentationOptions;
    self.dockPresentationActive = YES;
    NSApp.presentationOptions = (self.savedPresentationOptions & ~NSApplicationPresentationAutoHideDock) | NSApplicationPresentationHideDock;
}
- (void)groupHiddenForItem:(id)item atIndex:(NSUInteger)index {
    if (self.dockHiddenGroup == item) { [self restoreDockPresentation]; }
}
- (void)restoreDockPresentation {
    if (!self.dockPresentationActive) { return; }
    self.dockPresentationActive = NO;
    self.dockHiddenGroup = nil;
    NSApp.presentationOptions = self.savedPresentationOptions;
}
- (void)dragOfItemCompleted { [self scheduleLayoutSave]; }
- (void)cancelActionWithEvent:(id)event sender:(id)sender { [self hideLauncher]; }
- (void)willChangeToPage:(id)page {}
- (void)didChangeToPage:(id)page {}
- (void)selectionWillChangeFromItem:(id)from toItem:(id)to inPager:(id)pager {}
- (void)selectionDidChangeFromItem:(id)from toItem:(id)to inPager:(id)pager {}
- (void)performActionForItem:(NSURL *)url withEvent:(id)event sender:(id)sender {
    self.lastAction = url;
    NSLog(@"Native action callback: %@", url.path);
    if (!self.verifying) {
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        configuration.activates = YES;
        [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) { [[NSAlert alertWithError:error] runModal]; }
                else { [self hideLauncher]; }
            });
        }];
    }
}
- (BOOL)canMoveItemToTrash:(NSURL *)item {
    NSURL *url = item.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSBundle *bundle = [NSBundle bundleWithURL:url];
    if ([url isEqual:NSBundle.mainBundle.bundleURL.URLByResolvingSymlinksInPath.URLByStandardizingPath] ||
        (bundle.bundleIdentifier && [bundle.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier])) { return NO; }
    NSString *path = url.path;
    NSString *userApps = [NSFileManager.defaultManager URLsForDirectory:NSApplicationDirectory inDomains:NSUserDomainMask].firstObject.path;
    return [path.pathExtension.lowercaseString isEqualToString:@"app"] &&
        ([path hasPrefix:@"/Applications/"] || [path hasPrefix:[userApps stringByAppendingString:@"/"]]);
}
- (BOOL)shouldPresentAlertPanelForAction:(id)action ofItem:(id)item withEvent:(id)event { return NO; }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(showSettings:)) { return !self.verifying; }
    if (item.action == @selector(authorizeDesktopImage:)) { return !self.verifying && !self.view.downLayer; }
    if (item.action == @selector(revealItemInFinder:)) { return !self.verifying; }
    return YES;
}
- (NSMenu *)contextMenuForItem:(NSURL *)item {
    if (self.verifying) { return nil; }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *reveal = [menu addItemWithTitle:@"在 Finder 中显示" action:@selector(revealItemInFinder:) keyEquivalent:@""];
    reveal.target = self;
    reveal.representedObject = item;
    return menu;
}
- (void)revealItemInFinder:(NSMenuItem *)sender {
    if (self.verifying) { return; }
    [self hideLauncher];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[sender.representedObject]];
}
- (void)authorizeDesktopImage:(id)sender {
    if (self.verifying) { return; }
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    NSError *error = nil;
    NSURL *url = [NativeBackdrop desktopImageURLForScreen:screen error:&error];
    if (!url) {
        if (error) { [[NSAlert alertWithError:error] runModal]; }
        else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"当前桌面使用纯色背景，无需读取壁纸。";
            [alert runModal];
        }
        return;
    }
    [self finishGroupEditing];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = [NSString stringWithFormat:@"请选择当前壁纸“%@”，允许启动台读取并保存背景副本。", url.lastPathComponent];
    panel.prompt = @"允许读取";
    panel.directoryURL = url.URLByDeletingLastPathComponent;
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = NO;
    [NSApp activateIgnoringOtherApps:YES];
    if ([panel runModal] != NSModalResponseOK) { return; }
    NSURL *currentURL = [NativeBackdrop desktopImageURLForScreen:screen error:&error];
    if (error) { [[NSAlert alertWithError:error] runModal]; return; }
    if (![panel.URL.URLByResolvingSymlinksInPath.URLByStandardizingPath isEqual:currentURL.URLByResolvingSymlinksInPath.URLByStandardizingPath]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"所选文件不是当前桌面壁纸，请重新选择。";
        [alert runModal];
        return;
    }
    if (![self.view.backdrop cacheAuthorizedImageAtURL:currentURL error:&error]) {
        [[NSAlert alertWithError:error] runModal];
        return;
    }
    if (self.wantsLauncherVisible) { [self refreshDesktop:nil]; }
    else { [self showLauncherOnScreen:screen]; }
}
- (void)performRemoveActionForItem:(NSURL *)item withEvent:(id)event sender:(id)sender {
    if (self.verifying) { return; }
    if (![self canMoveItemToTrash:item]) {
        NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:@{
            NSLocalizedDescriptionKey: @"不能从启动台移除自身或系统应用。", NSURLErrorKey: item
        }];
        [[NSAlert alertWithError:error] runModal];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"将“%@”移到废纸篓？", [NSFileManager.defaultManager displayNameAtPath:item.path]];
    alert.informativeText = @"应用将从启动台移除。";
    [alert addButtonWithTitle:@"移到废纸篓"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) { return; }
    [NSWorkspace.sharedWorkspace recycleURLs:@[item] completionHandler:^(NSDictionary<NSURL *, NSURL *> *locations, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                os_log_error(OS_LOG_DEFAULT, "Cannot move app to Trash: %{public}@, %{public}@", item.path, error);
                [[NSAlert alertWithError:error] runModal];
                return;
            }
            NSMutableArray *items = [self.items mutableCopy];
            [items removeObject:item];
            [self reloadItems:items];
        });
    }];
}
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.groupTitle) {
        [self.groupTextInput _updateStringValue:self.groupTitle.stringValue width:self.groupTitle.frame.size.width complete:NO];
    } else if (notification.object == self.search) {
        [[self.springboard.layer searchTextInputLayer] _updateStringValue:self.search.stringValue width:self.search.frame.size.width complete:NO];
    }
}
- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    if (notification.object == self.search) { [[self.springboard.layer searchTextInputLayer] setHasFocus:YES]; }
    else { [self.groupTextInput setHasFocus:YES]; }
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.search) { [[self.springboard.layer searchTextInputLayer] setHasFocus:NO]; }
    else { [self.groupTextInput setHasFocus:NO]; }
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)editor doCommandBySelector:(SEL)command {
    if (control == self.groupTitle && (command == @selector(insertNewline:) || command == @selector(cancelOperation:))) {
        [self finishGroupEditing];
        return YES;
    }
    if (control == self.search && !editor.hasMarkedText &&
        (command == @selector(moveUp:) || command == @selector(moveDown:))) {
        [self.window makeFirstResponder:self.view];
        [[self.springboard.layer searchTextInputLayer] setHasFocus:NO];
        [self.view keyDown:NavigationKeyEvent(command == @selector(moveUp:) ? 126 : 125, YES, NO)];
        return YES;
    }
    if (command == @selector(insertNewline:)) {
        [self.view keyDown:NavigationKeyEvent(36, YES, NO)];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        if (self.search.stringValue.length) { [[self.springboard.layer searchTextInputLayer] setStringValue:@""]; }
        else { [self cancelNavigation]; }
        return YES;
    }
    return NO;
}
- (void)syncGroupEditor {
    if (self.hideTask) { return; }
    CALayer *input = object_getIvar(self.springboard, class_getInstanceVariable(self.springboard.class, "_textInputLayer"));
    if (input == self.groupTextInput) { return; }
    NSTextField *oldField = self.groupTitle;
    self.groupTitle = nil;
    self.groupTextInput = nil;
    [oldField removeFromSuperview];
    if (!input) { return; }
    void (^visible)(BOOL) = [input visibleBlock];
    if (!self.wantsLauncherVisible || ![[self.springboard pager] shownGroup]) {
        if (visible) { visible(YES); }
        [input _updateStringValue:[input stringValue] width:input.bounds.size.width complete:YES];
        return;
    }
    self.groupTextInput = input;
    self.groupTitle = LocalTextField(input, self, NSTextAlignmentCenter);
    self.groupTitle.stringValue = [input stringValue];
    [self.view addSubview:self.groupTitle];
    if (visible) { visible(YES); }
    [input layoutIfNeeded];
    [self.view setNeedsLayout:YES];
    [self.view layoutSubtreeIfNeeded];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.groupTitle selectText:nil];
}
- (void)finishGroupEditing {
    CALayer *input = self.groupTextInput;
    if (!input) { return; }
    NSTextField *field = self.groupTitle;
    self.groupTextInput = nil;
    self.groupTitle = nil;
    [self.window makeFirstResponder:self.view];
    [input setHasFocus:NO];
    [input _updateStringValue:field.stringValue width:field.frame.size.width complete:YES];
    [field removeFromSuperview];
}
- (void)searchTextCleared { [self searchTextChanged:@""]; }
- (void)searchTextChanged:(NSString *)query {
    if (![self.search.stringValue isEqualToString:query]) { self.search.stringValue = query; }
    BOOL version = [query isEqualToString:@"/version"];
    self.versionLabel.hidden = !version;
    if ([query isEqualToString:@"/settings"]) { [self showSettings:self]; return; }
    if (query.length == 0) {
        self.searchPages = nil;
        [self.springboard clearFilteredItems];
    }
    else if (version) {
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        self.versionLabel.stringValue = [NSString stringWithFormat:@"Launcheer %@ (Build %@)", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]];
        self.searchPages = @[];
        [self.springboard filterUsingItems:@[]];
    }
    else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
            NSString *title = [NSFileManager.defaultManager displayNameAtPath:url.path];
            return [title rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
        }];
        NSArray *matches = [self.items filteredArrayUsingPredicate:predicate];
        self.searchPages = [self pagesForItems:matches];
        [self.springboard filterUsingItems:matches];
    }
    [self.view setNeedsLayout:YES];
}
- (void)saveSnapshot:(NSString *)name {
    [self.view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [self.view bitmapImageRepForCachingDisplayInRect:self.view.bounds];
    [self.view cacheDisplayInRect:self.view.bounds toBitmapImageRep:bitmap];
    NSString *path = [@"tmp/launchpad-extraction/root" stringByAppendingPathComponent:name];
    NSError *error = nil;
    if (![[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path options:NSDataWritingAtomic error:&error]) { NSLog(@"%@", error); exit(1); }
}
- (void)verifyFirstPage {
    NSUInteger fixtureIndex = [self.items indexOfObject:[NSURL fileURLWithPath:@"/System/Applications/Utilities/Activity Monitor.app"]];
    Verify(fixtureIndex != NSNotFound, @"The unique search fixture is missing");
    self.verificationItem = self.items[fixtureIndex];
    Verify([self.springboard currentPageIndex] == 0, @"First page must be zero");
    Verify([[self.springboard pager] pages].count >= 2, @"Need at least two native pages");
    [self saveSnapshot:@"host-page-0.png"];
    [self.springboard setCurrentPageIndex:1];
    [self performSelector:@selector(verifySecondPage) withObject:nil afterDelay:0.6];
}
- (void)verifySecondPage {
    Verify([self.springboard currentPageIndex] == 1, @"Native paging failed");
    [self saveSnapshot:@"host-page-1.png"];
    CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, 0, 500);
    CGEventSetTimestamp(cg, (CGEventTimestamp)(NSProcessInfo.processInfo.systemUptime * 1e9));
    CGEventSetLocation(cg, CGPointMake(600, 400));
    [self.view scrollWheel:[NSEvent eventWithCGEvent:cg]];
    CFRelease(cg);
    [self performSelector:@selector(verifyWheel) withObject:nil afterDelay:0.7];
}
- (void)verifyWheel {
    NSLog(@"Native wheel page=%lu", (unsigned long)[self.springboard currentPageIndex]);
    Verify([self.springboard currentPageIndex] == 0, @"Native scroll wheel did not return to the first page");
    id nativeItem = [self.springboard itemForClientItem:self.items.firstObject];
    Verify([[nativeItem itemLayer] progressLayer] == nil && [[nativeItem itemLayer] progressLabelLayer] == nil,
           @"Installed application incorrectly displays download progress");
    CALayer *image = [[nativeItem itemLayer] imageLayer];
    CGPoint point = [image convertPoint:CGPointMake(CGRectGetMidX(image.bounds), CGRectGetMidY(image.bounds)) toLayer:self.view.layer];
    CGImageRef bitmap = (__bridge CGImageRef)image.contents;
    NSLog(@"Native icon: %zux%zu pixels, %.1fx%.1f points @%.1fx", CGImageGetWidth(bitmap), CGImageGetHeight(bitmap), image.bounds.size.width, image.bounds.size.height, image.contentsScale);
    Verify(CGImageGetWidth(bitmap) >= ceil(image.bounds.size.width * self.window.backingScaleFactor), @"Native icon is undersized for the current backing scale");
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime + 0.02 windowNumber:self.window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
    [self.view mouseDown:down];
    [self.view mouseUp:up];
    [self performSelector:@selector(verifyClick) withObject:nil afterDelay:0.2];
}
- (void)verifyClick {
    Verify([self.lastAction isEqual:self.items.firstObject], @"Original grid did not produce an icon action");
    self.search.stringValue = [[NSFileManager.defaultManager displayNameAtPath:self.verificationItem.path] stringByDeletingPathExtension];
    [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:self.search]];
    [self performSelector:@selector(verifySearch) withObject:nil afterDelay:0.3];
}
- (void)verifySearch {
    Verify([self.springboard filtering], @"Original grid filtering is inactive");
    Verify([[self.springboard pager] pages].count == 1, @"Filtering did not produce one native page");
    Verify([[self.springboard currentPage] numberOfGridItems] == 1, @"Filtered native page contains unexpected items");
    [self saveSnapshot:@"host-filtered.png"];
    self.search.stringValue = @"";
    [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:self.search]];
    Verify(![self.springboard filtering], @"Filtering did not clear");
    [self.springboard setCurrentPageIndex:0];
    [self performSelector:@selector(verifyTrackedGesture) withObject:nil afterDelay:0.6];
}
- (void)emitScroll:(int32_t)delta phase:(CGScrollPhase)phase {
    CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, 0, delta);
    CGEventSetTimestamp(cg, (CGEventTimestamp)(NSProcessInfo.processInfo.systemUptime * 1e9));
    CGEventSetIntegerValueField(cg, kCGScrollWheelEventScrollPhase, phase);
    CGEventSetLocation(cg, CGPointMake(600, 400));
    [self.view scrollWheel:[NSEvent eventWithCGEvent:cg]];
    CFRelease(cg);
}
- (void)verifyTrackedGesture {
    int32_t delta = -(int32_t)ceil(self.springboard.layer.bounds.size.width * 0.3);
    [self emitScroll:delta phase:kCGScrollPhaseBegan];
    [self emitScroll:delta phase:kCGScrollPhaseChanged];
    [self performSelector:@selector(verifyPausedGesture) withObject:nil afterDelay:0.22];
}
- (void)verifyPausedGesture {
    Verify([self.springboard currentPageIndex] == 0, @"Native tracked gesture settled while the finger was paused");
    [self emitScroll:0 phase:kCGScrollPhaseEnded];
    [self performSelector:@selector(verifyGestureFinished) withObject:nil afterDelay:0.7];
}
- (void)verifyGestureFinished {
    Verify([self.springboard currentPageIndex] == 1, @"Native tracked gesture did not settle after release");
    [self.window makeFirstResponder:self.search];
    NSTextView *editor = (NSTextView *)self.search.currentEditor;
    Verify(editor != nil, @"Native-style text field did not become editable");
    [editor setMarkedText:@"启" selectedRange:NSMakeRange(1, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
    Verify(editor.hasMarkedText, @"Marked text was destroyed by a search callback");
    [editor insertText:@"启动" replacementRange:NSMakeRange(NSNotFound, 0)];
    Verify([self.search.stringValue isEqualToString:@"启动"], @"Cocoa text commit did not reach native search");
    [self performSelector:@selector(verifyNativeClear) withObject:nil afterDelay:0.2];
}
- (void)verifyNativeClear {
    CALayer *search = [self.springboard.layer searchTextInputLayer];
    Verify(object_getIvar(search, class_getInstanceVariable(search.class, "_connection")) == nil, @"Search unexpectedly created a Dock helper connection");
    [self.view layoutSubtreeIfNeeded];
    CALayer *clear = object_getIvar(search, class_getInstanceVariable(search.class, "_cancelSearchLayer"));
    Verify(clear.contents != nil, @"Original search resources did not load");
    CGPoint point = [clear convertPoint:CGPointMake(CGRectGetMidX(clear.bounds), CGRectGetMidY(clear.bounds)) toLayer:self.view.layer];
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:3 clickCount:1 pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime + 0.02 windowNumber:self.window.windowNumber context:nil eventNumber:4 clickCount:1 pressure:0];
    [self.view mouseDown:down];
    [self.view mouseUp:up];
    Verify(self.search.stringValue.length == 0 && ![self.springboard filtering], @"Original clear button did not restore all pages");
    self.lastAction = nil;
    self.search.stringValue = [[NSFileManager.defaultManager displayNameAtPath:self.verificationItem.path] stringByDeletingPathExtension];
    [self controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:self.search]];
    [self performSelector:@selector(verifyReturn) withObject:nil afterDelay:0.2];
}
- (void)verifyReturn {
    [self control:self.search textView:(NSTextView *)self.search.currentEditor doCommandBySelector:@selector(insertNewline:)];
    Verify([self.lastAction isEqual:self.verificationItem], @"Native search completion did not activate its result");
    [self saveSnapshot:@"host-final.png"];
    NSLog(@"PASS: native render/page/wheel/click/filter/clear, installed-app appearance, tracked pause, marked-text commit and Return completion; no Dock helper");
    [NSApp terminate:nil];
}
@end
