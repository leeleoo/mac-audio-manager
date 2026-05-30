# CoreAudioManager 🔊

一个为 macOS 打造的原生、轻量、高颜值的菜单栏多路音频输入输出管理器。完全由 **Swift 6, SwiftUI 和 AppKit** 驱动，底层直接对接 C 语言级 **CoreAudio APIs**。

---

## 💡 项目存在的原因 (Why This Project Exists?)

### 痛点背景 (The Pain Point)
在日常工作或娱乐中，我们经常需要将 Mac 的声音**同时输出到多个设备**（例如：一边用内置扬声器播放，一边用蓝牙耳机或音箱播放；或者录音时需要同时输出到耳机与采集卡）。

macOS 系统提供了一个内置的隐藏功能——在“音频 MIDI 设置”中创建一个**“多输出设备” (Multi-Output Device / Aggregate Device)**，即可实现多路同步发声。  
然而，一旦启用这个内置的多输出设备，您会遇到一个极其恶劣的系统限制：
1. **系统音量按键彻底失效**：系统的音量控制滑条会直接变灰，键盘上的 F11/F12 音量调节按键完全失效。
2. **音量调节极其难用**：如果要调节音量，你必须每次都打开繁琐的“音频 MIDI 设置”窗口，在密密麻麻的小格子中去分别调整各物理通道的绝对分贝值，体验如同灾难。

虽然市面上存在如 *SoundSource* 等优秀的商业级音频控制器，但它们大多非常昂贵、包体积臃肿、且由于非开源而存在权限安全隐患。

### 我们的解决方案 (Our Solution)
**CoreAudioManager** 专为解决此痛点而生！
- **聚合设备一键动态挂载**：在菜单栏悬浮窗中勾选“多设备同步输出”，App 会在 CoreAudio 系统底层动态创建多输出聚合设备，并自动设置为系统默认输出。
- **突破限制的独立物理音量条**：我们绕过了 macOS 聚合设备本身的音量控制死锁限制。当您在面板中调节某设备的音量时，App 直接通过 CoreAudio 写入该物理声卡 ObjectID 的 `kAudioDevicePropertyVolumeScalar` 标量属性。**这让多路输出的各声卡音量能独立且丝滑地调节，同时完美支持媒体键盘按键的双向同步跟随**。
- **崩溃残留自愈**：虚拟聚合设备只要未被主动销毁就会留存在系统音频树中。App 在冷启动时会自动进行“自检”，一键清除上次意外退出或崩溃遗留的“幽灵聚合设备”，并在主动退出时安全将默认输出还原，保证系统整洁。

---

## ✨ 核心特性 (Key Features)

- 📱 **配件运行模式**：没有 Dock 图标干扰，静默常驻系统右上角菜单栏，极其轻量。
- 🔮 **HUD 磨砂玻璃美学**：使用 `NSVisualEffectView` HUD 材质和无边框 `NSPanel` 构建悬浮控制面板，支持系统暗黑模式，呈现原生的高级毛玻璃质感。
- 📐 **自适应高度与防溢出滚动**：悬浮窗高度根据设备数量自动拉伸或缩小。当设备过多时，内置 ScrollView 会自动滚动以保证底部的重置与退出按钮永远可用。
- 🎛️ **双模快速切换**：
  - 常规单路模式：点击设备卡片，秒级切换系统主默认输入/输出，默认设备带有高亮亮蓝色微光边框。
  - 多路输出模式：一键启用多设备同步混音输出，极速勾选多个物理设备。
- 🔄 **双向音量监听**：注册 CoreAudio 底层属性监听器。当您按下键盘 F11/F12 按键或在系统偏好设置里调整物理音量时，面板上的滑块会实时联动跟随。
- 🦀 **Swift 6 内存与并发安全**：针对低级 CoreAudio 复杂 C 指针回调（`AudioObjectPropertyListenerProc`）进行了严格的 `takeRetainedValue` 内存回收封装，且在 Swift 6 严格并发保护下做到编译 0 警告、0 错误。

---

## 📦 项目文件结构 (Code Structure)

```
Sources/CoreAudioManager/
├── main.swift                 # App 运行总入口，设置配件激活策略，接管 AppDelegate 生命周期
├── AudioDevice.swift          # 音频设备 Identifiable 模型，解决 SwiftUI 刷新与动画闪烁
├── AudioDeviceManager.swift   # 音频驱动控制核。实现 C 级 CoreAudio 接口的高级封装与安全监听
├── ContentView.swift          # 支持 Outputs & Inputs 列表、音量滑块与多选逻辑的主 SwiftUI 界面
├── Panel.swift                # 自定义 NSPanel，赋予 HUD 无边框磨砂玻璃属性
└── StatusBarController.swift  # 菜单栏 NSStatusItem 控制器，精确计算垂直挂载坐标与动态高度自适应
Tests/CoreAudioManagerTests/
└── CoreAudioManagerTests.swift# 基于 Swift Testing 框架，执行单元与物理硬件联调测试
```

---

## 🛠️ 本地编译与运行 (Compilation & Run)

本项目基于标准的 **Swift Package Manager (SPM)** 构建，无需 Xcode 即可在终端直接操作：

### 1. 编译 Release 发布版本
```bash
swift build -c release
```

### 2. 后台启动运行
```bash
nohup .build/release/CoreAudioManager > /dev/null 2>&1 &
```
启动后即可在菜单栏看见 `🔊` 控制图标。

### 3. 关闭应用与安全还原
只需点击悬浮窗底部的 **"退出应用"**，App 会自动清空当前后台的虚拟聚合设备，将系统音频输出无缝重置为您先前的默认声卡，干净无残留。

### 4. 运行硬件级单元测试
```bash
swift test
```
