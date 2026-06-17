import Foundation
import StockWatchCore

@MainActor
protocol QuoteProvider {
    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote]
}

@MainActor
final class ConfigurableQuoteProvider: QuoteProvider {
    private let tencentProvider: TencentQuoteProvider
    private let infowayProvider: InfowayQuoteProvider?

    init(
        tencentProvider: TencentQuoteProvider = TencentQuoteProvider(),
        infowayProvider: InfowayQuoteProvider? = InfowayQuoteProvider.configured()
    ) {
        self.tencentProvider = tencentProvider
        self.infowayProvider = infowayProvider
    }

    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote] {
        let hongKongSymbols = symbols.filter { $0.market == .hongKong }
        let tencentSymbols = symbols.filter { $0.market != .hongKong }
        var fetchedQuotes: [Quote] = []

        if !tencentSymbols.isEmpty {
            fetchedQuotes += try await tencentProvider.fetchQuotes(for: tencentSymbols)
        }

        if !hongKongSymbols.isEmpty {
            fetchedQuotes += try await fetchHongKongQuotes(for: hongKongSymbols)
        }

        let quotesByID = Dictionary(uniqueKeysWithValues: fetchedQuotes.map { ($0.symbol.id, $0) })
        return symbols.compactMap { quotesByID[$0.id] }
    }

    private func fetchHongKongQuotes(for symbols: [StockSymbol]) async throws -> [Quote] {
        guard let infowayProvider else {
            return try await tencentProvider.fetchQuotes(for: symbols)
        }

        do {
            let infowayQuotes = try await infowayProvider.fetchQuotes(for: symbols)
            let fetchedIDs = Set(infowayQuotes.map(\.symbol.id))
            let missingSymbols = symbols.filter { !fetchedIDs.contains($0.id) }

            guard !missingSymbols.isEmpty else {
                return infowayQuotes
            }

            let fallbackQuotes = try await tencentProvider.fetchQuotes(for: missingSymbols)
            return infowayQuotes + fallbackQuotes
        } catch {
            return try await tencentProvider.fetchQuotes(for: symbols)
        }
    }
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

@MainActor
final class InfowayQuoteProvider: QuoteProvider {
    private let apiKey: String
    private let klineEndpoint = URL(string: "https://data.infoway.io/stock/v2/batch_kline")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    static func configured() -> InfowayQuoteProvider? {
        guard let apiKey = InfowayConfiguration.apiKey else {
            return nil
        }

        return InfowayQuoteProvider(apiKey: apiKey)
    }

    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote] {
        let hongKongSymbols = symbols.filter { $0.market == .hongKong }
        guard !hongKongSymbols.isEmpty else {
            return []
        }

        async let minuteKlines = fetchKlines(for: hongKongSymbols, klineType: 1)
        async let dailyKlines = fetchDailyKlines(for: hongKongSymbols)
        let (minuteKlinesByCode, dailyKlinesByCode) = try await (try? minuteKlines, dailyKlines)

        return hongKongSymbols.compactMap { symbol in
            guard let dailyKline = dailyKlinesByCode[symbol.infowayCode] else {
                return nil
            }

            let minuteKline = minuteKlinesByCode?[symbol.infowayCode]
            let price = minuteKline?.close ?? dailyKline.close
            let updatedAt = minuteKline?.updatedAt ?? Date()
            let previousClose = dailyKline.close - dailyKline.change
            let change = previousClose == 0 ? dailyKline.change : price - previousClose
            let changePercent = previousClose == 0 ? dailyKline.changePercent : change / previousClose * 100

            return Quote(
                symbol: symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                candles: [],
                updatedAt: updatedAt
            )
        }
    }

    private func fetchDailyKlines(for symbols: [StockSymbol]) async throws -> [String: InfowayDailyKline] {
        try await fetchKlines(for: symbols, klineType: 8)
    }

    private func fetchKlines(for symbols: [StockSymbol], klineType: Int) async throws -> [String: InfowayDailyKline] {
        var request = makeRequest(url: klineEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            InfowayKlineRequest(
                klineType: klineType,
                klineNum: 1,
                codes: symbols.map(\.infowayCode).joined(separator: ",")
            )
        )

        let seriesList: [InfowayKlineSeries] = try await fetchPayload(request)
        var result: [String: InfowayDailyKline] = [:]

        for series in seriesList {
            guard let latest = series.responseList.first else {
                continue
            }

            result[series.symbol] = InfowayDailyKline(
                close: parseDouble(latest.close),
                change: parseDouble(latest.change),
                changePercent: parsePercent(latest.changePercent),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(parseDouble(latest.timestamp)))
            )
        }

        return result
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StockWatch/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(apiKey, forHTTPHeaderField: "apiKey")
        return request
    }

    private func fetchPayload<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InfowayQuoteProviderError.badResponse
        }

        let decoded = try JSONDecoder().decode(InfowayResponse<T>.self, from: data)
        guard decoded.ret == 200, let payload = decoded.data else {
            throw InfowayQuoteProviderError.apiError(decoded.messageText)
        }

        return payload
    }

    private func parseDouble(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) ?? 0
    }

    private func parsePercent(_ text: String) -> Double {
        parseDouble(text)
    }
}

enum InfowayConfiguration {
    static let environmentKey = "INFOWAY_API_KEY"
    static let userDefaultsKey = "infoway.apiKey"
    static let keyFileName = "infoway-api-key.txt"

    static var apiKey: String? {
        if let environmentValue = clean(ProcessInfo.processInfo.environment[environmentKey]) {
            return environmentValue
        }

        if let userDefaultsValue = clean(UserDefaults.standard.string(forKey: userDefaultsKey)) {
            return userDefaultsValue
        }

        return clean(keyFileValue())
    }

    private static func keyFileValue() -> String? {
        guard
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }

        let fileURL = applicationSupportURL
            .appendingPathComponent("StockWatch", isDirectory: true)
            .appendingPathComponent(keyFileName)

        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct InfowayResponse<T: Decodable>: Decodable {
    var ret: Int?
    var msg: String?
    var data: T?
    var code: Int?
    var message: String?

    var messageText: String {
        message ?? msg ?? "Infoway 行情返回异常"
    }
}

private struct InfowayKlineRequest: Encodable {
    var klineType: Int
    var klineNum: Int
    var codes: String
}

private struct InfowayKlineSeries: Decodable {
    var symbol: String
    var responseList: [InfowayKlinePayload]

    enum CodingKeys: String, CodingKey {
        case symbol = "s"
        case responseList = "respList"
    }
}

private struct InfowayKlinePayload: Decodable {
    var timestamp: String
    var close: String
    var changePercent: String
    var change: String

    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case close = "c"
        case changePercent = "pc"
        case change = "pca"
    }
}

private struct InfowayDailyKline {
    var close: Double
    var change: Double
    var changePercent: Double
    var updatedAt: Date
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

enum InfowayQuoteProviderError: LocalizedError {
    case invalidEndpoint
    case badResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Infoway 行情地址无效"
        case .badResponse:
            return "Infoway 行情返回异常"
        case .apiError(let message):
            return message
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

    var infowayCode: String {
        compactCode
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
