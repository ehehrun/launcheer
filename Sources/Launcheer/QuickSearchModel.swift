import Foundation

struct QuickSearchModel {
    struct Item: Equatable {
        let url: URL
        let name: String
        fileprivate let searchText: [String]
    }

    static let resultLimit = 8
    private var items: [Item] = []
    private(set) var query = ""
    private(set) var results: [Item] = []
    private(set) var selectedIndex: Int?

    var selectedItem: Item? {
        guard let selectedIndex else { return nil }
        return results[selectedIndex]
    }

    init(items: [URL]) {
        updateItems(items)
    }

    mutating func updateItems(_ urls: [URL]) {
        let selectedURL = selectedItem?.url
        items = urls.map { url in
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            let filename = url.deletingPathExtension().lastPathComponent
            var terms = [Self.fold(name)]
            let filenameTerm = Self.fold(filename)
            if !terms.contains(filenameTerm) { terms.append(filenameTerm) }
            if let latin = name.applyingTransform(.toLatin, reverse: false) {
                let syllables = Self.fold(latin).split(whereSeparator: \.isWhitespace)
                for term in [syllables.joined(), String(syllables.compactMap(\.first))] where !terms.contains(term) {
                    terms.append(term)
                }
            }
            return Item(url: url, name: name, searchText: terms)
        }
        search(query)
        if let selectedURL, let index = results.firstIndex(where: { $0.url == selectedURL }) {
            selectedIndex = index
        }
    }

    mutating func search(_ query: String) {
        self.query = query
        let term = Self.fold(query).filter { !$0.isWhitespace }
        if term.isEmpty {
            results = Array(items.prefix(Self.resultLimit))
        } else {
            results = items.enumerated().compactMap { index, item -> (Int, Int, Item)? in
                guard let rank = item.searchText.compactMap({ Self.rank(term, in: $0) }).min() else { return nil }
                return (rank, index, item)
            }.sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }.prefix(Self.resultLimit).map(\.2)
        }
        selectedIndex = results.isEmpty ? nil : 0
    }

    mutating func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(results.count - 1, max(0, (selectedIndex ?? 0) + offset))
    }

    mutating func select(_ index: Int) {
        selectedIndex = results.indices.contains(index) ? index : nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current).lowercased()
    }

    private static func rank(_ query: String, in text: String) -> Int? {
        if text == query { return 0 }
        if text.hasPrefix(query) { return 1 }
        if text.contains(query) { return 2 }
        var position = text.startIndex
        for character in query {
            guard let found = text[position...].firstIndex(of: character) else { return nil }
            position = text.index(after: found)
        }
        return 3
    }
}
