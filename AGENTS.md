# StockWatch Agent Notes

## Project Shape

- Native macOS SwiftUI menu-bar app built with Swift Package Manager.
- `StockWatchCore` contains stable domain models and symbol normalization.
- `StockWatch` contains the app UI, Tencent quote/search/trend providers, grouping state, and persistence.
- There is no local quote server, Python bridge, AKShare dependency, or bundled backend service.

## Commands

- Run: `swift run StockWatch`
- Test: `swift test`
- Build app bundle: `bash Scripts/build_app.sh`
- Open packaged app: `open dist/StockWatch.app`

## Data Sources

- Quotes: `https://qt.gtimg.cn/q=...`
- Search suggestions: `https://smartbox.gtimg.cn/s3/?q=...&t=all`
- Intraday trend: `https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=...`
- Treat these as public web endpoints for personal observation, not trading-grade APIs.

## Implementation Rules

- Keep the app low-profile: compact layout, muted colors, no large chart surfaces.
- Preserve serverless operation. Do not reintroduce Python, AKShare, or a local HTTP service unless explicitly requested.
- Keep generated artifacts out of git; `dist/` and `.build/` are ignored.
- Persist user watchlists with `UserDefaults`; migrate carefully if changing keys such as `watchlist.groups`.
