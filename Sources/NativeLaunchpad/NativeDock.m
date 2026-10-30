#import "NativeDock.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>

static NSString *const NativeDockErrorDomain = @"Launcheer.NativeDock";
static const char *DockPath = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock";

typedef struct { uintptr_t start, end; } AddressRange;
typedef struct {
    const struct mach_header_64 *header;
    intptr_t slide;
    AddressRange text, stubs, objcStubs, strings, cfstrings, selectors;
    const uint8_t *functions, *functionsEnd;
} DockImage;

static BOOL Fail(NSError **error, NSString *message) {
    if (error) { *error = [NSError errorWithDomain:NativeDockErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
    return NO;
}

static uintptr_t CodePointer(uintptr_t pointer) {
    __asm__("xpaci %0" : "+r"(pointer));
    return pointer;
}

static uintptr_t DataPointer(uintptr_t pointer) {
    __asm__("xpacd %0" : "+r"(pointer));
    return pointer;
}

static BOOL InRange(AddressRange range, uintptr_t address, size_t size) {
    return address >= range.start && address <= range.end && size <= range.end - address;
}

static BOOL InImage(const DockImage *image, uintptr_t address, size_t size, vm_prot_t protection) {
    const struct load_command *command = (const void *)(image->header + 1);
    for (uint32_t index = 0; index < image->header->ncmds; index++) {
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const void *)command;
            AddressRange range = {(uintptr_t)(segment->vmaddr + image->slide), (uintptr_t)(segment->vmaddr + image->slide + segment->vmsize)};
            if ((segment->initprot & protection) == protection && InRange(range, address, size)) { return YES; }
        }
        command = (const void *)((const char *)command + command->cmdsize);
    }
    return NO;
}

static BOOL ReadImage(const void *initializer, DockImage *image) {
    Dl_info info;
    if (!dladdr(initializer, &info) || strcmp(info.dli_fname, DockPath)) { return NO; }
    image->header = info.dli_fbase;
    if (image->header->magic != MH_MAGIC_64 || image->header->cputype != CPU_TYPE_ARM64) { return NO; }
    const struct segment_command_64 *text = NULL, *linkedit = NULL;
    const struct linkedit_data_command *functions = NULL;
    const struct load_command *command = (const void *)(image->header + 1);
    const char *commandsEnd = (const char *)command + image->header->sizeofcmds;
    for (uint32_t index = 0; index < image->header->ncmds; index++) {
        if ((const char *)command + sizeof(*command) > commandsEnd || command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(commandsEnd - (const char *)command)) { return NO; }
        if (command->cmd == LC_SEGMENT_64) {
            if (command->cmdsize < sizeof(struct segment_command_64)) { return NO; }
            const struct segment_command_64 *segment = (const void *)command;
            if (segment->nsects > (command->cmdsize - sizeof(*segment)) / sizeof(struct section_64)) { return NO; }
            if (!strcmp(segment->segname, SEG_TEXT)) { text = segment; }
            if (!strcmp(segment->segname, SEG_LINKEDIT)) { linkedit = segment; }
        } else if (command->cmd == LC_FUNCTION_STARTS) {
            if (command->cmdsize != sizeof(struct linkedit_data_command)) { return NO; }
            functions = (const void *)command;
        }
        command = (const void *)((const char *)command + command->cmdsize);
    }
    if (!text || !linkedit || !functions || functions->dataoff < linkedit->fileoff || functions->datasize > linkedit->filesize || functions->dataoff - linkedit->fileoff > linkedit->filesize - functions->datasize) { return NO; }
    image->slide = (intptr_t)image->header - (intptr_t)text->vmaddr;
    image->functions = (const void *)(linkedit->vmaddr + image->slide + functions->dataoff - linkedit->fileoff);
    image->functionsEnd = image->functions + functions->datasize;
    command = (const void *)(image->header + 1);
    for (uint32_t index = 0; index < image->header->ncmds; index++) {
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const void *)command;
            const struct section_64 *sections = (const void *)(segment + 1);
            for (uint32_t section = 0; section < segment->nsects; section++) {
                const struct section_64 *item = sections + section;
                AddressRange range = {(uintptr_t)(item->addr + image->slide), (uintptr_t)(item->addr + image->slide + item->size)};
                if (!strcmp(item->sectname, "__text")) { image->text = range; }
                else if (!strcmp(item->sectname, "__auth_stubs")) { image->stubs = range; }
                else if (!strcmp(item->sectname, "__objc_stubs")) { image->objcStubs = range; }
                else if (!strcmp(item->sectname, "__cstring")) { image->strings = range; }
                else if (!strcmp(item->sectname, "__cfstring")) { image->cfstrings = range; }
                else if (!strcmp(item->sectname, "__objc_selrefs")) { image->selectors = range; }
            }
        }
        command = (const void *)((const char *)command + command->cmdsize);
    }
    return InRange(image->text, (uintptr_t)initializer, sizeof(uint32_t));
}

static uintptr_t FunctionEnd(const DockImage *image, uintptr_t function) {
    uintptr_t address = (uintptr_t)image->header;
    BOOL found = NO;
    const uint8_t *cursor = image->functions;
    while (cursor < image->functionsEnd) {
        uint64_t delta = 0;
        unsigned shift = 0;
        uint8_t byte;
        do {
            if (cursor == image->functionsEnd || shift >= 63) { return 0; }
            byte = *cursor++;
            delta |= (uint64_t)(byte & 0x7f) << shift;
            shift += 7;
        } while (byte & 0x80);
        if (!delta || delta > UINTPTR_MAX - address) { return 0; }
        address += delta;
        if (!InRange(image->text, address, 0)) { return 0; }
        if (found) { return address; }
        if (address > function) { return 0; }
        found = address == function;
    }
    return 0;
}

static int64_t SignedImmediate(uint64_t value, unsigned bits) {
    return ((int64_t)(value << (64 - bits))) >> (64 - bits);
}

static BOOL AddressPair(const uint32_t *code, unsigned target, uintptr_t *address) {
    uint32_t page = code[0], addition = code[1];
    if ((page & 0x9f00001f) != (0x90000000 | target) || (addition & 0xffc003ff) != (0x91000000 | (target << 5) | target)) { return NO; }
    uint64_t immediate = ((page >> 5) & 0x7ffff) << 2 | ((page >> 29) & 3);
    *address = ((uintptr_t)code & ~(uintptr_t)0xfff) + SignedImmediate(immediate, 21) * 4096 + ((addition >> 10) & 0xfff);
    return YES;
}

static uintptr_t BranchTarget(const uint32_t *code) {
    return (uintptr_t)code + SignedImmediate(*code & 0x03ffffff, 26) * 4;
}

static BOOL IsReturn(uint32_t instruction) {
    return instruction == 0xd65f0fff || instruction == 0xd65f0bff || instruction == 0xd65f03c0;
}

static BOOL ConstantString(const DockImage *image, uintptr_t address, const char *expected) {
    if (!InRange(image->cfstrings, address, 32)) { return NO; }
    const uintptr_t *string = (const void *)address;
    uintptr_t characters = DataPointer(string[2]);
    size_t length = strlen(expected);
    return string[3] == length && InRange(image->strings, characters, length + 1) && !memcmp((const void *)characters, expected, length + 1);
}

static uintptr_t ImportedFunction(const DockImage *image, const uint32_t *stub) {
    uintptr_t slot;
    if (!AddressPair(stub, 17, &slot) || stub[2] != 0xf9400230 || stub[3] != 0xd71f0a11 || !InImage(image, slot, sizeof(uintptr_t), VM_PROT_READ)) { return 0; }
    return CodePointer(*(const uintptr_t *)slot);
}

static BOOL CallsSymbol(const DockImage *image, uintptr_t address, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    return symbol && InRange(image->stubs, address, 16) && ImportedFunction(image, (const void *)address) == CodePointer((uintptr_t)symbol);
}

static BOOL AllowedImport(const DockImage *image, uintptr_t address) {
    const char *symbols[] = {"CFPreferencesCopyAppValue", "objc_opt_class", "objc_opt_isKindOfClass", "objc_retainAutoreleasedReturnValue", "objc_autoreleaseReturnValue", "objc_release"};
    for (size_t index = 0; index < sizeof(symbols) / sizeof(*symbols); index++) {
        if (CallsSymbol(image, address, symbols[index])) { return YES; }
    }
    if (!InRange(image->objcStubs, address, 24)) { return NO; }
    const uint32_t *stub = (const void *)address;
    uint32_t page = stub[0], load = stub[1];
    if ((page & 0x9f00001f) != 0x90000001 || (load & 0xffc003ff) != 0xf9400021) { return NO; }
    uint64_t immediate = ((page >> 5) & 0x7ffff) << 2 | ((page >> 29) & 3);
    uintptr_t slot = (address & ~(uintptr_t)0xfff) + SignedImmediate(immediate, 21) * 4096 + ((load >> 10) & 0xfff) * 8;
    if (!InRange(image->selectors, slot, sizeof(SEL)) || ImportedFunction(image, stub + 2) != CodePointer((uintptr_t)dlsym(RTLD_DEFAULT, "objc_msgSend"))) { return NO; }
    SEL selector = *(SEL const *)slot;
    return selector == @selector(boolValue) || selector == @selector(intValue) || selector == @selector(objectForKeyedSubscript:);
}

static BOOL PreferenceCallback(const DockImage *image, uintptr_t callback) {
    uintptr_t end = FunctionEnd(image, callback);
    if (!end) { return NO; }
    const char *keys[] = {"eyecandy-show-borders", "springboard-reverse-scroll-gesture", "springboard-columns", "springboard-rows"};
    const uint16_t defaults[] = {0, 1, 7, 5};
    size_t key = 0;
    for (const uint32_t *code = (const void *)callback; code + 1 < (const uint32_t *)end; code++) {
        uintptr_t address;
        if (!AddressPair(code, 0, &address) || !InRange(image->cfstrings, address, 32)) { continue; }
        if (key == 4 || !ConstantString(image, address, keys[key])) { return NO; }
        const uint32_t *call = code + 2;
        BOOL correctDefault = NO;
        for (; call < (const uint32_t *)end && (*call & 0xfc000000) != 0x94000000; call++) {
            if ((*call & 0xffe0001f) == 0x52800001) { correctDefault = ((*call >> 5) & 0xffff) == defaults[key]; }
        }
        if (!correctDefault || call == (const uint32_t *)end) { return NO; }
        key++;
    }
    if (key != 4) { return NO; }
    uintptr_t pending[32] = {callback};
    size_t count = 1;
    BOOL readsDockDomain = NO;
    for (size_t index = 0; index < count; index++) {
        uintptr_t start = pending[index];
        end = FunctionEnd(image, start);
        if (!end) { return NO; }
        for (const uint32_t *code = (const void *)start; code < (const uint32_t *)end; code++) {
            uintptr_t address;
            if (code + 1 < (const uint32_t *)end && AddressPair(code, *code & 31, &address) && ConstantString(image, address, "com.apple.dock")) { readsDockDomain = YES; }
            if ((*code & 0xfe000000) == 0xd6000000 && !IsReturn(*code)) { return NO; }
            int64_t conditional = 0;
            if ((*code & 0xff000010) == 0x54000000 || (*code & 0x7e000000) == 0x34000000) { conditional = SignedImmediate((*code >> 5) & 0x7ffff, 19) * 4; }
            else if ((*code & 0x7e000000) == 0x36000000) { conditional = SignedImmediate((*code >> 5) & 0x3fff, 14) * 4; }
            if (conditional && ((uintptr_t)code + conditional < start || (uintptr_t)code + conditional >= end)) { return NO; }
            if ((*code & 0x7c000000) != 0x14000000) { continue; }
            uintptr_t target = BranchTarget(code);
            if (target >= start && target < end) { continue; }
            if (AllowedImport(image, target)) { continue; }
            if (!FunctionEnd(image, target)) { return NO; }
            size_t known = 0;
            while (known < count && pending[known] != target) { known++; }
            if (known == count) {
                if (count == sizeof(pending) / sizeof(*pending)) { return NO; }
                pending[count++] = target;
            }
        }
    }
    return readsDockDomain;
}

static BOOL PreferenceWrapper(const DockImage *image, uintptr_t address) {
    uintptr_t end = FunctionEnd(image, address);
    if (!end || end - address != 40) { return NO; }
    const uint32_t *code = (const void *)address;
    // The isolated dispatch_once reads preferences; Springboard.init also creates Dock-owned windows.
    if (code[0] != 0xd503237f || code[1] != 0xa9bf7bfd || code[2] != 0x910003fd || (code[7] & 0xfc000000) != 0x94000000 || code[8] != 0xa8c17bfd || code[9] != 0xd65f0fff) { return NO; }
    uintptr_t token, block;
    if (!AddressPair(code + 3, 0, &token) || !AddressPair(code + 5, 1, &block) || !InImage(image, token, sizeof(dispatch_once_t), VM_PROT_WRITE) || !InImage(image, block, 32, VM_PROT_READ) || !CallsSymbol(image, BranchTarget(code + 7), "dispatch_once")) { return NO; }
    const uintptr_t *literal = (const void *)block;
    if (DataPointer(literal[0]) != DataPointer((uintptr_t)dlsym(RTLD_DEFAULT, "_NSConcreteGlobalBlock")) || !((uint32_t)literal[1] & (1u << 28))) { return NO; }
    return PreferenceCallback(image, CodePointer(literal[2]));
}

const void *NativeDockPreferenceInitializer(const void *springboardInit, NSError **error) {
    DockImage image = {0};
    springboardInit = (const void *)CodePointer((uintptr_t)springboardInit);
    if (!ReadImage(springboardInit, &image)) { Fail(error, @"无法读取当前系统 Dock 的原生初始化入口。"); return NULL; }
    uintptr_t end = FunctionEnd(&image, (uintptr_t)springboardInit);
    if (!end) { Fail(error, @"当前系统 Dock 缺少可验证的原生函数边界。"); return NULL; }
    const void *initializer = NULL;
    BOOL returned = NO;
    for (const uint32_t *code = springboardInit; code + 1 < (const uint32_t *)end; code++) {
        if (IsReturn(*code)) { returned = YES; }
        if (!returned || (*code & 0xfc000000) != 0x94000000 || (code[1] & 0xfc000000) != 0x14000000 || !PreferenceWrapper(&image, BranchTarget(code))) { continue; }
        BOOL coldEntry = NO;
        for (const uint32_t *branch = springboardInit; branch < code; branch++) {
            if ((*branch & 0xff000010) == 0x54000000 && (uintptr_t)branch + SignedImmediate((*branch >> 5) & 0x7ffff, 19) * 4 == (uintptr_t)code) { coldEntry = YES; break; }
        }
        uintptr_t continuation = BranchTarget(code + 1);
        if (!coldEntry || continuation < (uintptr_t)springboardInit || continuation >= (uintptr_t)code || initializer) { Fail(error, @"当前系统 Dock 的偏好初始化路径不唯一或已发生变化。"); return NULL; }
        initializer = (const void *)BranchTarget(code);
    }
    if (!initializer) { Fail(error, @"当前系统 Dock 的偏好初始化逻辑不受支持。"); }
    return initializer;
}

static BOOL NativeInterfacesAvailable(NSError **error) {
    const struct { const char *className, *selector, *encoding; } methods[] = {
        {"Springboard", "init", "@16@0:8"},
        {"ECSBSpringboard", "initWithHandler:numberOfRowsPerPage:numberOfColumnsPerPage:scaleFactor:layoutRTL:", "@48@0:8@16Q24Q32f40B44"},
        {"ECSBSpringboard", "layer", "@16@0:8"},
        {"ECSBSpringboard", "eventHandler", "@16@0:8"},
        {"ECSBSpringboard", "setSupportsGroups:", "v20@0:8B16"},
        {"ECSBSpringboard", "invalidate", "v16@0:8"},
        {"ECSBSpringboard", "cancelDrag:", "v20@0:8B16"},
        {"ECSBSpringboard", "setGroupShown:", "v20@0:8B16"},
        {"ECSBSpringboard", "setValue:forKey:ofItem:", "v40@0:8@16@24@32"},
        {"ECSBPager", "setEditing:", "v20@0:8B16"},
        {"ECSBPager", "setDeleting:", "v20@0:8B16"},
        {"ECSBEventHandler", "dragCapture", "@16@0:8"},
        {"ECSBEventHandler", "setAllowDragging:", "v20@0:8B16"},
        {"ECSBEventHandler", "setAllowDeleting:", "v20@0:8B16"},
        {"ECSBItemLayer", "item", "@16@0:8"},
        {"ECSBItem", "clientItem", "@16@0:8"},
        {"ECSBLayer", "gesture:", "B24@0:8@16"},
        {"ECSBLayer", "searchTextInputLayer", "@16@0:8"},
        {"ECSBGroupLayer", "gesture:", "B24@0:8@16"},
        {"ECEvent", "initWithEvent:hitLayer:hitWindow:session:", "@48@0:8@16@24@32@40"},
        {"ECModalEventController", "addHandler:externalEventSource:usingMouseHysteresis:", "v32@0:8@16B24B28"},
        {"ECModalEventController", "removeHandler:", "v24@0:8@16"},
        {"ECModalEventControllerHandler", "performMouseUpBlocksWithEvent:", "v24@0:8@16"},
        {"ECTextInputLayer", "_setupConnection", "v16@0:8"},
        {"ECTextInputLayer", "_sendStringValueMessage", "v16@0:8"},
        {"ECTextInputLayer", "font", "@16@0:8"},
        {"ECTextInputLayer", "foregroundColor", "^{CGColor=}16@0:8"},
        {"ECTextInputLayer", "stringValue", "@16@0:8"},
        {"ECTextInputLayer", "setStringValue:", "v24@0:8@16"},
        {"ECTextInputLayer", "_updateStringValue:width:complete:", "v36@0:8@16d24B32"},
        {"ECTextInputLayer", "visibleBlock", "@?16@0:8"}
    };
    for (size_t index = 0; index < sizeof(methods) / sizeof(*methods); index++) {
        Class cls = objc_getClass(methods[index].className);
        Method method = class_getInstanceMethod(cls, sel_registerName(methods[index].selector));
        if (!method || strcmp(method_getTypeEncoding(method), methods[index].encoding)) {
            return Fail(error, [NSString stringWithFormat:@"当前系统 Dock 的 %s.%s 接口不兼容。", methods[index].className, methods[index].selector]);
        }
    }
    Method shared = class_getClassMethod(objc_getClass("ECModalEventController"), sel_registerName("sharedController"));
    if (!shared || strcmp(method_getTypeEncoding(shared), "@16@0:8")) {
        return Fail(error, @"当前系统 Dock 的 ECModalEventController.sharedController 接口不兼容。");
    }
    const struct { const char *className, *name; } ivars[] = {
        {"ECModalEventController", "_eventHandlers"},
        {"ECTextInputLayer", "_hostLayer"},
        {"ECTextInputLayer", "_cancelSearchLayer"},
        {"ECSBSpringboard", "_textInputLayer"}
    };
    for (size_t index = 0; index < sizeof(ivars) / sizeof(*ivars); index++) {
        Ivar ivar = class_getInstanceVariable(objc_getClass(ivars[index].className), ivars[index].name);
        if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') {
            return Fail(error, [NSString stringWithFormat:@"当前系统 Dock 的 %s.%s 对象成员不兼容。", ivars[index].className, ivars[index].name]);
        }
    }
    return YES;
}

BOOL NativeInitializeDock(NSError **error) {
    static dispatch_once_t once;
    static BOOL initialized;
    static NSError *initializationError;
    dispatch_once(&once, ^{
        NSError *failure = nil;
        @try {
            if (!dlopen(DockPath, RTLD_LAZY | RTLD_LOCAL)) {
                Fail(&failure, [NSString stringWithFormat:@"无法加载当前系统 Dock：%s", dlerror()]);
                return;
            }
            if (!NativeInterfacesAvailable(&failure)) { return; }
            Method method = class_getInstanceMethod(NSClassFromString(@"Springboard"), @selector(init));
            const void *initializer = NativeDockPreferenceInitializer((const void *)method_getImplementation(method), &failure);
            if (!initializer) { return; }
            ((void (*)(void))initializer)();
            initialized = YES;
        } @catch (NSException *exception) {
            Fail(&failure, [NSString stringWithFormat:@"当前系统 Dock 初始化失败：%@", exception.reason]);
        } @finally {
            initializationError = failure;
        }
    });
    if (!initialized && error) { *error = initializationError; }
    return initialized;
}
