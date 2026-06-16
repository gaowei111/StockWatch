import Foundation
import StockWatchCore

@MainActor
protocol IntradayTrendProvider {
    func fetchTrends(for symbols: [StockSymbol]) async -> [String: [TrendPoint]]
}

@MainActor
struct TencentIntradayTrendProvider: IntradayTrendProvider {
    func fetchTrends(for symbols: [StockSymbol]) async -> [String: [TrendPoint]] {
        var trends: [String: [TrendPoint]] = [:]

        await withTaskGroup(of: (String, [TrendPoint]).self) { group in
            for symbol in symbols {
                group.addTask {
                    let points = await Self.fetchTrend(for: symbol)
                    return (symbol.id, points)
                }
            }

            for await (symbolID, points) in group where !points.isEmpty {
                trends[symbolID] = points
            }
        }

        return trends
    }

    private static func fetchTrend(for symbol: StockSymbol) async -> [TrendPoint] {
        guard let url = URL(string: "https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=\(symbol.tencentCode)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return []
            }

            let payload = try JSONDecoder().decode(TencentMinuteResponse.self, from: data)
            return payload.data[symbol.tencentCode]?.data.data.compactMap(Self.parsePoint) ?? []
        } catch {
            return []
        }
    }

    private static func parsePoint(_ raw: String) -> TrendPoint? {
        let parts = raw.split(separator: " ")
        guard parts.count >= 2, let price = Double(parts[1]) else {
            return nil
        }

        return TrendPoint(time: String(parts[0]), price: price)
    }
}

private struct TencentMinuteResponse: Decodable {
    var data: [String: TencentMinuteSymbolData]
}

private struct TencentMinuteSymbolData: Decodable {
    var data: TencentMinuteData
}

private struct TencentMinuteData: Decodable {
    var data: [String]
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
