# StockWatch

StockWatch 是一个低存在感的 macOS 菜单栏股票观察小窗，面向 A 股和港股自选股。它使用原生 SwiftUI 构建，App 直接访问腾讯公开行情接口，不需要本地 server。

## 功能

- 菜单栏小窗口，不显示 Dock 图标。
- 支持自选股分组 tab，可新增、删除分组，并自定义分组名称。
- 支持在当前分组内添加、删除、拖拽排序股票。
- 支持代码添加，例如 `700`、`00700`、`HK.00700`、`600519`、`SZ.000001`。
- 支持中文名称搜索联想，点击建议项即可加入当前分组。
- 行内展示名称、代码、价格、涨跌幅和当天迷你走势线。
- 自动刷新会按 A 股和港股交易时段运行，非交易时段暂停行情请求。
- 默认开启低调模式，涨跌和走势颜色使用灰度。
- 首次启动默认自选：腾讯控股、贵州茅台、平安银行。

## 环境要求

- macOS 14 或更新版本。
- Xcode Command Line Tools，Swift 6.3 或更新版本。
- 能访问腾讯公开行情接口的网络环境。

## 运行

```bash
swift run StockWatch
```

## 测试

```bash
swift test
```

## 打包 App

```bash
bash Scripts/build_app.sh
open dist/StockWatch.app
```

打包产物位置：

```text
dist/StockWatch.app
```

`dist/` 和 `.build/` 是生成产物，不进入 git。

## 项目结构

```text
Sources/StockWatchCore
  StockSymbol.swift        领域模型：市场、股票、报价、走势点
  SymbolNormalizer.swift   本地代码/名称规范化和常用别名
  TradingRefreshSchedule.swift  A 股/港股交易时段刷新调度

Sources/StockWatch
  StockWatchApp.swift          macOS 菜单栏 App 入口
  WatchlistView.swift          主窗口 UI
  StockRowView.swift           单行股票展示
  WatchlistStore.swift         分组、持久化、刷新、添加/删除逻辑
  QuoteProvider.swift          腾讯行情获取和解析
  SymbolSearchProvider.swift   腾讯股票搜索联想
  IntradayTrendProvider.swift  腾讯当天走势数据获取
  IntradayTrendView.swift      迷你走势线渲染

Scripts/build_app.sh       生成 dist/StockWatch.app
Tests/StockWatchTests      股票代码/名称规范化和交易时段测试
```

## 数据源

StockWatch 在 App 内直接访问腾讯公开网页接口：

- 实时报价：`https://qt.gtimg.cn/q=...`
- 搜索联想：`https://smartbox.gtimg.cn/s3/?q=...&t=all`
- 当天走势：`https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=...`

这些接口适合个人观察使用，不是正式授权的交易级 API，不建议用于自动交易或商业行情分发。

## 持久化

自选分组、当前选中分组、低调模式保存在 `UserDefaults`。

主要 key：

- `watchlist.groups`
- `watchlist.selectedGroupID`
- `watchlist.discreetMode`

旧版 `watchlist.symbols` 仍会读取一次，用于迁移到默认分组。

## 刷新规则

后台自动刷新只在当前分组股票所属市场的交易窗口内请求行情。混合 A 股/港股分组里，只刷新当前仍在交易窗口内的市场；手动点击刷新按钮仍会立即请求全部当前分组股票。

- A 股：工作日 `09:15-11:35`、`12:55-15:10`。
- 港股：工作日 `09:15-12:05`、`12:55-16:15`。
- 非交易窗口不请求行情接口，只做低频本地时间检查。

当前版本只按 Asia/Shanghai 时区的工作日和交易时段判断，暂未接入交易所节假日表。

## 维护注意

- 保持 UI 紧凑、低调，定位是工作电脑上的一眼观察工具。
- 除非有明确需求，不要重新引入 Python、AKShare 或本地 HTTP server。
- 修改腾讯接口解析时，要同时验证 A 股和港股。
- 修改持久化 key 时，要保留对已有用户数据的迁移。

## 后续计划

- 正式签名打包 `.app`，支持可选开机自启动。
- 设置页：刷新间隔、透明度、置顶行为。
