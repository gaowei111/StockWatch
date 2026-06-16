import StockWatchCore
import SwiftUI

struct IntradayTrendView: View {
    var points: [TrendPoint]
    var color: Color

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else {
                drawPlaceholder(context: context, size: size)
                return
            }

            let prices = points.map(\.price)
            let minPrice = prices.min() ?? 0
            let maxPrice = prices.max() ?? 1
            let range = max(maxPrice - minPrice, 0.0001)

            var path = Path()
            for (index, point) in points.enumerated() {
                let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * size.width
                let normalized = (point.price - minPrice) / range
                let y = size.height - CGFloat(normalized) * size.height
                let coordinate = CGPoint(x: x, y: y)

                if index == 0 {
                    path.move(to: coordinate)
                } else {
                    path.addLine(to: coordinate)
                }
            }

            context.stroke(path, with: .color(color.opacity(0.78)), lineWidth: 1.25)
        }
    }

    private func drawPlaceholder(context: GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height * 0.55))
        path.addLine(to: CGPoint(x: size.width, y: size.height * 0.55))
        context.stroke(path, with: .color(.secondary.opacity(0.28)), lineWidth: 1)
    }
}
