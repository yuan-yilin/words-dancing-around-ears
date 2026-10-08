import SwiftUI
import Core

/// 书库首页：最近阅读列表 + 导入 + 模型状态
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var showImporter = false

    var body: some View {
        Group {
            if app.books.isEmpty {
                emptyState
            } else {
                bookList
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .fileImporter(
            isPresented: $showImporter,
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
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("词绕耳畔")
                .font(.title.bold())
            Text("完全离线的 PDF AI 朗读 · iPhone & Mac")
                .foregroundStyle(.secondary)
            Button {
                showImporter = true
            } label: {
                Label("导入 PDF", systemImage: "doc.badge.plus")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Text("sherpa-onnx \(SherpaOnnxInfo.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            modelSection
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 书库列表

    private var bookList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { app.currentBook?.id }, set: { _ in })) {
                Section("书库") {
                    ForEach(app.books) { book in
                        Button {
                            app.openBook(book)
                        } label: {
                            BookRow(book: book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("移出书库", role: .destructive) {
                                app.deleteBook(book)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            Divider()
            HStack(spacing: 12) {
                Button {
                    showImporter = true
                } label: {
                    Label("导入 PDF", systemImage: "doc.badge.plus")
                }
                Spacer()
                Text("\(app.books.count) 本书")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 模型状态

    @ViewBuilder
    private var modelSection: some View {
        if !app.isModelReady {
            VStack(spacing: 8) {
                Label(
                    "Kokoro 语音模型未安装（约 330MB, 下载后永久离线）",
                    systemImage: "arrow.down.circle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                if app.isModelDownloading {
                    VStack(spacing: 4) {
                        ProgressView(value: app.modelDownloadProgress)
                            .frame(width: 260)
                        HStack {
                            Text(app.modelDownloadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("取消") { app.cancelModelDownload() }
                                .controlSize(.small)
                        }
                    }
                } else {
                    Button("下载模型") {
                        app.downloadModel()
                    }
                }
            }
            .padding(.top, 24)
        }
    }
}

private struct BookRow: View {
    let book: BookRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(book.pageCount) 页")
                    Text("·")
                    Text("进度 \(book.currentChunkIndex) 段")
                    Text("·")
                    Text(book.lastReadAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview("空") {
    LibraryView()
        .environment(AppModel())
}
