import CryptoKit
import Foundation
import StockWatchCore

@MainActor
protocol QuoteProvider {
    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote]
}

@MainActor
final class ConfigurableQuoteProvider: QuoteProvider {
    private let tencentProvider: TencentQuoteProvider

    init(
        tencentProvider: TencentQuoteProvider = TencentQuoteProvider()
    ) {
        self.tencentProvider = tencentProvider
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
        let longbridgeProvider = LongbridgeQuoteProvider.configured()
        guard let longbridgeProvider else {
            return try await tencentProvider.fetchQuotes(for: symbols)
        }

        do {
            let longbridgeQuotes = try await longbridgeProvider.fetchQuotes(for: symbols)
            let fetchedIDs = Set(longbridgeQuotes.map(\.symbol.id))
            let missingSymbols = symbols.filter { !fetchedIDs.contains($0.id) }

            guard !missingSymbols.isEmpty else {
                return longbridgeQuotes
            }

            let fallbackQuotes = try await tencentProvider.fetchQuotes(for: missingSymbols)
            return longbridgeQuotes + fallbackQuotes
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
                updatedAt: now,
                source: .mock
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
            updatedAt: Date(),
            source: .tencent
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
final class LongbridgeQuoteProvider: QuoteProvider {
    private let credentials: LongbridgeCredentials
    private let httpEndpoint = URL(string: "https://openapi.longbridge.com")!
    private let quoteWebSocketEndpoint = URL(string: "wss://openapi-quote.longbridge.com?version=1&codec=1&platform=9")!

    init(credentials: LongbridgeCredentials) {
        self.credentials = credentials
    }

    static func configured() -> LongbridgeQuoteProvider? {
        guard let credentials = LongbridgeConfiguration.credentials else {
            return nil
        }

        return LongbridgeQuoteProvider(credentials: credentials)
    }

    func fetchQuotes(for symbols: [StockSymbol]) async throws -> [Quote] {
        let hongKongSymbols = symbols.filter { $0.market == .hongKong }
        guard !hongKongSymbols.isEmpty else {
            return []
        }

        let otp = try await fetchSocketOTP()
        let longbridgeSymbols = hongKongSymbols.map(\.longbridgeSymbol)
        let symbolsByLongbridgeID = Dictionary(uniqueKeysWithValues: zip(longbridgeSymbols, hongKongSymbols))

        let responseBody = try await requestQuoteBody(symbols: longbridgeSymbols, otp: otp)
        let quoteMessages = try ProtobufReader(data: responseBody).lengthDelimitedFields(number: 1)

        return quoteMessages.compactMap { data in
            guard let payload = try? LongbridgeSecurityQuote(data: data),
                  let symbol = symbolsByLongbridgeID[payload.symbol]
            else {
                return nil
            }

            let price = payload.lastDone
            let change = price - payload.previousClose
            let changePercent = payload.previousClose == 0 ? 0 : change / payload.previousClose * 100
            return Quote(
                symbol: symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                candles: [],
                updatedAt: Date(timeIntervalSince1970: TimeInterval(payload.timestamp)),
                source: .longbridge
            )
        }
    }

    func fetchSocketOTP() async throws -> String {
        let path = "/v1/socket/token"
        var request = URLRequest(url: URL(string: httpEndpoint.absoluteString + path)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        sign(&request, method: "GET", path: path, query: "", body: nil)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LongbridgeQuoteProviderError.badResponse
        }

        let decoded = try JSONDecoder().decode(LongbridgeOTPResponse.self, from: data)
        guard decoded.code == 0, let otp = decoded.data?.otp, !otp.isEmpty else {
            throw LongbridgeQuoteProviderError.apiError(decoded.message)
        }

        return otp
    }

    private func requestQuoteBody(symbols: [String], otp: String) async throws -> Data {
        let task = URLSession.shared.webSocketTask(with: quoteWebSocketEndpoint)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
        }

        try await task.send(.data(LongbridgeSocketPacket.request(
            command: 2,
            requestID: 1,
            body: ProtobufWriter.stringField(1, otp)
        )))

        let authResponse = try await receiveResponse(command: 2, requestID: 1, from: task)
        guard authResponse.status == 0 else {
            throw LongbridgeQuoteProviderError.socketStatus(authResponse.status)
        }

        try await task.send(.data(LongbridgeSocketPacket.request(
            command: 11,
            requestID: 2,
            body: ProtobufWriter.stringFields(1, symbols)
        )))

        let quoteResponse = try await receiveResponse(command: 11, requestID: 2, from: task)
        guard quoteResponse.status == 0 else {
            throw LongbridgeQuoteProviderError.socketStatus(quoteResponse.status)
        }

        return quoteResponse.body
    }

    private func receiveResponse(
        command: UInt8,
        requestID: UInt32,
        from task: URLSessionWebSocketTask
    ) async throws -> LongbridgeSocketResponse {
        for _ in 0..<8 {
            let message = try await receiveMessage(from: task)
            let data: Data
            switch message {
            case .data(let payload):
                data = payload
            case .string(let text):
                data = Data(text.utf8)
            @unknown default:
                continue
            }

            guard let response = try LongbridgeSocketPacket.response(from: data) else {
                continue
            }

            if response.command == command, response.requestID == requestID {
                return response
            }
        }

        throw LongbridgeQuoteProviderError.socketTimeout
    }

    private func receiveMessage(from task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(6))
                throw LongbridgeQuoteProviderError.socketTimeout
            }

            guard let message = try await group.next() else {
                throw LongbridgeQuoteProviderError.socketTimeout
            }

            group.cancelAll()
            return message
        }
    }

    private func sign(_ request: inout URLRequest, method: String, path: String, query: String, body: Data?) {
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let signedHeaders = "authorization;x-api-key;x-timestamp"
        let signedValues = "authorization:\(credentials.accessToken)\n"
            + "x-api-key:\(credentials.appKey)\n"
            + "x-timestamp:\(timestamp)\n"

        var textToSign = "\(method)|\(path)|\(query)|\(signedValues)|\(signedHeaders)|"
        if let body, !body.isEmpty {
            textToSign += body.sha1Hex
        }

        let canonical = "HMAC-SHA256|\(Data(textToSign.utf8).sha1Hex)"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(canonical.utf8),
            using: SymmetricKey(data: Data(credentials.appSecret.utf8))
        ).hexString

        request.setValue(credentials.accessToken, forHTTPHeaderField: "authorization")
        request.setValue(credentials.appKey, forHTTPHeaderField: "x-api-key")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.setValue(
            "HMAC-SHA256 SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "x-api-signature"
        )
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        request.setValue("zh-CN", forHTTPHeaderField: "accept-language")
    }
}

@MainActor
final class LongbridgeQuoteStream {
    var onQuote: ((Quote) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let quoteWebSocketEndpoint = URL(string: "wss://openapi-quote.longbridge.com?version=1&codec=1&platform=9")!
    private var runTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var symbols: [StockSymbol] = []
    private var symbolsByLongbridgeID: [String: StockSymbol] = [:]
    private var lastQuotes: [String: Quote] = [:]
    private var isConnected = false

    func update(symbols newSymbols: [StockSymbol]) {
        let hongKongSymbols = Array(
            Dictionary(uniqueKeysWithValues: newSymbols.filter { $0.market == .hongKong }.map { ($0.id, $0) })
                .values
                .sorted { $0.id < $1.id }
                .prefix(500)
        )

        guard hongKongSymbols.map(\.id) != symbols.map(\.id) else {
            if !hongKongSymbols.isEmpty, runTask == nil {
                restart()
            }
            return
        }

        symbols = hongKongSymbols
        symbolsByLongbridgeID = Dictionary(uniqueKeysWithValues: hongKongSymbols.map { ($0.longbridgeSymbol, $0) })
        restart()
    }

    func restart() {
        stop()

        guard !symbols.isEmpty else {
            return
        }

        guard LongbridgeConfiguration.credentials != nil else {
            onConnectionChange?(false)
            return
        }

        runTask = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        setConnected(false)
    }

    private func run() async {
        while !Task.isCancelled, !symbols.isEmpty {
            do {
                try await connectAndListen()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                setConnected(false)
                onError?(error.localizedDescription)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func connectAndListen() async throws {
        guard let credentials = LongbridgeConfiguration.credentials else {
            throw LongbridgeQuoteProviderError.badCredentials
        }

        let provider = LongbridgeQuoteProvider(credentials: credentials)
        let otp = try await provider.fetchSocketOTP()
        let task = URLSession.shared.webSocketTask(with: quoteWebSocketEndpoint)
        webSocketTask = task
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
            if webSocketTask === task {
                webSocketTask = nil
            }
            setConnected(false)
        }

        try await task.send(.data(LongbridgeSocketPacket.request(
            command: 2,
            requestID: 1,
            body: ProtobufWriter.stringField(1, otp)
        )))

        let authResponse = try await receiveResponse(command: 2, requestID: 1, from: task)
        guard authResponse.status == 0 else {
            throw LongbridgeQuoteProviderError.socketStatus(authResponse.status)
        }

        let longbridgeSymbols = symbols.map(\.longbridgeSymbol)
        try await requestInitialQuotes(symbols: longbridgeSymbols, from: task)
        try await subscribe(symbols: longbridgeSymbols, from: task)
        setConnected(true)

        while !Task.isCancelled {
            let message = try await task.receive()
            try handle(message)
        }
    }

    private func requestInitialQuotes(symbols: [String], from task: URLSessionWebSocketTask) async throws {
        guard !symbols.isEmpty else {
            return
        }

        try await task.send(.data(LongbridgeSocketPacket.request(
            command: 11,
            requestID: 2,
            body: ProtobufWriter.stringFields(1, symbols)
        )))

        let response = try await receiveResponse(command: 11, requestID: 2, from: task)
        guard response.status == 0 else {
            throw LongbridgeQuoteProviderError.socketStatus(response.status)
        }

        let quoteMessages = try ProtobufReader(data: response.body).lengthDelimitedFields(number: 1)
        for data in quoteMessages {
            guard let payload = try? LongbridgeSecurityQuote(data: data) else {
                continue
            }

            publish(securityQuote: payload)
        }
    }

    private func subscribe(symbols: [String], from task: URLSessionWebSocketTask) async throws {
        var body = Data()
        body.append(ProtobufWriter.stringFields(1, symbols))
        body.append(ProtobufWriter.varintFields(2, [1]))
        body.append(ProtobufWriter.boolField(3, true))

        try await task.send(.data(LongbridgeSocketPacket.request(
            command: 6,
            requestID: 3,
            body: body
        )))

        let response = try await receiveResponse(command: 6, requestID: 3, from: task)
        guard response.status == 0 else {
            throw LongbridgeQuoteProviderError.socketStatus(response.status)
        }
    }

    private func receiveResponse(
        command: UInt8,
        requestID: UInt32,
        from task: URLSessionWebSocketTask
    ) async throws -> LongbridgeSocketResponse {
        for _ in 0..<16 {
            let message = try await receiveMessage(from: task)
            let data = message.dataValue

            if let response = try LongbridgeSocketPacket.response(from: data),
               response.command == command,
               response.requestID == requestID {
                return response
            }

            if let push = try LongbridgeSocketPacket.push(from: data) {
                try handle(push)
            }
        }

        throw LongbridgeQuoteProviderError.socketTimeout
    }

    private func receiveMessage(from task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw LongbridgeQuoteProviderError.socketTimeout
            }

            guard let message = try await group.next() else {
                throw LongbridgeQuoteProviderError.socketTimeout
            }

            group.cancelAll()
            return message
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) throws {
        let data = message.dataValue

        if let push = try LongbridgeSocketPacket.push(from: data) {
            try handle(push)
        }
    }

    private func handle(_ push: LongbridgeSocketPush) throws {
        guard push.command == 101 else {
            return
        }

        let payload = try LongbridgePushQuote(data: push.body)
        publish(pushQuote: payload)
    }

    private func publish(securityQuote payload: LongbridgeSecurityQuote) {
        guard let symbol = symbolsByLongbridgeID[payload.symbol] else {
            return
        }

        let price = payload.lastDone
        let previousClose = payload.previousClose
        let change = price - previousClose
        let changePercent = previousClose == 0 ? 0 : change / previousClose * 100
        let quote = Quote(
            symbol: symbol,
            price: price,
            change: change,
            changePercent: changePercent,
            candles: [],
            updatedAt: Date(timeIntervalSince1970: TimeInterval(payload.timestamp)),
            source: .longbridge
        )
        lastQuotes[symbol.id] = quote
        onQuote?(quote)
    }

    private func publish(pushQuote payload: LongbridgePushQuote) {
        guard let symbol = symbolsByLongbridgeID[payload.symbol] else {
            return
        }

        let price = payload.lastDone
        let lastQuote = lastQuotes[symbol.id]
        let previousClose = lastQuote.map { $0.price - $0.change } ?? price
        let change = price - previousClose
        let changePercent = previousClose == 0 ? 0 : change / previousClose * 100
        let quote = Quote(
            symbol: symbol,
            price: price,
            change: change,
            changePercent: changePercent,
            candles: lastQuote?.candles ?? [],
            updatedAt: Date(timeIntervalSince1970: TimeInterval(payload.timestamp)),
            source: .longbridge
        )
        lastQuotes[symbol.id] = quote
        onQuote?(quote)
    }

    private func setConnected(_ connected: Bool) {
        guard connected != isConnected else {
            return
        }

        isConnected = connected
        onConnectionChange?(connected)
    }
}

struct LongbridgeCredentials {
    var appKey: String
    var appSecret: String
    var accessToken: String
}

enum LongbridgeConfiguration {
    static let appKeyEnvironmentKey = "LONGBRIDGE_APP_KEY"
    static let appSecretEnvironmentKey = "LONGBRIDGE_APP_SECRET"
    static let accessTokenEnvironmentKey = "LONGBRIDGE_ACCESS_TOKEN"

    static let appKeyUserDefaultsKey = "longbridge.appKey"
    static let appSecretUserDefaultsKey = "longbridge.appSecret"
    static let accessTokenUserDefaultsKey = "longbridge.accessToken"
    static let appKeyDraftUserDefaultsKey = "longbridge.draft.appKey"
    static let appSecretDraftUserDefaultsKey = "longbridge.draft.appSecret"
    static let accessTokenDraftUserDefaultsKey = "longbridge.draft.accessToken"

    static var credentials: LongbridgeCredentials? {
        guard
            let appKey = firstValue(userDefaultsKey: appKeyUserDefaultsKey, environmentKey: appKeyEnvironmentKey),
            let appSecret = firstValue(userDefaultsKey: appSecretUserDefaultsKey, environmentKey: appSecretEnvironmentKey),
            let accessToken = firstValue(userDefaultsKey: accessTokenUserDefaultsKey, environmentKey: accessTokenEnvironmentKey)
        else {
            return nil
        }

        guard isPlausible(appKey: appKey, appSecret: appSecret, accessToken: accessToken) else {
            return nil
        }

        return LongbridgeCredentials(appKey: appKey, appSecret: appSecret, accessToken: accessToken)
    }

    static var savedAppKey: String {
        UserDefaults.standard.string(forKey: appKeyUserDefaultsKey) ?? ""
    }

    static var savedAppSecret: String {
        UserDefaults.standard.string(forKey: appSecretUserDefaultsKey) ?? ""
    }

    static var savedAccessToken: String {
        UserDefaults.standard.string(forKey: accessTokenUserDefaultsKey) ?? ""
    }

    static var draftAppKey: String {
        UserDefaults.standard.string(forKey: appKeyDraftUserDefaultsKey) ?? savedAppKey
    }

    static var draftAppSecret: String {
        UserDefaults.standard.string(forKey: appSecretDraftUserDefaultsKey) ?? savedAppSecret
    }

    static var draftAccessToken: String {
        UserDefaults.standard.string(forKey: accessTokenDraftUserDefaultsKey) ?? savedAccessToken
    }

    static var hasEffectiveCredentials: Bool {
        credentials != nil
    }

    static var hasEnteredCredentials: Bool {
        clean(UserDefaults.standard.string(forKey: appKeyUserDefaultsKey)) != nil
            || clean(UserDefaults.standard.string(forKey: appSecretUserDefaultsKey)) != nil
            || clean(UserDefaults.standard.string(forKey: accessTokenUserDefaultsKey)) != nil
    }

    static var statusText: String {
        if hasEffectiveCredentials {
            return "已配置"
        }

        return hasEnteredCredentials ? "待检查" : "未配置"
    }

    static func save(appKey: String, appSecret: String, accessToken: String) {
        saveValue(appKey, forKey: appKeyUserDefaultsKey)
        saveValue(appSecret, forKey: appSecretUserDefaultsKey)
        saveValue(accessToken, forKey: accessTokenUserDefaultsKey)
        clearDraftCredentials()
    }

    static func saveDraft(appKey: String, appSecret: String, accessToken: String) {
        saveValue(appKey, forKey: appKeyDraftUserDefaultsKey)
        saveValue(appSecret, forKey: appSecretDraftUserDefaultsKey)
        saveValue(accessToken, forKey: accessTokenDraftUserDefaultsKey)
    }

    static func clearSavedCredentials() {
        UserDefaults.standard.removeObject(forKey: appKeyUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: appSecretUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: accessTokenUserDefaultsKey)
        clearDraftCredentials()
    }

    static func clearDraftCredentials() {
        UserDefaults.standard.removeObject(forKey: appKeyDraftUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: appSecretDraftUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: accessTokenDraftUserDefaultsKey)
    }

    private static func firstValue(userDefaultsKey: String, environmentKey: String) -> String? {
        if let userDefaultsValue = clean(UserDefaults.standard.string(forKey: userDefaultsKey)) {
            return userDefaultsValue
        }

        return clean(ProcessInfo.processInfo.environment[environmentKey])
    }

    private static func saveValue(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isPlausible(appKey: String, appSecret: String, accessToken: String) -> Bool {
        appKey.count == 32
            && appKey.allSatisfy(\.isHexDigit)
            && appSecret.count >= 32
            && accessToken.count > 100
    }
}

private struct LongbridgeOTPResponse: Decodable {
    var code: Int
    var message: String
    var data: LongbridgeOTPData?
}

private struct LongbridgeOTPData: Decodable {
    var otp: String
}

private struct LongbridgeSecurityQuote {
    var symbol = ""
    var lastDone = 0.0
    var previousClose = 0.0
    var timestamp: UInt64 = 0

    init(data: Data) throws {
        let fields = try ProtobufReader(data: data).fields()
        for field in fields {
            switch field.number {
            case 1:
                symbol = field.stringValue ?? symbol
            case 2:
                lastDone = field.stringValue.flatMap(Double.init) ?? lastDone
            case 3:
                previousClose = field.stringValue.flatMap(Double.init) ?? previousClose
            case 7:
                timestamp = field.varintValue ?? timestamp
            default:
                continue
            }
        }
    }
}

private struct LongbridgePushQuote {
    var symbol = ""
    var lastDone = 0.0
    var timestamp: UInt64 = 0

    init(data: Data) throws {
        let fields = try ProtobufReader(data: data).fields()
        for field in fields {
            switch field.number {
            case 1:
                symbol = field.stringValue ?? symbol
            case 3:
                lastDone = field.stringValue.flatMap(Double.init) ?? lastDone
            case 7:
                timestamp = field.varintValue ?? timestamp
            default:
                continue
            }
        }
    }
}

private enum LongbridgeSocketPacket {
    static func request(command: UInt8, requestID: UInt32, body: Data) -> Data {
        var data = Data()
        data.append(0x01)
        data.append(command)
        data.appendUInt32BE(requestID)
        data.appendUInt16BE(60_000)
        data.appendUInt24BE(UInt32(body.count))
        data.append(body)
        return data
    }

    static func response(from data: Data) throws -> LongbridgeSocketResponse? {
        guard data.count >= 10 else {
            throw LongbridgeQuoteProviderError.badSocketPacket
        }

        let bytes = [UInt8](data)
        let packetType = bytes[0] & 0x0f
        guard packetType == 2 else {
            return nil
        }

        let length = Int(bytes[7]) << 16 | Int(bytes[8]) << 8 | Int(bytes[9])
        guard data.count >= 10 + length else {
            throw LongbridgeQuoteProviderError.badSocketPacket
        }

        return LongbridgeSocketResponse(
            command: bytes[1],
            requestID: data.uint32BE(at: 2),
            status: bytes[6],
            body: data.subdata(in: 10..<(10 + length))
        )
    }

    static func push(from data: Data) throws -> LongbridgeSocketPush? {
        guard data.count >= 5 else {
            throw LongbridgeQuoteProviderError.badSocketPacket
        }

        let bytes = [UInt8](data)
        let packetType = bytes[0] & 0x0f
        guard packetType == 3 else {
            return nil
        }

        let length = Int(bytes[2]) << 16 | Int(bytes[3]) << 8 | Int(bytes[4])
        guard data.count >= 5 + length else {
            throw LongbridgeQuoteProviderError.badSocketPacket
        }

        return LongbridgeSocketPush(
            command: bytes[1],
            body: data.subdata(in: 5..<(5 + length))
        )
    }
}

private struct LongbridgeSocketResponse {
    var command: UInt8
    var requestID: UInt32
    var status: UInt8
    var body: Data
}

private struct LongbridgeSocketPush {
    var command: UInt8
    var body: Data
}

private enum ProtobufWriter {
    static func stringFields(_ number: UInt64, _ values: [String]) -> Data {
        values.reduce(into: Data()) { result, value in
            result.append(stringField(number, value))
        }
    }

    static func stringField(_ number: UInt64, _ value: String) -> Data {
        let payload = Data(value.utf8)
        var data = Data()
        data.appendVarint((number << 3) | 2)
        data.appendVarint(UInt64(payload.count))
        data.append(payload)
        return data
    }

    static func varintFields(_ number: UInt64, _ values: [UInt64]) -> Data {
        values.reduce(into: Data()) { result, value in
            result.append(varintField(number, value))
        }
    }

    static func boolField(_ number: UInt64, _ value: Bool) -> Data {
        varintField(number, value ? 1 : 0)
    }

    static func varintField(_ number: UInt64, _ value: UInt64) -> Data {
        var data = Data()
        data.appendVarint(number << 3)
        data.appendVarint(value)
        return data
    }
}

private struct ProtobufReader {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func fields() throws -> [ProtobufField] {
        var fields: [ProtobufField] = []
        var offset = 0

        while offset < data.count {
            let key = try readVarint(offset: &offset)
            let number = Int(key >> 3)
            let wireType = Int(key & 0x07)

            switch wireType {
            case 0:
                fields.append(ProtobufField(number: number, varintValue: try readVarint(offset: &offset)))
            case 2:
                let length = Int(try readVarint(offset: &offset))
                guard offset + length <= data.count else {
                    throw LongbridgeQuoteProviderError.badProtobuf
                }
                let payload = data.subdata(in: offset..<(offset + length))
                offset += length
                fields.append(ProtobufField(number: number, dataValue: payload))
            default:
                throw LongbridgeQuoteProviderError.badProtobuf
            }
        }

        return fields
    }

    func lengthDelimitedFields(number: Int) throws -> [Data] {
        try fields().compactMap { field in
            field.number == number ? field.dataValue : nil
        }
    }

    private func readVarint(offset: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift

            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
            if shift >= 64 {
                throw LongbridgeQuoteProviderError.badProtobuf
            }
        }

        throw LongbridgeQuoteProviderError.badProtobuf
    }
}

private struct ProtobufField {
    var number: Int
    var varintValue: UInt64?
    var dataValue: Data?

    var stringValue: String? {
        guard let dataValue else {
            return nil
        }

        return String(data: dataValue, encoding: .utf8)
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

enum LongbridgeQuoteProviderError: LocalizedError {
    case badCredentials
    case badResponse
    case apiError(String)
    case socketStatus(UInt8)
    case socketTimeout
    case badSocketPacket
    case badProtobuf

    var errorDescription: String? {
        switch self {
        case .badCredentials:
            return "Longbridge 配置待检查"
        case .badResponse:
            return "Longbridge 行情返回异常"
        case .apiError(let message):
            return message
        case .socketStatus(let status):
            return "Longbridge 行情连接异常：\(status)"
        case .socketTimeout:
            return "Longbridge 行情连接超时"
        case .badSocketPacket:
            return "Longbridge 行情数据包无法解析"
        case .badProtobuf:
            return "Longbridge 行情数据无法解析"
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

    var longbridgeSymbol: String {
        switch market {
        case .hongKong:
            let trimmed = code.drop { $0 == "0" }
            return "\(trimmed.isEmpty ? code : String(trimmed)).HK"
        case .shanghai:
            return "\(code).SH"
        case .shenzhen:
            return "\(code).SZ"
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

private extension Data {
    var sha1Hex: String {
        Insecure.SHA1.hash(data: self).hexString
    }

    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt24BE(_ value: UInt32) {
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendVarint(_ value: UInt64) {
        var remaining = value
        while remaining >= 0x80 {
            append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        append(UInt8(remaining))
    }

    func uint32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }
}

private extension URLSessionWebSocketTask.Message {
    var dataValue: Data {
        switch self {
        case .data(let payload):
            return payload
        case .string(let text):
            return Data(text.utf8)
        @unknown default:
            return Data()
        }
    }
}

private extension Sequence where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Insecure.SHA1Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension HMAC<SHA256>.MAC {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
