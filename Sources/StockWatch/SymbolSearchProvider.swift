import Foundation
import StockWatchCore

@MainActor
protocol SymbolSearchProvider {
    func search(_ query: String) async throws -> [StockSymbol]
}

struct TencentSymbolSearchProvider: SymbolSearchProvider {
    private let endpoint = URL(string: "https://smartbox.gtimg.cn/s3/")!

    func search(_ query: String) async throws -> [StockSymbol] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "t", value: "all")
        ]

        guard let url = components?.url else {
            throw SymbolSearchError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SymbolSearchError.badResponse
        }

        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        guard let text = String(data: data, encoding: encoding) else {
            throw SymbolSearchError.badEncoding
        }

        return parseSearchResponse(text)
    }

    private func parseSearchResponse(_ text: String) -> [StockSymbol] {
        guard let assignmentRange = text.range(of: "=\"") else {
            return []
        }

        let escapedPayload = text[assignmentRange.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: "\";\n\r"))
        let payload = decodeJavaScriptEscapes(String(escapedPayload))
        let candidates = payload.split(separator: "^").map(String.init)

        return Array(candidates
            .compactMap(parseCandidate)
            .filter { symbol in
                symbol.market == .shanghai || symbol.market == .shenzhen || symbol.market == .hongKong
            }
            .prefix(5))
    }

    private func parseCandidate(_ candidate: String) -> StockSymbol? {
        let values = candidate.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard values.count >= 5 else {
            return nil
        }

        let marketCode = values[0].uppercased()
        let rawCode = values[1]
        let name = values[2]
        let assetType = values[4].uppercased()

        guard assetType.hasPrefix("GP") else {
            return nil
        }

        switch marketCode {
        case "SH":
            return StockSymbol(market: .shanghai, code: rawCode.leftPadded(to: 6), name: name)
        case "SZ":
            return StockSymbol(market: .shenzhen, code: rawCode.leftPadded(to: 6), name: name)
        case "HK":
            return StockSymbol(market: .hongKong, code: rawCode.leftPadded(to: 5), name: name)
        default:
            return nil
        }
    }

    private func decodeJavaScriptEscapes(_ text: String) -> String {
        let json = "\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
        guard
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(String.self, from: data)
        else {
            return text
        }

        return decoded
    }
}

enum SymbolSearchError: LocalizedError {
    case invalidEndpoint
    case badResponse
    case badEncoding

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "股票搜索地址无效"
        case .badResponse:
            return "股票搜索返回异常"
        case .badEncoding:
            return "股票搜索编码无法解析"
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
