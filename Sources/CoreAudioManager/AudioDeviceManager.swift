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

struct RegisteredListener: Hashable {
    var objectID: AudioObjectID
    var selector: AudioObjectPropertySelector
    var scope: AudioObjectPropertyScope
    var element: AudioObjectPropertyElement
}

private let deviceVolumeListener: AudioObjectPropertyListenerProc = { (objectID, numberAddresses, addresses, clientData) -> OSStatus in
    guard let clientData = clientData else { return noErr }
    let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData).takeUnretainedValue()
    Task { @MainActor in
        manager.deviceVolumeChanged(objectID)
    }
    return noErr
}

@MainActor
public class AudioDeviceManager: ObservableObject {
    @Published public var outputDevices: [AudioDevice] = []
    @Published public var inputDevices: [AudioDevice] = []
    @Published public var activeAggregateID: AudioObjectID? = nil
    @Published public var defaultOutputDeviceUID: String? = nil
    @Published public var defaultInputDeviceUID: String? = nil
    @Published public var isMultiOutputEnabled = false
    @Published public var selectedOutputUIDs: Set<String> = []
    private var previousDefaultDeviceID: AudioObjectID? = nil
    private var registeredListeners: Set<RegisteredListener> = []
    
    public let aggregateName = "Multi-Output CoreManager"
    public let aggregateUID = "com.antigravity.audiomanager.aggregate"
    
    public init() {
        self.cleanUpGhostDevices()
        self.reloadDevices()
        self.setupListener()
    }
    
    deinit {
        let listeners = registeredListeners
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
        
        // Remove all registered volume listeners
        for listener in listeners {
            var addr = AudioObjectPropertyAddress(
                mSelector: listener.selector,
                mScope: listener.scope,
                mElement: listener.element
            )
            _ = AudioObjectRemovePropertyListener(
                listener.objectID,
                &addr,
                deviceVolumeListener,
                clientData
            )
        }
    }
    
    public func reloadDevices() {
        removeVolumeListeners()
        
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
        
        // Query default output device UID
        var defaultOutputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultOutputID: AudioObjectID = 0
        var defaultOutputSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let defaultOutputStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddr,
            0,
            nil,
            &defaultOutputSize,
            &defaultOutputID
        )
        if defaultOutputStatus == noErr {
            self.defaultOutputDeviceUID = getDeviceUID(defaultOutputID)
        } else {
            self.defaultOutputDeviceUID = nil
        }
        
        // Query default input device UID
        var defaultInputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultInputID: AudioObjectID = 0
        var defaultInputSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let defaultInputStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddr,
            0,
            nil,
            &defaultInputSize,
            &defaultInputID
        )
        if defaultInputStatus == noErr {
            self.defaultInputDeviceUID = getDeviceUID(defaultInputID)
        } else {
            self.defaultInputDeviceUID = nil
        }
        
        setupVolumeListeners()
    }
    
    public func setVolume(for device: AudioDevice, to value: Float) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: device.isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volumeValue = value
        let status = AudioObjectSetPropertyData(
            device.objectID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float>.size),
            &volumeValue
        )
        
        if status == noErr {
            if device.isInput {
                if let index = inputDevices.firstIndex(where: { $0.uid == device.uid }) {
                    inputDevices[index].volume = value
                }
            } else {
                if let index = outputDevices.firstIndex(where: { $0.uid == device.uid }) {
                    outputDevices[index].volume = value
                }
            }
        } else {
            print("Failed to set volume for device \(device.name): \(status)")
        }
    }
    
    public func setDefaultOutputDevice(uid: String) {
        guard let device = outputDevices.first(where: { $0.uid == uid }) else { return }
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetID = device.objectID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &targetID
        )
        if status == noErr {
            self.defaultOutputDeviceUID = uid
        } else {
            print("Failed to set default output device: \(status)")
        }
    }
    
    public func setDefaultInputDevice(uid: String) {
        guard let device = inputDevices.first(where: { $0.uid == uid }) else { return }
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetID = device.objectID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &targetID
        )
        if status == noErr {
            self.defaultInputDeviceUID = uid
        } else {
            print("Failed to set default input device: \(status)")
        }
    }
    
    public func deviceVolumeChanged(_ objectID: AudioObjectID) {
        for i in 0..<outputDevices.count {
            if outputDevices[i].objectID == objectID {
                let newVol = getDeviceVolume(objectID, isInput: false)
                outputDevices[i].volume = newVol
            }
        }
        for i in 0..<inputDevices.count {
            if inputDevices[i].objectID == objectID {
                let newVol = getDeviceVolume(objectID, isInput: true)
                inputDevices[i].volume = newVol
            }
        }
    }
    
    private func removeVolumeListeners() {
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        for listener in registeredListeners {
            var addr = AudioObjectPropertyAddress(
                mSelector: listener.selector,
                mScope: listener.scope,
                mElement: listener.element
            )
            _ = AudioObjectRemovePropertyListener(
                listener.objectID,
                &addr,
                deviceVolumeListener,
                clientData
            )
        }
        registeredListeners.removeAll()
    }
    
    private func setupVolumeListeners() {
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        
        for dev in outputDevices {
            guard dev.uid != aggregateUID else { continue }
            registerVolumeListener(for: dev.objectID, isInput: false, clientData: clientData)
        }
        
        for dev in inputDevices {
            guard dev.uid != aggregateUID else { continue }
            registerVolumeListener(for: dev.objectID, isInput: true, clientData: clientData)
        }
    }
    
    private func registerVolumeListener(for objectID: AudioObjectID, isInput: Bool, clientData: UnsafeMutableRawPointer) {
        let scope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let listener = RegisteredListener(
            objectID: objectID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: scope,
            element: kAudioObjectPropertyElementMain
        )
        
        guard !registeredListeners.contains(listener) else { return }
        
        var addr = AudioObjectPropertyAddress(
            mSelector: listener.selector,
            mScope: listener.scope,
            mElement: listener.element
        )
        
        let status = AudioObjectAddPropertyListener(
            objectID,
            &addr,
            deviceVolumeListener,
            clientData
        )
        
        if status == noErr {
            registeredListeners.insert(listener)
        }
    }
    
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
        // 1. Ensure any old aggregate device is thoroughly cleaned up first
        disableMultiDeviceOutput()
        
        guard physicalUIDs.count >= 2 else { return }
        
        // 2. Configure the aggregate device dictionary description
        let descDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: false,
            kAudioAggregateDeviceIsStackedKey: true
        ]
        
        var aggregateID: AudioObjectID = 0
        var status = AudioHardwareCreateAggregateDevice(descDict as CFDictionary, &aggregateID)
        guard status == noErr else {
            print("Failed to create aggregate device: \(status)")
            return
        }
        
        // 3. Set the sub-devices array
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let subDevicesArray: CFArray = physicalUIDs.map { $0 as CFString } as CFArray
        let subDevicesSize = UInt32(MemoryLayout<CFArray>.size)
        
        status = withUnsafePointer(to: subDevicesArray) { ptr in
            AudioObjectSetPropertyData(
                aggregateID,
                &propertyAddress,
                0,
                nil,
                subDevicesSize,
                ptr
            )
        }
        
        guard status == noErr else {
            print("Failed to set sub device list: \(status)")
            AudioHardwareDestroyAggregateDevice(aggregateID)
            return
        }
        
        // 4. Configure drift compensation to avoid clock drift issues between sub-devices
        // Drift compensation must be set on the AudioSubDevice objects owned by the aggregate device.
        var ownedAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyOwnedObjects,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ownedObjectsSize: UInt32 = 0
        status = AudioObjectGetPropertyDataSize(aggregateID, &ownedAddress, 0, nil, &ownedObjectsSize)
        
        if status == noErr {
            let ownedObjectsCount = Int(ownedObjectsSize) / MemoryLayout<AudioObjectID>.size
            var ownedObjectIDs = [AudioObjectID](repeating: 0, count: ownedObjectsCount)
            let getStatus = AudioObjectGetPropertyData(aggregateID, &ownedAddress, 0, nil, &ownedObjectsSize, &ownedObjectIDs)
            
            if getStatus == noErr {
                for objID in ownedObjectIDs {
                    var classAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioObjectPropertyClass,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    var classID: AudioClassID = 0
                    var classSize = UInt32(MemoryLayout<AudioClassID>.size)
                    let classStatus = AudioObjectGetPropertyData(objID, &classAddress, 0, nil, &classSize, &classID)
                    guard classStatus == noErr else { continue }
                    
                    if classID == kAudioSubDeviceClassID {
                        var uidAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyDeviceUID,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        var uidString: Unmanaged<CFString>?
                        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                        let uidStatus = AudioObjectGetPropertyData(objID, &uidAddress, 0, nil, &uidSize, &uidString)
                        guard uidStatus == noErr, let uid = uidString?.takeRetainedValue() as String? else { continue }
                        
                        var driftAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioSubDevicePropertyDriftCompensation,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        var driftValue: UInt32 = (uid == physicalUIDs.first) ? 0 : 1
                        AudioObjectSetPropertyData(objID, &driftAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &driftValue)
                    }
                }
            }
        }
        
        self.activeAggregateID = aggregateID
        
        // 5. Query and store the current system default output device before swapping
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var currentDefaultID: AudioObjectID = 0
        var currentDefaultSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let getDefaultStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            &currentDefaultSize,
            &currentDefaultID
        )
        if getDefaultStatus == noErr {
            if currentDefaultID != aggregateID && getDeviceUID(currentDefaultID) != aggregateUID {
                self.previousDefaultDeviceID = currentDefaultID
            }
        }
        
        // 6. Configure the system default audio output to the newly created aggregate device
        var defaultID = aggregateID
        status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &defaultID
        )
        
        if status == noErr {
            self.isMultiOutputEnabled = true
            self.selectedOutputUIDs = Set(physicalUIDs)
            print("Success: Multi-Device Output enabled with \(physicalUIDs)")
        } else {
            print("Warning: Created aggregate device but failed to set it as system default output: \(status)")
        }
    }
    
    public func disableMultiDeviceOutput() {
        self.isMultiOutputEnabled = false
        self.selectedOutputUIDs = []
        guard let id = activeAggregateID else { return }
        
        // 1. Find a fallback physical output device that is not our aggregate device, and restore system default output to it
        var fallbackID: AudioObjectID = 0
        if let prevID = previousDefaultDeviceID {
            fallbackID = prevID
        } else {
            for dev in outputDevices {
                if dev.uid != aggregateUID && dev.objectID != id {
                    fallbackID = dev.objectID
                    break
                }
            }
        }
        
        if fallbackID != 0 {
            var defaultAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var targetID = fallbackID
            let status = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddr,
                0,
                nil,
                UInt32(MemoryLayout<AudioObjectID>.size),
                &targetID
            )
            if status != noErr {
                print("Failed to restore default output device: \(status)")
            }
        }
        
        // Clear the stored previous default
        self.previousDefaultDeviceID = nil
        
        // 2. Safely destroy the aggregate device
        let status = AudioHardwareDestroyAggregateDevice(id)
        if status == noErr {
            print("Success: Aggregate Device destroyed.")
        } else {
            print("Failed to destroy aggregate device: \(status)")
        }
        self.activeAggregateID = nil
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
    
    public func isDeviceVolumeSettable(_ id: AudioObjectID, isInput: Bool) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(id, &propertyAddress, &isSettable)
        return status == noErr ? isSettable.boolValue : false
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
