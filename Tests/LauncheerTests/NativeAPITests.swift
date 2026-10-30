import Darwin
import Foundation
import ObjectiveC
import Testing

struct NativeAPITests {
    @Test func hostCallsMatchTheInstalledNativeClasses() throws {
        let image = dlopen("/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock", RTLD_LAZY | RTLD_LOCAL)
        try #require(image != nil)
        let methods = [
            ("ECSBSpringboard", "cancelDrag:", "v20@0:8B16"),
            ("ECSBSpringboard", "setGroupShown:", "v20@0:8B16"),
            ("ECSBSpringboard", "setValue:forKey:ofItem:", "v40@0:8@16@24@32"),
            ("ECSBPager", "setEditing:", "v20@0:8B16"),
            ("ECSBPager", "setDeleting:", "v20@0:8B16"),
            ("ECSBEventHandler", "dragCapture", "@16@0:8"),
            ("ECSBItemLayer", "item", "@16@0:8"),
            ("ECSBItem", "clientItem", "@16@0:8"),
            ("ECSBLayer", "gesture:", "B24@0:8@16"),
            ("ECSBGroupLayer", "gesture:", "B24@0:8@16")
        ]
        for (name, selector, encoding) in methods {
            let cls: AnyClass = try #require(NSClassFromString(name))
            let method = try #require(class_getInstanceMethod(cls, NSSelectorFromString(selector)), "\(name).\(selector)")
            let actual = try #require(method_getTypeEncoding(method))
            #expect(String(cString: actual) == encoding, "\(name).\(selector)")
        }
    }
}
