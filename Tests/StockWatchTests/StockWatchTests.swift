import Foundation
import Testing
@testable import StockWatchCore

@Test func normalizesHongKongCodes() async throws {
    let symbol = try #require(SymbolNormalizer.normalize("700"))
    #expect(symbol.id == "HK.00700")
    #expect(symbol.name == "腾讯控股")
}

@Test func normalizesQualifiedHongKongCodes() async throws {
    let symbol = try #require(SymbolNormalizer.normalize("00700.hk"))
    #expect(symbol.id == "HK.00700")
}

@Test func normalizesShanghaiCodes() async throws {
    let symbol = try #require(SymbolNormalizer.normalize("600519"))
    #expect(symbol.id == "SH.600519")
    #expect(symbol.name == "贵州茅台")
}

@Test func normalizesShenzhenCodes() async throws {
    let symbol = try #require(SymbolNormalizer.normalize("000001.sz"))
    #expect(symbol.id == "SZ.000001")
    #expect(symbol.name == "平安银行")
}

@Test func normalizesCommonChineseNames() async throws {
    #expect(SymbolNormalizer.normalize("腾讯")?.id == "HK.00700")
    #expect(SymbolNormalizer.normalize("茅台")?.id == "SH.600519")
    #expect(SymbolNormalizer.normalize("宁德时代")?.id == "SZ.300750")
    #expect(SymbolNormalizer.normalize("三花智控")?.id == "SZ.002050")
    #expect(SymbolNormalizer.normalize("盛新锂能")?.id == "SZ.002240")
}

@Test func ashareRefreshWindowKeepsOpeningAndClosingBuffers() async throws {
    let symbol = StockSymbol(market: .shanghai, code: "600519", name: "贵州茅台")

    #expect(TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 16, hour: 9, minute: 15)))
    #expect(TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 16, hour: 15, minute: 10)))
    #expect(!TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 16, hour: 15, minute: 20)))
}

@Test func ashareRefreshPausesDuringLunch() async throws {
    let symbol = StockSymbol(market: .shenzhen, code: "000001", name: "平安银行")

    #expect(!TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 16, hour: 11, minute: 50)))
    #expect(TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 16, hour: 12, minute: 55)))
}

@Test func hongKongRefreshWindowKeepsClosingBuffer() async throws {
    let symbol = StockSymbol(market: .hongKong, code: "00700", name: "腾讯控股")

    #expect(TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 16, hour: 16, minute: 15)))
    #expect(!TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 16, hour: 16, minute: 25)))
}

@Test func refreshWindowPausesOnWeekends() async throws {
    let symbol = StockSymbol(market: .hongKong, code: "00700", name: "腾讯控股")

    #expect(!TradingRefreshSchedule.isActive(for: [symbol], at: date(year: 2026, month: 6, day: 20, hour: 10, minute: 0)))
}

@Test func activeSymbolsOnlyKeepsCurrentlyOpenMarkets() async throws {
    let ashare = StockSymbol(market: .shanghai, code: "600519", name: "贵州茅台")
    let hongKong = StockSymbol(market: .hongKong, code: "00700", name: "腾讯控股")
    let activeSymbols = TradingRefreshSchedule.activeSymbols(
        from: [ashare, hongKong],
        at: date(year: 2026, month: 6, day: 16, hour: 15, minute: 30)
    )

    #expect(activeSymbols.map(\.id) == ["HK.00700"])
}

@Test func inactiveRefreshDelayUsesLowFrequencyLocalCheck() async throws {
    let symbol = StockSymbol(market: .hongKong, code: "00700", name: "腾讯控股")
    let delay = TradingRefreshSchedule.nextDelay(
        for: [symbol],
        at: date(year: 2026, month: 6, day: 16, hour: 20, minute: 0)
    )

    #expect(delay == TradingRefreshSchedule.idleCheckInterval)
}

private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

    var components = DateComponents()
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = 0

    return calendar.date(from: components)!
}
