import SwiftUI
import Combine

@main
struct PoolserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var service = UniswapService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(service)
        } label: {
            if service.isLoading && service.positions.isEmpty {
                LoadingMenuBarLabel()
            } else {
                Text(service.titleText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct LoadingMenuBarLabel: View {
    @State private var frame = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    private let frames = ["👀 ·", "👀 ··", "👀 ···", "👀 ··"]

    var body: some View {
        Text(frames[frame])
            .onReceive(timer) { _ in
                frame = (frame + 1) % frames.count
            }
    }
}
