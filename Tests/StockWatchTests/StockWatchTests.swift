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
