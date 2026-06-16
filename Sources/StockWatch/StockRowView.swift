import StockWatchCore
import SwiftUI

struct StockRowView: View {
    var symbol: StockSymbol
    var quote: Quote?
    var trend: [TrendPoint]
    var discreetMode: Bool
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(symbol.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(symbol.compactCode)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(priceText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(changeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(changeColor)
                    .lineLimit(1)
            }
            .frame(width: 74, alignment: .trailing)

            IntradayTrendView(points: trend, color: trendColor)
                .frame(width: 74, height: 26)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 0.75 : 0)
            .help("删除")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var priceText: String {
        guard let quote else {
            return "--"
        }

        if quote.price >= 1000 {
            return quote.price.formatted(.number.precision(.fractionLength(1)))
        }

        return quote.price.formatted(.number.precision(.fractionLength(2)))
    }

    private var changeText: String {
        guard let quote else {
            return "--"
        }

        let sign = quote.changePercent >= 0 ? "+" : ""
        return "\(sign)\(quote.changePercent.formatted(.number.precision(.fractionLength(2))))%"
    }

    private var changeColor: Color {
        guard !discreetMode, let quote else {
            return .secondary
        }

        if quote.changePercent > 0 {
            return Color(red: 0.58, green: 0.18, blue: 0.18)
        }

        if quote.changePercent < 0 {
            return Color(red: 0.20, green: 0.42, blue: 0.28)
        }

        return .secondary
    }

    private var rowBackground: Color {
        isHovered ? Color(nsColor: .controlBackgroundColor) : .clear
    }

    private var trendColor: Color {
        guard !discreetMode, let quote else {
            return .secondary
        }

        return quote.changePercent >= 0
            ? Color(red: 0.58, green: 0.18, blue: 0.18)
            : Color(red: 0.20, green: 0.42, blue: 0.28)
    }
}
