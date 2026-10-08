import SwiftUI
import Core

/// 根视图：书库 ⇄ 阅读器切换
struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            LibraryView()
                .opacity(app.isReading ? 0 : 1)
                .allowsHitTesting(!app.isReading)
            if app.isReading {
                ReaderView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: app.isReading)
        .onChange(of: app.isReading) { _, reading in
            #if canImport(MediaPlayer)
            if !reading {
                NowPlayingCoordinator.shared.deactivate()
            }
            // 播放中离开阅读页 = 停止（MVP 简化；后台播放只发生在阅读器停留时）
            #endif
        }
    }
}
