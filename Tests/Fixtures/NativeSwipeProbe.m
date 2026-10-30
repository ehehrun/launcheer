// Appended only to a temporary host build by verify_swipe.sh.
#import <AppKit/AppKit.h>
static NSUInteger probeLayouts;
static NSUInteger probeIcons;

@interface NSObject (NativeSwipeInspection)
- (CALayer *)scrollLayer;
- (double)scrollValue;
@end

typedef struct {
    double time, target, model, presentation, inputTime;
    NSUInteger layouts, icons, page;
    int phase;
} SwipeFrame;

@interface NativeSwipeProbe : NSObject
@property(nonatomic, strong) NativeHost *host;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic) NSUInteger count;
@property(nonatomic) BOOL flush;
@property(nonatomic) BOOL relayout;
@property(nonatomic, strong) NSTask *sampler;
@property(nonatomic) NSUInteger cancelledPage;
@property(nonatomic) double heldPosition;
@end

static NativeSwipeProbe *activeSwipeProbe;
static SwipeFrame swipeFrames[1024];

@implementation NativeSwipeProbe
- (void)emit:(int32_t)delta phase:(CGScrollPhase)phase {
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, 0, delta);
    CGEventSetTimestamp(event, (CGEventTimestamp)(NSProcessInfo.processInfo.systemUptime * 1e9));
    CGEventSetIntegerValueField(event, kCGScrollWheelEventScrollPhase, phase);
    CGEventSetLocation(event, CGPointMake(600, 400));
    [self.host.view scrollWheel:[NSEvent eventWithCGEvent:event]];
    CFRelease(event);
    if (self.flush) { [CATransaction flush]; }
}
- (void)tick:(CADisplayLink *)link {
    NSUInteger index = self.count++;
    CALayer *scroll = [self.host.springboard.layer scrollLayer];
    SwipeFrame *frame = &swipeFrames[index];
    frame->time = CACurrentMediaTime();
    frame->target = link.targetTimestamp;
    frame->model = scroll.bounds.origin.x;
    frame->presentation = scroll.presentationLayer.bounds.origin.x;
    frame->layouts = probeLayouts;
    frame->icons = probeIcons;
    frame->page = [self.host.springboard currentPageIndex];
    NSUInteger step = index % 240;
    BOOL pauseAfterTakeover = index / 240 == 1;
    double start = CACurrentMediaTime();
    if (step == 0 || step == 120 || step == 216) { [self emit:-1 phase:kCGScrollPhaseBegan]; frame->phase = 1; }
    else if (step == 65) {
        double before = scroll.presentationLayer.bounds.origin.x;
        [self emit:1 phase:kCGScrollPhaseBegan];
        Verify(fabs(scroll.bounds.origin.x - before) < 1, @"New gesture jumped to the animation destination");
        Verify([scroll animationForKey:@"bounds"] == nil, @"The old page animation is still overriding the finger");
        self.heldPosition = scroll.bounds.origin.x;
        frame->phase = 1;
    }
    else if (step < 45) { [self emit:-12 phase:kCGScrollPhaseChanged]; frame->phase = 2; }
    else if (!pauseAfterTakeover && step > 65 && step < 86) { [self emit:10 phase:kCGScrollPhaseChanged]; frame->phase = 2; }
    else if (pauseAfterTakeover && step == 94) {
        Verify(fabs(scroll.presentationLayer.bounds.origin.x - self.heldPosition) < 0.01,
               @"Old animation continued underneath a paused finger after takeover");
    }
    else if (pauseAfterTakeover && step > 94 && step < 115) { [self emit:10 phase:kCGScrollPhaseChanged]; frame->phase = 2; }
    else if (step > 120 && step < 136) { [self emit:-40 phase:kCGScrollPhaseChanged]; frame->phase = 2; }
    else if (step > 216 && step < 237) { [self emit:-10 phase:kCGScrollPhaseChanged]; frame->phase = 2; }
    else if (step == 61 || (!pauseAfterTakeover && step == 86) || (pauseAfterTakeover && step == 115) || step == 237) { [self emit:0 phase:kCGScrollPhaseEnded]; frame->phase = 4; }
    else if (step == 136) {
        self.cancelledPage = [self.host.springboard currentPageIndex];
        [self emit:0 phase:kCGScrollPhaseCancelled];
        frame->phase = 8;
    }
    else if (step == 215) {
        double expected = self.cancelledPage * self.host.springboard.layer.bounds.size.width;
        Verify([self.host.springboard currentPageIndex] == self.cancelledPage, @"Cancellation changed the page");
        Verify(fabs(scroll.bounds.origin.x - expected) < 0.01, @"Cancelled gesture left the grid between pages");
        Verify(fabs(scroll.presentationLayer.bounds.origin.x - expected) < 0.5, @"Cancellation did not finish returning to its page");
    }
    if (self.relayout && step == 20) { self.host.view.needsLayout = YES; }
    frame->inputTime = (CACurrentMediaTime() - start) * 1000;
    if (index == 5 && [NSProcessInfo.processInfo.arguments containsObject:@"--profile"]) {
        self.sampler = [[NSTask alloc] init];
        self.sampler.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sample"];
        self.sampler.arguments = @[[NSString stringWithFormat:@"%d", getpid()], @"5", @"-file", @"tmp/native-swipe-validation/paging.sample.txt"];
        NSError *error;
        Verify([self.sampler launchAndReturnError:&error], error.description);
    }
    if (self.count == 720) {
        [self.displayLink invalidate];
        Verify(probeIcons == swipeFrames[0].icons, @"Swiping unexpectedly reloaded icons");
        NSMutableString *csv = [NSMutableString stringWithString:@"frame,time,target,model,presentation,input_ms,layouts,icons,page,phase\n"];
        for (NSUInteger i = 0; i < self.count; i++) {
            SwipeFrame *row = &swipeFrames[i];
            [csv appendFormat:@"%lu,%.9f,%.9f,%.6f,%.6f,%.6f,%lu,%lu,%lu,%d\n", (unsigned long)i,
             row->time, row->target, row->model, row->presentation, row->inputTime,
             (unsigned long)row->layouts, (unsigned long)row->icons, (unsigned long)row->page, row->phase];
        }
        NSString *name = self.relayout ? @"relayout" : self.flush ? @"flush" : @"current";
        NSString *path = [NSString stringWithFormat:@"tmp/native-swipe-validation/%@.csv", name];
        NSError *error;
        Verify([csv writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error], error.description);
        NSLog(@"Swipe probe: %@; %lu display callbacks; %lu layouts; %lu icon requests", path,
              (unsigned long)self.count, (unsigned long)probeLayouts, (unsigned long)probeIcons);
        printf("PASS: swipe probe, %lu display callbacks; executable=%s\n", (unsigned long)self.count,
               NSProcessInfo.processInfo.arguments.firstObject.UTF8String);
        fflush(stdout);
        [NSApp terminate:nil];
    }
}
@end

@implementation NativeHost (SwipePerformance)
- (void)verifySwipePerformance {
    activeSwipeProbe = [[NativeSwipeProbe alloc] init];
    activeSwipeProbe.host = self;
    activeSwipeProbe.flush = [NSProcessInfo.processInfo.arguments containsObject:@"--flush"];
    activeSwipeProbe.relayout = [NSProcessInfo.processInfo.arguments containsObject:@"--relayout"];
    activeSwipeProbe.displayLink = [self.view displayLinkWithTarget:activeSwipeProbe selector:@selector(tick:)];
    [activeSwipeProbe.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
@end
