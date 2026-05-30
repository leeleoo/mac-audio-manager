import Foundation
import CoreAudio

private let hardwareDevicesListener: AudioObjectPropertyListenerProc = { (objectID, numberAddresses, addresses, clientData) -> OSStatus in
    guard let clientData = clientData else { return noErr }
    let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData).takeUnretainedValue()
    Task { @MainActor in
        manager.reloadDevices()
    }
    return noErr
}

@MainActor
public class AudioDeviceManager: ObservableObject {
    @Published public var outputDevices: [AudioDevice] = []
    @Published public var inputDevices: [AudioDevice] = []
    
    public init() {
        self.reloadDevices()
        self.setupListener()
    }
    
    deinit {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        _ = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            hardwareDevicesListener,
            clientData
        )
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
            
            if hasOutput {
                let vol = getDeviceVolume(id, isInput: false)
                let mute = getDeviceMute(id, isInput: false)
                newOutputs.append(AudioDevice(objectID: id, name: name, uid: uid, isInput: false, volume: vol, isMuted: mute))
            }
            if hasInput {
                let vol = getDeviceVolume(id, isInput: true)
                let mute = getDeviceMute(id, isInput: true)
                newInputs.append(AudioDevice(objectID: id, name: name, uid: uid, isInput: true, volume: vol, isMuted: mute))
            }
        }
        
        self.outputDevices = newOutputs
        self.inputDevices = newInputs
    }
    
    private func setupListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            hardwareDevicesListener,
            clientData
        )
        if status != noErr {
            // Can log or handle listener registration error if necessary
        }
    }
    
    private func getDeviceName(_ id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &nameString)
        return status == noErr ? (nameString?.takeRetainedValue() as String?) : nil
    }
    
    private func getDeviceUID(_ id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidString: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &uidString)
        return status == noErr ? (uidString?.takeRetainedValue() as String?) : nil
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
    
    private func getDeviceVolume(_ id: AudioObjectID, isInput: Bool) -> Float {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float = 0.0
        var dataSize = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &volume)
        return status == noErr ? volume : 0.5
    }
    
    private func getDeviceMute(_ id: AudioObjectID, isInput: Bool) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isMuted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, &isMuted)
        return status == noErr ? (isMuted != 0) : false
    }
}
