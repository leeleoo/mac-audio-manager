# macOS 多路音频设备管理器设计方案 (macOS Multi-Device Audio Manager Spec)

本项目旨在开发一款轻量、现代的 macOS 菜单栏应用，使用户能够轻松管理系统音频输入输出设备，并实现无延迟的多设备同步输出以及独立的音量调节功能，解决 macOS 系统原生 Audio MIDI 设置中对多输出设备音量调节极其难用的痛点。

---

## 1. 交互与 UI 架构设计 (UX & Window Architecture)

为了呈现原生、高质感且快捷的操作体验，我们采用 **菜单栏常驻图标 + 自定义悬浮控制面板** 的混合交互模式：

### 1.1 系统集成 (AppKit StatusItem)
- 应用在系统后台静默运行，不占用 Dock 栏，完全在菜单栏运行。
- 在 macOS 右上角状态栏注册一个 `NSStatusItem`。
- 图标采用 macOS 原生 `SF Symbols` 字符（如 `speaker.wave.2`），支持系统暗黑模式自适应变色。

### 1.2 悬浮面板 (NSPanel with SwiftUI)
- 常规的 SwiftUI `MenuBarExtra` 无法定制无边框和高品质毛玻璃背景。我们自定义一个 AppKit `NSPanel` 作为容器，其属性配置如下：
  - `styleMask`: `.nonactivatingPanel` 配合 `.borderless`（保证窗口无边框、不抢占前台输入焦点）。
  - `level`: `.statusBar`（确保悬浮窗始终层级最高，能盖在其他应用之上）。
  - `hidesOnDeactivate = true`（实现焦点失去时自动淡出隐藏）。
  - `backgroundColor = .clear`。
- **毛玻璃效果 backing**：使用 `NSVisualEffectView` 作为 `NSPanel` 的背景视图，设置材质为 `.hudWindow` 或 `.popover`，并根据系统暗黑模式自适应。
- **SwiftUI 视图承载**：使用 `NSHostingView(rootView: ContentView)` 将 SwiftUI 控制面板嵌入 `NSPanel` 中。

### 1.3 窗口智能定位
- 每次用户点击菜单栏图标时，悬浮窗都会在显示前动态获取当前 StatusItem 按钮的屏幕物理坐标（`statusItem.button.window.frame`）。
- 悬浮窗会计算并贴合在状态栏按钮正下方水平居中的位置，带微小的滑动出现动画。

---

## 2. CoreAudio 音频引擎设计 (CoreAudio Engine)

应用的核心数据处理由底层 Swift 对 CoreAudio C API 的封装承担。

### 2.1 数据结构映射
```swift
struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID      // CoreAudio 对象句柄
    let name: String            // 设备名称 (如 "Built-in Speakers")
    let uid: String             // 设备持久化唯一标识 (如 "AppleGFXHDA-Output-1")
    let isInput: Bool           // 是否为输入设备
    var volume: Float           // 音量标量 (0.0 ~ 1.0)
    var isMuted: Bool           // 是否静音
}
```

### 2.2 多路输出实现 (Aggregate Device)
macOS 默认仅允许选择一个输出目标。要让声音同时进入多个物理设备（例如：扬声器与耳机同时响），我们通过动态创建虚拟聚合设备来实现：
1. **聚合设备创建**：
   - 当用户启用“多设备输出”并勾选多个物理设备时，调用 CoreAudio API 的 `AudioHardwareCreateAggregateDevice` 动态创建一个虚拟的 `Aggregate Device`。
2. **子设备绑定 (Sub-devices Binding)**：
   - 将选中的物理设备的 UID（如内置扬声器、蓝牙耳机）封装进字典，将其配置为该聚合设备的 `kAudioAggregateDevicePropertyFullSubDeviceList` 属性。
   - 设定首选的设备作为主时钟源 (`kAudioSubDevicePropertyDriftCompensation`），防止多设备声音同步漂移。
3. **系统默认输出切换**：
   - 调用 API 将当前默认系统输出（`kAudioHardwarePropertyDefaultOutputDevice`）切换至此新创建的虚拟聚合设备。系统会自动把所有 App 播放的音频混合并发送给这个聚合设备，随后被 CoreAudio 分发至所有绑定的子物理通道中。

### 2.3 物理音量独立调节机制（关键避坑设计）
macOS 官方的“多输出设备”设计中，系统会将聚合设备本身的音量控制置灰，提示“此设备没有主音量控制”。  
**我们的核心解决方案**：
- 当用户在我们的悬浮窗 UI 中拖动某个子设备的音量滑块时，我们的 `AudioDeviceManager` 会**直接对该物理设备（Sub-device）的 `AudioObjectID`** 进行操作。
- 我们使用 CoreAudio C API 修改物理设备的音量属性：
  ```swift
  var volumeValue = newVolume // Float 0.0 - 1.0
  var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain // 兼容新旧系统的 Main/Master 元素
  )
  AudioObjectSetPropertyData(physicalDeviceID, &propertyAddress, 0, nil, UInt32(MemoryLayout<Float>.size), &volumeValue)
  ```
- 这样，系统音频流以 100% 音量无损传入虚拟聚合设备，而各物理设备的最终输出音量完全由我们的滑块调节，从而完美解决音量失控问题。

---

## 3. 双向数据同步与生命周期监听 (Listeners & Lifecycle)

为了保证 App 在设备插拔和系统调节音量时的准确反应，我们设计了一套完善的监听与生命周期保障机制。

### 3.1 CoreAudio 实时监听器
1. **物理设备列表监听 (Plug & Play Listener)**：
   - 在系统音频对象 `kAudioObjectSystemObject` 上注册监听属性 `kAudioHardwarePropertyDevices`。
   - 当插入或拔出 USB 耳机、连接/断开蓝牙耳机时，触发回调通知 `AudioDeviceManager`，自动重载物理设备列表。如果当前正在多设备输出中，且被移除的设备在输出列表中，则自动重构聚合设备；如果设备插入，则将其无缝加入可选列表。
2. **音量同步监听 (Volume Follower)**：
   - 对每一个活跃的物理设备注册监听属性 `kAudioDevicePropertyVolumeScalar`。
   - 当用户在系统“声音偏好设置”或使用键盘上的物理媒体按键（F11/F12）调节某个物理设备音量时，监听器会收到系统回调。
   - 回调触发 Swift 中的属性发布器更新（`@Published`），悬浮面板上的对应音量滑块会**实时跟随系统同步移动**。

### 3.2 完备的生命周期清理
为防止在系统中残留未销毁的虚拟设备，App 包含严格的清理职责：
1. **正常退出销毁 (Graceful Stop)**：
   - 当用户点击“退出应用”或系统发出 `applicationWillTerminate` 通知时，App 优先将系统主输出切换回某个安全的物理备份设备（如内置扬声器）。
   - 接着向 CoreAudio 发送销毁命令，彻底删除我们创建的 Aggregate Device。
2. **崩溃与异常自检 (Crash Protection & Self-Check)**：
   - 聚合设备在 CoreAudio 中一旦创建，只要未显式销毁，即使 App 崩溃也会留存在系统（表现为 MIDI 设置中的幽灵设备）。
   - **解决方案**：在 App 每次启动（`applicationDidFinishLaunching`）时，启动一个**残留自检逻辑**。扫描 CoreAudio 中现存的所有聚合设备。若发现名称或特征匹配我们 App 创建的“残留虚拟设备”，则自动调用销毁接口将其彻底清除，保证系统音频树的纯净。

---

## 4. 验证与测试计划 (Verification Plan)

由于音频设备控制极其依赖 macOS 真实硬件环境，我们设计了自动化构建验证与硬件功能跑测方案。

### 4.1 构建验证
- 使用 macOS 命令行工具或 Swift Package Manager 进行静态分析与构建：
  ```bash
  swift build
  ```
- 确保代码没有任何 Swift 编译器警告，且 CoreAudio C 桥接层类型转换无任何安全漏洞。

### 4.2 功能与边界条件手动测试
1. **基础路由测试**：
   - 单选切换：在悬浮面板中单击某输入或输出设备，验证系统默认设备是否能秒级切换，且系统声音正常。
2. **多设备输出与音量控制测试**：
   - 勾选“内置扬声器”和“蓝牙耳机/外接显示器”，验证虚拟设备是否成功创建并自动设为默认。
   - 佩戴耳机并播放音乐，验证耳机与内置扬声器是否同时发出同步混音。
   - 拖动内置扬声器滑块，验证扬声器声音是否减小而耳机音量不受影响。
   - 使用物理键盘音量键调节，验证悬浮面板滑块是否正确联动同步。
 3. **鲁棒性与异常测试**：
   - 在多输出播放过程中直接拔掉耳机，验证系统是否平滑重构聚合设备，且音频输出正常切换不发生崩溃。
   - 通过终端强杀 App 进程模拟崩溃，重新启动 App，验证“残留自检逻辑”是否能完美扫描并销毁残留的虚拟设备。
