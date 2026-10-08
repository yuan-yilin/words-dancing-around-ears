# 词绕耳畔（WordsDancing）实现计划

> 目标：在本仓库（words-dancing-around-ears）构建文档《chatgpt问答PDF朗读项目.md》描述的应用——
> **一个完全离线的 Apple 原生 PDF AI 阅读朗读器**：
> PDF（含扫描版 OCR）→ 中文文本 → Kokoro Mandarin 本地 AI 人声 → 播放，同时支持 iPhone 和 macOS。

---

## 一、调研结论（已在本机验证的事实）

以下结论均来自已 clone 的参考仓库，直接决定技术选型：

| 事实 | 来源 |
|---|---|
| sherpa-onnx 官方 SPM 包支持 **iOS 15+ / macOS 10.15+**，产物名 `sherpa-onnx`，当前版本 `1.13.8`，自带 xcframework（无需自己编译 ONNX Runtime） | `sherpa-onnx/Package.swift` |
| Swift 层 TTS 封装已存在：`SherpaOnnxOfflineTtsWrapper`，提供 `generate(text:sid:speed:)`、`generateWithConfig(callback:)`（流式回调）、`sampleRate`、`numSpeakers` | `sherpa-onnx/swift-api-examples/SherpaOnnx.swift:1387` |
| Kokoro 中英文模型完整调用示例（config 构造 + 生成 + 回调）已存在，可直接照抄 | `sherpa-onnx/swift-api-examples/tts-kokoro-zh-en.swift` |
| 模型下载：`https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2`，所需文件：`model.onnx / voices.bin / tokens.txt / lexicon-us-en.txt / lexicon-zh.txt / espeak-ng-data/` | 同上示例的 run 脚本 |
| 中文 8 个声音的 speaker ID：`zf_xiaobei=45, zf_xiaoni=46, zf_xiaoxiao=47, zf_xiaoyi=48, zm_yunjian=49, zm_yunxi=50, zm_yunxia=51, zm_yunyang=52`（共 53 speakers） | `sherpa-onnx/scripts/kokoro/v1.0/generate_voices_bin.py:55` |
| 原生 SwiftUI PDF 阅读 + 提取的参考实现 | `ios-pdf-tts/PDFtts/`（PDFReaderView / PDFTextExtractor） |
| 后台播放 / AudioSession / MVVM 播放器架构参考 | `runandread-ios/RunAndRead/`（Speech/AudioSessionManager、Info.plist 的 `UIBackgroundModes=audio`） |
| XcodeGen（`project.yml`）管理 Xcode 工程的先例 | `vreader/project.yml` |
| 注意：Yappy 实际是 **Tauri（Rust+Svelte）应用**，非原生 SwiftUI，仅作产品功能参考 | `yappy/yappy-app/` |

---

## 二、总体架构

```
words-dancing-around-ears/
├── project.yml                    # XcodeGen 描述：iOS / macOS 两个 App target，共享 App/ 源码
├── Packages/Core/                 # 本地 SPM 包（跨平台共享核心，纯逻辑无 UI）
│   ├── Package.swift              # 依赖 sherpa-onnx (k2-fsa, exact 1.13.8)
│   └── Sources/Core/
│       ├── PDF/                   # PDFDocumentManager / PDFTextExtractor / PDFPageRenderer
│       ├── OCR/                   # OCRProvider 协议 + VisionOCR + ReadingOrderProcessor
│       ├── TTS/                   # TTSEngine 协议 + KokoroEngine(sherpa-onnx) + TextChunker
│       ├── Audio/                 # PCMChunkPlayer (AVAudioEngine) + AudioSessionManager
│       ├── Reader/                # ReadingDocument / ReadingProgress 模型
│       └── Storage/               # ModelManager(模型下载) + 书库持久化(SwiftData 或 JSON)
├── App/                           # SwiftUI 界面（两 target 共用，少量 #if os(iOS)）
│   ├── WordsDancingApp.swift
│   ├── Views/                     # LibraryView / ReaderView / PlayerBar / VoicePickerView / ModelDownloadView
│   └── ViewModels/                # ReaderViewModel（串起 PDF→OCR→分段→TTS→播放）
├── scripts/
│   └── fetch-model.sh             # 开发期手动下载 Kokoro 模型
├── docs/ 与 PLAN.md
```

**分层原则**（与文档中建议一致）：
- `Packages/Core` 全部平台共享：PDFKit、Vision、sherpa-onnx、AVFoundation 都是跨平台框架
- 平台差异只出现在 `App/` 少量文件（文件导入方式、锁屏控制入口）用 `#if os(iOS)` 处理
- 所有引擎走协议（`OCRProvider`、`TTSEngine`），将来可换 Piper / Supertonic / AVSpeechSynthesizer

**部署目标**：iOS 17+ / macOS 14+（SwiftData 需要；sherpa-onnx 只需 iOS 15+，无冲突）。

**工具链**：Xcode 16.4（用户 macOS 15.6.1 已确认兼容）+ XcodeGen（`brew install xcodegen`，避免手维护 .xcodeproj）。

---

## 三、核心模块设计

### 1. 文本管线（PDF → 文本）

```
PDFDocument(url:)
   → 逐页 page.string 提取
   → 若某页文本几乎为空 → 该页走 OCR：
       PDFPage → CGContext 渲染 CGImage → VNRecognizeTextRequest(.accurate, ["zh-Hans","zh-Hant","en-US"], correction=false)
       → 按 boundingBox 做阅读顺序修正（先按 y 聚类分行/分栏，栏内按 y 降序、栏间按 x 升序）
   → 文本清洗（去页眉页脚/页码、去连字符断行、合并断行）
```

### 2. 分段（TextChunker）

- 中文按 `。！？；` + 换行切句，聚合成 **300–600 字** 的 chunk
- 英文数字混排时避免在单词/数字中间切断
- chunk 列表即播放队列，也是进度保存单位（存「第 N 个 chunk」）

### 3. TTS 引擎（KokoroEngine）

- 包装 `SherpaOnnxOfflineTtsWrapper`，config 照抄 `tts-kokoro-zh-en.swift`
- 模型路径用绝对路径（Application Support 下）；`espeak-ng-data` 与两个 lexicon 必须显式传
- 声音：固定暴露 8 个中文声音（sid 45–52）+ 若干英文声音
- 生成在后台线程；输出 Float PCM、采样率从 wrapper.sampleRate 读取（Kokoro 为 24000 Hz）

### 4. 流水线播放（ReaderViewModel + PCMChunkPlayer）

```
播放 chunk N（AVAudioEngine scheduleBuffer）
  ‖ 同时后台线程 generate chunk N+1
  ↓ 播完无缝衔接（预生成保证不卡顿）
```

- 播放/暂停/上一段/下一段、1.0×–2.0× 倍速（TTS speed 参数重生成 or 播放端变速，MVP 用 TTS speed）
- 后台播放：iOS `UIBackgroundModes=audio` + `AVAudioSession .playback`；锁屏控制：`MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`（仅 iOS 分支）

### 5. 模型管理（ModelManager）

- App 不内置 330MB 模型；首次选择声音时提示下载
- 下载 `kokoro-multi-lang-v1_0.tar.bz2` → 解压到 `Application Support/Models/kokoro-multi-lang-v1_0/`，带进度
- 开发期用 `scripts/fetch-model.sh` 预先下载到同一目录，跳过应用内下载

---

## 四、分阶段实施（每阶段可独立验证）

### M1 工程骨架 ✅ 完成（2026-10-09）
- ~~`Packages/Core` 建包并依赖 sherpa-onnx 1.13.8；写一个 `VersionProbe` 调 `SherpaOnnxGetVersionStr()` 验证链接成功~~
- 实际落地调整：因网络受限（GitHub Releases 二进制走 objects.githubusercontent.com 被墙），
  改为**本地 vendor**：`Packages/Core/Vendor/` 下 4 个 xcframework（checksum 与官方一致），
  Swift wrapper 用官方 `SherpaOnnx.swift` 原样拷贝；`scripts/setup-vendor.sh` 可从 `vendor-downloads/` 重建
- ~~`project.yml` 生成 iOS / macOS 两个 App target；空壳 SwiftUI 界面~~
- **验证通过**：macOS target BUILD SUCCEEDED；Core 包 8 个单测全过（版本探针 OK）

### M2 PDF 导入与阅读 ✅ 完成（2026-10-09）
- fileImporter 导入；`PDFKitView` 跨平台显示；`PDFTextExtractor` 逐页提取并标记「文字页/扫描页」（<16 字判为疑似扫描）
- macOS 双栏布局（PDF 视图 + 页面检查器），iOS 单栏
- **验证通过**：macOS BUILD SUCCEEDED

### M3 Kokoro 人声朗读 ✅ 核心链路打通（2026-10-09）
- `KokoroEngine`（封装 SherpaOnnxOfflineTtsWrapper，8 个中文声音 sid 45–52 + 4 个英文声音）
- `TextChunker`（句界切分 + 300~600 字聚合 + 超长句按子句切 + 硬切保护英文数字）7 个单测全过
- `PCMChunkPlayer`（AVAudioEngine + playerNode 源采样率连接，自动 SRC）
- `ReaderViewModel` 流水线：播放 chunk N 时后台预生成 N+1
- `ModelLocator`（开发机 `~/.local/share/wordsdancing/models` + App 沙盒 Application Support）
- **验证通过**：集成测试真实合成——中文 24 字 → 5.2s/24kHz 音频（峰值校验非静音），中英混读通过；
  试听文件 /tmp/wordsdancing-kokoro-test.wav
- UI：底栏播放条（播放/暂停/停止、段进度、声音选择、5 档语速）

### M4 扫描版 PDF：Vision OCR（待做）
- OCRProvider + VisionOCR + ReadingOrderProcessor + 文本清洗；接入自动判断逻辑
- **验证**：导入纯扫描 PDF，OCR 结果正确、多栏顺序正确、可朗读

### M5 播放体验完善
- 后台播放、锁屏控制、倍速、进度保存与恢复、书库列表（LibraryView）
- **验证**：锁屏下继续朗读、杀掉重开能续播

### M6 可选增强（后续按需）
- M4B/整本有声书导出、批量 OCR、全文搜索、英语声音补充、v1.1 模型（103 speakers）支持

---

## 五、风险与对策

| 风险 | 对策 |
|---|---|
| SPM 解析需从 GitHub 下载 xcframework（网络受限时失败） | 提前手动缓存；或改用本地 binaryTarget 路径 |
| model.onnx ~310MB，iOS 内存压力 | 分 chunk 生成、每 chunk 生成完即释放；不在生成线程持有全文音频 |
| Vision 中文 OCR 的 language correction 不支持中文 | 自己做文本清洗与阅读顺序修正（M4 已包含） |
| Kokoro 中文个别多音字不准 | 接受 MVP 级质量；TTSEngine 协议预留换 Piper 中文模型的可能 |
| .xcodeproj 频繁变动难 review | 只提交 project.yml，产物 .xcodeproj 加入 .gitignore（或提交生成物，二选一，默认不提交） |

---

## 六、环境准备清单

- [ ] Xcode 16.4（App Store 安装）
- [ ] `brew install xcodegen`
- [ ] 首次 `swift package resolve` 联网拉取 sherpa-onnx 依赖
- [ ] `scripts/fetch-model.sh` 下载 kokoro-multi-lang-v1_0（约 330MB）
