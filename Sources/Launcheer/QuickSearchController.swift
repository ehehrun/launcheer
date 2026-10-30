import AppKit

@MainActor
final class QuickSearchController: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var model: QuickSearchModel
    private let iconProvider: (URL) -> NSImage?
    private let search = NSTextField()
    private let clearButton = NSButton()
    private let table = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "未找到应用")
    private var availableHeight: CGFloat = 0
    private static let contentPadding: CGFloat = 116

    init(items: [URL], iconProvider: @escaping (URL) -> NSImage?) {
        model = QuickSearchModel(items: items)
        self.iconProvider = iconProvider
        super.init(window: nil)
        buildWindow()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildWindow() {
        let panel = QuickSearchPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 532), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.delegate = self

        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer!.cornerRadius = 18
        material.layer!.masksToBounds = true
        let mask = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        mask.resizingMode = .stretch
        material.maskImage = mask
        panel.contentView = material

        let searchIcon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "搜索")!)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.imageScaling = .scaleProportionallyUpOrDown
        search.font = .systemFont(ofSize: 22)
        search.placeholderAttributedString = NSAttributedString(string: "搜索应用", attributes: [
            .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.placeholderTextColor
        ])
        search.isBordered = false
        search.isBezeled = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.maximumNumberOfLines = 1
        search.cell!.usesSingleLineMode = true
        search.lineBreakMode = .byClipping
        search.delegate = self
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "清空搜索")
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.isBordered = false
        clearButton.refusesFirstResponder = true
        clearButton.target = self
        clearButton.action = #selector(clearSearch(_:))
        clearButton.toolTip = "清空搜索"
        clearButton.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("application"))
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 52
        table.intercellSpacing = .zero
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(openClicked(_:))
        scroll.documentView = table

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        let hint = NSTextField(labelWithString: "↑↓ 选择    ↩ 打开    esc 关闭")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        for view in [searchIcon, search, clearButton, separator, scroll, emptyLabel, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(view)
        }
        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 26),
            searchIcon.topAnchor.constraint(equalTo: material.topAnchor, constant: 26),
            searchIcon.widthAnchor.constraint(equalToConstant: 20),
            searchIcon.heightAnchor.constraint(equalToConstant: 20),
            search.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -12),
            search.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            search.heightAnchor.constraint(equalToConstant: 30),
            clearButton.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -22),
            clearButton.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 24),
            clearButton.heightAnchor.constraint(equalToConstant: 24),
            separator.topAnchor.constraint(equalTo: material.topAnchor, constant: 72),
            separator.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),
            hint.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 22),
            hint.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
        window = panel
    }

    func updateItems(_ items: [URL]) {
        model.updateItems(items)
        if window!.isVisible { reloadResults() }
    }

    func refreshIcon(for url: URL) {
        guard window!.isVisible,
              let row = model.results.firstIndex(where: { $0.url == url }),
              table.rect(ofRow: row).intersects(table.visibleRect),
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let image = iconProvider(url) else { return }
        cell.imageView!.image = image
    }

    func toggle() {
        if window!.isVisible { hide(); return }
        let panel = window!
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main!
        let visible = screen.visibleFrame
        availableHeight = visible.height - 48
        search.stringValue = ""
        model.search("")
        let width = min(640, visible.width - 48)
        let height = min(Self.contentPadding + CGFloat(max(1, model.results.count)) * 52, availableHeight)
        let top = visible.maxY - visible.height * 0.18
        panel.setFrame(NSRect(x: visible.midX - width / 2, y: max(visible.minY + 24, top - height), width: width, height: height), display: false)
        reloadResults()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        let panel = window!
        let wasKey = panel.isKeyWindow
        panel.orderOut(nil)
        if wasKey { NSApp.deactivate() }
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    func controlTextDidChange(_ notification: Notification) {
        model.search(search.stringValue)
        reloadResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if textView.hasMarkedText() { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelection(by: -1)
            updateSelection()
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelection(by: 1)
            updateSelection()
        case #selector(NSResponder.insertNewline(_:)):
            openSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
        default: return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { model.results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { QuickSearchRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("quickSearchResult")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            let title = NSTextField(labelWithString: "")
            title.font = .systemFont(ofSize: 16, weight: .medium)
            title.lineBreakMode = .byTruncatingTail
            for view in [image, title] {
                view.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(view)
            }
            cell.imageView = image
            cell.textField = title
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 36),
                image.heightAnchor.constraint(equalToConstant: 36),
                title.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12),
                title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                title.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let item = model.results[row]
        cell.textField!.stringValue = item.name
        cell.imageView!.image = iconProvider(item.url) ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { model.select(table.selectedRow) }

    private func reloadResults() {
        let selection = model.selectedIndex
        table.reloadData()
        if let selection { model.select(selection) }
        emptyLabel.isHidden = !model.results.isEmpty
        clearButton.isHidden = search.stringValue.isEmpty
        updateSelection()
        let panel = window!
        let height = min(Self.contentPadding + CGFloat(max(1, model.results.count)) * 52, availableHeight)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func updateSelection() {
        if let selection = model.selectedIndex {
            table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
            table.scrollRowToVisible(selection)
        } else { table.deselectAll(nil) }
    }

    @objc private func openClicked(_ sender: NSTableView) {
        guard sender.clickedRow >= 0 else { return }
        model.select(sender.clickedRow)
        openSelected()
    }

    @objc private func clearSearch(_ sender: NSButton) {
        if let editor = search.currentEditor() as? NSTextView {
            editor.unmarkText()
            editor.string = ""
        }
        search.stringValue = ""
        model.search("")
        reloadResults()
        window!.makeFirstResponder(search)
    }

    @objc private func openSelected() {
        guard let item = model.selectedItem else { return }
        hide()
        NSWorkspace.shared.openApplication(at: item.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSAlert(error: error).runModal()
                }
            }
        }
    }
}

private final class QuickSearchRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 4), xRadius: 10, yRadius: 10).fill()
    }
}

private final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
