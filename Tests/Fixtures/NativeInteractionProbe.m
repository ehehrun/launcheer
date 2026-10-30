// Appended only to the temporary --interactions verification host.
@interface NSObject (NativeInteractionInspection)
- (CALayer *)controlLayer;
- (NSArray<CALayer *> *)indicatorLayers;
- (BOOL)_validatePageItem:(id)page clientPageItem:(id)client;
- (id)item;
- (id)clientItem;
- (id)labelLayer;
- (CALayer *)labelEditLayer;
- (BOOL)openingGroup;
- (BOOL)closingGroup;
- (NSString *)string;
@end

@interface NativeInteractionProbe : NSObject
@property(nonatomic, strong) NativeHost *host;
@property(nonatomic, strong) NSURL *moved;
@property(nonatomic, strong) NSURL *target;
@property(nonatomic, strong) NSURL *third;
@property(nonatomic, strong) NativeGroup *group;
@property(nonatomic) CGPoint destination;
@property(nonatomic) NSUInteger eventNumber;
@end
static NativeInteractionProbe *activeInteractionProbe;

@implementation NativeInteractionProbe
- (void)next:(SEL)selector after:(NSTimeInterval)delay {
    NSLog(@"Native interaction next: %@", NSStringFromSelector(selector));
    [self performSelector:selector withObject:nil afterDelay:delay];
}
- (CGPoint)centerOfApp:(id)item {
    CALayer *layer = [[self.host.springboard itemForClientItem:item] itemLayer];
    CALayer *image = [layer imageLayer];
    Verify(image != nil, @"The interaction fixture has no native icon layer");
    return [image convertPoint:CGPointMake(CGRectGetMidX(image.bounds), CGRectGetMidY(image.bounds)) toLayer:self.host.view.layer];
}
- (void)mouse:(NSEventType)type at:(CGPoint)point {
    CGPoint location = [self.host.view convertPoint:point toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:type location:location modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.host.window.windowNumber context:nil eventNumber:++self.eventNumber clickCount:1 pressure:type == NSEventTypeLeftMouseUp ? 0 : 1];
    if (type == NSEventTypeLeftMouseDown) { [self.host.view mouseDown:event]; }
    else if (type == NSEventTypeLeftMouseDragged) { [self.host.view mouseDragged:event]; }
    else { [self.host.view mouseUp:event]; }
}
- (void)click:(CGPoint)point {
    [self mouse:NSEventTypeLeftMouseDown at:point];
    [self mouse:NSEventTypeLeftMouseUp at:point];
}
- (void)drag:(NSURL *)app to:(CGPoint)point completion:(SEL)completion {
    CGPoint start = [self centerOfApp:app];
    self.destination = point;
    [self mouse:NSEventTypeLeftMouseDown at:start];
    [self mouse:NSEventTypeLeftMouseDragged at:CGPointMake(start.x + 4, start.y)];
    [self mouse:NSEventTypeLeftMouseDragged at:CGPointMake(start.x + 8, start.y)];
    [self mouse:NSEventTypeLeftMouseDragged at:CGPointMake(start.x + (point.x - start.x) * 0.5, start.y + (point.y - start.y) * 0.5)];
    [self mouse:NSEventTypeLeftMouseDragged at:point];
    [self next:completion after:0.9];
}
- (NSUInteger)groupCount {
    NSUInteger count = 0;
    for (NativePage *page in self.group.items) { count += page.items.count; }
    return count;
}
- (void)checkNativeModel {
    NSArray *native = [[self.host.springboard pager] pages];
    Verify(native.count == self.host.layout.pages.count, @"Native/client root page counts diverged");
    for (NSUInteger index = 0; index < native.count; ++index) {
        Verify([self.host.springboard _validatePageItem:[(NSObject *)native[index] item] clientPageItem:self.host.layout.pages[index]], @"Native/client page identities or order diverged");
    }
}
- (void)begin {
    Verify(self.host.verifying, @"Interaction verification must use an in-memory layout");
    Verify(self.host.items.count > 40, @"Need two native pages for interactions");
    // Physical pointer input must not race this fixture's synthetic sequence.
    self.host.window.ignoresMouseEvents = YES;
    [self.host.springboard setCurrentPageIndex:0];
    [self next:@selector(reorderRoot) after:0.6];
}
- (void)reorderRoot {
    NativePage *page = self.host.layout.pages.firstObject;
    self.moved = page.items[0];
    CGPoint a = [self centerOfApp:page.items[2]];
    CGPoint b = [self centerOfApp:page.items[3]];
    [self drag:self.moved to:CGPointMake((a.x + b.x) * 0.5, a.y) completion:@selector(releaseRoot)];
}
- (void)releaseRoot {
    [self mouse:NSEventTypeLeftMouseUp at:self.destination];
    [self next:@selector(checkReorder) after:0.7];
}
- (void)checkReorder {
    NativePage *page = self.host.layout.pages.firstObject;
    Verify(page.items.firstObject != self.moved && [page.items containsObject:self.moved], @"Real mouse drag did not reorder the root page");
    [self checkNativeModel];
    self.moved = page.items[0];
    self.target = page.items[1];
    self.third = page.items[2];
    [self drag:self.moved to:[self centerOfApp:self.target] completion:@selector(releaseNewGroup)];
}
- (void)releaseNewGroup {
    [self mouse:NSEventTypeLeftMouseUp at:self.destination];
    [self next:@selector(checkNewGroup) after:0.7];
}
- (void)checkNewGroup {
    for (id item in self.host.layout.pages.firstObject.items) {
        if ([item isKindOfClass:NativeGroup.class]) { self.group = item; break; }
    }
    Verify(self.group && [self groupCount] == 2, @"Hovering one app over another did not create a native folder");
    [self checkNativeModel];
    if ([[self.host.springboard pager] shownGroup]) {
        [self.host finishGroupEditing];
        [self.host.springboard setGroupShown:NO];
        [self next:@selector(openGroup) after:0.7];
    } else { [self openGroup]; }
}
- (void)openGroup {
    [self click:[self centerOfApp:self.group]];
    [self next:@selector(renameGroup) after:0.7];
}
- (void)renameGroup {
    [NSApp activateIgnoringOtherApps:YES];
    [self.host.window makeKeyAndOrderFront:nil];
    [self next:@selector(editGroupTitle) after:0.2];
}
- (void)editGroupTitle {
    id native = [[self.host.springboard pager] shownGroup];
    Verify(native != nil, @"Clicking the native folder did not open it");
    CALayer *label = [[native layer] labelLayer];
    CGPoint point = [label convertPoint:CGPointMake(CGRectGetMidX(label.bounds), CGRectGetMidY(label.bounds)) toLayer:self.host.view.layer];
    [self click:point];
    [self.host syncGroupEditor];
    Verify(self.host.groupTitle.currentEditor != nil, @"Native folder title did not acquire the local editor");
    Verify(object_getIvar(self.host.groupTextInput, class_getInstanceVariable(self.host.groupTextInput.class, "_connection")) == nil, @"Folder rename created a Dock helper");
    NSTextView *editor = (NSTextView *)self.host.groupTitle.currentEditor;
    [editor selectAll:nil];
    [editor insertText:@"原生文件夹" replacementRange:NSMakeRange(NSNotFound, 0)];
    [self.host control:self.host.groupTitle textView:editor doCommandBySelector:@selector(insertNewline:)];
    Verify([self.group.title isEqualToString:@"原生文件夹"] && self.host.groupTitle == nil, @"Native rename completion did not commit the local editor");
    [self.host captureNativeWindow:^{
        [self.host.springboard setGroupShown:NO];
        [self next:@selector(moveIntoGroup) after:0.7];
    }];
}
- (void)moveIntoGroup {
    [self drag:self.third to:[self centerOfApp:self.group] completion:@selector(releaseIntoGroup)];
}
- (void)releaseIntoGroup {
    [self mouse:NSEventTypeLeftMouseUp at:self.destination];
    [self next:@selector(checkMoveIn) after:0.7];
}
- (void)checkMoveIn {
    Verify([self groupCount] == 3, @"Dragging an app onto a native folder did not move it inside");
    [self checkNativeModel];
    if (![[self.host.springboard pager] shownGroup]) {
        [self click:[self centerOfApp:self.group]];
        [self next:@selector(moveOutOfGroup) after:0.7];
    } else { [self moveOutOfGroup]; }
}
- (void)moveOutOfGroup {
    CGPoint outside = CGPointMake(self.host.view.bounds.size.width - 50, 190);
    [self drag:self.third to:outside completion:@selector(releaseOutOfGroup)];
}
- (void)releaseOutOfGroup {
    [self mouse:NSEventTypeLeftMouseUp at:self.destination];
    [self next:@selector(checkMoveOut) after:0.7];
}
- (void)checkMoveOut {
    NativePage *destination = [self.host.layout pageContainingItem:self.third];
    Verify([self groupCount] == 2 && [self.host.layout.pages containsObject:destination], @"Dragging outside the folder did not move its app to the root page");
    [self checkNativeModel];
    [self.host.springboard setGroupShown:NO];
    [self.host.springboard setCurrentPageIndex:0];
    [self next:@selector(clickDots) after:0.7];
}
- (void)clickDots {
    NSArray<CALayer *> *dots = [[self.host.springboard.layer controlLayer] indicatorLayers];
    Verify(dots.count >= 2, @"Native pager did not create its page dots");
    CALayer *dot = dots[1];
    CGPoint point = [dot convertPoint:CGPointMake(CGRectGetMidX(dot.bounds), CGRectGetMidY(dot.bounds)) toLayer:self.host.view.layer];
    [self click:point];
    Verify([self.host.springboard currentPageIndex] == 1 && self.host.wantsLauncherVisible, @"Native dots were swallowed by background dismissal");
    [self next:@selector(clickBlank) after:0.7];
}
- (void)clickBlank {
    [self click:CGPointMake(self.host.view.bounds.size.width * 0.5, 15)];
    Verify(!self.host.wantsLauncherVisible, @"Blank background click did not dismiss the launcher");
    [self next:@selector(reopen) after:0.3];
}
- (void)reopen {
    [self.host showLauncher];
    self.host.window.ignoresMouseEvents = YES;
    [self.host.springboard setCurrentPageIndex:0];
    [self next:@selector(reopenGroup) after:0.7];
}
- (void)reopenGroup {
    [self click:[self centerOfApp:self.group]];
    [self next:@selector(finish) after:0.7];
}
- (void)finish {
    Verify([[self.host.springboard pager] shownGroup] != nil, @"Folder failed to reopen after launcher dismissal");
    [self checkNativeModel];
    self.moved = self.group.items.firstObject.items.firstObject;
    self.destination = CGPointMake(self.host.view.bounds.size.width - 50, 190);
    [self mouse:NSEventTypeLeftMouseDown at:[self centerOfApp:self.moved]];
    [self mouse:NSEventTypeLeftMouseDragged at:self.destination];
    [self next:@selector(releaseFastExit) after:0.15];
}
- (void)releaseFastExit {
    [self mouse:NSEventTypeLeftMouseUp at:self.destination];
    [self next:@selector(checkFastExit) after:0.7];
}
- (void)checkFastExit {
    [self checkNativeModel];
    NativePage *page = [self.host.layout pageContainingItem:self.moved];
    Verify(page != nil && ![[[self.host.springboard eventHandler] dragCapture] dragging], @"Single-event folder exit lost its app or left dragging active");
    NSMutableSet *paths = [NSMutableSet set];
    NSUInteger count = 0;
    for (NativePage *root in self.host.layout.pages) {
        for (id item in root.items) {
            if ([item isKindOfClass:NSURL.class]) { [paths addObject:[item path]]; count++; continue; }
            for (NativePage *contents in [item items]) {
                for (NSURL *url in contents.items) { [paths addObject:url.path]; count++; }
            }
        }
    }
    Verify(count == self.host.items.count && paths.count == count, @"Folder dragging lost or duplicated an app");
    NSLog(@"Fast first-event folder exit: %@; native/client layout remains valid", [self.host.layout.pages containsObject:page] ? @"moved" : @"cancelled");
    [self.host.springboard setGroupShown:NO];
    [self next:@selector(interruptGroupOpening) after:0.7];
}
- (void)interruptGroupOpening {
    [self click:[self centerOfApp:self.group]];
    Verify([[self.host.springboard pager] openingGroup], @"Opening interruption fixture missed the native opening animation");
    [NSApp deactivate];
    [self.host hideLauncher];
    [self next:@selector(checkInactiveOpening) after:0.35];
}
- (void)checkHiddenFolderState {
    id pager = [self.host.springboard pager];
    Verify(!NSApp.isActive && !self.host.window.isVisible && !self.host.wantsLauncherVisible,
           @"Inactive launcher did not hide independently of its layer animation");
    Verify(![pager openingGroup] && ![pager closingGroup] && ![pager shownGroup],
           [NSString stringWithFormat:@"Hidden folder did not finish: opening=%d closing=%d shown=%@", [pager openingGroup], [pager closingGroup], [pager shownGroup]]);
    Verify(self.host.groupTitle == nil && self.host.groupTextInput == nil,
           @"Hidden launcher retained its local folder editor");
    Verify(object_getIvar(self.host.springboard, class_getInstanceVariable(self.host.springboard.class, "_textInputLayer")) == nil,
           @"Hidden launcher retained the native folder text input");
}
- (void)checkInactiveOpening {
    [self checkHiddenFolderState];
    NSLog(@"Inactive opening interruption: window hidden, native opening/closing finished before show");
    [self.host showLauncher];
    self.host.window.ignoresMouseEvents = YES;
    [self next:@selector(reopenInterruptedFolder) after:0.7];
}
- (void)reopenInterruptedFolder {
    [self click:[self centerOfApp:self.group]];
    [self next:@selector(hideWhileRenaming) after:0.7];
}
- (void)hideWhileRenaming {
    id pager = [self.host.springboard pager];
    id group = [pager shownGroup];
    Verify(group && ![pager openingGroup] && ![pager closingGroup], @"Folder failed to reopen after an interrupted opening");
    CALayer *label = [[group layer] labelLayer];
    CGPoint point = [label convertPoint:CGPointMake(CGRectGetMidX(label.bounds), CGRectGetMidY(label.bounds)) toLayer:self.host.view.layer];
    [self click:point];
    Verify(self.host.groupTitle.currentEditor != nil, @"Rename-hide fixture did not acquire its local editor");
    NSTextView *editor = (NSTextView *)self.host.groupTitle.currentEditor;
    [editor selectAll:nil];
    [editor insertText:@"隐藏后保留名称" replacementRange:NSMakeRange(NSNotFound, 0)];
    Verify(![self.group.title isEqualToString:@"隐藏后保留名称"], @"Folder title committed before the native editing completion");
    [NSApp deactivate];
    [self.host hideLauncher];
    [self next:@selector(checkInactiveRename) after:0.35];
}
- (void)checkInactiveRename {
    [self checkHiddenFolderState];
    Verify([self.group.title isEqualToString:@"隐藏后保留名称"], @"Hiding during rename lost the entered folder title");
    [self.host showLauncher];
    self.host.window.ignoresMouseEvents = YES;
    [self next:@selector(reopenRenamedFolder) after:0.7];
}
- (void)reopenRenamedFolder {
    [self click:[self centerOfApp:self.group]];
    [self next:@selector(checkReopenedRename) after:0.7];
}
- (void)checkReopenedRename {
    id pager = [self.host.springboard pager];
    id group = [pager shownGroup];
    Verify(group && ![pager openingGroup] && ![pager closingGroup], @"Renamed folder did not reopen after inactive hiding");
    Verify([[[[group layer] labelLayer] string] isEqualToString:@"隐藏后保留名称"], @"Reopened native folder label lost the committed title");
    Verify(self.host.groupTitle == nil && self.host.groupTextInput == nil, @"Reopening restored a stale local folder editor");
    [self checkNativeModel];
    NSLog(@"PASS: real native root reorder, hover group creation, folder open/rename, move in/out, dots, blank dismissal, inactive opening interruption and rename hide/show; memory layout, no Dock helper");
    [NSApp terminate:nil];
}
@end

@implementation NativeHost (InteractionVerification)
- (void)verifyNativeInteractions {
    activeInteractionProbe = [NativeInteractionProbe new];
    activeInteractionProbe.host = self;
    [activeInteractionProbe begin];
}
@end
