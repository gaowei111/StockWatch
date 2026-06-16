import Foundation

public enum Market: String, Codable, CaseIterable, Sendable {
    case shanghai = "SH"
    case shenzhen = "SZ"
    case hongKong = "HK"

    public var displayName: String {
        switch self {
        case .shanghai:
            return "沪市"
        case .shenzhen:
            return "深市"
        case .hongKong:
            return "港股"
        }
    }
}

public struct StockSymbol: Codable, Hashable, Identifiable, Sendable {
    public var market: Market
    public var code: String
    public var name: String

    public var id: String {
        "\(market.rawValue).\(code)"
    }

    public var compactCode: String {
        "\(code).\(market.rawValue)"
    }

    public init(market: Market, code: String, name: String) {
        self.market = market
        self.code = code
        self.name = name
    }
}

public struct Candle: Codable, Hashable, Sendable {
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double

    public init(open: Double, high: Double, low: Double, close: Double) {
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

public struct Quote: Codable, Hashable, Identifiable, Sendable {
    public var symbol: StockSymbol
    public var price: Double
    public var change: Double
    public var changePercent: Double
    public var candles: [Candle]
    public var updatedAt: Date

    public var id: String {
        symbol.id
    }

    public init(
        symbol: StockSymbol,
        price: Double,
        change: Double,
        changePercent: Double,
        candles: [Candle],
        updatedAt: Date
    ) {
        self.symbol = symbol
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.candles = candles
        self.updatedAt = updatedAt
    }
}

public struct TrendPoint: Codable, Hashable, Identifiable, Sendable {
    public var time: String
    public var price: Double

    public var id: String {
        time
    }

    public init(time: String, price: Double) {
        self.time = time
        self.price = price
    }
}
