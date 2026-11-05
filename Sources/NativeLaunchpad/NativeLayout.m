#import "NativeLayout.h"

static const NSUInteger PageCapacity = 35;

@implementation NativePage
- (instancetype)initWithItems:(NSArray *)items {
    if ((self = [super init])) { _items = [items mutableCopy]; }
    return self;
}
@end

@implementation NativeGroup
- (instancetype)initWithID:(NSString *)id title:(NSString *)title pages:(NSArray<NativePage *> *)pages {
    if ((self = [super init])) {
        _id = [id copy];
        _title = [title copy];
        _items = [pages mutableCopy];
    }
    return self;
}
@end

@implementation NativeSavedPreset
- (instancetype)initWithID:(NSString *)id title:(NSString *)title {
    if ((self = [super init])) {
        _id = [id copy];
        _title = [title copy];
    }
    return self;
}
@end

@interface NativeLayout ()
@property(nonatomic, strong, nullable) NSURL *destination;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *appRecords;
@end

@implementation NativeLayout
+ (BOOL)isSavedPreset:(NSString *)preset {
    if (![preset hasPrefix:@"saved-"] || preset.length != 42) { return NO; }
    NSString *suffix = [preset substringFromIndex:6];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:suffix];
    return uuid && [uuid.UUIDString isEqualToString:suffix];
}
+ (NSURL *)fileURL {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:@"Launcheer/native-layout.json"];
}
- (instancetype)initWithApps:(NSArray<NSURL *> *)apps fileURL:(NSURL *)fileURL error:(NSError **)error {
    if (!(self = [super init])) { return nil; }
    _destination = fileURL;
    _pages = [NSMutableArray array];
    _appRecords = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSURL *> *appsByPath = [NSMutableDictionary dictionaryWithCapacity:apps.count];
    for (NSURL *app in apps) { appsByPath[app.path] = app; }

    NSData *data = nil;
    NSError *readError = nil;
    BOOL savedPreset = [fileURL.lastPathComponent hasPrefix:@"native-layout-saved-"];
    if (fileURL) {
        data = [NSData dataWithContentsOfURL:fileURL options:0 error:&readError];
        if (!data && (savedPreset || ![readError.domain isEqualToString:NSCocoaErrorDomain] || readError.code != NSFileReadNoSuchFileError)) { if (error) { *error = readError; } return nil; }
    }
    NSMutableSet<NSString *> *seenApps = [NSMutableSet set];
    NSMutableSet<NSString *> *seenIDs = [NSMutableSet set];
    if (data) {
        id document = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
        if (!document) { return nil; }
        if (![document isKindOfClass:NSDictionary.class] || ![document[@"pages"] isKindOfClass:NSArray.class]) {
            [self invalidFile:fileURL error:error];
            return nil;
        }
        id title = document[@"title"];
        if ((title && ![title isKindOfClass:NSString.class]) || (savedPreset && (![title isKindOfClass:NSString.class] || [[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] == 0))) {
            [self invalidFile:fileURL error:error];
            return nil;
        }
        _title = [title copy];
        NSArray *recordsByPage = document[@"pages"];

        for (id records in recordsByPage) {
            if (![records isKindOfClass:NSArray.class] || [records count] > PageCapacity) { [self invalidFile:fileURL error:error]; return nil; }
            NativePage *page = [[NativePage alloc] initWithItems:@[]];
            for (id record in records) {
                if (![record isKindOfClass:NSDictionary.class] || ![record[@"id"] isKindOfClass:NSString.class] || [record[@"id"] length] == 0 || [seenIDs containsObject:record[@"id"]]) { [self invalidFile:fileURL error:error]; return nil; }
                [seenIDs addObject:record[@"id"]];
                if (record[@"title"] && ![record[@"title"] isKindOfClass:NSString.class]) { [self invalidFile:fileURL error:error]; return nil; }
                if ([record[@"kind"] isEqual:@"app"]) {
                    NSString *path = record[@"appID"];
                    if (![self acceptPath:path seen:seenApps]) { [self invalidFile:fileURL error:error]; return nil; }
                    _appRecords[path] = record;
                    NSURL *app = appsByPath[path];
                    if (app) { [page.items addObject:app]; }
                } else if ([record[@"kind"] isEqual:@"folder"] && [record[@"appIDs"] isKindOfClass:NSArray.class]) {
                    NSArray *paths = record[@"appIDs"];
                    NSArray *sizes = record[@"pageSizes"];
                    if (sizes && ![sizes isKindOfClass:NSArray.class]) { [self invalidFile:fileURL error:error]; return nil; }
                    NSMutableArray<NativePage *> *groupPages = [NSMutableArray array];
                    if (sizes) {
                        NSUInteger count = 0;
                        for (id size in sizes) {
                            if (![size isKindOfClass:NSNumber.class] || [size doubleValue] != [size unsignedIntegerValue] || [size unsignedIntegerValue] > PageCapacity) { [self invalidFile:fileURL error:error]; return nil; }
                            count += [size unsignedIntegerValue];
                        }
                        if (count != paths.count) { [self invalidFile:fileURL error:error]; return nil; }
                    } else {
                        NSMutableArray *counts = [NSMutableArray array];
                        for (NSUInteger index = 0; index < paths.count; index += PageCapacity) { [counts addObject:@(MIN(PageCapacity, paths.count - index))]; }
                        sizes = counts;
                    }
                    NSUInteger index = 0;
                    for (NSNumber *size in sizes) {
                        NativePage *groupPage = [[NativePage alloc] initWithItems:@[]];
                        for (NSUInteger end = index + size.unsignedIntegerValue; index < end; ++index) {
                            NSString *path = paths[index];
                            if (![self acceptPath:path seen:seenApps]) { [self invalidFile:fileURL error:error]; return nil; }
                            NSURL *app = appsByPath[path];
                            if (app) { [groupPage.items addObject:app]; }
                        }
                        if (groupPage.items.count) { [groupPages addObject:groupPage]; }
                    }
                    NSUInteger count = 0;
                    for (NativePage *groupPage in groupPages) { count += groupPage.items.count; }
                    if (count) { [page.items addObject:[[NativeGroup alloc] initWithID:record[@"id"] title:record[@"title"] pages:groupPages]]; }
                } else { [self invalidFile:fileURL error:error]; return nil; }
            }
            if (page.items.count) { [_pages addObject:page]; }
        }
    }
    if (_pages.count == 0) { [_pages addObject:[[NativePage alloc] initWithItems:@[]]]; }
    for (NSURL *app in apps) {
        if ([seenApps containsObject:app.path]) { continue; }
        NativePage *page = _pages.lastObject;
        if (page.items.count == PageCapacity) { page = [[NativePage alloc] initWithItems:@[]]; [_pages addObject:page]; }
        [page.items addObject:app];
    }
    return self;
}
- (BOOL)acceptPath:(NSString *)path seen:(NSMutableSet<NSString *> *)seen {
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath || ![path.pathExtension.lowercaseString isEqualToString:@"app"] || [seen containsObject:path]) { return NO; }
    [seen addObject:path];
    return YES;
}
- (id)copyWithZone:(NSZone *)zone {
    NativeLayout *copy = [[NativeLayout allocWithZone:zone] init];
    copy.destination = self.destination;
    copy.title = self.title;
    copy.appRecords = [self.appRecords mutableCopy];
    copy->_pages = [NSMutableArray arrayWithCapacity:self.pages.count];
    for (NativePage *page in self.pages) {
        NSMutableArray *items = [NSMutableArray arrayWithCapacity:page.items.count];
        for (id item in page.items) {
            if ([item isKindOfClass:NativeGroup.class]) {
                NativeGroup *group = item;
                NSMutableArray *pages = [NSMutableArray arrayWithCapacity:group.items.count];
                for (NativePage *groupPage in group.items) {
                    [pages addObject:[[NativePage alloc] initWithItems:groupPage.items]];
                }
                [items addObject:[[NativeGroup alloc] initWithID:group.id title:group.title pages:pages]];
            } else { [items addObject:item]; }
        }
        [copy.pages addObject:[[NativePage alloc] initWithItems:items]];
    }
    return copy;
}
- (NativeLayout *)copyToURL:(NSURL *)destination {
    NativeLayout *copy = [self copy];
    copy.destination = destination;
    return copy;
}
- (void)invalidFile:(NSURL *)url error:(NSError **)error {
    if (error) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSLocalizedDescriptionKey:@"The saved Launchpad layout is invalid.", NSURLErrorKey:url}]; }
}
- (NativePage *)pageContainingItem:(id)item {
    for (NativePage *page in self.pages) {
        if ([page.items indexOfObjectIdenticalTo:item] != NSNotFound) { return page; }
        for (id entry in page.items) {
            if (![entry isKindOfClass:NativeGroup.class]) { continue; }
            for (NativePage *groupPage in [entry items]) {
                if ([groupPage.items indexOfObjectIdenticalTo:item] != NSNotFound) { return groupPage; }
            }
        }
    }
    return nil;
}
- (BOOL)flattenGroup:(NativeGroup *)group {
    for (NSUInteger pageIndex = 0; pageIndex < self.pages.count; ++pageIndex) {
        NativePage *page = self.pages[pageIndex];
        NSUInteger index = [page.items indexOfObjectPassingTest:^BOOL(id item, NSUInteger position, BOOL *stop) {
            return [item isKindOfClass:NativeGroup.class] && [((NativeGroup *)item).id isEqualToString:group.id];
        }];
        if (index == NSNotFound) { continue; }
        NativeGroup *storedGroup = page.items[index];
        NSMutableArray *apps = [NSMutableArray array];
        for (NativePage *groupPage in storedGroup.items) { [apps addObjectsFromArray:groupPage.items]; }
        [page.items replaceObjectsInRange:NSMakeRange(index, 1) withObjectsFromArray:apps];
        for (NSUInteger current = pageIndex; current < self.pages.count; ++current) {
            NativePage *overflowing = self.pages[current];
            if (overflowing.items.count <= PageCapacity) { break; }
            NSRange range = NSMakeRange(PageCapacity, overflowing.items.count - PageCapacity);
            NSArray *overflow = [overflowing.items subarrayWithRange:range];
            [overflowing.items removeObjectsInRange:range];
            if (current + 1 == self.pages.count) { [self.pages addObject:[[NativePage alloc] initWithItems:@[]]]; }
            [self.pages[current + 1].items insertObjects:overflow atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, overflow.count)]];
        }
        return YES;
    }
    return NO;
}
- (BOOL)save:(NSError **)error {
    if (!self.destination) { return YES; }
    NSMutableArray *pages = [NSMutableArray arrayWithCapacity:self.pages.count];
    for (NativePage *page in self.pages) {
        NSMutableArray *records = [NSMutableArray arrayWithCapacity:page.items.count];
        for (id item in page.items) {
            if ([item isKindOfClass:NativeGroup.class]) {
                NativeGroup *group = item;
                NSMutableArray *appIDs = [NSMutableArray array];
                NSMutableArray *pageSizes = [NSMutableArray arrayWithCapacity:group.items.count];
                for (NativePage *groupPage in group.items) {
                    [pageSizes addObject:@(groupPage.items.count)];
                    for (NSURL *app in groupPage.items) { [appIDs addObject:app.path]; }
                }
                NSMutableDictionary *record = [@{@"id":group.id, @"kind":@"folder", @"appIDs":appIDs, @"pageSizes":pageSizes} mutableCopy];
                if (group.title) { record[@"title"] = group.title; }
                [records addObject:record];
            } else {
                NSURL *app = item;
                NSDictionary *record = self.appRecords[app.path];
                [records addObject:record ?: @{@"id":app.path, @"kind":@"app", @"appID":app.path}];
            }
        }
        [pages addObject:records];
    }
    NSMutableDictionary *document = [@{@"pages":pages} mutableCopy];
    if (self.title) { document[@"title"] = self.title; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    if (!data) { return NO; }
    if (![NSFileManager.defaultManager createDirectoryAtURL:self.destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) { return NO; }
    return [data writeToURL:self.destination options:NSDataWritingAtomic error:error];
}
@end
