import AppKit
import NativeLaunchpad

@MainActor
final class AutoArrangeSettingsView: NSView {
    private let onArrange: () -> Void
    private let onSavedPresets: () throws -> [NativeSavedPreset]
    private let onSavePreset: (String) throws -> String
    private let preset = NSPopUpButton()
    private let explanation = NSTextField(wrappingLabelWithString: "")
    private let presets: [AutoArrangePreset] = [.none, .categories, .system]
    private let ruleStack = AutoArrangeRuleStack()
    private var ruleEditor: NSStackView!
    private let status = NSTextField(wrappingLabelWithString: "")
    private var rows: [AutoArrangeRuleRow] = []
    private var savedRules: [AutoArrangeRule] = []
    private var savedPresets: [NativeSavedPreset] = []
    private var saveButton: NSButton!
    private var arrangeButton: NSButton!
    private var savePresetButton: NSButton!
    private var loaded = false

    init(onArrange: @escaping () -> Void,
         onSavedPresets: @escaping () throws -> [NativeSavedPreset],
         onSavePreset: @escaping (String) throws -> String) {
        self.onArrange = onArrange
        self.onSavedPresets = onSavedPresets
        self.onSavePreset = onSavePreset
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let heading = NSTextField(labelWithString: "智能整理")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let commands = NSTextField(wrappingLabelWithString: "在启动台输入 /智能整理 或 /autobuild，应用已保存的模式。")
        commands.font = .systemFont(ofSize: 12)
        setPresets([])
        preset.target = self
        preset.action = #selector(changePreset(_:))
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor

        let headers = horizontal([
            label("App 类型", width: 112), label("名称包含", width: 120),
            label("目标文件夹", width: 138), label("优先顺序", width: 84)
        ])
        headers.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        ruleStack.orientation = .vertical
        ruleStack.distribution = .fill
        ruleStack.alignment = .leading
        ruleStack.spacing = 8
        ruleStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        ruleStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = ruleStack
        NSLayoutConstraint.activate([
            ruleStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            ruleStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            ruleStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        let add = NSButton(title: "添加规则", target: self, action: #selector(addRule(_:)))
        let restore = NSButton(title: "恢复默认设置", target: self, action: #selector(restoreRules(_:)))
        saveButton = NSButton(title: "保存设置", target: self, action: #selector(saveRules(_:)))
        arrangeButton = NSButton(title: "立即应用", target: self, action: #selector(arrangeNow(_:)))
        savePresetButton = NSButton(title: "另存为新分类…", target: self, action: #selector(savePreset(_:)))
        status.font = .systemFont(ofSize: 12)
        let footer = NSTextField(wrappingLabelWithString: "分类规则从上到下匹配；类型与名称条件需同时满足。留空表示不限，未匹配的 App 保持原样。")
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .secondaryLabelColor

        ruleEditor = NSStackView(views: [headers, scroll, add, footer])
        ruleEditor.orientation = .vertical
        ruleEditor.alignment = .leading
        ruleEditor.spacing = 10
        let persistence = NSTextField(wrappingLabelWithString: "布局分别保存，互不覆盖；重新应用内置分类仍会按规则整理，命名分类只保留手动排列。保存设置不改布局，立即应用或输入命令才切换并应用。")
        persistence.font = .systemFont(ofSize: 12)
        persistence.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, commands, preset, explanation, ruleEditor,
                                       persistence, status,
                                       horizontal([savePresetButton, restore, saveButton, arrangeButton])])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            ruleEditor.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: ruleEditor.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            commands.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: ruleEditor.widthAnchor),
            persistence.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        let scrollHeight = scroll.heightAnchor.constraint(equalToConstant: 220)
        scrollHeight.priority = .defaultLow
        scrollHeight.isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    func reload() {
        do {
            let settings = try AutoArrangeSettings.load()
            let saved = try onSavedPresets()
            let selection: Int
            if let id = settings.customPreset {
                guard let index = saved.firstIndex(where: { $0.id == id }) else {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                                  userInfo: [NSLocalizedDescriptionKey: "已选的命名分类不存在，请恢复默认设置后重新选择。"])
                }
                selection = presets.count + index
            } else {
                selection = presets.firstIndex(of: settings.preset)!
            }
            setPresets(saved)
            preset.selectItem(at: selection)
            savedRules = settings.rules
            replaceRows(settings.rules)
            loaded = true
            status.stringValue = ""
        } catch {
            loaded = false
            show(error)
        }
        updateControls()
    }

    @objc private func changePreset(_ sender: NSPopUpButton) {
        status.stringValue = "模式已更改，保存后供命令使用。"
        status.textColor = .secondaryLabelColor
        updateControls()
    }

    private func updateControls() {
        let index = preset.indexOfSelectedItem
        let categories = index == 1
        if index < presets.count {
            switch presets[index] {
            case .none:
                explanation.stringValue = "展开全部分组，按当前顺序平铺应用；每页最多35个。"
            case .categories:
                explanation.stringValue = "依据 App 声明的类型和名称过滤条件，整理到对应文件夹。可调整下方规则。"
            case .system:
                explanation.stringValue = "系统应用排在前面，其他应用另起页。每页最多35个，超过后续页；不创建分类文件夹。"
            }
        } else {
            explanation.stringValue = "使用这份命名分类的手动排列，不重新执行智能分组。"
        }
        preset.isEnabled = loaded
        saveButton.isEnabled = loaded
        arrangeButton.isEnabled = loaded
        savePresetButton.isEnabled = loaded
        ruleEditor.isHidden = !categories || !loaded
    }

    private func setPresets(_ saved: [NativeSavedPreset]) {
        savedPresets = saved
        preset.removeAllItems()
        preset.addItems(withTitles: ["不分类（默认）", "智能分类", "二分类"])
        preset.addItems(withTitles: saved.map { "已保存：\($0.title)" })
    }

    private func replaceRows(_ rules: [AutoArrangeRule]) {
        for view in ruleStack.arrangedSubviews {
            ruleStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rows = rules.map { rule in
            AutoArrangeRuleRow(rule: rule) { [weak self] row, offset in
                self?.move(row, offset: offset)
            }
        }
        rows.forEach { ruleStack.addArrangedSubview($0) }
        ruleStack.scroll(.zero)
    }

    @objc private func addRule(_ sender: NSButton) {
        let row = AutoArrangeRuleRow(rule: AutoArrangeRule(id: UUID(), title: "", category: "", nameContains: "")) { [weak self] row, offset in
            self?.move(row, offset: offset)
        }
        rows.append(row)
        ruleStack.addArrangedSubview(row)
        ruleStack.layoutSubtreeIfNeeded()
        row.scrollToVisible(row.bounds)
        window?.makeFirstResponder(row.titleField)
    }

    private func move(_ row: AutoArrangeRuleRow, offset: Int) {
        guard let index = rows.firstIndex(where: { $0 === row }) else { return }
        if offset == 0 {
            rows.remove(at: index)
            ruleStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        } else {
            let target = index + offset
            guard rows.indices.contains(target) else { return }
            rows.swapAt(index, target)
            ruleStack.insertArrangedSubview(row, at: target)
        }
    }

    @objc private func restoreRules(_ sender: NSButton) {
        do {
            let saved = try onSavedPresets()
            savedRules = AutoArrangeSettings.defaultRules
            replaceRows(savedRules)
            setPresets(saved)
            preset.selectItem(at: 0)
            loaded = true
            status.stringValue = "已恢复默认不分类和内置分类规则，点击保存设置后生效。"
            status.textColor = .secondaryLabelColor
        } catch {
            show(error)
        }
        updateControls()
    }

    @discardableResult
    private func save() -> Bool {
        window?.makeFirstResponder(nil)
        do {
            let index = preset.indexOfSelectedItem
            let selected = index < presets.count ? presets[index] : .none
            let custom = index < presets.count ? nil : savedPresets[index - presets.count].id
            let rules = selected == .categories ? rows.map(\.rule) : savedRules
            guard rules.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError,
                              userInfo: [NSLocalizedDescriptionKey: "请为每条规则填写目标文件夹名称。"])
            }
            try AutoArrangeSettings(preset: selected, rules: rules, customPreset: custom).save()
            savedRules = rules
            status.stringValue = "设置已保存，应用后切换布局。"
            status.textColor = .secondaryLabelColor
            return true
        } catch {
            show(error)
            return false
        }
    }

    @objc private func saveRules(_ sender: NSButton) { save() }
    @objc private func arrangeNow(_ sender: NSButton) {
        if save() { onArrange() }
    }

    @objc private func savePreset(_ sender: NSButton) {
        guard let window else { return }
        window.makeFirstResponder(nil)
        let alert = NSAlert()
        alert.messageText = "另存为新分类"
        alert.informativeText = "保存启动台当前正在使用的布局，不会应用设置中尚未切换的模式，也不会覆盖已有分类。"
        let name = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        name.placeholderString = "分类名称"
        alert.accessoryView = name
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = name
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let title = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                show(NSError(domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError,
                             userInfo: [NSLocalizedDescriptionKey: "请填写新分类名称。"]))
                return
            }
            let selection = preset.indexOfSelectedItem
            let previousSavedID = selection < presets.count ? nil : savedPresets[selection - presets.count].id
            let savedID: String
            do {
                savedID = try onSavePreset(title)
            } catch {
                show(error)
                return
            }
            do {
                let saved = try onSavedPresets()
                guard saved.contains(where: { $0.id == savedID }) else {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                                  userInfo: [NSLocalizedDescriptionKey: "列表中找不到刚保存的分类。"])
                }
                let restoredSelection: Int
                if let previousSavedID {
                    guard let index = saved.firstIndex(where: { $0.id == previousSavedID }) else {
                        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                                      userInfo: [NSLocalizedDescriptionKey: "先前选择的分类已不存在，请重新打开设置。"])
                    }
                    restoredSelection = presets.count + index
                } else {
                    restoredSelection = selection
                }
                setPresets(saved)
                preset.selectItem(at: restoredSelection)
                status.stringValue = "已保存当前布局为“\(title)”。可在模式列表选中并点击立即应用。"
                status.textColor = .secondaryLabelColor
            } catch {
                status.stringValue = "“\(title)”已保存，但分类列表读取失败：\(error.localizedDescription)"
                status.textColor = .systemRed
            }
            updateControls()
        }
    }

    private func show(_ error: Error) {
        status.stringValue = error.localizedDescription
        status.textColor = .systemRed
    }

    private func label(_ title: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func horizontal(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }
}

@MainActor
private final class AutoArrangeRuleStack: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class AutoArrangeRuleRow: NSStackView {
    private let id: UUID
    private let category = NSPopUpButton()
    private let nameField = NSTextField()
    let titleField = NSTextField()
    private let onMove: (AutoArrangeRuleRow, Int) -> Void

    init(rule: AutoArrangeRule, onMove: @escaping (AutoArrangeRuleRow, Int) -> Void) {
        id = rule.id
        self.onMove = onMove
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        category.addItem(withTitle: "任意类型")
        category.addItems(withTitles: AutoArrange.categories.map(\.title))
        let selectedCategory = rule.category.isEmpty ? 0 : AutoArrange.categories.firstIndex(where: { $0.id == rule.category })! + 1
        category.selectItem(at: selectedCategory)
        nameField.stringValue = rule.nameContains
        nameField.placeholderString = "不限名称"
        titleField.stringValue = rule.title
        titleField.placeholderString = "文件夹名称"
        for (view, width) in [(category as NSView, 112.0), (nameField, 120.0), (titleField, 138.0)] {
            addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        for (title, offset) in [("↑", -1), ("↓", 1), ("−", 0)] {
            let button = NSButton(title: title, target: self, action: #selector(move(_:)))
            button.tag = offset
            button.toolTip = offset == 0 ? "删除规则" : (offset < 0 ? "提高优先级" : "降低优先级")
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            addArrangedSubview(button)
        }
        for control in arrangedSubviews.compactMap({ $0 as? NSControl }) { control.controlSize = .small }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var rule: AutoArrangeRule {
        AutoArrangeRule(id: id, title: titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                        category: category.indexOfSelectedItem == 0 ? "" : AutoArrange.categories[category.indexOfSelectedItem - 1].id,
                        nameContains: nameField.stringValue)
    }

    @objc private func move(_ sender: NSButton) { onMove(self, sender.tag) }
}
