import Foundation
import NativeLaunchpad

enum AutoArrangePreset: String, CaseIterable, Codable, Sendable {
    case none, categories, system

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "unused" { self = .none }
        else if let preset = Self(rawValue: value) { self = preset }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown arrangement mode: \(value)") }
    }
}

struct AutoArrangeRule: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var category: String
    var nameContains: String
}

struct AutoArrangeSettings: Codable, Equatable, Sendable {
    var preset: AutoArrangePreset
    var rules: [AutoArrangeRule]
    var customPreset: String? = nil

    var selectedPresetID: String { customPreset ?? preset.rawValue }

    static var defaultRules: [AutoArrangeRule] {
        AutoArrange.categories.map {
            AutoArrangeRule(id: UUID(), title: $0.title, category: $0.id, nameContains: "")
        }
    }

    static func load(from defaults: UserDefaults = .standard) throws -> Self {
        guard let value = defaults.object(forKey: "arrange.settings") else {
            return Self(preset: .none, rules: defaultRules)
        }
        guard let data = value as? Data else { throw invalidSettings }
        let settings = try JSONDecoder().decode(Self.self, from: data)
        try settings.validate()
        return settings
    }

    func save(to defaults: UserDefaults = .standard) throws {
        try validate()
        defaults.set(try JSONEncoder().encode(self), forKey: "arrange.settings")
    }

    private func validate() throws {
        if let customPreset, !NativeLayout.isSavedPreset(customPreset) { throw Self.invalidSettings }
        let categories = Set(AutoArrange.categories.map(\.id) + [""])
        guard Set(rules.map(\.id)).count == rules.count,
              rules.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && categories.contains($0.category) })
        else { throw Self.invalidSettings }
    }

    private static var invalidSettings: NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSValidationErrorMinimum, userInfo: [
            NSLocalizedDescriptionKey: "智能整理设置无效，请检查分类、文件夹名称和应用类型。"
        ])
    }
}

struct AutoArrangeApp: Sendable {
    let url: URL
    let name: String
    let category: String
}

struct AutoArrangeGroup: Sendable {
    let title: String
    let apps: [URL]
}

enum AutoArrange {
    static let categories: [(id: String, title: String)] = [
        ("developer", "Developer Tools"), ("productivity", "效率与财务"),
        ("business", "商业"), ("social", "社交"), ("utilities", "工具"),
        ("entertainment", "娱乐"), ("information", "信息与阅读"),
        ("creativity", "创意"), ("education", "教育"), ("other", "其他")
    ]

    static func readApps(_ urls: [URL]) -> [AutoArrangeApp] {
        urls.map { url in
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            let category = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            return AutoArrangeApp(url: url, name: name, category: categoryID(for: category))
        }
    }

    static func categoryID(for category: String?) -> String {
        switch category {
        case "public.app-category.developer-tools": "developer"
        case "public.app-category.productivity", "public.app-category.finance": "productivity"
        case "public.app-category.business": "business"
        case "public.app-category.social-networking": "social"
        case "public.app-category.utilities", "public.app-category.weather", "public.app-category.travel": "utilities"
        case "public.app-category.entertainment", "public.app-category.games", "public.app-category.sports": "entertainment"
        case "public.app-category.books", "public.app-category.news", "public.app-category.reference": "information"
        case "public.app-category.graphics-design", "public.app-category.photography", "public.app-category.music", "public.app-category.video": "creativity"
        case "public.app-category.education": "education"
        default:
            category?.hasSuffix("-games") == true ? "entertainment" : "other"
        }
    }

    static func groups(apps: [AutoArrangeApp], settings: AutoArrangeSettings) -> [AutoArrangeGroup] {
        guard settings.customPreset == nil, settings.preset == .categories else { return [] }
        var grouped: [String: [URL]] = [:]
        for app in apps {
            let title = settings.rules.first {
                ($0.category.isEmpty || $0.category == app.category) &&
                ($0.nameContains.isEmpty || app.name.range(of: $0.nameContains, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
            }?.title
            guard let title else { continue }
            grouped[title, default: []].append(app.url)
        }
        let titles = settings.rules.map(\.title).filter { grouped[$0] != nil }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        return titles.map { AutoArrangeGroup(title: $0, apps: grouped[$0]!) }
    }

    static func isSystemApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/System/Applications/") ||
            path.hasPrefix("/System/Library/CoreServices/") ||
            path.hasPrefix("/System/Library/PreferencePanes/") ||
            path.hasPrefix("/System/Cryptexes/App/System/Applications/") ||
            path.hasPrefix("/System/Volumes/Preboot/Cryptexes/App/System/Applications/")
    }

    @discardableResult
    static func arrange(_ layout: NativeLayout, settings: AutoArrangeSettings, groups: [AutoArrangeGroup]) -> Bool {
        guard settings.customPreset == nil else { return false }
        switch settings.preset {
        case .categories: return arrange(layout, groups: groups)
        case .none, .system:
            let pages = layout.pages as! [NativePage]
            var system: [URL] = []
            var other: [URL] = []
            for page in pages {
                for item in page.items {
                    let apps: [URL]
                    if let group = item as? NativeGroup { apps = (group.items as! [NativePage]).flatMap { $0.items as! [URL] } }
                    else { apps = [item as! URL] }
                    for app in apps {
                        if settings.preset == .system && isSystemApp(app) { system.append(app) }
                        else { other.append(app) }
                    }
                }
            }
            var separated = [system, other].flatMap { apps in
                stride(from: 0, to: apps.count, by: 35).map { start in
                    Array(apps[start..<min(start + 35, apps.count)])
                }
            }
            if separated.isEmpty { separated = [[]] }
            let changed = pages.count != separated.count || zip(pages, separated).contains { ($0.0.items as? [URL]) != $0.1 }
            guard changed else { return false }
            layout.pages.setArray(separated.map { NativePage(items: $0) })
            return true
        }
    }

    @discardableResult
    static func arrange(_ layout: NativeLayout, groups: [AutoArrangeGroup]) -> Bool {
        let pages = layout.pages as! [NativePage]
        var apps: [URL] = []
        var containingGroup: [URL: NativeGroup] = [:]
        var existingGroups: [String: NativeGroup] = [:]
        for page in pages {
            for item in page.items {
                if let group = item as? NativeGroup {
                    if let title = group.title, existingGroups[title] == nil { existingGroups[title] = group }
                    for groupPage in group.items as! [NativePage] {
                        for app in groupPage.items as! [URL] {
                            apps.append(app)
                            containingGroup[app] = group
                        }
                    }
                } else { apps.append(item as! URL) }
            }
        }
        let available = Set(apps)
        var assignments: [URL: String] = [:]
        var titles: [String] = []
        for group in groups {
            for app in group.apps where available.contains(app) && assignments[app] == nil {
                assignments[app] = group.title
                if !titles.contains(group.title) { titles.append(group.title) }
            }
        }
        guard !assignments.isEmpty else { return false }
        let moving = apps.filter { app in
            guard let title = assignments[app] else { return false }
            guard let current = containingGroup[app], let target = existingGroups[title] else { return true }
            return current !== target
        }
        var changed = !moving.isEmpty
        if changed {
            let movingSet = Set(moving)

            for page in pages {
                page.items.setArray(page.items.filter { item in
                    if let group = item as? NativeGroup {
                        for groupPage in group.items as! [NativePage] {
                            groupPage.items.setArray((groupPage.items as! [URL]).filter { !movingSet.contains($0) })
                        }
                        return true
                    }
                    return !movingSet.contains(item as! URL)
                })
            }
            for title in titles {
                let incoming = moving.filter { assignments[$0] == title }
                guard !incoming.isEmpty else { continue }
                let target: NativeGroup
                if let existing = existingGroups[title] { target = existing }
                else {
                    target = NativeGroup(id: "folder-" + UUID().uuidString, title: title, pages: [])
                    let last = layout.pages.lastObject as! NativePage
                    if last.items.count == 35 { layout.pages.add(NativePage(items: [target])) }
                    else { last.items.add(target) }
                }
                for app in incoming {
                    if let last = target.items.lastObject as? NativePage, last.items.count < 35 { last.items.add(app) }
                    else { target.items.add(NativePage(items: [app])) }
                }
            }
            for page in layout.pages as! [NativePage] {
                page.items.setArray(page.items.filter { item in
                    guard let group = item as? NativeGroup else { return true }
                    group.items.setArray((group.items as! [NativePage]).filter { $0.items.count > 0 })
                    return group.items.count > 0
                })
            }
            layout.pages.setArray((layout.pages as! [NativePage]).filter { $0.items.count > 0 })
        }
        let rootPages = layout.pages as! [NativePage]
        let rootItems = rootPages.flatMap { Array($0.items) }
        let starts = stride(from: 0, to: rootItems.count, by: 35)
        let counts = starts.map { min(35, rootItems.count - $0) }
        if rootPages.map({ $0.items.count }) != counts {
            layout.pages.setArray(starts.map { start in
                NativePage(items: Array(rootItems[start..<min(start + 35, rootItems.count)]))
            })
            changed = true
        }
        return changed
    }
}
