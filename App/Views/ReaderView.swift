import SwiftUI
import PDFKit
import Core

/// 阅读器页：PDF 视图 + 页面检查器 + 播放条
struct ReaderView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedPage: PDFPageText?

    private var readerVM: ReaderViewModel { app.readerVM }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            #if os(macOS)
            HSplitView {
                PDFKitViewRepresentable(document: app.document)
                    .frame(minWidth: 380, idealWidth: 560)
                pageInspector
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
            }
            #else
            PDFKitViewRepresentable(document: app.document)
            #endif
            Divider()
            PlayerBar(viewModel: readerVM, title: app.currentBook?.title ?? "")
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                app.closeBook()
            } label: {
                Label("书库", systemImage: "chevron.left")
            }
            Text(app.currentBook?.title ?? "未命名.pdf")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if app.ocrTotal > 0 {
                ProgressView(value: Double(app.ocrDone), total: Double(app.ocrTotal))
                    .frame(width: 120)
                Text("OCR \(app.ocrDone)/\(app.ocrTotal)")
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .font(.caption)
                Button {
                    app.cancelOCR()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("取消 OCR")
            } else {
                Label(
                    "\(app.pages.count) 页 · \(scannedCount) 页疑似扫描",
                    systemImage: scannedCount > 0 ? "doc.text.viewfinder" : "doc.text"
                )
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 页面检查器

    private var pageInspector: some View {
        List(selection: $selectedPage) {
            Section("页面文本状态") {
                ForEach(app.pages) { page in
                    HStack {
                        Text("第 \(page.id + 1) 页")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .leading)
                        if page.isLikelyScanned {
                            Label("需 OCR", systemImage: "viewfinder")
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                        } else {
                            Label("\(page.effectiveCharacterCount) 字", systemImage: "textformat")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .tag(page)
                }
            }
            if let selected = selectedPage, !selected.isLikelyScanned {
                Section("第 \(selected.id + 1) 页文本预览") {
                    Text(String(selected.text.prefix(2000)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            if selectedPage == nil {
                selectedPage = app.pages.first
            }
        }
    }

    private var scannedCount: Int {
        app.pages.filter(\.isLikelyScanned).count
    }
}
