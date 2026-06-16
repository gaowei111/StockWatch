import Foundation
import StockWatchCore

@MainActor
protocol QuoteProvider {
    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote]
}

@MainActor
final class MockQuoteProvider: QuoteProvider {
    private var tick: Double = 0

    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote] {
        tick += 1
        let now = Date()

        return symbols.enumerated().map { index, symbol in
            let base = basePrice(for: symbol)
            let wave = sin((tick + Double(index) * 2.7) / 5)
            let drift = cos((tick + Double(index)) / 11) * 0.006
            let percent = wave * 0.018 + drift
            let price = base * (1 + percent)
            let change = base * percent
            let candles = makeCandles(base: base, seed: Double(index) + tick / 3)

            return Quote(
                symbol: symbol,
                price: price,
                change: change,
                changePercent: percent * 100,
                candles: candles,
                updatedAt: now
            )
        }
    }

    private func basePrice(for symbol: StockSymbol) -> Double {
        switch symbol.id {
        case "HK.00700":
            return 388.60
        case "HK.03690":
            return 116.20
        case "HK.09988":
            return 83.45
        case "SH.600519":
            return 1_520.00
        case "SH.601318":
            return 47.30
        case "SZ.000001":
            return 10.25
        case "SZ.300750":
            return 201.80
        default:
            let numeric = Double(symbol.code.filter(\.isNumber)) ?? 100
            return max(5, numeric.truncatingRemainder(dividingBy: 300) + 12)
        }
    }

    private func makeCandles(base: Double, seed: Double) -> [Candle] {
        (0..<28).map { index in
            let step = Double(index)
            let mid = base * (1 + sin(seed + step / 3.3) * 0.012)
            let open = mid * (1 + cos(seed + step) * 0.002)
            let close = mid * (1 + sin(seed + step / 1.7) * 0.0025)
            let high = max(open, close) * 1.0025
            let low = min(open, close) * 0.9975
            return Candle(open: open, high: high, low: low, close: close)
        }
    }
}

@MainActor
final class FallbackQuoteProvider: QuoteProvider {
    private let primary: QuoteProvider
    private let fallback: QuoteProvider

    init(primary: QuoteProvider, fallback: QuoteProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote] {
        do {
            return try await primary.fetchQuotes(for: symbols)
        } catch {
            return try await fallback.fetchQuotes(for: symbols)
        }
    }
}

@MainActor
final class TencentQuoteProvider: QuoteProvider {
    private let endpoint = URL(string: "https://qt.gtimg.cn/q=")!

    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote] {
        let query = symbols.map(\.tencentCode).joined(separator: ",")
        guard let url = URL(string: endpoint.absoluteString + query) else {
            throw QuoteProviderError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw QuoteProviderError.badResponse
        }

        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        guard let text = String(data: data, encoding: encoding) else {
            throw QuoteProviderError.badEncoding
        }

        return try text
            .split(separator: "\n")
            .compactMap { try parseLine(String($0)) }
    }

    private func parseLine(_ line: String) throws -> Quote? {
        guard let assignmentRange = line.range(of: "=\"") else {
            return nil
        }

        let rawCode = String(line[..<assignmentRange.lowerBound]).replacingOccurrences(of: "v_", with: "")
        let payload = line[assignmentRange.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\";"))
        let values = payload.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard values.count > 32, let symbol = stockSymbol(fromTencentCode: rawCode, name: values[1]) else {
            return nil
        }

        let price = parseDouble(values[3])
        let change = parseDouble(values[31])
        let changePercent = parseDouble(values[32])

        return Quote(
            symbol: symbol,
            price: price,
            change: change,
            changePercent: changePercent,
            candles: [],
            updatedAt: Date()
        )
    }

    private func stockSymbol(fromTencentCode rawCode: String, name: String) -> StockSymbol? {
        if rawCode.hasPrefix("hk") {
            return StockSymbol(market: .hongKong, code: String(rawCode.dropFirst(2)).leftPadded(to: 5), name: name)
        }

        if rawCode.hasPrefix("sh") {
            return StockSymbol(market: .shanghai, code: String(rawCode.dropFirst(2)).leftPadded(to: 6), name: name)
        }

        if rawCode.hasPrefix("sz") {
            return StockSymbol(market: .shenzhen, code: String(rawCode.dropFirst(2)).leftPadded(to: 6), name: name)
        }

        return nil
    }

    private func parseDouble(_ text: String) -> Double {
        Double(text) ?? 0
    }
}

enum QuoteProviderError: LocalizedError {
    case invalidEndpoint
    case badResponse
    case badEncoding

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "腾讯行情地址无效"
        case .badResponse:
            return "腾讯行情返回异常"
        case .badEncoding:
            return "腾讯行情编码无法解析"
        }
    }
}

private extension StockSymbol {
    var tencentCode: String {
        switch market {
        case .hongKong:
            return "hk\(code)"
        case .shanghai:
            return "sh\(code)"
        case .shenzhen:
            return "sz\(code)"
        }
    }
}

private extension String {
    func leftPadded(to targetLength: Int) -> String {
        guard count < targetLength else {
            return self
        }

        return String(repeating: "0", count: targetLength - count) + self
    }
}
