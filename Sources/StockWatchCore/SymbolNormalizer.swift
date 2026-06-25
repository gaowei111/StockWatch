import Foundation

public enum SymbolNormalizer {
    private static let knownNames: [String: String] = [
        "HK.00700": "腾讯控股",
        "HK.03690": "美团",
        "HK.09988": "阿里巴巴-W",
        "HK.01024": "快手-W",
        "HK.01810": "小米集团-W",
        "HK.09618": "京东集团-SW",
        "HK.09888": "百度集团-SW",
        "SH.600519": "贵州茅台",
        "SH.601318": "中国平安",
        "SH.600036": "招商银行",
        "SH.601012": "隆基绿能",
        "SH.601888": "中国中免",
        "SZ.000001": "平安银行",
        "SZ.000333": "美的集团",
        "SZ.000651": "格力电器",
        "SZ.002594": "比亚迪",
        "SZ.002415": "海康威视",
        "SZ.002050": "三花智控",
        "SZ.002240": "盛新锂能",
        "SZ.300750": "宁德时代",
        "SH.510300": "沪深300ETF华泰柏瑞",
        "SH.510500": "中证500ETF南方",
        "SH.512880": "证券ETF国泰",
        "SH.513100": "纳指ETF国泰",
        "SH.588000": "科创50ETF华夏",
        "SZ.159915": "创业板ETF易方达",
        "SZ.159919": "沪深300ETF嘉实",
        "SZ.159941": "纳指ETF广发",
        "SZ.161725": "白酒基金LOF"
    ]

    private static let aliases: [String: String] = [
        "腾讯": "HK.00700",
        "腾讯控股": "HK.00700",
        "美团": "HK.03690",
        "阿里": "HK.09988",
        "阿里巴巴": "HK.09988",
        "阿里巴巴W": "HK.09988",
        "快手": "HK.01024",
        "小米": "HK.01810",
        "小米集团": "HK.01810",
        "京东": "HK.09618",
        "百度": "HK.09888",
        "茅台": "SH.600519",
        "贵州茅台": "SH.600519",
        "中国平安": "SH.601318",
        "招商银行": "SH.600036",
        "招行": "SH.600036",
        "隆基": "SH.601012",
        "隆基绿能": "SH.601012",
        "中国中免": "SH.601888",
        "中免": "SH.601888",
        "平安银行": "SZ.000001",
        "美的": "SZ.000333",
        "美的集团": "SZ.000333",
        "格力": "SZ.000651",
        "格力电器": "SZ.000651",
        "比亚迪": "SZ.002594",
        "海康": "SZ.002415",
        "海康威视": "SZ.002415",
        "三花": "SZ.002050",
        "三花智控": "SZ.002050",
        "盛新": "SZ.002240",
        "盛新锂能": "SZ.002240",
        "宁德": "SZ.300750",
        "宁德时代": "SZ.300750",
        "沪深300ETF": "SH.510300",
        "300ETF": "SH.510300",
        "中证500ETF": "SH.510500",
        "500ETF": "SH.510500",
        "证券ETF": "SH.512880",
        "券商ETF": "SH.512880",
        "科创50ETF": "SH.588000",
        "科创ETF": "SH.588000",
        "创业板ETF": "SZ.159915",
        "纳指ETF": "SZ.159941",
        "白酒LOF": "SZ.161725",
        "白酒基金": "SZ.161725"
    ]

    public static func normalize(_ rawInput: String) -> StockSymbol? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let compactName = normalizedName(trimmed)
        if let symbolID = aliases[compactName], let symbol = symbol(from: symbolID) {
            return symbol
        }

        let uppercased = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: ".")
            .uppercased()

        if let symbol = normalizeQualifiedCode(uppercased) {
            return symbol
        }

        let digits = uppercased.filter(\.isNumber)
        if (1...5).contains(digits.count) {
            return makeSymbol(market: .hongKong, code: digits.leftPadded(to: 5, with: "0"))
        }

        if digits.count == 6 {
            if digits.hasPrefix("5") || digits.hasPrefix("6") || digits.hasPrefix("9") {
                return makeSymbol(market: .shanghai, code: digits)
            }

            if digits.hasPrefix("0") || digits.hasPrefix("1") || digits.hasPrefix("2") || digits.hasPrefix("3") {
                return makeSymbol(market: .shenzhen, code: digits)
            }
        }

        return nil
    }

    public static func displayName(for symbolID: String) -> String? {
        knownNames[symbolID]
    }

    private static func normalizeQualifiedCode(_ input: String) -> StockSymbol? {
        let separators = CharacterSet(charactersIn: ".-:/")
        let parts = input.components(separatedBy: separators).filter { !$0.isEmpty }
        guard parts.count == 2 else {
            return nil
        }

        let first = parts[0]
        let second = parts[1]

        if let market = Market(rawValue: first), second.allSatisfy(\.isNumber) {
            return makeSymbol(market: market, code: paddedCode(second, market: market))
        }

        if let market = Market(rawValue: second), first.allSatisfy(\.isNumber) {
            return makeSymbol(market: market, code: paddedCode(first, market: market))
        }

        return nil
    }

    private static func makeSymbol(market: Market, code: String) -> StockSymbol {
        let symbolID = "\(market.rawValue).\(code)"
        return StockSymbol(
            market: market,
            code: code,
            name: knownNames[symbolID] ?? symbolID
        )
    }

    private static func symbol(from symbolID: String) -> StockSymbol? {
        let parts = symbolID.split(separator: ".")
        guard parts.count == 2, let market = Market(rawValue: String(parts[0])) else {
            return nil
        }

        return makeSymbol(market: market, code: String(parts[1]))
    }

    private static func normalizedName(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    private static func paddedCode(_ code: String, market: Market) -> String {
        switch market {
        case .hongKong:
            return code.leftPadded(to: 5, with: "0")
        case .shanghai, .shenzhen:
            return code.leftPadded(to: 6, with: "0")
        }
    }
}

private extension String {
    func leftPadded(to targetLength: Int, with character: Character) -> String {
        guard count < targetLength else {
            return self
        }

        return String(repeating: String(character), count: targetLength - count) + self
    }
}
