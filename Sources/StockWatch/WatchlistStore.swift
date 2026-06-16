import Foundation
import StockWatchCore
import SwiftUI

struct WatchlistGroup: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var symbols: [StockSymbol]

    init(id: UUID = UUID(), name: String, symbols: [StockSymbol]) {
        self.id = id
        self.name = name
        self.symbols = symbols
    }
}

@MainActor
final class WatchlistStore: ObservableObject {
    @Published private(set) var groups: [WatchlistGroup] = []
    @Published private(set) var selectedGroupID: UUID?
    @Published private(set) var symbols: [StockSymbol] = []
    @Published private(set) var quotes: [String: Quote] = [:]
    @Published private(set) var trends: [String: [TrendPoint]] = [:]
    @Published var newSymbolText = ""
    @Published var discreetMode = true {
        didSet {
            UserDefaults.standard.set(discreetMode, forKey: discreetModeKey)
        }
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var isAdding = false
    @Published private(set) var isSearching = false
    @Published private(set) var searchSuggestions: [StockSymbol] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var refreshStatusText = TradingRefreshSchedule.statusText(for: [])

    private let provider: QuoteProvider
    private let searchProvider: SymbolSearchProvider
    private let trendProvider: IntradayTrendProvider
    private let groupsKey = "watchlist.groups"
    private let selectedGroupIDKey = "watchlist.selectedGroupID"
    private let symbolsKey = "watchlist.symbols"
    private let discreetModeKey = "watchlist.discreetMode"
    private var refreshTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    var currentGroupName: String {
        groups.first { $0.id == selectedGroupID }?.name ?? "自选"
    }

    init(
        provider: QuoteProvider = FallbackQuoteProvider(primary: TencentQuoteProvider(), fallback: MockQuoteProvider()),
        searchProvider: SymbolSearchProvider = TencentSymbolSearchProvider(),
        trendProvider: IntradayTrendProvider = TencentIntradayTrendProvider()
    ) {
        self.provider = provider
        self.searchProvider = searchProvider
        self.trendProvider = trendProvider
        discreetMode = UserDefaults.standard.object(forKey: discreetModeKey) as? Bool ?? true
        groups = Self.loadGroups(groupsKey: groupsKey, legacySymbolsKey: symbolsKey)
        selectedGroupID = Self.loadSelectedGroupID(key: selectedGroupIDKey, groups: groups)
        syncSymbolsFromSelectedGroup()
        updateRefreshStatus()
        persistGroups()
    }

    deinit {
        refreshTask?.cancel()
        searchTask?.cancel()
    }

    func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let delay = await self.scheduledRefreshCycle()
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    func refresh() async {
        await refresh(symbolsToRefresh: symbols, replaceAll: true)
    }

    private func refresh(symbolsToRefresh: [StockSymbol], replaceAll: Bool) async {
        defer {
            updateRefreshStatus()
        }

        guard !symbolsToRefresh.isEmpty else {
            if replaceAll {
                quotes = [:]
                trends = [:]
            }
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            let fetchedQuotes = try await provider.fetchQuotes(for: symbolsToRefresh)
            let fetchedTrends = await trendProvider.fetchTrends(for: symbolsToRefresh)

            if replaceAll {
                quotes = Dictionary(uniqueKeysWithValues: fetchedQuotes.map { ($0.symbol.id, $0) })
                trends = fetchedTrends
            } else {
                for quote in fetchedQuotes {
                    quotes[quote.symbol.id] = quote
                }

                for (id, trend) in fetchedTrends {
                    trends[id] = trend
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectGroup(_ group: WatchlistGroup) {
        selectedGroupID = group.id
        UserDefaults.standard.set(group.id.uuidString, forKey: selectedGroupIDKey)
        syncSymbolsFromSelectedGroup()
        updateRefreshStatus()
        Task {
            await refresh()
        }
    }

    func addGroup() {
        let name = nextGroupName()
        let group = WatchlistGroup(name: name, symbols: [])
        groups.append(group)
        persistGroups()
        selectGroup(group)
    }

    func deleteCurrentGroup() {
        guard groups.count > 1, let selectedGroupID else {
            return
        }

        groups.removeAll { $0.id == selectedGroupID }
        self.selectedGroupID = groups.first?.id
        if let id = self.selectedGroupID {
            UserDefaults.standard.set(id.uuidString, forKey: selectedGroupIDKey)
        }
        syncSymbolsFromSelectedGroup()
        updateRefreshStatus()
        persistGroups()
        Task {
            await refresh()
        }
    }

    func renameCurrentGroup(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "未命名" : trimmed
        guard let index = currentGroupIndex else {
            return
        }

        groups[index].name = finalName
        persistGroups()
    }

    func updateSearchQuery(_ query: String) {
        searchTask?.cancel()
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard shouldSearchSuggestions(for: input) else {
            isSearching = false
            searchSuggestions = []
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }

            await self?.loadSuggestions(for: input)
        }
    }

    func addCurrentSymbol() {
        let input = newSymbolText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return
        }

        Task {
            if let firstSuggestion = searchSuggestions.first {
                await addSymbol(firstSuggestion)
            } else {
                await addSymbol(input)
            }
        }
    }

    func addSuggestion(_ symbol: StockSymbol) {
        Task {
            await addSymbol(symbol)
        }
    }

    private func addSymbol(_ input: String) async {
        isAdding = true
        defer {
            isAdding = false
        }

        let resolved: StockSymbol?
        if let localSymbol = SymbolNormalizer.normalize(input) {
            resolved = localSymbol
        } else {
            let results = try? await searchProvider.search(input)
            resolved = results?.first
        }

        guard let normalized = resolved else {
            errorMessage = "没找到这只股票，可输入代码或更完整的名称"
            return
        }

        await addSymbol(normalized)
    }

    private func addSymbol(_ normalized: StockSymbol) async {
        isAdding = true
        defer {
            isAdding = false
        }

        guard !symbols.contains(where: { $0.id == normalized.id }) else {
            newSymbolText = ""
            searchSuggestions = []
            return
        }

        symbols.append(normalized)
        newSymbolText = ""
        searchSuggestions = []
        errorMessage = nil
        persistCurrentSymbols()
        updateRefreshStatus()
        await refresh()
    }

    func remove(_ symbol: StockSymbol) {
        symbols.removeAll { $0.id == symbol.id }
        quotes.removeValue(forKey: symbol.id)
        trends.removeValue(forKey: symbol.id)
        persistCurrentSymbols()
        updateRefreshStatus()
    }

    func move(from source: IndexSet, to destination: Int) {
        symbols.move(fromOffsets: source, toOffset: destination)
        persistCurrentSymbols()
    }

    @discardableResult
    func move(symbolID: String, to targetIndex: Int) -> Bool {
        guard
            let fromIndex = symbols.firstIndex(where: { $0.id == symbolID }),
            symbols.indices.contains(targetIndex),
            fromIndex != targetIndex
        else {
            return false
        }

        let movedSymbol = symbols.remove(at: fromIndex)
        symbols.insert(movedSymbol, at: min(targetIndex, symbols.count))
        persistCurrentSymbols()
        return true
    }

    private var currentGroupIndex: Int? {
        guard let selectedGroupID else {
            return nil
        }

        return groups.firstIndex { $0.id == selectedGroupID }
    }

    private func scheduledRefreshCycle() async -> TimeInterval {
        updateRefreshStatus()

        let activeSymbols = TradingRefreshSchedule.activeSymbols(from: symbols)
        if !activeSymbols.isEmpty {
            await refresh(symbolsToRefresh: activeSymbols, replaceAll: false)
        }

        return TradingRefreshSchedule.nextDelay(for: symbols)
    }

    private func updateRefreshStatus() {
        refreshStatusText = TradingRefreshSchedule.statusText(for: symbols)
    }

    private func shouldSearchSuggestions(for input: String) -> Bool {
        input.count >= 2 && input.contains { character in
            character.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            }
        }
    }

    private func loadSuggestions(for input: String) async {
        isSearching = true
        defer {
            isSearching = false
        }

        let results = (try? await searchProvider.search(input)) ?? []
        guard newSymbolText.trimmingCharacters(in: .whitespacesAndNewlines) == input else {
            return
        }

        let existingIDs = Set(symbols.map(\.id))
        searchSuggestions = results.filter { !existingIDs.contains($0.id) }
    }

    private func syncSymbolsFromSelectedGroup() {
        symbols = groups.first { $0.id == selectedGroupID }?.symbols ?? []
    }

    private func persistCurrentSymbols() {
        guard let index = currentGroupIndex else {
            return
        }

        groups[index].symbols = symbols
        persistGroups()
    }

    private func persistGroups() {
        guard let data = try? JSONEncoder().encode(groups) else {
            return
        }

        UserDefaults.standard.set(data, forKey: groupsKey)
    }

    private func nextGroupName() -> String {
        let existingNames = Set(groups.map(\.name))
        var index = groups.count + 1
        while existingNames.contains("分组 \(index)") {
            index += 1
        }

        return "分组 \(index)"
    }

    private static func loadGroups(groupsKey: String, legacySymbolsKey: String) -> [WatchlistGroup] {
        if
            let data = UserDefaults.standard.data(forKey: groupsKey),
            let decoded = try? JSONDecoder().decode([WatchlistGroup].self, from: data),
            !decoded.isEmpty
        {
            return decoded
        }

        let legacySymbols = loadSymbols(key: legacySymbolsKey)
        if !legacySymbols.isEmpty {
            return [WatchlistGroup(name: "自选", symbols: legacySymbols)]
        }

        return [
            WatchlistGroup(
                name: "自选",
                symbols: [
                    StockSymbol(market: .hongKong, code: "00700", name: "腾讯控股"),
                    StockSymbol(market: .shanghai, code: "600519", name: "贵州茅台"),
                    StockSymbol(market: .shenzhen, code: "000001", name: "平安银行")
                ]
            )
        ]
    }

    private static func loadSelectedGroupID(key: String, groups: [WatchlistGroup]) -> UUID? {
        guard
            let rawID = UserDefaults.standard.string(forKey: key),
            let id = UUID(uuidString: rawID),
            groups.contains(where: { $0.id == id })
        else {
            return groups.first?.id
        }

        return id
    }

    private static func loadSymbols(key: String) -> [StockSymbol] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([StockSymbol].self, from: data)
        else {
            return []
        }

        return decoded
    }
}
