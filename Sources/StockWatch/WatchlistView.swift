import StockWatchCore
import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var store: WatchlistStore
    @State private var groupNameDraft = ""
    @State private var isRenamingGroup = false
    @State private var dragState: StockRowDragState?

    private let stockRowHeight: CGFloat = 40
    private let stockRowSpacing: CGFloat = 2
    private var stockRowStep: CGFloat {
        stockRowHeight + stockRowSpacing
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            groupTabs
            if isRenamingGroup {
                Divider()
                groupNameBar
            }
            Divider()
            addBar
            if !store.searchSuggestions.isEmpty {
                Divider()
                suggestionList
            }
            Divider()
            listContent
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            groupNameDraft = store.currentGroupName
        }
        .onChange(of: store.currentGroupName) { _, newName in
            groupNameDraft = newName
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("自选观察")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                store.discreetMode.toggle()
            } label: {
                Image(systemName: store.discreetMode ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(store.discreetMode ? "低调模式" : "普通涨跌色")

            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Image(systemName: store.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出 StockWatch")
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var groupTabs: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.groups) { group in
                        Button {
                            store.selectGroup(group)
                        } label: {
                            VStack(spacing: 3) {
                                Text(group.name)
                                    .font(.system(size: 11, weight: group.id == store.selectedGroupID ? .semibold : .regular))
                                    .lineLimit(1)
                                Rectangle()
                                    .fill(group.id == store.selectedGroupID ? Color.primary.opacity(0.72) : Color.clear)
                                    .frame(height: 1)
                            }
                            .frame(minWidth: 36)
                        }
                        .buttonStyle(.plain)
                        .help(group.name)
                    }
                }
                .padding(.vertical, 6)
            }

            Button {
                store.addGroup()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("新增分组")

            Button {
                groupNameDraft = store.currentGroupName
                isRenamingGroup.toggle()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("重命名当前分组")

            Button {
                store.deleteCurrentGroup()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(store.groups.count <= 1)
            .help("删除当前分组")
        }
        .padding(.horizontal, 14)
    }

    private var groupNameBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField("分组名称", text: $groupNameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    store.renameCurrentGroup(groupNameDraft)
                    isRenamingGroup = false
                }
            Button {
                store.renameCurrentGroup(groupNameDraft)
                isRenamingGroup = false
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .help("保存分组名称")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("腾讯 / 茅台 / 600519 / 00700", text: $store.newSymbolText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onChange(of: store.newSymbolText) { _, newValue in
                    store.updateSearchQuery(newValue)
                }
                .onSubmit {
                    store.addCurrentSymbol()
                }

            Button {
                store.addCurrentSymbol()
            } label: {
                Image(systemName: store.isAdding || store.isSearching ? "magnifyingglass" : "plus")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.return, modifiers: [])
            .help("添加股票")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(store.searchSuggestions) { symbol in
                Button {
                    store.addSuggestion(symbol)
                } label: {
                    HStack(spacing: 8) {
                        Text(symbol.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(symbol.compactCode)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("添加一只 A 股或港股")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let message = store.errorMessage {
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
            }

            Spacer()
            Text(store.refreshStatusText)
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 14)
        .frame(height: 22)
    }

    private var listContent: some View {
        Group {
            if store.symbols.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: stockRowSpacing) {
                        ForEach(store.symbols) { symbol in
                            StockRowView(
                                symbol: symbol,
                                quote: store.quotes[symbol.id],
                                trend: store.trends[symbol.id] ?? [],
                                discreetMode: store.discreetMode
                            ) {
                                store.remove(symbol)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: stockRowHeight)
                            .offset(y: rowOffset(for: symbol))
                            .opacity(dragState?.symbolID == symbol.id ? 0.92 : 1)
                            .shadow(
                                color: dragState?.symbolID == symbol.id ? Color.black.opacity(0.12) : .clear,
                                radius: 5,
                                x: 0,
                                y: 2
                            )
                            .zIndex(dragState?.symbolID == symbol.id ? 1 : 0)
                            .gesture(rowDragGesture(for: symbol))
                        }
                    }
                    .padding(.vertical, 2)
                    .animation(.easeInOut(duration: 0.12), value: dragState?.targetIndex)
                }
                .frame(minHeight: 145, idealHeight: 210, maxHeight: 310)
            }
        }
    }

    private func rowDragGesture(for symbol: StockSymbol) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard let currentIndex = store.symbols.firstIndex(where: { $0.id == symbol.id }) else {
                    return
                }

                let startIndex: Int
                if let dragState, dragState.symbolID == symbol.id {
                    startIndex = dragState.startIndex
                } else {
                    startIndex = currentIndex
                }

                let offset = Int((value.translation.height / stockRowStep).rounded())
                let targetIndex = min(max(startIndex + offset, 0), store.symbols.count - 1)
                dragState = StockRowDragState(
                    symbolID: symbol.id,
                    startIndex: startIndex,
                    targetIndex: targetIndex,
                    translation: value.translation.height
                )
            }
            .onEnded { _ in
                if let dragState, dragState.symbolID == symbol.id {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        _ = store.move(symbolID: symbol.id, to: dragState.targetIndex)
                    }
                }

                dragState = nil
            }
    }

    private func rowOffset(for symbol: StockSymbol) -> CGFloat {
        guard
            let dragState,
            let currentIndex = store.symbols.firstIndex(where: { $0.id == symbol.id })
        else {
            return 0
        }

        if symbol.id == dragState.symbolID {
            return dragState.translation
        }

        if dragState.targetIndex > dragState.startIndex,
           currentIndex > dragState.startIndex,
           currentIndex <= dragState.targetIndex {
            return -stockRowStep
        }

        if dragState.targetIndex < dragState.startIndex,
           currentIndex >= dragState.targetIndex,
           currentIndex < dragState.startIndex {
            return stockRowStep
        }

        return 0
    }
}

private struct StockRowDragState {
    var symbolID: String
    var startIndex: Int
    var targetIndex: Int
    var translation: CGFloat
}
