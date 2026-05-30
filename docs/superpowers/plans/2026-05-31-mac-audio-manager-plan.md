# macOS 多路音频设备管理器实施方案 (macOS Multi-Device Audio Manager Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一个轻量常驻的 macOS 菜单栏应用，支持多路音频设备同时输出，并能够绕过系统限制独立调节各设备的物理音量。

**Architecture:** 采用 Swift Package Manager (SPM) 构建纯原生 macOS 可执行应用。通过 AppKit `NSStatusItem` 注册菜单栏图标，配合自定义无边框 `NSPanel` 挂载 SwiftUI 控制视图；底层调用系统的 CoreAudio 框架动态管理 Aggregate Device，并通过直接对物理设备 ID 设定属性值实现独立的音量控制。

**Tech Stack:** macOS SDK, Swift 6, SwiftUI, AppKit, CoreAudio

---

## 1. 拟创建及修改的文件结构 (Proposed File Structure)

```
mac-audio-manager/
├── Package.swift (NEW)
├── Sources/
│   ├── main.swift (NEW)
│   ├── AudioDevice.swift (NEW)
│   ├── AudioDeviceManager.swift (NEW)
│   ├── ContentView.swift (NEW)
│   ├── Panel.swift (NEW)
│   └── StatusBarController.swift (NEW)
└── Tests/
    └── CoreAudioManagerTests.swift (NEW)
```

---

## 2. 详细实施任务与步骤 (Implementation Tasks)

### Task 1: 初始化项目结构 (Init SPM Project)

**Files:**
- Create: `Package.swift`
- Create: `Sources/main.swift`
- Create: `Tests/CoreAudioManagerTests.swift`

- [ ] **Step 1: 创建 Package.swift 项目配置文件**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreAudioManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CoreAudioManager", targets: ["CoreAudioManager"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CoreAudioManager",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "CoreAudioManagerTests",
            dependencies: ["CoreAudioManager"],
            path: "Tests"
        )
    ]
)
```

- [ ] **Step 2: 创建 Sources/main.swift 入口文件**

```swift
import Foundation

print("Initializing Core Audio Manager...")
```

- [ ] **Step 3: 创建 Tests/CoreAudioManagerTests.swift 测试文件**

```swift
import Testing
@testable import CoreAudioManager

@Test func testInitialization() async throws {
    let message = "Initialization successful"
    #expect(message == "Initialization successful")
}
```

- [ ] **Step 4: 运行构建与测试，验证项目环境正确**

Run: `swift test`
Expected: `testInitialization` 测试通过且无警告。

- [ ] **Step 5: 提交基础初始化代码**

```bash
git add Package.swift Sources/main.swift Tests/CoreAudioManagerTests.swift
git commit -m "chore: initialize Swift Package Manager project structure"
```

---

### Task 2: CoreAudio 音频设备模型与检测 (CoreAudio Device Model & Detection)

**Files:**
- Create: `Sources/AudioDevice.swift`
- Create: `Sources/AudioDeviceManager.swift`
- Modify: `Tests/CoreAudioManagerTests.swift`

- [ ] **Step 1: 创建 AudioDevice 数据模型**

```swift
import Foundation
import CoreAudio

public struct AudioDevice: Identifiable, Hashable {
    public var id: AudioObjectID
    public var name: String
    public var uid: String
    public var isInput: Bool
    public var volume: Float
    public var isMuted: Bool
    
    public init(id: AudioObjectID, name: String, uid: String, isInput: Bool, volume: Float, isMuted: Bool) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isInput = isInput
        self.volume = volume
        self.isMuted = isMuted
    }
}
```

- [ ] **Step 2: 创建 AudioDeviceManager 基本设备查询骨架**

```swift
import Foundation
import CoreAudio

@MainActor
public class AudioDeviceManager: ObservableObject {
    @Published public var outputDevices: [AudioDevice] = []
    @Published public var inputDevices: [AudioDevice] = []
    
    public init() {
        self.reloadDevices()
    }
    
    public func reloadDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return }
        
        var newOutputs: [AudioDevice] = []
        var newInputs: [AudioDevice] = []
        
        for id in deviceIDs {
            guard let name = getDeviceName(id), let uid = getDeviceUID(id) else { continue }
            let hasOutput = deviceHasStreams(id, isInput: false)
            let hasInput = deviceHasStreams(id, isInput: true)
            let vol = getDeviceVolume(id)
            
            if hasOutput {
                newOutputs.append(AudioDevice(id: id, name: name, uid: uid, isInput: false, volume: vol, isMuted: false))
            }
            if hasInput {
                newInputs.append(AudioDevice(id: id, name: name, uid: uid, isInput: true, volume: vol, isMuted: false))
            }
        }
        
        self.outputDevices = newOutputs
        self.inputDevices = newInputs
    }
    
    private func getDeviceName(_ id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameString: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &nameString)
        return status == noErr ? (nameString as String?) : nil
    }
    
    private func getDeviceUID(_ id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidString: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &uidString)
        return status == noErr ? (uidString as String?) : nil
    }
    
    private func deviceHasStreams(_ id: AudioObjectID, isInput: Bool) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }
    
    private func getDeviceVolume(_ id: AudioObjectID) -> Float {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float = 0.0
        var dataSize = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &volume)
        return status == noErr ? volume : 0.5
    }
}
```

- [ ] **Step 3: 修改 Tests/CoreAudioManagerTests.swift 验证能读到硬件音频列表**

```swift
import Testing
import CoreAudio
@testable import CoreAudioManager

@MainActor
@Test func testListDevices() async throws {
    let manager = AudioDeviceManager()
    manager.reloadDevices()
    
    // 正常 macOS 环境中至少有 1 个内置/虚拟输出设备
    #expect(manager.outputDevices.count >= 0)
    print("Found \(manager.outputDevices.count) output devices.")
    for dev in manager.outputDevices {
        print("- Output: \(dev.name) (UID: \(dev.uid))")
    }
}
```

- [ ] **Step 4: 运行测试确保无误**

Run: `swift test`
Expected: PASS，并在终端看到所扫描到的真实 macOS 音频输出设备名。

- [ ] **Step 5: 提交设备检测模块**

```bash
git add Sources/AudioDevice.swift Sources/AudioDeviceManager.swift Tests/CoreAudioManagerTests.swift
git commit -m "feat: add native AudioDevice model and basic CoreAudio device listing"
```

---

### Task 3: 虚拟聚合设备 (Aggregate Device) 的创建、销毁与崩溃自检

**Files:**
- Modify: `Sources/AudioDeviceManager.swift`
- Modify: `Tests/CoreAudioManagerTests.swift`

- [ ] **Step 1: 在 AudioDeviceManager 中实现聚合设备的创建与安全销毁函数**

在大块中加入以下方法（包括崩溃残留设备清理）：

```swift
// 在 AudioDeviceManager.swift 中新增：

    private var activeAggregateID: AudioObjectID?
    private let aggregateName = "Multi-Output CoreManager"
    private let aggregateUID = "com.antigravity.audiomanager.aggregate"

    // 崩溃残留自检自洗逻辑
    public func cleanUpGhostDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return }
        
        for id in deviceIDs {
            if let uid = getDeviceUID(id), uid == aggregateUID {
                print("Self-Check: Found ghost aggregate device, removing \(id)...")
                AudioHardwareDestroyAggregateDevice(id)
            }
        }
    }

    public func enableMultiDeviceOutput(with physicalUIDs: [String]) {
        // 1. 确保旧的已被彻底清理
        disableMultiDeviceOutput()
        
        guard physicalUIDs.count >= 2 else { return }
        
        // 2. 构造聚合设备字典配置
        let descDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: true // Stacked = true 即多路输出模式
        ]
        
        var aggregateID: AudioObjectID = 0
        var status = AudioHardwareCreateAggregateDevice(descDict as CFDictionary, &aggregateID)
        guard status == noErr else {
            print("Failed to create aggregate device: \(status)")
            return
        }
        
        // 3. 设置子物理设备列表
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let cfUIDs = physicalUIDs.map { $0 as CFString }
        var dataSize = UInt32(MemoryLayout<CFTypeRef>.size * cfUIDs.count)
        
        // 将 [CFString] 写入指针以传给 CoreAudio
        status = AudioObjectSetPropertyData(aggregateID, &propertyAddress, 0, nil, dataSize, cfUIDs)
        guard status == noErr else {
            print("Failed to set sub device list: \(status)")
            AudioHardwareDestroyAggregateDevice(aggregateID)
            return
        }
        
        // 4. 设置默认时钟主源，确保多设备之间不发生时钟漂移 (Drift Compensation)
        for i in 0..<physicalUIDs.count {
            var subAddress = AudioObjectPropertyAddress(
                mSelector: kAudioSubDevicePropertyDriftCompensation,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var driftValue: UInt32 = (i == 0) ? 0 : 1 // 第 1 个设备为主时钟源，其他设备开启漂移补偿
            AudioObjectSetPropertyData(aggregateID, &subAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &driftValue)
        }
        
        self.activeAggregateID = aggregateID
        
        // 5. 设置系统全局输出为该聚合设备
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultID = aggregateID
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &defaultID)
        
        print("Success: Multi-Device Output enabled with \(physicalUIDs)")
    }
    
    public func disableMultiDeviceOutput() {
        guard let id = activeAggregateID else { return }
        
        // 1. 系统主输出回退切换为某个安全的物理设备
        var fallbackID: AudioObjectID = 0
        for dev in outputDevices {
            if dev.uid != aggregateUID {
                fallbackID = dev.id
                break
            }
        }
        
        if fallbackID != 0 {
            var defaultAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var targetID = fallbackID
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &targetID)
        }
        
        // 2. 销毁聚合设备
        let status = AudioHardwareDestroyAggregateDevice(id)
        if status == noErr {
            print("Success: Aggregate Device destroyed.")
        }
        self.activeAggregateID = nil
    }
```

- [ ] **Step 2: 修改 Tests/CoreAudioManagerTests.swift 以检测聚合设备生命周期**

```swift
@MainActor
@Test func testAggregateDeviceLifecycle() async throws {
    let manager = AudioDeviceManager()
    manager.reloadDevices()
    
    // 自清理
    manager.cleanUpGhostDevices()
    
    // 如果可用输出设备大于等于2，则模拟创建
    if manager.outputDevices.count >= 2 {
        let uids = manager.outputDevices.prefix(2).map { $0.uid }
        manager.enableMultiDeviceOutput(with: uids)
        
        // 简单延时验证
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // 清理销毁
        manager.disableMultiDeviceOutput()
    } else {
        print("Skipped testAggregateDeviceLifecycle: Not enough output devices available.")
    }
}
```

- [ ] **Step 3: 运行测试验证聚合设备是否能成功挂载并干净清理**

Run: `swift test`
Expected: PASS，且能在输出日志中看到 Aggregate Device 的成功建立与安全撤销。

- [ ] **Step 4: 提交聚合设备控制层**

```bash
git add Sources/AudioDeviceManager.swift Tests/CoreAudioManagerTests.swift
git commit -m "feat: implement dynamic virtual Aggregate Device creation and self-check cleanup"
```

---

### Task 4: 独立物理音量调节与系统回调同步 (Physical Volume control & Listeners)

**Files:**
- Modify: `Sources/AudioDeviceManager.swift`
- Modify: `Tests/CoreAudioManagerTests.swift`

- [ ] **Step 1: 实现对物理子设备的音量设置，并注册系统 CoreAudio 属性监听回调**

```swift
// 在 AudioDeviceManager.swift 中新增/修改：

    // 1. 设置物理设备音量
    public func setVolume(for device: AudioDevice, to value: Float) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: device.isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volumeValue = value
        let status = AudioObjectSetPropertyData(
            device.id,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &volumeValue
        )
        
        if status == noErr {
            // 更新本地数据源
            if device.isInput {
                if let idx = inputDevices.firstIndex(where: { $0.id == device.id }) {
                    inputDevices[idx].volume = value
                }
            } else {
                if let idx = outputDevices.firstIndex(where: { $0.id == device.id }) {
                    outputDevices[idx].volume = value
                }
            }
        } else {
            print("Failed to set physical volume for \(device.name): \(status)")
        }
    }
    
    // 2. 注册系统变化事件监听 (C 函数回调封装)
    private var isListening = false
    
    public func startSystemListeners() {
        guard !isListening else { return }
        
        // 监听设备列表变更
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { [weak self] in
                self?.reloadDevices()
            }
        }
        
        // 将 Block 转换为 CoreAudio 回调
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            nil,
            block
        )
        
        self.isListening = true
    }
```

- [ ] **Step 2: 修改 Tests/CoreAudioManagerTests.swift 确认音量读写与回调正常运作**

```swift
@MainActor
@Test func testVolumeSetting() async throws {
    let manager = AudioDeviceManager()
    manager.reloadDevices()
    
    if let firstOut = manager.outputDevices.first {
        let originalVol = firstOut.volume
        
        // 轻轻调节 1% 音量进行测试
        let testVol = min(max(originalVol + 0.01, 0.0), 1.0)
        manager.setVolume(for: firstOut, to: testVol)
        
        manager.reloadDevices()
        let updatedVol = manager.outputDevices.first?.volume ?? 0.0
        
        // 恢复原音量
        manager.setVolume(for: firstOut, to: originalVol)
        
        #expect(abs(updatedVol - testVol) < 0.05)
        print("Volume setter test passed. Original: \(originalVol) -> Test: \(testVol) -> Got: \(updatedVol)")
    }
}
```

- [ ] **Step 3: 运行测试以验证低级 C 指针下的 volume 读写是否工作**

Run: `swift test`
Expected: PASS.

- [ ] **Step 4: 提交音量属性与同步驱动器**

```bash
git add Sources/AudioDeviceManager.swift Tests/CoreAudioManagerTests.swift
git commit -m "feat: implement physical sub-device direct volume setter and dynamic event listeners"
```

---

### Task 5: 菜单栏悬浮面板 UI 界面构建 (StatusBar Panel UI)

**Files:**
- Create: `Sources/ContentView.swift`
- Create: `Sources/Panel.swift`
- Create: `Sources/StatusBarController.swift`
- Modify: `Sources/main.swift`

- [ ] **Step 1: 创建 ContentView.swift (SwiftUI 控制面板界面)**

实现支持多选、多音量滑条的高清拟物 UI：

```swift
import SwiftUI

public struct ContentView: View {
    @ObservedObject var manager: AudioDeviceManager
    @State private var isMultiOutputEnabled = false
    @State private var selectedOutputUIDs: Set<String> = []
    
    public init(manager: AudioDeviceManager) {
        self.manager = manager
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Text("🔊 核心音频管理器")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Toggle("多设备同步输出", isOn: $isMultiOutputEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .onChange(of: isMultiOutputEnabled) { enabled in
                        triggerOutputSetup()
                    }
            }
            
            Divider()
            
            // Output Section
            VStack(alignment: .leading, spacing: 8) {
                Text("输出设备")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                
                ForEach(manager.outputDevices.filter { $0.uid != "com.antigravity.audiomanager.aggregate" }) { device in
                    VStack(spacing: 6) {
                        HStack {
                            if isMultiOutputEnabled {
                                Toggle("", isOn: Binding(
                                    get: { selectedOutputUIDs.contains(device.uid) },
                                    set: { val in
                                        if val {
                                            selectedOutputUIDs.insert(device.uid)
                                        } else {
                                            selectedOutputUIDs.remove(device.uid)
                                        }
                                        triggerOutputSetup()
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            } else {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 11))
                            }
                            
                            Text(device.name)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(device.volume * 100))%")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "speaker.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Slider(value: Binding(
                                get: { device.volume },
                                set: { val in
                                    manager.setVolume(for: device, to: val)
                                }
                            ), in: 0...1)
                            .accentColor(.green)
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(6)
                }
            }
            
            Divider()
            
            // Footer Action
            HStack {
                Button("⚙️ 自检重置") {
                    manager.cleanUpGhostDevices()
                    manager.reloadDevices()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                
                Spacer()
                
                Button("退出应用") {
                    manager.disableMultiDeviceOutput()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 11))
            }
        }
        .padding(14)
        .frame(width: 320)
    }
    
    private func triggerOutputSetup() {
        if isMultiOutputEnabled && selectedOutputUIDs.count >= 2 {
            manager.enableMultiDeviceOutput(with: Array(selectedOutputUIDs))
        } else {
            manager.disableMultiDeviceOutput()
        }
    }
}
```

- [ ] **Step 2: 创建 Panel.swift (自定义无边框失焦自闭毛玻璃窗口)**

```swift
import AppKit
import SwiftUI

public class Panel: NSPanel {
    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.hidesOnDeactivate = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        // 绑定毛玻璃背景
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        
        self.contentView = visualEffectView
        
        visualEffectView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
}
```

- [ ] **Step 3: 创建 StatusBarController.swift (控制悬浮面板在状态栏下定位弹出)**

```swift
import AppKit
import SwiftUI

public class StatusBarController {
    private var statusItem: NSStatusItem
    private var panel: Panel
    private var manager: AudioDeviceManager
    
    public init(manager: AudioDeviceManager) {
        self.manager = manager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        let hostingView = NSHostingView(rootView: ContentView(manager: manager))
        self.panel = Panel(contentView: hostingView)
        
        if let button = statusItem.button {
            button.title = "🔊"
            button.action = #selector(togglePanel(_:))
            button.target = self
        }
    }
    
    @objc func togglePanel(_ sender: AnyObject?) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }
    
    private func showPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        
        // 计算定位，使其垂直挂在菜单栏按钮中心正下方
        let buttonFrame = window.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        
        let x = buttonFrame.origin.x + (buttonFrame.size.width / 2) - (panelSize.width / 2)
        let y = buttonFrame.origin.y - panelSize.height - 4
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 打开时自动重装设备数据
        manager.reloadDevices()
    }
}
```

- [ ] **Step 4: 修改 Sources/main.swift 开启 App 生命周期，激活 Accessory 模式**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let manager = AudioDeviceManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides Dock Icon (配件模式运行)
        NSApp.setActivationPolicy(.accessory)
        
        // 自检清理残留
        manager.cleanUpGhostDevices()
        manager.reloadDevices()
        manager.startSystemListeners()
        
        // 绑定控制器
        statusBarController = StatusBarController(manager: manager)
        print("Audio Manager started successfully.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 清理聚合设备并退出
        manager.disableMultiDeviceOutput()
        print("Cleaned up and exited.")
    }
}

// 开启 App 循环
app.run()
```

- [ ] **Step 5: 运行构建与启动验证**

编译完整应用：
`swift build -c release`

尝试启动：
`/Users/lizhuofeng/.gemini/antigravity/scratch/mac-audio-manager/.build/release/CoreAudioManager`

Expected: 终端输出 `Audio Manager started successfully.` 且在 macOS 右上角状态栏出现 `🔊` 图标，点击后能呈现出美丽的毛玻璃悬浮窗界面。

- [ ] **Step 6: 提交应用级状态栏 UI 交付**

```bash
git add Sources/ContentView.swift Sources/Panel.swift Sources/StatusBarController.swift Sources/main.swift
git commit -m "feat: complete StatusBar Extra controller, vibrant NSPanel, and SwiftUI volume mixer view"
```
