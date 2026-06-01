import SwiftUI

@MainActor public struct ContentView: View {
    @ObservedObject var manager: AudioDeviceManager
    
    public init(manager: AudioDeviceManager) {
        self.manager = manager
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            headerView
            Divider()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    outputSection
                    Divider()
                    inputSection
                }
            }
            
            Divider()
            footerView
        }
        .padding(14)
        .frame(width: 320)
    }
    
    private var headerView: some View {
        HStack {
            Text("🔊 核心音频管理器")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Toggle("多设备同步输出", isOn: $manager.isMultiOutputEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .onChange(of: manager.isMultiOutputEnabled) { enabled in
                    triggerOutputSetup()
                }
        }
    }
    
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("输出设备")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
            
            if manager.isMultiOutputEnabled {
                // 多设备同步输出启用
                let allOutputs = manager.outputDevices.filter { $0.uid != manager.aggregateUID }
                let syncedOutputs = allOutputs.filter { manager.selectedOutputUIDs.contains($0.uid) }
                let availableOutputs = allOutputs.filter { !manager.selectedOutputUIDs.contains($0.uid) }
                
                // 🟢 同步输出组卡片容器
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(syncedOutputs.count >= 2 ? "🟢 同步中 (\(syncedOutputs.count)个设备)" : "⚠️ 同步未激活 (请至少勾选 2 个设备)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(syncedOutputs.count >= 2 ? .green : .orange)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    
                    if syncedOutputs.isEmpty {
                        Text("暂无已加入设备，点击下方设备加入同步")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(syncedOutputs) { device in
                                OutputDeviceCardView(
                                    device: device,
                                    isMultiOutputEnabled: true,
                                    isSelected: true,
                                    isVolumeSettable: device.isVolumeSettable,
                                    volume: Binding(
                                        get: { device.volume },
                                        set: { val in
                                            manager.setVolume(for: device, to: val)
                                        }
                                    ),
                                    onToggle: {
                                        manager.selectedOutputUIDs.remove(device.uid)
                                        triggerOutputSetup()
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(syncedOutputs.count >= 2 ? Color.green.opacity(0.4) : Color.orange.opacity(0.4), lineWidth: 1.5)
                )
                
                // ➕ 待添加至同步物理列表
                if !availableOutputs.isEmpty {
                    Text("可加入同步的设备")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(.top, 6)
                    
                    VStack(spacing: 8) {
                        ForEach(availableOutputs) { device in
                            OutputDeviceCardView(
                                device: device,
                                isMultiOutputEnabled: true,
                                isSelected: false,
                                isVolumeSettable: device.isVolumeSettable,
                                volume: Binding(
                                    get: { device.volume },
                                    set: { val in
                                        manager.setVolume(for: device, to: val)
                                    }
                                ),
                                onToggle: {
                                    manager.selectedOutputUIDs.insert(device.uid)
                                    triggerOutputSetup()
                                }
                            )
                        }
                    }
                }
            } else {
                // 单输出模式 (普通切换)
                let allOutputs = manager.outputDevices.filter { $0.uid != manager.aggregateUID }
                VStack(spacing: 8) {
                    ForEach(allOutputs) { device in
                        OutputDeviceCardView(
                            device: device,
                            isMultiOutputEnabled: false,
                            isSelected: manager.defaultOutputDeviceUID == device.uid,
                            isVolumeSettable: device.isVolumeSettable,
                            volume: Binding(
                                get: { device.volume },
                                set: { val in
                                    manager.setVolume(for: device, to: val)
                                }
                            ),
                            onToggle: {
                                manager.setDefaultOutputDevice(uid: device.uid)
                            }
                        )
                    }
                }
            }
        }
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("输入设备")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
            
            ForEach(manager.inputDevices) { device in
                InputDeviceCardView(
                    device: device,
                    isSelected: manager.defaultInputDeviceUID == device.uid,
                    isVolumeSettable: device.isVolumeSettable,
                    volume: Binding(
                        get: { device.volume },
                        set: { val in
                            manager.setVolume(for: device, to: val)
                        }
                    ),
                    onSelect: {
                        manager.setDefaultInputDevice(uid: device.uid)
                    }
                )
            }
        }
    }
    
    private var footerView: some View {
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
    
    private func triggerOutputSetup() {
        if manager.isMultiOutputEnabled && manager.selectedOutputUIDs.count >= 2 {
            manager.enableMultiDeviceOutput(with: Array(manager.selectedOutputUIDs))
        } else {
            manager.disableMultiDeviceOutput()
        }
    }
}

@MainActor struct OutputDeviceCardView: View {
    let device: AudioDevice
    let isMultiOutputEnabled: Bool
    let isSelected: Bool
    let isVolumeSettable: Bool
    let volume: Binding<Float>
    let onToggle: @MainActor () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                if isMultiOutputEnabled {
                    Button(action: onToggle) {
                        Image(systemName: isSelected ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundColor(isSelected ? .red : .green)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
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
                if isVolumeSettable {
                    Slider(value: volume, in: 0...1)
                        .accentColor(isMultiOutputEnabled ? .green : .blue)
                } else {
                    Text("数字 HDMI/DP 设备，不支持系统软件调音")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            isMultiOutputEnabled
                ? (isSelected ? Color.green.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                : (isSelected ? Color.blue.opacity(0.15) : Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isMultiOutputEnabled
                        ? (isSelected ? Color.green : Color.clear)
                        : (isSelected ? Color.blue : Color.clear),
                    lineWidth: 1.5
                )
        )
        .onTapGesture {
            onToggle()
        }
    }
}

@MainActor struct InputDeviceCardView: View {
    let device: AudioDevice
    let isSelected: Bool
    let isVolumeSettable: Bool
    let volume: Binding<Float>
    let onSelect: @MainActor () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 11))
                
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(device.volume * 100))%")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                if isVolumeSettable {
                    Slider(value: volume, in: 0...1)
                        .accentColor(.blue)
                } else {
                    Text("数字输入设备，不支持系统软件调音")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                Image(systemName: "mic.and.signal.meter.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            isSelected
                ? Color.blue.opacity(0.15)
                : Color(NSColor.controlBackgroundColor).opacity(0.4)
        )
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
        )
        .onTapGesture {
            onSelect()
        }
    }
}
