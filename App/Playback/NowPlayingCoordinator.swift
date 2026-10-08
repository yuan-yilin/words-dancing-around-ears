import Foundation
import Core

#if canImport(MediaPlayer)
import MediaPlayer

/// iOS 锁屏/控制中心的「正在播放」与远程控制。
/// PlayerBar 在播放状态变化时调用 activate/update。
@MainActor
final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()
    private var active = false

    private init() {}

    func activate(title: String, artist: String) {
        guard !active else { return }
        active = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.handleRemote(.play)
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handleRemote(.pause)
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.handleRemote(.stop)
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleRemote(.next)
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.handleRemote(.previous)
            return .success
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: 0,
        ]
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func update(index: Int, total: Int, playing: Bool) {
        guard active else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(index)
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = Double(max(total, 1))
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func deactivate() {
        guard active else { return }
        active = false
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - 远程指令分发

    private var readerVM: ReaderViewModel? {
        // 通过共享的模型访问当前播放器
        NowPlayingBridge.shared.reader
    }

    private func handleRemote(_ action: RemoteAction) {
        switch action {
        case .play: readerVM?.play()
        case .pause: readerVM?.pause()
        case .stop: readerVM?.stop()
        case .next: readerVM?.nextChunk()
        case .previous: readerVM?.previousChunk()
        }
    }

    private enum RemoteAction {
        case play, pause, stop, next, previous
    }
}

/// 桥接：AppModel 播放时注入 readerVM, 锁屏控制通过它转发指令
@MainActor
final class NowPlayingBridge {
    static let shared = NowPlayingBridge()
    weak var reader: ReaderViewModel?
    private init() {}
}

#endif
