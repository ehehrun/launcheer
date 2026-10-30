import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing

@Suite(.serialized)
@MainActor
struct NativeNavigationTests {
    @Test(arguments: [(UInt16(123), 2), (124, 3), (125, 1), (126, 0)], [false, true])
    func arrowsUseNativeNavigationUnlessTheLayerHandledThem(key: (UInt16, Int), handled: Bool) throws {
        let input = NavigationInput()
        input.springboard.handlesKey = handled
        try press(key.0, in: input)
        #expect(input.springboard.keyDownCount == 1)
        #expect(input.springboard.directions == (handled ? [] : [key.1]))
        #expect(input.host.hideCount == 0)
    }

    @Test(arguments: [UInt16(36), 76])
    func confirmationUsesTheNativeActionPath(key: UInt16) throws {
        let input = NavigationInput()
        try press(key, in: input)
        #expect(input.springboard.actionCount == 1)
        #expect(input.springboard.directions.isEmpty)
        #expect(input.host.hideCount == 0)
    }

    @Test(arguments: ["drag", "delete", "folder", "search", "root"])
    func returningUnwindsTheCurrentInteractionBeforeHiding(state: String) throws {
        let input = NavigationInput()
        let springboard = input.springboard
        springboard.dragging = state == "drag"
        springboard.deleting = state == "drag" || state == "delete"
        springboard.groupShown = state == "drag" || state == "delete" || state == "folder"
        springboard.filtering = state != "root"
        try press(53, in: input)
        #expect(springboard.cancelDragCount == (state == "drag" ? 1 : 0))
        #expect(springboard.deleting == (state == "drag"))
        #expect(springboard.groupShown == (state == "drag" || state == "delete"))
        #expect(springboard.layer.searchTextInputLayer.stringValue == (state == "search" ? "" : "query"))
        #expect(input.host.hideCount == (state == "root" ? 1 : 0))
    }

    @Test(arguments: [("moveUp:", UInt16(126), 0xF700), ("moveDown:", 125, 0xF701), ("insertNewline:", 36, 13)])
    func searchCommandsCreateACompleteLocalNativeKey(command: (String, UInt16, Int)) throws {
        let input = NavigationInput()
        let search = NSObject()
        input.host.setValue(input, forKey: "view")
        input.host.setValue(input.window, forKey: "window")
        input.host.setValue(search, forKey: "search")
        let selector = NSSelectorFromString("control:textView:doCommandBySelector:")
        let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Command = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, Selector) -> Bool
        let dispatch = unsafeBitCast(method_getImplementation(method), to: Command.self)
        #expect(dispatch(input.host, selector, search, NavigationEditor(), NSSelectorFromString(command.0)))
        let event = try #require(input.deliveredKey)
        let cgEvent = try #require(event.cgEvent)
        #expect(event.keyCode == command.1)
        // ECEvent.keyData uses the low 16 bits of this signed CGEvent field.
        #expect(UInt16(truncatingIfNeeded: cgEvent.getIntegerValueField(CGEventField(rawValue: 78)!)) == UInt16(command.2))
        #expect(input.springboard.layer.searchTextInputLayer.stringValue == "query")
        #expect(input.springboard.layer.searchTextInputLayer.hasFocus == (command.0 == "insertNewline:"))
    }

    @Test(arguments: [(UInt16(123), 0xF702), (124, 0xF703), (125, 0xF701), (126, 0xF700), (36, 13), (76, 3), (53, 27)])
    func releasingAfterHidingStillDeliversACompleteLocalKey(command: (UInt16, Int)) throws {
        let input = NavigationInput()
        input.host.setValue(input, forKey: "view")
        input.host.handleControllerKey(command.0, pressed: false, repeated: false)
        let event = try #require(input.deliveredKeyUp)
        let cgEvent = try #require(event.cgEvent)
        #expect(event.type == .keyUp && event.keyCode == command.0)
        #expect(UInt16(truncatingIfNeeded: cgEvent.getIntegerValueField(CGEventField(rawValue: 78)!)) == UInt16(command.1))
        #expect(!input.host.wantsLauncherVisible && input.host.hideCount == 0)
    }

    @Test func rightPastTheLastRootItemSelectsTheNextPagesFirstItem() throws {
        let input = NavigationInput()
        input.springboard.usesPages = true
        input.springboard.layer.searchTextInputLayer.hasFocus = false
        let pager = input.springboard.pager
        pager.currentPageIndex = 1
        pager.selectedItem = pager.currentPage.items.last

        try press(124, in: input)

        #expect(pager.currentPageIndex == 2)
        #expect(pager.selectedItem === pager.currentPage.items.first)
        #expect(input.springboard.directions == [3, 4])
        #expect(input.host.hideCount == 0)
    }

    @Test func rightOnTheFinalRootPageDoesNotWrap() throws {
        let input = NavigationInput()
        input.springboard.usesPages = true
        input.springboard.layer.searchTextInputLayer.hasFocus = false
        let pager = input.springboard.pager
        pager.currentPageIndex = 2
        let last = pager.currentPage.items.last
        pager.selectedItem = last

        try press(124, in: input)

        #expect(pager.currentPageIndex == 2 && pager.selectedItem === last)
        #expect(input.springboard.directions == [3, 4])
        #expect(input.host.hideCount == 0)
    }

    @Test(arguments: [false, true])
    func groupRightStaysOnItsPageAndOnlyBackClosesTheGroup(atBoundary: Bool) throws {
        let input = NavigationInput()
        let springboard = input.springboard
        springboard.usesPages = true
        springboard.groupShown = true
        springboard.layer.searchTextInputLayer.hasFocus = false
        springboard.pager.currentPageIndex = 1
        let pager = springboard.folderPager
        let page = pager.currentPage
        pager.selectedItem = atBoundary ? page.items.last : page.items.first

        try press(124, in: input)

        #expect(pager.currentPageIndex == 0 && springboard.pager.currentPageIndex == 1)
        #expect(pager.selectedItem === page.items.last)
        #expect(page.directions == [3] && springboard.directions.isEmpty)
        #expect(springboard.groupShown && input.host.hideCount == 0)

        try press(53, in: input)
        #expect(!springboard.groupShown && input.host.hideCount == 0)
        #expect(springboard.pager.currentPageIndex == 1)
    }

    @Test(arguments: ["drag", "search", "title"])
    func groupNavigationStillRespectsTheCurrentInputMode(mode: String) throws {
        let input = NavigationInput()
        let springboard = input.springboard
        springboard.usesPages = true
        springboard.groupShown = true
        springboard.dragging = mode == "drag"
        springboard.layer.searchTextInputLayer.hasFocus = mode == "search"
        if mode == "title" { input.host.setValue(CALayer(), forKey: "groupTextInput") }
        let page = springboard.folderPager.currentPage
        springboard.folderPager.selectedItem = page.items.first

        try press(124, in: input)

        #expect(springboard.folderPager.selectedItem === page.items.first)
        #expect(page.directions.isEmpty && springboard.directions.isEmpty)
        #expect(springboard.groupShown && input.host.hideCount == 0)
    }

    private func press(_ keyCode: UInt16, in input: NavigationInput) throws {
        let type: AnyClass = try #require(NSClassFromString("NativeView"))
        let selector = NSSelectorFromString("keyDown:")
        let method = try #require(class_getInstanceMethod(type, selector))
        typealias Key = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let dispatch = unsafeBitCast(method_getImplementation(method), to: Key.self)
        dispatch(input, selector, NavigationEvent(keyCode: keyCode))
    }
}

@MainActor
private final class NavigationInput: NSObject {
    @objc let host = NavigationHost()
    @objc let springboard = NavigationSpringboard()
    @objc let window = NavigationWindow()
    private(set) var deliveredKey: NSEvent?
    private(set) var deliveredKeyUp: NSEvent?
    override init() {
        super.init()
        host.setValue(springboard, forKey: "springboard")
    }
    @objc(nativeEvent:hitLayer:)
    func nativeEvent(_ event: NSObject, hitLayer: NSObject) -> NSObject { event }
    @objc func keyDown(_ event: NSEvent) { deliveredKey = event }
    @objc func keyUp(_ event: NSEvent) { deliveredKeyUp = event }
    @objc func activePager() -> NavigationPager { springboard.groupShown ? springboard.folderPager : springboard.pager }
}

private final class NavigationHost: NativeHost {
    private(set) var hideCount = 0
    override func hideLauncher() { hideCount += 1 }
}

@MainActor
private final class NavigationSpringboard: NSObject {
    @objc let layer = NavigationLayer()
    @objc var dragging = false
    @objc var deleting = false
    @objc var groupShown = false
    @objc var filtering = false
    var handlesKey = false
    var usesPages = false
    @objc let pager = NavigationPager(pageSizes: [3, 2, 2])
    let folderPager = NavigationPager(pageSizes: [2, 2])
    private(set) var keyDownCount = 0
    private(set) var actionCount = 0
    private(set) var cancelDragCount = 0
    private(set) var directions: [Int] = []
    @objc func keyDown(_ event: NavigationEvent) -> Bool {
        keyDownCount += 1
        if event.keyCode == 36 || event.keyCode == 76 { actionCount += 1; return true }
        return handlesKey
    }
    @objc(navigate:withEvent:)
    func navigate(_ direction: Int, with event: NSObject) -> Bool {
        directions.append(direction)
        if !usesPages { return true }
        if dragging || layer.searchTextInputLayer.hasFocus { return false }
        let active = groupShown ? folderPager : pager
        if direction == 4 {
            if active.currentPageIndex + 1 == active.pages.count { return false }
            active.currentPageIndex += 1
            active.selectedItem = active.currentPage.items.first
            return true
        }
        return active.currentPage.navigate(direction, with: event)
    }
    @objc func cancelDrag(_ animated: Bool) { cancelDragCount += 1 }
}

@MainActor
private final class NavigationLayer: NSObject {
    @objc let searchTextInputLayer = NavigationSearch()
}

@MainActor
private final class NavigationSearch: NSObject {
    @objc var stringValue = "query"
    @objc var hasFocus = true
}

private final class NavigationEvent: NSObject {
    @objc let keyCode: UInt16
    init(keyCode: UInt16) { self.keyCode = keyCode }
}

@MainActor
private final class NavigationWindow: NSObject {
    @objc func makeFirstResponder(_ responder: NSObject) -> Bool { true }
}

private final class NavigationEditor: NSObject {
    @objc let hasMarkedText = false
}

@MainActor
private final class NavigationPager: NSObject {
    var pages: [NavigationPage] = []
    @objc var currentPageIndex = 0
    @objc var selectedItem: NSObject?
    @objc var currentPage: NavigationPage { pages[currentPageIndex] }

    init(pageSizes: [Int]) {
        super.init()
        pages = pageSizes.map { NavigationPage(pager: self, count: $0) }
    }
}

@MainActor
private final class NavigationPage: NSObject {
    unowned let pager: NavigationPager
    let items: [NSObject]
    private(set) var directions: [Int] = []

    init(pager: NavigationPager, count: Int) {
        self.pager = pager
        items = (0..<count).map { _ in NSObject() }
        super.init()
    }

    @objc(navigate:withEvent:)
    func navigate(_ direction: Int, with event: NSObject) -> Bool {
        directions.append(direction)
        let index = items.firstIndex { $0 === pager.selectedItem }
        if direction == 3 {
            let next = index.map { $0 + 1 } ?? 0
            if next == items.count { return false }
            pager.selectedItem = items[next]
            return true
        }
        return false
    }
}
