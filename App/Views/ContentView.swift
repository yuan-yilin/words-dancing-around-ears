import SwiftUI
import PDFKit
import Core
import UniformTypeIdentifiers

/// M2：PDF 导入 → 阅读 → 逐页文本提取与「文字页/扫描页」判断
struct ContentView: View {
    @State private var document: PDFDocument?
    @State private var documentURL: URL?
    @State private var pages: [PDFPageText] = []
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var selectedPage: PDFPageText?
    @State private var readerVM = ReaderViewModel()
    // OCR 进度（0 = 未在跑）
    @State private var ocrDone = 0
    @State private var ocrTotal = 0
    @State private var ocrTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let document {
                readerLayout(document)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                openPDF(url: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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
            Text("离线 PDF AI 朗读")
                .foregroundStyle(.secondary)
            Button {
                showImporter = true
            } label: {
                Label("导入 PDF", systemImage: "doc.badge.plus")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Text("sherpa-onnx \(SherpaOnnxInfo.version) · onnxruntime \(SherpaOnnxInfo.onnxruntimeVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 阅读布局

    private func readerLayout(_ document: PDFDocument) -> some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            #if os(macOS)
            HSplitView {
                PDFKitViewRepresentable(document: document)
                    .frame(minWidth: 380, idealWidth: 560)
                pageInspector
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
            }
            #else
            PDFKitViewRepresentable(document: document)
            #endif
            Divider()
            PlayerBar(viewModel: readerVM)
        }
    }

    // MARK: - 播放控制条

    private func PlayerBar(viewModel: ReaderViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                if viewModel.isPlaying && !viewModel.isPaused {
                    viewModel.pause()
                } else {
                    viewModel.play()
                }
            } label: {
                Image(systemName: viewModel.isEngineLoading
                      ? "hourglass"
                      : (viewModel.isPlaying && !viewModel.isPaused ? "pause.fill" : "play.fill"))
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.totalChunks == 0 || viewModel.isEngineLoading)
            .help(viewModel.isEngineLoading ? "正在加载模型…" : (viewModel.isPlaying && !viewModel.isPaused ? "暂停" : "播放"))

            Button {
                viewModel.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .controlSize(.regular)
            .disabled(!viewModel.isPlaying)
            .help("停止")

            Text("\(min(viewModel.currentChunkIndex + 1, viewModel.totalChunks))/\(viewModel.totalChunks) 段")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            }

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .help("正在后台合成下一段")
            }

            Spacer()

            Picker("声音", selection: Binding(
                get: { viewModel.voice },
                set: { viewModel.voice = $0 }
            )) {
                ForEach(KokoroVoiceCatalog.chineseVoices) { voice in
                    Text(voice.displayName).tag(voice)
                }
            }
            .frame(maxWidth: 160)

            Picker("语速", selection: Binding(
                get: { viewModel.speed },
                set: { viewModel.speed = $0 }
            )) {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { s in
                    Text(String(format: "%.2g×", s)).tag(Float(s))
                }
            }
            .frame(maxWidth: 80)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                showImporter = true
            } label: {
                Label("打开…", systemImage: "folder")
            }
            Text(documentURL?.lastPathComponent ?? "未命名.pdf")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if ocrTotal > 0 {
                ProgressView(value: Double(ocrDone), total: Double(ocrTotal))
                    .frame(width: 120)
                Text("OCR \(ocrDone)/\(ocrTotal)")
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .font(.caption)
                Button {
                    ocrTask?.cancel()
                    ocrTotal = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("取消 OCR")
            } else {
                Label(
                    "\(pages.count) 页 · \(scannedCount) 页疑似扫描",
                    systemImage: scannedCount > 0 ? "doc.text.viewfinder" : "doc.text"
                )
                .foregroundStyle(.secondary)
                if scannedCount > 0 {
                    Button("识别扫描页") {
                        if let document { startOCR(document: document) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var pageInspector: some View {
        List(selection: $selectedPage) {
            Section("页面文本状态") {
                ForEach(pages) { page in
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
    }

    private var scannedCount: Int {
        pages.filter(\.isLikelyScanned).count
    }

    // MARK: - 行为

    /// 把当前页面文本（含 OCR 结果）装载进朗读器
    private func reloadReadingText() {
        let fullText = pages
            .filter { !$0.isLikelyScanned }
            .map(\.text)
            .joined(separator: "\n")
        readerVM.load(text: fullText)
    }

    /// 后台跑 OCR, 完成后替换扫描页文本并重新装载朗读全文
    private func startOCR(document: PDFDocument) {
        ocrTask?.cancel()
        ocrTotal = pages.filter(\.isLikelyScanned).count
        ocrDone = 0
        let sourcePages = pages

        ocrTask = Task { @MainActor in
            let result = await PDFOCRPipeline.process(
                document: document,
                pages: sourcePages
            ) { done, total in
                self.ocrDone = done
                self.ocrTotal = total
            }
            if !Task.isCancelled {
                self.pages = result
                reloadReadingText()
            }
            self.ocrDone = 0
            self.ocrTotal = 0
        }
    }

    private func openPDF(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            guard let doc = PDFDocument(url: url) else {
                throw PDFExtractionError.cannotOpenDocument
            }
            self.document = doc
            self.documentURL = url
            self.pages = PDFTextExtractor.extractPages(from: doc)
            self.selectedPage = pages.first
            reloadReadingText()
            // 打开即自动识别扫描页（识别中可取消）
            if pages.contains(where: \.isLikelyScanned) {
                startOCR(document: doc)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
