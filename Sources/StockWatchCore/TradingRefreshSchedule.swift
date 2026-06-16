import Foundation

public enum TradingRefreshSchedule {
    public static let activeRefreshInterval: TimeInterval = 12
    public static let idleCheckInterval: TimeInterval = 300

    private static let tradingTimeZone = TimeZone(identifier: "Asia/Shanghai")!

    private struct TradingWindow {
        var startMinute: Int
        var endMinute: Int

        func contains(_ minute: Int) -> Bool {
            minute >= startMinute && minute <= endMinute
        }
    }

    public static func isActive(for symbols: [StockSymbol], at date: Date = Date()) -> Bool {
        let markets = Set(symbols.map(\.market))
        guard !markets.isEmpty, isWeekday(date) else {
            return false
        }

        return markets.contains(where: { market in
            isActive(for: market, at: date)
        })
    }

    public static func activeSymbols(from symbols: [StockSymbol], at date: Date = Date()) -> [StockSymbol] {
        symbols.filter { isActive(for: $0.market, at: date) }
    }

    public static func nextDelay(for symbols: [StockSymbol], at date: Date = Date()) -> TimeInterval {
        guard !symbols.isEmpty else {
            return idleCheckInterval
        }

        guard !isActive(for: symbols, at: date) else {
            return activeRefreshInterval
        }

        guard let nextOpen = nextOpenDate(for: Set(symbols.map(\.market)), after: date) else {
            return idleCheckInterval
        }

        let wait = max(activeRefreshInterval, nextOpen.timeIntervalSince(date))
        return min(wait, idleCheckInterval)
    }

    public static func statusText(for symbols: [StockSymbol], at date: Date = Date()) -> String {
        guard !symbols.isEmpty else {
            return "空"
        }

        return isActive(for: symbols, at: date) ? "12s" : "休市"
    }

    private static func windows(for market: Market) -> [TradingWindow] {
        switch market {
        case .shanghai, .shenzhen:
            return [
                TradingWindow(startMinute: minutes(hour: 9, minute: 15), endMinute: minutes(hour: 11, minute: 35)),
                TradingWindow(startMinute: minutes(hour: 12, minute: 55), endMinute: minutes(hour: 15, minute: 10)),
            ]
        case .hongKong:
            return [
                TradingWindow(startMinute: minutes(hour: 9, minute: 15), endMinute: minutes(hour: 12, minute: 5)),
                TradingWindow(startMinute: minutes(hour: 12, minute: 55), endMinute: minutes(hour: 16, minute: 15)),
            ]
        }
    }

    private static func isActive(for market: Market, at date: Date) -> Bool {
        guard isWeekday(date) else {
            return false
        }

        let currentMinute = minuteOfDay(for: date)
        return windows(for: market).contains { $0.contains(currentMinute) }
    }

    private static func nextOpenDate(for markets: Set<Market>, after date: Date) -> Date? {
        guard !markets.isEmpty else {
            return nil
        }

        let calendar = tradingCalendar
        let currentMinute = minuteOfDay(for: date)

        for dayOffset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay(for: date)) else {
                continue
            }

            guard isWeekday(candidateDay) else {
                continue
            }

            let candidateWindows = markets
                .flatMap(windows(for:))
                .map(\.startMinute)
                .sorted()

            for startMinute in candidateWindows {
                if dayOffset == 0, startMinute <= currentMinute {
                    continue
                }

                return makeDate(on: candidateDay, minuteOfDay: startMinute)
            }
        }

        return nil
    }

    private static var tradingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tradingTimeZone
        return calendar
    }

    private static func isWeekday(_ date: Date) -> Bool {
        let weekday = tradingCalendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    private static func minuteOfDay(for date: Date) -> Int {
        let components = tradingCalendar.dateComponents([.hour, .minute], from: date)
        return minutes(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    private static func startOfDay(for date: Date) -> Date {
        tradingCalendar.startOfDay(for: date)
    }

    private static func makeDate(on day: Date, minuteOfDay: Int) -> Date? {
        var components = tradingCalendar.dateComponents([.year, .month, .day], from: day)
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        components.second = 0
        return tradingCalendar.date(from: components)
    }

    private static func minutes(hour: Int, minute: Int) -> Int {
        hour * 60 + minute
    }
}
