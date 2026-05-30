import SwiftUI

public struct ContentView: View {
    @ObservedObject var manager: AudioDeviceManager
    
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
                Toggle("多设备同步输出", isOn: $manager.isMultiOutputEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .onChange(of: manager.isMultiOutputEnabled) { enabled in
                        triggerOutputSetup()
                    }
            }
            
            Divider()
            
            // Scrollable List Area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Output Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("输出设备")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        
                        ForEach(manager.outputDevices.filter { $0.uid != "com.antigravity.audiomanager.aggregate" }) { device in
                            VStack(spacing: 6) {
                                HStack {
                                    if manager.isMultiOutputEnabled {
                                        Toggle("", isOn: Binding(
                                            get: { manager.selectedOutputUIDs.contains(device.uid) },
                                            set: { val in
                                                if val {
                                                    manager.selectedOutputUIDs.insert(device.uid)
                                                } else {
                                                    manager.selectedOutputUIDs.remove(device.uid)
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
                            .background(
                                (!manager.isMultiOutputEnabled && manager.defaultOutputDeviceUID == device.uid)
                                    ? Color.blue.opacity(0.15)
                                    : Color(NSColor.controlBackgroundColor).opacity(0.4)
                            )
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke((!manager.isMultiOutputEnabled && manager.defaultOutputDeviceUID == device.uid) ? Color.blue : Color.clear, lineWidth: 1.5)
                            )
                            .onTapGesture {
                                if !manager.isMultiOutputEnabled {
                                    manager.setDefaultOutputDevice(uid: device.uid)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Input Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("输入设备")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        
                        ForEach(manager.inputDevices) { device in
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
                                    Slider(value: Binding(
                                        get: { device.volume },
                                        set: { val in
                                            manager.setVolume(for: device, to: val)
                                        }
                                    ), in: 0...1)
                                    .accentColor(.blue)
                                    Image(systemName: "mic.and.signal.meter.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(
                                manager.defaultInputDeviceUID == device.uid
                                    ? Color.blue.opacity(0.15)
                                    : Color(NSColor.controlBackgroundColor).opacity(0.4)
                            )
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(manager.defaultInputDeviceUID == device.uid ? Color.blue : Color.clear, lineWidth: 1.5)
                            )
                            .onTapGesture {
                                manager.setDefaultInputDevice(uid: device.uid)
                            }
                        }
                    }
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
        if manager.isMultiOutputEnabled && manager.selectedOutputUIDs.count >= 2 {
            manager.enableMultiDeviceOutput(with: Array(manager.selectedOutputUIDs))
        } else {
            manager.disableMultiDeviceOutput()
        }
    }
}
