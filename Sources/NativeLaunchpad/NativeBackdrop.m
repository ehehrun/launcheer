#import "NativeBackdrop.h"
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import <stdatomic.h>

typedef struct { float values[20]; } NativeColorMatrix;
static const CGFloat BlurRadius = 12;

@interface NSObject (NativeBackdropFilter)
+ (id)filterWithType:(NSString *)type;
@end

@interface NSValue (NativeBackdropColorMatrix)
+ (NSValue *)valueWithCAColorMatrix:(NativeColorMatrix)matrix;
@end

static CGSize ImageSizeForBounds(CGSize imageSize, CGSize bounds, NSImageScaling scaling, BOOL allowClipping) {
    if (scaling == NSImageScaleAxesIndependently) { return bounds; }
    if (scaling == NSImageScaleNone) { return imageSize; }
    CGFloat x = bounds.width / imageSize.width;
    CGFloat y = bounds.height / imageSize.height;
    CGFloat scale = allowClipping ? MAX(x, y) : MIN(x, y);
    if (scaling == NSImageScaleProportionallyDown) { scale = MIN(1, scale); }
    return CGSizeMake(imageSize.width * scale, imageSize.height * scale);
}

static CGFloat DecodePixelSize(CGSize imageSize, CGSize sourceSize, CGSize screenSize, CGFloat backingScaleFactor, NSImageScaling scaling, BOOL allowClipping) {
    CGSize size = ImageSizeForBounds(imageSize, screenSize, scaling, allowClipping);
    CGFloat scale = MAX(size.width / sourceSize.width, size.height / sourceSize.height) * backingScaleFactor;
    CGFloat pixels = MAX(sourceSize.width, sourceSize.height) * MIN(1, scale);
    // Heavily cropped panoramas trade sampling detail for a bounded, blurred background.
    CGFloat limit = 2 * MAX(screenSize.width, screenSize.height) * backingScaleFactor;
    return ceil(MIN(pixels, limit));
}

static NSURL *DesktopImageURL(NSURL *url, NSError **error) {
    if (![url.pathExtension.lowercaseString isEqualToString:@"madesktop"]) { return url; }
    NSDictionary *desktop = [NSDictionary dictionaryWithContentsOfURL:url error:error];
    if (!desktop) { return nil; }
    NSString *thumbnailPath = desktop[@"thumbnailPath"];
    if (![thumbnailPath isKindOfClass:NSString.class] || !thumbnailPath.isAbsolutePath) {
        if (error) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
            NSLocalizedDescriptionKey: @"系统壁纸描述文件缺少有效的静态图片路径。", NSURLErrorKey: url
        }]; }
        return nil;
    }
    return [NSURL fileURLWithPath:thumbnailPath];
}

static NSURL *CacheURLForImageURL(NSURL *url, NSURL *directory) {
    NSData *name = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(name.bytes, (CC_LONG)name.length, digest);
    NSMutableString *key = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < sizeof(digest); index++) { [key appendFormat:@"%02x", digest[index]]; }
    return [directory URLByAppendingPathComponent:key];
}

@interface NativeBackdrop ()
@property(nonatomic, strong) NSURL *imageCacheDirectory;
- (void)prepareForScreen:(NSScreen *)screen asynchronously:(BOOL)asynchronously completion:(void (^)(BOOL, NSError *))completion;
@end

@implementation NativeBackdrop {
    CALayer *_imageLayer;
    NSURL *_desktopImageURL;
    NSDate *_modificationDate;
    CGSize _imageSize;
    CGSize _sourceSize;
    CGFloat _maxPixelSize;
    NSImageScaling _imageScaling;
    BOOL _allowClipping;
    dispatch_queue_t _prepareQueue;
    atomic_uint_fast64_t _requestGeneration;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _prepareQueue = dispatch_queue_create("vip.kodify.launcheer.wallpaper", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        atomic_init(&_requestGeneration, 0);
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        _imageCacheDirectory = [support URLByAppendingPathComponent:@"Launcheer/Wallpapers" isDirectory:YES];
        Class filterClass = NSClassFromString(@"CAFilter");
        id blur = [filterClass filterWithType:@"gaussianBlur"];
        [blur setValue:@YES forKey:@"inputHardEdges"];
        [blur setValue:@(BlurRadius) forKey:@"inputRadius"];
        id saturation = [filterClass filterWithType:@"colorSaturate"];
        [saturation setValue:@1.8 forKey:@"inputAmount"];
        id matrix = [filterClass filterWithType:@"colorMatrix"];
        NativeColorMatrix values = {{
            .75f, 0, 0, 0, .05292f,
            0, .75f, 0, 0, .05292f,
            0, 0, .75f, 0, .05292f,
            0, 0, 0, 1, 0
        }};
        [matrix setValue:[NSValue valueWithCAColorMatrix:values] forKey:@"inputColorMatrix"];
        self.filters = @[blur, saturation, matrix];
        self.shouldRasterize = YES;
        self.masksToBounds = YES;
        self.backgroundColor = NSColor.blackColor.CGColor;
        _imageLayer = [CALayer layer];
        [self addSublayer:_imageLayer];
    }
    return self;
}

- (BOOL)hasImage { return _imageLayer.contents != nil; }

- (void)updateMenuBarCoverLayer:(CALayer *)layer {
    [self layoutIfNeeded];
    CGFloat height = MIN(CGRectGetHeight(self.bounds), CGRectGetHeight(layer.bounds) + 3 * BlurRadius);
    CGRect source = CGRectMake(CGRectGetMinX(self.bounds), CGRectGetMaxY(self.bounds) - height, CGRectGetWidth(self.bounds), height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.masksToBounds = YES;
    layer.contentsScale = self.rasterizationScale;
    CALayer *slice = [CALayer layer];
    slice.frame = CGRectMake(CGRectGetMinX(layer.bounds), CGRectGetMaxY(layer.bounds) - height, source.size.width, height);
    slice.backgroundColor = self.backgroundColor;
    slice.filters = self.filters;
    slice.shouldRasterize = YES;
    slice.rasterizationScale = self.rasterizationScale;
    slice.masksToBounds = YES;
    CALayer *image = [CALayer layer];
    image.contents = _imageLayer.contents;
    image.contentsScale = _imageLayer.contentsScale;
    image.frame = CGRectOffset(_imageLayer.frame, -source.origin.x, -source.origin.y);
    slice.sublayers = @[image];
    layer.sublayers = @[slice];
    [CATransaction commit];
}

- (void)useBackgroundColorForScreen:(NSScreen *)screen {
    NSAssert(NSThread.isMainThread, @"Desktop image settings must be read on the main thread");
    [self cancelPendingUpdate];
    BOOL customImage = [NSUserDefaults.standardUserDefaults stringForKey:@"background.customImagePath"].length > 0;
    NSColor *fillColor = customImage ? NSColor.blackColor : [NSWorkspace.sharedWorkspace desktopImageOptionsForScreen:screen][NSWorkspaceDesktopImageFillColorKey];
    if (!fillColor) { fillColor = NSColor.blackColor; }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.backgroundColor = fillColor.CGColor;
    self.rasterizationScale = screen.backingScaleFactor;
    _imageLayer.contents = nil;
    _desktopImageURL = nil;
    _modificationDate = nil;
    _imageSize = CGSizeZero;
    _sourceSize = CGSizeZero;
    _maxPixelSize = 0;
    [CATransaction commit];
}

+ (NSURL *)desktopImageURLForScreen:(NSScreen *)screen error:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Desktop image settings must be read on the main thread");
    return DesktopImageURL([NSWorkspace.sharedWorkspace desktopImageURLForScreen:screen], error);
}

- (BOOL)cacheAuthorizedImageAtURL:(NSURL *)url error:(NSError **)error {
    NSFileManager *files = NSFileManager.defaultManager;
    NSDictionary *before = [files attributesOfItemAtPath:url.path error:error];
    if (!before) { return NO; }
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) { return NO; }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    CGImageRef image = source ? CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), (__bridge CFDictionaryRef)@{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @64
    }) : NULL;
    if (source) { CFRelease(source); }
    if (!image) {
        if (error) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
            NSLocalizedDescriptionKey: @"所选壁纸不是可解码的图片。", NSURLErrorKey: url
        }]; }
        return NO;
    }
    CGImageRelease(image);
    NSDictionary *after = [files attributesOfItemAtPath:url.path error:error];
    if (!after) { return NO; }
    NSDate *date = before[NSFileModificationDate];
    if (![date isEqual:after[NSFileModificationDate]]) {
        if (error) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{
            NSLocalizedDescriptionKey: @"壁纸在读取期间发生变化，请重新选择。", NSURLErrorKey: url
        }]; }
        return NO;
    }
    if (![files createDirectoryAtURL:self.imageCacheDirectory withIntermediateDirectories:YES attributes:nil error:error]) { return NO; }
    NSURL *cacheURL = CacheURLForImageURL(url, self.imageCacheDirectory);
    if (![data writeToURL:cacheURL options:NSDataWritingAtomic error:error]) { return NO; }
    // FileManager's date setter loses subsecond precision on this macOS build.
    if (![cacheURL setResourceValue:date forKey:NSURLContentModificationDateKey error:error]) { return NO; }
    // Explicit authorization must reload the saved bytes even when source metadata is unchanged.
    [self cancelPendingUpdate];
    _modificationDate = nil;
    return YES;
}

- (BOOL)updateForScreen:(NSScreen *)screen error:(NSError **)error {
    __block BOOL success = NO;
    __block NSError *updateError = nil;
    [self prepareForScreen:screen asynchronously:NO completion:^(BOOL result, NSError *failure) {
        success = result;
        updateError = failure;
    }];
    if (error) { *error = updateError; }
    return success;
}

- (void)updateForScreen:(NSScreen *)screen completion:(void (^)(BOOL, NSError *))completion {
    [self prepareForScreen:screen asynchronously:YES completion:completion];
}

- (void)cancelPendingUpdate {
    NSAssert(NSThread.isMainThread, @"Backdrop requests must be changed on the main thread");
    atomic_fetch_add(&_requestGeneration, 1);
}

- (void)prepareForScreen:(NSScreen *)screen asynchronously:(BOOL)asynchronously completion:(void (^)(BOOL, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Desktop image settings must be read on the main thread");
    uint_fast64_t generation = atomic_fetch_add(&_requestGeneration, 1) + 1;
    NSString *customImagePath = [NSUserDefaults.standardUserDefaults stringForKey:@"background.customImagePath"];
    BOOL customImage = customImagePath.length > 0;
    NSURL *desktopImageURL = customImage ? [NSURL fileURLWithPath:customImagePath] : [NSWorkspace.sharedWorkspace desktopImageURLForScreen:screen];
    NSDictionary *options = customImage ? nil : [NSWorkspace.sharedWorkspace desktopImageOptionsForScreen:screen];
    NSColor *fillColor = customImage ? NSColor.blackColor : options[NSWorkspaceDesktopImageFillColorKey];
    if (!fillColor) {
        completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{
            NSLocalizedDescriptionKey: @"The system did not provide the desktop background color."
        }]);
        return;
    }
    NSNumber *imageScaling = options[NSWorkspaceDesktopImageScalingKey];
    NSImageScaling scaling = imageScaling ? imageScaling.unsignedIntegerValue : NSImageScaleProportionallyUpOrDown;
    if (scaling > NSImageScaleProportionallyUpOrDown) {
        completion(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError userInfo:@{
            NSLocalizedDescriptionKey: @"The desktop image scaling mode is unsupported."
        }]);
        return;
    }
    CGSize screenSize = screen.frame.size;
    CGFloat backingScaleFactor = screen.backingScaleFactor;
    NSURL *imageCacheDirectory = self.imageCacheDirectory;
    NSURL *previousURL = _desktopImageURL;
    NSDate *previousDate = _modificationDate;
    CGFloat previousPixelSize = _maxPixelSize;
    BOOL allowClipping = customImage || [options[NSWorkspaceDesktopImageAllowClippingKey] boolValue];
    __block NSURL *url = nil;
    __block NSDate *modificationDate = nil;
    __block BOOL imageChanged = NO;
    __block BOOL prepareImage = NO;
    __block CGImageRef image = NULL;
    __block CGSize imageSize = _imageSize;
    __block CGSize sourceSize = _sourceSize;
    __block CGFloat maxPixelSize = 0;
    void (^finish)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
        dispatch_block_t apply = ^{
            BOOL current = generation == atomic_load(&_requestGeneration);
            if (current && success) {
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                self.backgroundColor = fillColor.CGColor;
                self.rasterizationScale = backingScaleFactor;
                _imageLayer.contentsScale = backingScaleFactor;
                _imageScaling = scaling;
                _allowClipping = allowClipping;
                if (imageChanged || prepareImage) {
                    _imageLayer.contents = (__bridge id)image;
                    _desktopImageURL = url;
                    _modificationDate = modificationDate;
                    _imageSize = imageSize;
                    _sourceSize = sourceSize;
                    _maxPixelSize = maxPixelSize;
                }
                [self setNeedsLayout];
                [CATransaction commit];
            }
            if (image) { CGImageRelease(image); image = NULL; }
            completion(current && success, current ? error : [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
        };
        if (asynchronously) { dispatch_async(dispatch_get_main_queue(), apply); }
        else { apply(); }
    };
    dispatch_block_t prepare = ^{
        @autoreleasepool {
            if (generation != atomic_load(&_requestGeneration)) { finish(NO, nil); return; }
            NSError *error = nil;
            url = customImage ? desktopImageURL : DesktopImageURL(desktopImageURL, &error);
            if (error) { finish(NO, error); return; }
            if (url) {
                NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:&error];
                if (!attributes) { finish(NO, error); return; }
                modificationDate = attributes[NSFileModificationDate];
            }
            imageChanged = url ? ![url isEqual:previousURL] || ![modificationDate isEqual:previousDate] : previousURL != nil;
            maxPixelSize = url && !imageChanged ? DecodePixelSize(imageSize, sourceSize, screenSize, backingScaleFactor, scaling, allowClipping) : 0;
            prepareImage = url && (imageChanged || maxPixelSize > previousPixelSize);
            if (prepareImage) {
                NSURL *readURL = url;
                if (!customImage) {
                    NSURL *cacheURL = CacheURLForImageURL(url, imageCacheDirectory);
                    NSError *cacheError = nil;
                    NSDictionary *cached = [NSFileManager.defaultManager attributesOfItemAtPath:cacheURL.path error:&cacheError];
                    if (cached) {
                        if ([modificationDate isEqual:cached[NSFileModificationDate]]) { readURL = cacheURL; }
                    } else if (![cacheError.domain isEqualToString:NSCocoaErrorDomain] || cacheError.code != NSFileReadNoSuchFileError) {
                        finish(NO, cacheError);
                        return;
                    }
                }
                NSData *data = [NSData dataWithContentsOfURL:readURL options:NSDataReadingMappedIfSafe error:&error];
                if (!data) { finish(NO, error); return; }
                if (generation != atomic_load(&_requestGeneration)) { finish(NO, nil); return; }
                CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
                if (source) {
                    size_t index = CGImageSourceGetPrimaryImageIndex(source);
                    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
                    CGFloat width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
                    CGFloat height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
                    CGFloat dpiWidth = [properties[(__bridge NSString *)kCGImagePropertyDPIWidth] doubleValue];
                    CGFloat dpiHeight = [properties[(__bridge NSString *)kCGImagePropertyDPIHeight] doubleValue];
                    NSUInteger orientation = [properties[(__bridge NSString *)kCGImagePropertyOrientation] unsignedIntegerValue];
                    if (orientation >= 5 && orientation <= 8) {
                        CGFloat swap = width; width = height; height = swap;
                        swap = dpiWidth; dpiWidth = dpiHeight; dpiHeight = swap;
                    }
                    sourceSize = CGSizeMake(width, height);
                    imageSize = CGSizeMake(width * 72 / (dpiWidth > 0 ? dpiWidth : 72), height * 72 / (dpiHeight > 0 ? dpiHeight : 72));
                    maxPixelSize = DecodePixelSize(imageSize, sourceSize, screenSize, backingScaleFactor, scaling, allowClipping);
                    NSDictionary *decode = @{
                        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
                        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
                    };
                    image = CGImageSourceCreateThumbnailAtIndex(source, index, (__bridge CFDictionaryRef)decode);
                    CFRelease(source);
                }
                if (!image) {
                    finish(NO, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
                        NSLocalizedDescriptionKey: [readURL isEqual:url] ? [NSString stringWithFormat:customImage ? @"无法解码自定义背景图片“%@”。" : @"无法解码桌面壁纸图片“%@”。", url.lastPathComponent] : @"已授权的壁纸副本无法解码，请重新允许读取当前壁纸。",
                        NSURLErrorKey: url
                    }]);
                    return;
                }
            }
            finish(YES, nil);
        }
    };
    if (asynchronously) { dispatch_async(_prepareQueue, prepare); }
    else { prepare(); }
}

- (void)layoutSublayers {
    [super layoutSublayers];
    if (!_imageLayer.contents) { return; }
    CGSize imageSize = ImageSizeForBounds(_imageSize, self.bounds.size, _imageScaling, _allowClipping);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _imageLayer.frame = CGRectMake(CGRectGetMidX(self.bounds) - imageSize.width / 2,
                                  CGRectGetMidY(self.bounds) - imageSize.height / 2,
                                  imageSize.width, imageSize.height);
    [CATransaction commit];
}
@end
