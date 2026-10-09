import SwiftUI
import Core
import UniformTypeIdentifiers

/// 根视图：书库 ⇄ 阅读器切换。
/// fileImporter 与 alert 统一挂在这一层（挂在内层与 alert 同层级会互相卡死呈现）。
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: Binding(
                get: { app.showImporter },
                set: { app.showImporter = $0 }
            ),
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                app.importPDF(url: url)
            }
        }
        .alert("错误", isPresented: .init(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.clearError() } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
        .animation(.easeInOut(duration: 0.15), value: app.isReading)
        .onChange(of: app.isReading) { _, reading in
            #if canImport(MediaPlayer)
            if !reading {
                NowPlayingCoordinator.shared.deactivate()
            }
            #endif
        }
    }
}

