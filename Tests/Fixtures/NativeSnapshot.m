// Capture only this temporary application's window, including compositor filters.
#import <ScreenCaptureKit/ScreenCaptureKit.h>

@interface NativeHost (NativeSnapshot)
- (void)captureNativeWindow:(dispatch_block_t)completion;
@end

@implementation NativeHost (NativeSnapshot)
- (void)captureNativeWindow:(dispatch_block_t)completion {
    [SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
        Verify(content != nil, error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            SCWindow *window = nil;
            for (SCWindow *candidate in content.windows) {
                if (candidate.windowID == (CGWindowID)self.window.windowNumber) { window = candidate; break; }
            }
            Verify(window != nil, @"The test window is unavailable for compositor capture");
            SCContentFilter *filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
            SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
            configuration.width = (size_t)llround(self.window.frame.size.width * self.window.backingScaleFactor);
            configuration.height = (size_t)llround(self.window.frame.size.height * self.window.backingScaleFactor);
            configuration.showsCursor = NO;
            configuration.ignoreShadowsSingleWindow = YES;
            [SCScreenshotManager captureImageWithFilter:filter configuration:configuration completionHandler:^(CGImageRef image, NSError *captureError) {
                Verify(image != NULL, captureError.localizedDescription);
                NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
                NSData *data = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSError *writeError = nil;
                BOOL written = [data writeToFile:@"tmp/launchpad-extraction/root/native-rendered-folder.png" options:NSDataWritingAtomic error:&writeError];
                Verify(written, writeError.localizedDescription);
                dispatch_async(dispatch_get_main_queue(), completion);
            }];
        });
    }];
}
@end
