import AppKit
import NativeLaunchpad
import ObjectiveC
import QuartzCore
import Testing

@Suite(.serialized)
@MainActor
struct NativeHideAnimationTests {
    @Test(arguments: [CGFloat(0), 0.5], [false, true])
    func theTransitionKeepsTheGeometryAndModelLayersUnchanged(anchor: CGFloat, reduceMotion: Bool) throws {
        let restoreMotion = try interceptHideMotion(reduceMotion)
        defer { restoreMotion() }
        let input = HideAnimationInput(anchor: anchor)
        let root = input.window.contentView.layer
        let model = (root.transform, root.frame, root.position)
        let iconModel = (input.icon.transform, input.icon.frame, input.icon.position)
        let backgrounds = [input.view.backdrop, input.backgroundView.layer]
        let backgroundModels = backgrounds.map { ($0.transform, $0.frame, $0.position) }
        if reduceMotion {
            root.filters = [try transitionFilter(name: "launcheerDissolve", radius: 0)]
            let previous = CABasicAnimation(keyPath: "filters.launcheerDissolve.inputRadius")
            previous.fromValue = 4
            previous.toValue = 12
            root.add(previous, forKey: "launcheer.dissolve")
        }

        input.host.hideLauncher()

        let duration = reduceMotion ? 0.16 : 0.36
        for layer in [root, input.cover.contentView.layer] {
            let animation = try visibilityAnimation(layer, key: "launcheer.hide")
            #expect(animation.duration == duration && !animation.isRemovedOnCompletion && animation.fillMode == .both)
            let fade = try visibilityComponent(animation, keyPath: "opacity")
            #expect((fade.fromValue as? NSNumber)?.floatValue == layer.opacity)
            #expect((fade.toValue as? NSNumber)?.floatValue == 0)
        }
        if reduceMotion {
            #expect(namedTransitionFilter(root) == nil && root.animation(forKey: "launcheer.dissolve") == nil)
        } else {
            let blur = try visibilityComponent(visibilityAnimation(root, key: "launcheer.dissolve"), keyPath: "filters.launcheerDissolve.inputRadius")
            #expect(blur.duration == duration && (blur.fromValue as? NSNumber)?.doubleValue == 0 && (blur.toValue as? NSNumber)?.doubleValue == 12)
            #expect((namedTransitionFilter(root)?.value(forKey: "inputRadius") as? NSNumber)?.doubleValue == 0)
        }
        for (background, state) in zip(backgrounds, backgroundModels) {
            for key in ["launcheer.hide", "launcheer.show", "launcheer.dissolve"] { #expect(background.animation(forKey: key) == nil) }
            #expect(CATransform3DEqualToTransform(background.transform, state.0) && background.frame == state.1 && background.position == state.2 && background.opacity == 1)
        }
        #expect(CATransform3DEqualToTransform(root.transform, model.0) && root.frame == model.1 && root.position == model.2 && root.opacity == 1)
        #expect(input.cover.contentView.layer.opacity == 1 && input.cover.contentView.layer.animation(forKey: "launcheer.dissolve") == nil)
        #expect(input.icon.frame == iconModel.1 && input.icon.position == iconModel.2 && CATransform3DEqualToTransform(input.icon.transform, iconModel.0))
        #expect(input.view.layer.animation(forKey: "launcheer.hide") == nil && input.icon.animation(forKey: "launcheer.hide") == nil)
        #expect(!input.host.wantsLauncherVisible && input.window.ignoresMouseEvents)
        #expect(input.window.orderOutCount == 0 && input.cover.orderOutCount == 0)
        #expect(input.view.downLayer == nil && input.view.downPage == nil && input.view.downHitLayer == nil && !input.view.downSearch)
        #expect(!input.springboard.dragging && input.springboard.completedDragCount == 1)
        try immediateHide(input.host)
        #expect(namedTransitionFilter(root) == nil && root.animation(forKey: "launcheer.dissolve") == nil)
        #expect(NSApp == nil)
    }

    @Test(arguments: [CGFloat(0), 0.5], [false, true])
    func showingStartsTransparentBeforeEitherWindowOrdersFront(anchor: CGFloat, reduceMotion: Bool) throws {
        let restoreMotion = try interceptHideMotion(reduceMotion)
        defer { restoreMotion() }
        let input = HideAnimationInput(anchor: anchor)
        input.host.setValue(false, forKey: "wantsLauncherVisible")
        let root = input.window.contentView.layer
        let cover = input.cover.contentView.layer
        let backgrounds = [input.view.backdrop, input.backgroundView.layer]
        let backgroundModels = backgrounds.map { ($0.transform, $0.frame, $0.position) }
        root.opacity = 0.84
        cover.opacity = 0.58
        let model = (root.transform, root.frame, root.position)
        let iconModel = (input.icon.transform, input.icon.frame, input.icon.position)
        root.sampledPresentation = try sampledVisibility(opacity: 0.91, blurRadius: 9)
        cover.sampledPresentation = try sampledVisibility(opacity: 0.79)
        var rootPrepared = false
        var coverPrepared = false
        input.window.onOrderFront = {
            rootPrepared = root.animation(forKey: "launcheer.show") != nil &&
                (reduceMotion ? root.animation(forKey: "launcheer.dissolve") == nil : root.animation(forKey: "launcheer.dissolve") != nil)
        }
        input.cover.onOrderFront = { coverPrepared = cover.animation(forKey: "launcheer.show") != nil }

        try show(input)

        #expect(rootPrepared && coverPrepared && input.window.orderFrontCount == 1 && input.cover.orderFrontCount == 1)
        let duration = reduceMotion ? 0.16 : 0.36
        for layer in [root, cover] {
            let animation = try visibilityAnimation(layer, key: "launcheer.show")
            #expect(animation.duration == duration && animation.isRemovedOnCompletion && animation.fillMode == .both)
            let fade = try visibilityComponent(animation, keyPath: "opacity")
            #expect((fade.fromValue as? NSNumber)?.floatValue == 0 && (fade.toValue as? NSNumber)?.floatValue == layer.opacity)
        }
        if reduceMotion {
            #expect(namedTransitionFilter(root) == nil && root.animation(forKey: "launcheer.dissolve") == nil)
        } else {
            let blur = try visibilityComponent(visibilityAnimation(root, key: "launcheer.dissolve"), keyPath: "filters.launcheerDissolve.inputRadius")
            #expect(blur.duration == duration && (blur.fromValue as? NSNumber)?.doubleValue == 12 && (blur.toValue as? NSNumber)?.doubleValue == 0)
            #expect((namedTransitionFilter(root)?.value(forKey: "inputRadius") as? NSNumber)?.doubleValue == 0)
        }
        for (background, state) in zip(backgrounds, backgroundModels) {
            for key in ["launcheer.hide", "launcheer.show", "launcheer.dissolve"] { #expect(background.animation(forKey: key) == nil) }
            #expect(CATransform3DEqualToTransform(background.transform, state.0) && background.frame == state.1 && background.position == state.2 && background.opacity == 1)
        }
        #expect(CATransform3DEqualToTransform(root.transform, model.0) && root.frame == model.1 && root.position == model.2 && root.opacity == 0.84 && cover.opacity == 0.58)
        #expect(input.icon.frame == iconModel.1 && input.icon.position == iconModel.2 && CATransform3DEqualToTransform(input.icon.transform, iconModel.0))
        #expect(input.view.layer.animation(forKey: "launcheer.show") == nil && input.icon.animation(forKey: "launcheer.show") == nil)
        try immediateHide(input.host)
        for layer in input.transitionLayers {
            for key in ["launcheer.show", "launcheer.hide", "launcheer.dissolve"] { #expect(layer.animation(forKey: key) == nil) }
        }
        #expect(namedTransitionFilter(root) == nil)
        #expect(NSApp == nil)
    }

    @Test func reversingUsesTheOpacityAndBlurPresentationInBothDirections() throws {
        let restoreMotion = try interceptHideMotion(false)
        defer { restoreMotion() }
        let input = HideAnimationInput()
        input.host.setValue(false, forKey: "wantsLauncherVisible")
        let root = input.window.contentView.layer
        let cover = input.cover.contentView.layer
        let model = (root.transform, input.icon.frame, input.icon.position)
        try show(input)
        root.sampledPresentation = try sampledVisibility(opacity: 0.31, blurRadius: 4.5)
        cover.sampledPresentation = try sampledVisibility(opacity: 0.62)

        input.host.hideLauncher()

        for (layer, opacity) in [(root, Float(0.31)), (cover, Float(0.62))] {
            let fade = try visibilityComponent(visibilityAnimation(layer, key: "launcheer.hide"), keyPath: "opacity")
            #expect((fade.fromValue as? NSNumber)?.floatValue == opacity)
        }
        let hideBlur = try visibilityComponent(visibilityAnimation(root, key: "launcheer.dissolve"), keyPath: "filters.launcheerDissolve.inputRadius")
        #expect((hideBlur.fromValue as? NSNumber)?.doubleValue == 4.5 && (hideBlur.toValue as? NSNumber)?.doubleValue == 12)
        for layer in input.transitionLayers { #expect(layer.animation(forKey: "launcheer.show") == nil) }
        root.sampledPresentation = try sampledVisibility(opacity: 0.14, blurRadius: 8.25)
        cover.sampledPresentation = try sampledVisibility(opacity: 0.38)
        input.view.backdrop.isHidden = true
        input.backgroundView.layer.isHidden = false

        try show(input)

        for (layer, opacity) in [(root, Float(0.14)), (cover, Float(0.38))] {
            let fade = try visibilityComponent(visibilityAnimation(layer, key: "launcheer.show"), keyPath: "opacity")
            #expect((fade.fromValue as? NSNumber)?.floatValue == opacity)
        }
        let showBlur = try visibilityComponent(visibilityAnimation(root, key: "launcheer.dissolve"), keyPath: "filters.launcheerDissolve.inputRadius")
        #expect((showBlur.fromValue as? NSNumber)?.doubleValue == 8.25 && (showBlur.toValue as? NSNumber)?.doubleValue == 0)
        #expect((namedTransitionFilter(root)?.value(forKey: "inputRadius") as? NSNumber)?.doubleValue == 0)
        for layer in input.transitionLayers { #expect(layer.animation(forKey: "launcheer.hide") == nil) }
        for background in [input.view.backdrop, input.backgroundView.layer] {
            for key in ["launcheer.show", "launcheer.hide", "launcheer.dissolve"] { #expect(background.animation(forKey: key) == nil) }
        }
        #expect(CATransform3DEqualToTransform(root.transform, model.0) && root.opacity == 1 && cover.opacity == 1)
        #expect(input.icon.frame == model.1 && input.icon.position == model.2)
        try immediateHide(input.host)
        #expect(NSApp == nil)
    }

    @Test(arguments: [false, true])
    func reversingBeforeTheBlurPresentationExistsKeepsItsSubmittedStart(partialPresentation: Bool) throws {
        let restoreMotion = try interceptHideMotion(false)
        defer { restoreMotion() }
        let input = HideAnimationInput()
        input.host.setValue(false, forKey: "wantsLauncherVisible")
        let root = input.window.contentView.layer
        let cover = input.cover.contentView.layer
        try show(input)
        if partialPresentation { root.sampledPresentation = try sampledVisibility(opacity: 0.23) }
        for visible in [false, true] {
            if visible { try show(input) } else { input.host.hideLauncher() }
            let key = visible ? "launcheer.show" : "launcheer.hide"
            let previous = visible ? "launcheer.hide" : "launcheer.show"
            for layer in [root, cover] {
                let fade = try visibilityComponent(visibilityAnimation(layer, key: key), keyPath: "opacity")
                #expect((fade.fromValue as? NSNumber)?.floatValue == (layer === root && partialPresentation ? Float(0.23) : 0))
            }
            let blur = try visibilityComponent(visibilityAnimation(root, key: "launcheer.dissolve"), keyPath: "filters.launcheerDissolve.inputRadius")
            #expect((blur.fromValue as? NSNumber)?.doubleValue == 12)
            #expect((blur.toValue as? NSNumber)?.doubleValue == (visible ? 0 : 12))
            for layer in input.transitionLayers { #expect(layer.animation(forKey: previous) == nil) }
        }
        #expect(root.opacity == 1 && cover.opacity == 1)
        try immediateHide(input.host)
        #expect(NSApp == nil)
    }

    @Test(arguments: [false, true])
    func theShowDeadlineRemovesOnlyItsOwnDissolveFilter(interruptedByHide: Bool) async throws {
        let restoreMotion = try interceptHideMotion(false)
        defer { restoreMotion() }
        let input = HideAnimationInput()
        let root = input.window.contentView.layer
        root.filters = [try transitionFilter(name: "existingBlur", radius: 3)]
        input.host.setValue(false, forKey: "wantsLauncherVisible")
        try show(input)
        #expect(root.filters?.count == 2 && namedTransitionFilter(root) != nil)

        if interruptedByHide {
            try await Task.sleep(for: .milliseconds(200))
            input.host.hideLauncher()
            try await Task.sleep(for: .milliseconds(220))
            #expect(root.animation(forKey: "launcheer.dissolve") != nil && namedTransitionFilter(root) != nil)
            #expect(input.window.orderOutCount == 0)
            try await Task.sleep(for: .milliseconds(280))
            #expect(input.window.orderOutCount == 1)
        } else {
            try await Task.sleep(for: .milliseconds(480))
            #expect(input.host.wantsLauncherVisible && input.window.orderOutCount == 0)
        }
        #expect(namedTransitionFilter(root) == nil && root.animation(forKey: "launcheer.dissolve") == nil)
        let filters = try #require(root.filters as? [NSObject])
        #expect(filters.count == 1)
        #expect(filters.first?.value(forKey: "name") as? String == "existingBlur")
        #expect((filters.first?.value(forKey: "inputRadius") as? NSNumber)?.doubleValue == 3)
        if !interruptedByHide { try immediateHide(input.host) }
        #expect(NSApp == nil)
    }

    @Test func disablingAnimationsMakesShowingAndHidingImmediate() async throws {
        let restoreMotion = try interceptHideMotion(false, animationsDisabled: { true })
        defer { restoreMotion() }
        let input = HideAnimationInput()
        input.host.setValue(false, forKey: "wantsLauncherVisible")
        let layers = input.transitionLayers
        let model = layers[0].transform
        let checkBeforeOrdering = {
            for layer in layers {
                #expect(layer.animation(forKey: "launcheer.show") == nil && layer.animation(forKey: "launcheer.hide") == nil && layer.animation(forKey: "launcheer.dissolve") == nil)
            }
        }
        input.window.onOrderFront = checkBeforeOrdering
        input.cover.onOrderFront = checkBeforeOrdering

        try show(input)

        #expect(input.host.wantsLauncherVisible && !input.window.ignoresMouseEvents && !input.cover.ignoresMouseEvents)
        #expect(input.window.orderFrontCount == 1 && input.cover.orderFrontCount == 1)
        #expect(input.host.value(forKey: "hideTask") == nil)
        input.host.hideLauncher()
        #expect(input.window.orderOutCount == 1 && input.cover.orderOutCount == 1)
        #expect(input.cleanupWasHidden && !input.springboard.visible && !input.host.wantsLauncherVisible)
        #expect(input.host.value(forKey: "hideTask") == nil)
        for layer in layers {
            #expect(layer.animation(forKey: "launcheer.show") == nil && layer.animation(forKey: "launcheer.hide") == nil && layer.animation(forKey: "launcheer.dissolve") == nil)
            #expect(layer.opacity == 1)
        }
        #expect(CATransform3DEqualToTransform(layers[0].transform, model))
        #expect(namedTransitionFilter(layers[0]) == nil)
        try await Task.sleep(for: .milliseconds(480))
        #expect(input.window.orderOutCount == 1 && input.springboard.closeCount == 1)
        #expect(NSApp == nil)
    }

    @Test(arguments: [false, true])
    func disablingAnimationsFinishesAnExistingTransition(showing: Bool) async throws {
        var disabled = false
        let restoreMotion = try interceptHideMotion(false, animationsDisabled: { disabled })
        defer { restoreMotion() }
        let input = HideAnimationInput()
        if showing {
            input.host.setValue(false, forKey: "wantsLauncherVisible")
            try show(input)
        } else {
            input.host.hideLauncher()
        }
        let key = showing ? "launcheer.show" : "launcheer.hide"
        let layers = input.transitionLayers
        input.host.applyAnimationSettings()
        #expect([input.window.contentView.layer, input.cover.contentView.layer].allSatisfy { $0.animation(forKey: key) != nil })
        #expect(namedTransitionFilter(input.window.contentView.layer) != nil)

        disabled = true
        input.host.applyAnimationSettings()

        for layer in layers {
            #expect(layer.animation(forKey: "launcheer.show") == nil && layer.animation(forKey: "launcheer.hide") == nil && layer.animation(forKey: "launcheer.dissolve") == nil)
            #expect(layer.opacity == 1)
        }
        #expect(input.host.value(forKey: "hideTask") == nil)
        #expect(namedTransitionFilter(input.window.contentView.layer) == nil)
        #expect(input.host.wantsLauncherVisible == showing)
        #expect(input.window.orderOutCount == (showing ? 0 : 1))
        #expect(showing ? !input.window.ignoresMouseEvents : input.cleanupWasHidden)
        try await Task.sleep(for: .milliseconds(480))
        #expect(input.window.orderOutCount == (showing ? 0 : 1))
        #expect(input.springboard.closeCount == (showing ? 0 : 1))
        #expect(NSApp == nil)
    }

    @Test func theDeadlineOrdersOutBeforeCleaningNativeContent() async throws {
        let restoreMotion = try interceptHideMotion(false)
        defer { restoreMotion() }
        let input = HideAnimationInput()
        input.host.hideLauncher()
        input.host.hideLauncher()
        #expect(input.springboard.visible && input.springboard.closeCount == 0 && input.searchClearCount == 0)

        try await Task.sleep(for: .milliseconds(480))

        #expect(input.window.orderOutCount == 1 && input.cover.orderOutCount == 1)
        #expect(input.springboard.closeCount == 1 && input.searchClearCount == 1 && input.cleanupWasHidden)
        #expect(!input.springboard.visible && input.springboard.completedDragCount == 1)
        #expect(namedTransitionFilter(input.window.contentView.layer) == nil && input.window.contentView.layer.animation(forKey: "launcheer.dissolve") == nil)
        for layer in input.transitionLayers { #expect(layer.animation(forKey: "launcheer.hide") == nil) }
        #expect(input.host.value(forKey: "hideTask") == nil)
        #expect(NSApp == nil)
    }

    @Test(arguments: ["reopen", "newHide", "synchronousReopen"])
    func reopeningInvalidatesTheOlderDeadline(interruption: String) throws {
        let restoreMotion = try interceptHideMotion(false)
        defer { restoreMotion() }
        let input = HideAnimationInput()
        let reservedDockFrame = CGRect(x: 0, y: 70, width: 800, height: 506)
        input.view.visibleFrame = reservedDockFrame
        input.window.screen.visibleFrame = input.window.screen.frame
        let queued = [URL(fileURLWithPath: "/Applications/Queued While Hiding Fixture.app")]
        var observation: NSKeyValueObservation?
        if interruption == "synchronousReopen" {
            observation = input.host.observe(\.wantsLauncherVisible, options: [.new]) { [weak input] host, _ in
                MainActor.assumeIsolated {
                    if !host.wantsLauncherVisible, let input {
                        input.host.reloadItems(queued)
                        do {
                            input.olderDeadline = try pendingHideDeadline(input.host)
                            try show(input)
                        } catch { Issue.record(error) }
                    }
                }
            }
        }
        input.host.hideLauncher()
        if interruption == "synchronousReopen" {
            observation?.invalidate()
        } else {
            input.olderDeadline = try pendingHideDeadline(input.host)
            input.host.reloadItems(queued)
            try show(input)
        }
        #expect(input.host.wantsLauncherVisible && !input.window.ignoresMouseEvents)
        #expect(input.view.visibleFrame == reservedDockFrame)
        #expect(input.host.appliedItems == queued && input.host.value(forKey: "pendingItems") == nil)
        for layer in input.transitionLayers { #expect(layer.animation(forKey: "launcheer.hide") == nil) }
        #expect(input.host.value(forKey: "hideTask") == nil)

        let oldDeadline = try #require(input.olderDeadline)
        if interruption == "newHide" {
            input.host.hideLauncher()
            let currentDeadline = try pendingHideDeadline(input.host)
            oldDeadline()
            #expect(input.window.orderOutCount == 0 && input.cover.orderOutCount == 0 && input.springboard.visible)
            currentDeadline()
            #expect(input.window.orderOutCount == 1 && input.cover.orderOutCount == 1 && !input.springboard.visible)
            currentDeadline()
            #expect(input.window.orderOutCount == 1 && input.cover.orderOutCount == 1 && input.springboard.closeCount == 1)
        } else {
            oldDeadline()
            #expect(input.window.orderOutCount == 0 && input.cover.orderOutCount == 0)
            #expect(input.host.wantsLauncherVisible && input.springboard.visible && !input.window.ignoresMouseEvents)
            try immediateHide(input.host)
        }
        #expect(NSApp == nil)
    }

    @Test(arguments: [false, true])
    func resigningActiveFinishesImmediatelyAndReloadsWaitForTheTransition(showing: Bool) async throws {
        let restoreMotion = try interceptHideMotion(false)
        defer { restoreMotion() }
        let input = HideAnimationInput()
        if showing {
            input.host.setValue(false, forKey: "wantsLauncherVisible")
            try show(input)
        } else {
            input.host.hideLauncher()
            let items = [URL(fileURLWithPath: "/Applications/Hide Animation Fixture.app")]
            input.host.reloadItems(items)
            #expect(input.host.value(forKey: "pendingItems") as? [URL] == items)
            let apply = NSSelectorFromString("applyPendingItems")
            let method = try #require(class_getInstanceMethod(NativeHost.self, apply))
            typealias Callback = @convention(c) (AnyObject, Selector) -> Void
            unsafeBitCast(method_getImplementation(method), to: Callback.self)(input.host, apply)
            #expect(input.host.value(forKey: "pendingItems") as? [URL] == items)
            // The test stops before a real layout reload; no user layout is read or saved.
            input.host.setValue(nil, forKey: "pendingItems")
        }
        let selector = NSSelectorFromString("applicationDidResignActive:")
        let resign = try #require(class_getInstanceMethod(NativeHost.self, selector))
        typealias Resign = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        unsafeBitCast(method_getImplementation(resign), to: Resign.self)(input.host, selector, nil)

        #expect(input.window.orderOutCount == 1 && input.cover.orderOutCount == 1)
        #expect(input.cleanupWasHidden && !input.springboard.visible && input.springboard.completedDragCount == 1)
        #expect(input.host.value(forKey: "hideTask") == nil)
        #expect(namedTransitionFilter(input.window.contentView.layer) == nil)
        for layer in input.transitionLayers {
            #expect(layer.animation(forKey: "launcheer.show") == nil && layer.animation(forKey: "launcheer.hide") == nil && layer.animation(forKey: "launcheer.dissolve") == nil)
        }
        try await Task.sleep(for: .milliseconds(480))
        #expect(input.window.orderOutCount == 1 && input.springboard.closeCount == 1)
        #expect(NSApp == nil)
    }
}

@MainActor
private func visibilityAnimation(_ layer: CALayer, key: String) throws -> CABasicAnimation {
    try #require(layer.animation(forKey: key) as? CABasicAnimation)
}

@MainActor
private func visibilityComponent(_ animation: CABasicAnimation, keyPath: String) throws -> CABasicAnimation {
    try #require(animation.keyPath == keyPath)
    return animation
}

@MainActor
private func sampledVisibility(opacity: Float, blurRadius: CGFloat? = nil) throws -> HideAnimationSurfaceLayer {
    let layer = HideAnimationSurfaceLayer()
    layer.opacity = opacity
    if let blurRadius { layer.filters = [try transitionFilter(name: "launcheerDissolve", radius: blurRadius)] }
    return layer
}

@MainActor
private func transitionFilter(name: String, radius: CGFloat) throws -> NSObject {
    let type: AnyClass = try #require(NSClassFromString("CAFilter"))
    let selector = NSSelectorFromString("filterWithType:")
    let method = try #require(class_getClassMethod(type, selector))
    typealias Factory = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    let make = unsafeBitCast(method_getImplementation(method), to: Factory.self)
    let filter = try #require(make(type as AnyObject, selector, "gaussianBlur")?.takeUnretainedValue() as? NSObject)
    filter.setValue(name, forKey: "name")
    filter.setValue(radius, forKey: "inputRadius")
    return filter
}

private func namedTransitionFilter(_ layer: CALayer) -> NSObject? {
    (layer.filters as? [NSObject])?.first { $0.value(forKey: "name") as? String == "launcheerDissolve" }
}

@MainActor
private func interceptHideMotion(_ reduceMotion: Bool, animationsDisabled: @escaping () -> Bool = { false }) throws -> () -> Void {
    let method = try #require(class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString("accessibilityDisplayShouldReduceMotion")))
    let defaultsSelector = NSSelectorFromString("boolForKey:")
    let defaultsMethod = try #require(class_getInstanceMethod(UserDefaults.self, defaultsSelector))
    let previousDefaults = method_getImplementation(defaultsMethod)
    typealias ReadBool = @convention(c) (AnyObject, Selector, NSString) -> Bool
    let read = unsafeBitCast(previousDefaults, to: ReadBool.self)
    let defaultsBlock: @convention(block) (AnyObject, NSString) -> Bool = { receiver, key in
        if key == "animations.disabled" { return animationsDisabled() }
        return read(receiver, defaultsSelector, key)
    }
    let defaultsImplementation = imp_implementationWithBlock(defaultsBlock)
    method_setImplementation(defaultsMethod, defaultsImplementation)
    let block: @convention(block) (AnyObject) -> Bool = { _ in reduceMotion }
    let implementation = imp_implementationWithBlock(block)
    let previous = method_setImplementation(method, implementation)
    return {
        method_setImplementation(method, previous)
        method_setImplementation(defaultsMethod, previousDefaults)
        imp_removeBlock(implementation)
        imp_removeBlock(defaultsImplementation)
    }
}

@MainActor
private func immediateHide(_ host: NativeHost) throws {
    let selector = NSSelectorFromString("hideLauncherImmediately")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Hide = @convention(c) (AnyObject, Selector) -> Void
    unsafeBitCast(method_getImplementation(method), to: Hide.self)(host, selector)
}

@MainActor
private func pendingHideDeadline(_ host: NativeHost) throws -> @convention(block) () -> Void {
    let task = try #require(host.value(forKey: "hideTask")) as AnyObject
    return unsafeBitCast(task, to: (@convention(block) () -> Void).self)
}

@MainActor
private func show(_ input: HideAnimationInput) throws {
    let selector = NSSelectorFromString("showLauncherOnScreen:")
    let method = try #require(class_getInstanceMethod(NativeHost.self, selector))
    typealias Show = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    unsafeBitCast(method_getImplementation(method), to: Show.self)(input.host, selector, input.window.screen)
}

@MainActor
private final class HideAnimationInput {
    let host = HideAnimationHost()
    let window = HideAnimationWindow()
    let cover = HideAnimationWindow()
    let view = HideAnimationView()
    let backgroundView = HideAnimationSurface()
    let springboard = HideAnimationSpringboard()
    let icon = CALayer()
    var olderDeadline: (@convention(block) () -> Void)?
    var transitionLayers: [HideAnimationSurfaceLayer] { [window.contentView.layer, cover.contentView.layer, view.backdrop, backgroundView.layer] }
    private(set) var cleanupWasHidden = true
    private(set) var searchClearCount = 0

    init(anchor: CGFloat = 0.5) {
        let layer = window.contentView.layer
        layer.bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        layer.anchorPoint = CGPoint(x: anchor, y: anchor)
        layer.transform = CATransform3DMakeTranslation(7, -3, 0)
        for background in [view.backdrop, backgroundView.layer] {
            background.bounds = layer.bounds
            background.anchorPoint = layer.anchorPoint
        }
        view.backdrop.transform = CATransform3DMakeTranslation(7, -3, 0)
        backgroundView.layer.transform = CATransform3DMakeTranslation(-4, 9, 0)
        backgroundView.layer.isHidden = true
        layer.addSublayer(backgroundView.layer)
        layer.addSublayer(view.layer)
        view.layer.addSublayer(view.backdrop)
        view.layer.addSublayer(springboard.layer)
        icon.frame = CGRect(x: 120, y: 180, width: 80, height: 80)
        springboard.layer.addSublayer(icon)
        springboard.pager = view.pager
        springboard.onClose = { [weak self] in
            guard let self else { return }
            cleanupWasHidden = cleanupWasHidden && window.orderOutCount > 0 && cover.orderOutCount > 0
        }
        springboard.layer.searchTextInputLayer.onClear = { [weak self] in
            guard let self else { return }
            searchClearCount += 1
            cleanupWasHidden = cleanupWasHidden && window.orderOutCount > 0 && cover.orderOutCount > 0
        }
        host.setValue(window, forKey: "window")
        host.setValue(cover, forKey: "menuBarCoverWindow")
        host.setValue(view, forKey: "view")
        host.setValue(backgroundView, forKey: "backgroundView")
        host.setValue(springboard, forKey: "springboard")
        host.setValue(128, forKey: "iconPixelSize")
        host.setValue(true, forKey: "wantsLauncherVisible")
    }
}

private final class HideAnimationHost: NativeHost {
    private(set) var appliedItems: [URL]?
    @objc func applyPendingItems() {
        appliedItems = value(forKey: "pendingItems") as? [URL]
        setValue(nil, forKey: "pendingItems")
    }
    @objc(updateBackgroundMaterial:)
    func updateBackgroundMaterial(_ notification: NSNotification?) {}
    @objc(updateMenuBarCoverForScreen:)
    func updateMenuBarCover(_ screen: NSObject) {}
    @objc(prepareDesktopForScreen:)
    func prepareDesktop(_ screen: NSObject) {}
}

@MainActor
private final class HideAnimationWindow: NSObject {
    @objc let contentView = HideAnimationSurface()
    @objc let screen = HideAnimationScreen()
    @objc var ignoresMouseEvents = false
    @objc var isKeyWindow: Bool { false }
    private(set) var orderOutCount = 0
    private(set) var orderFrontCount = 0
    var onOrderFront: (() -> Void)?
    @objc func orderOut(_ sender: NSObject?) { orderOutCount += 1 }
    @objc func makeKeyAndOrderFront(_ sender: NSObject?) { orderFront(sender) }
    @objc func orderFront(_ sender: NSObject?) { orderFrontCount += 1; onOrderFront?() }
    @objc func makeFirstResponder(_ responder: NSObject?) -> Bool { true }
    @objc(setFrame:display:)
    func setFrame(_ frame: NSRect, display: Bool) {}
}

@MainActor
private final class HideAnimationSurface: NSObject {
    @objc let layer = HideAnimationSurfaceLayer()
}

private final class HideAnimationSurfaceLayer: CALayer {
    var sampledPresentation: HideAnimationSurfaceLayer?
    private var submitted: [String: CAAnimation] = [:]
    // Layers without a render tree discard show animations at flush; retain their exact submitted values until removal.
    override func add(_ animation: CAAnimation, forKey key: String?) {
        if let key { submitted[key] = animation.copy() as? CAAnimation }
    }
    override func animation(forKey key: String) -> CAAnimation? { submitted[key]?.copy() as? CAAnimation }
    override func removeAnimation(forKey key: String) { submitted.removeValue(forKey: key) }
    override func removeAllAnimations() { submitted.removeAll() }
    override func presentation() -> Self? { sampledPresentation as? Self }
}

@MainActor
private final class HideAnimationScreen: NSObject {
    @objc let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    @objc var visibleFrame = CGRect(x: 0, y: 70, width: 800, height: 506)
    @objc let backingScaleFactor: CGFloat = 1
}

@MainActor
private final class HideAnimationView: NSObject {
    @objc let layer = CALayer()
    @objc let backdrop = HideAnimationSurfaceLayer()
    @objc let pager = HideAnimationPager()
    @objc var downLayer: CALayer? = CALayer()
    @objc var downPage: NSObject? = NSObject()
    @objc var downHitLayer: CALayer? = CALayer()
    @objc var downSearch = true
    @objc var visibleFrame = CGRect.zero
    @objc var layoutBounds = CGRect.null
    @objc var needsLayout = false
    @objc func activePager() -> HideAnimationPager { pager }
    @objc(scrollGesture:phase:)
    func scrollGesture(_ event: NSObject, phase: Int64) {}
}

@MainActor
private final class HideAnimationPager: NSObject {
    @objc var currentPageIndex: UInt = 1
    @objc func currentPage() -> NSObject? { nil }
    @objc func setEditing(_ editing: Bool) {}
    @objc func setDeleting(_ deleting: Bool) {}
}

@MainActor
private final class HideAnimationSpringboard: NSObject {
    @objc let layer = HideAnimationLayer()
    @objc var pager: HideAnimationPager?
    @objc var visible = true
    @objc var dragging = true
    private(set) var completedDragCount = 0
    private(set) var closeCount = 0
    var onClose: (() -> Void)?
    @objc func cancelDrag(_ animated: Bool) {
        if dragging { completedDragCount += 1; dragging = false }
    }
    @objc func setGroupShown(_ shown: Bool) { if !shown { closeCount += 1; onClose?() } }
}

private final class HideAnimationSearch: NSObject {
    @objc var stringValue = "query" { didSet { if stringValue.isEmpty { onClear?() } } }
    @objc var hasFocus = true
    var onClear: (() -> Void)?
}

private final class HideAnimationLayer: CALayer {
    @objc var searchTextInputLayer = HideAnimationSearch()
}
