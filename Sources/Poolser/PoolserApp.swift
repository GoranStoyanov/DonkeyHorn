import SwiftUI

@main
struct PoolserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var service = UniswapService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(service)
        } label: {
            Text(service.titleText)
        }
        .menuBarExtraStyle(.window)
    }
}
