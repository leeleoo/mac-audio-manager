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
    @Published public var activeAggregateID: AudioObjectID? = nil
    private var previousDefaultDeviceID: AudioObjectID? = nil
    
    public let aggregateName = "Multi-Output CoreManager"
    public let aggregateUID = "com.antigravity.audiomanager.aggregate"
    
    public init() {
        self.cleanUpGhostDevices()
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
            print("Success: Multi-Device Output enabled with \(physicalUIDs)")
        } else {
            print("Warning: Created aggregate device but failed to set it as system default output: \(status)")
        }
    }
    
    public func disableMultiDeviceOutput() {
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
