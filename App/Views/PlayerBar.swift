import SwiftUI
import Core
import AVFoundation

/// 底部播放条：播放/暂停/停止、上一/下一段、段进度、声音、语速
struct PlayerBar: View {
    @Bindable var viewModel: ReaderViewModel
    let title: String

    var body: some View {
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
            .disabled(!viewModel.isPlaying)
            .help("停止")

            Button {
                viewModel.previousChunk()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(viewModel.totalChunks == 0)
            .help("上一段")

            Button {
                viewModel.nextChunk()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .disabled(viewModel.totalChunks == 0)
            .help("下一段")

            Text("\(min(viewModel.currentChunkIndex + 1, viewModel.totalChunks))/\(viewModel.totalChunks) 段")
                .monospacedDigit()
                .foregroundStyle(.secondary)

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
}

#Preview {
    PlayerBar(viewModel: ReaderViewModel(), title: "预览")
        .padding()
}
