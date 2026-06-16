# StockWatch

StockWatch is a low-profile macOS menu-bar stock watcher for A-share and Hong Kong market watchlists. It is built as a native SwiftUI app and talks directly to public Tencent market endpoints, so it does not need a local server.

## Features

- Menu-bar window with no Dock icon.
- Group tabs for watchlists, including add/delete group and custom group names.
- Add/remove stocks in the active group.
- Add by code, for example `700`, `00700`, `HK.00700`, `600519`, `SZ.000001`.
- Add by Chinese name with search suggestions; clicking a suggestion adds it to the active group.
- Rows show name, code, price, change percent, and a compact intraday trend line.
- Discreet mode is enabled by default and renders change/trend colors in muted gray.
- Default symbols on first launch: 腾讯控股, 贵州茅台, 平安银行.

## Requirements

- macOS 14 or newer.
- Xcode command-line tools with Swift 6.3 or newer.
- Network access to Tencent public quote endpoints.

## Run

```bash
swift run StockWatch
```

## Test

```bash
swift test
```

## Build App Bundle

```bash
bash Scripts/build_app.sh
open dist/StockWatch.app
```

The app bundle is generated at:

```text
dist/StockWatch.app
```

Generated build output is intentionally ignored by git.

## Project Structure

```text
Sources/StockWatchCore
  StockSymbol.swift        Domain models: market, symbol, quote, trend point
  SymbolNormalizer.swift   Local code/name normalization and common aliases

Sources/StockWatch
  StockWatchApp.swift          macOS menu-bar app entry
  WatchlistView.swift          Main window UI
  StockRowView.swift           One watchlist row
  WatchlistStore.swift         Groups, persistence, refresh, add/remove logic
  QuoteProvider.swift          Tencent quote fetch and parsing
  SymbolSearchProvider.swift   Tencent search suggestions
  IntradayTrendProvider.swift  Tencent intraday trend fetch
  IntradayTrendView.swift      Compact trend rendering

Scripts/build_app.sh       Creates dist/StockWatch.app
Tests/StockWatchTests      Symbol normalization tests
```

## Data Sources

StockWatch uses public Tencent web endpoints directly from the app:

- Quotes: `https://qt.gtimg.cn/q=...`
- Search suggestions: `https://smartbox.gtimg.cn/s3/?q=...&t=all`
- Intraday trend: `https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=...`

These endpoints are suitable for personal observation. They are not official trading-grade APIs and should not be used for automated trading or commercial market-data distribution.

## Persistence

Watchlist groups, selected group, and discreet mode are stored in `UserDefaults`.

Important keys:

- `watchlist.groups`
- `watchlist.selectedGroupID`
- `watchlist.discreetMode`

The legacy `watchlist.symbols` key is still read once for migration into the default group.

## Maintenance Notes

- Keep the UI compact and muted; this is intended to be a work-computer glance tool.
- Keep the app serverless unless a future requirement explicitly needs richer historical data.
- If changing Tencent response parsing, verify both A-share and HK symbols.
- If changing persistence keys, preserve migration for existing users.

## Planned Improvements

- Formal signed `.app` packaging and optional launch at login.
- Settings for refresh interval, opacity, and always-on-top behavior.
- Trading-session-aware refresh intervals.
