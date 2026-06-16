import AppKit
import StockWatchCore
import SwiftUI

@main
struct StockWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WatchlistStore()

    var body: some Scene {
        MenuBarExtra("StockWatch", systemImage: "chart.line.uptrend.xyaxis") {
            WatchlistView()
                .environmentObject(store)
                .frame(width: 318)
                .frame(minHeight: 320)
                .task {
                    store.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
