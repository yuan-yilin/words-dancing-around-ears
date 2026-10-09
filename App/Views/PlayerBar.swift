import SwiftUI
import Core
import AVFoundation

/// 底部播放条：播放/暂停/停止、上一/下一段、段进度、声音、语速
struct PlayerBar: View {
    @Bindable var viewModel: ReaderViewModel
    let title: String

    var body: some View {
        #if os(macOS)
        fullBar
        #else
        compactBar
        #endif
    }

    /// macOS 单行布局
    private var fullBar: some View {
        HStack(spacing: 12) {
            transportControls
            progressSection
            Spacer()
            pickers
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: viewModel.isPlaying) { _, playing in
            if playing {
                NowPlayingCoordinator.shared.activate(
                    title: title,
                    artist: "词绕耳畔 · \(viewModel.voice.displayName)"
                )
            }
        }
        .onChange(of: viewModel.currentChunkIndex) { _, index in
            NowPlayingCoordinator.shared.update(
                index: index,
                total: viewModel.totalChunks,
                playing: viewModel.isPlaying && !viewModel.isPaused
            )
        }
    }

    /// iOS 紧凑两行布局
    private var compactBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                transportControls
                progressSection
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                pickers
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: viewModel.isPlaying) { _, playing in
            if playing {
                NowPlayingCoordinator.shared.activate(
                    title: title,
                    artist: "词绕耳畔 · \(viewModel.voice.displayName)"
                )
            }
        }
        .onChange(of: viewModel.currentChunkIndex) { _, index in
            NowPlayingCoordinator.shared.update(
                index: index,
                total: viewModel.totalChunks,
                playing: viewModel.isPlaying && !viewModel.isPaused
            )
        }
    }

    // MARK: - 子区块

    private var transportControls: some View {
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

            Button {
                viewModel.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(!viewModel.isPlaying)

            Button {
                viewModel.previousChunk()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(viewModel.totalChunks == 0)

            Button {
                viewModel.nextChunk()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .disabled(viewModel.totalChunks == 0)
        }
    }

    private var progressSection: some View {
        HStack(spacing: 8) {
            Text("\(min(viewModel.currentChunkIndex + 1, viewModel.totalChunks))/\(viewModel.totalChunks) 段")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .help("正在后台合成下一段")
            }

            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            }
        }
    }

    private var pickers: some View {
        HStack(spacing: 12) {
            Picker("声音", selection: Binding(
                get: { viewModel.voice },
                set: { viewModel.voice = $0 }
            )) {
                ForEach(KokoroVoiceCatalog.chineseVoices) { voice in
                    Text(voice.displayName).tag(voice)
                }
            }
            .pickerStyle(.menu)
            #if os(macOS)
            .frame(maxWidth: 160)
            #else
            .frame(maxWidth: .infinity)
            #endif

            Picker("语速", selection: Binding(
                get: { viewModel.speed },
                set: { viewModel.speed = $0 }
            )) {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { s in
                    Text(String(format: "%.2g×", s)).tag(Float(s))
                }
            }
            .pickerStyle(.menu)
            #if os(macOS)
            .frame(maxWidth: 80)
            #endif
        }
    }
}

#Preview {
    PlayerBar(viewModel: ReaderViewModel(), title: "预览")
        .padding()
}
