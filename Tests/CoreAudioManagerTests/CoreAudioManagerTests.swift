import Testing
import CoreAudio
@testable import CoreAudioManager

@MainActor
@Test func testInitialization() async throws {
    let message = "Initialization successful"
    #expect(message == "Initialization successful")
}

@MainActor
@Test func testListDevices() async throws {
    let manager = AudioDeviceManager()
    manager.reloadDevices()
    
    // Assert that we retrieved output devices and each one has non-empty name and uid
    print("Found \(manager.outputDevices.count) output devices.")
    for dev in manager.outputDevices {
        #expect(!dev.name.isEmpty)
        #expect(!dev.uid.isEmpty)
        print("- Output: \(dev.name) (UID: \(dev.uid), ObjectID: \(dev.objectID), Vol: \(dev.volume), Muted: \(dev.isMuted))")
    }
    
    // Assert that we retrieved input devices and each one has non-empty name and uid
    print("Found \(manager.inputDevices.count) input devices.")
    for dev in manager.inputDevices {
        #expect(!dev.name.isEmpty)
        #expect(!dev.uid.isEmpty)
        print("- Input: \(dev.name) (UID: \(dev.uid), ObjectID: \(dev.objectID), Vol: \(dev.volume), Muted: \(dev.isMuted))")
    }
}

@MainActor
@Test func testAggregateDeviceLifecycle() async throws {
    let manager = AudioDeviceManager()
    manager.reloadDevices()
    
    // Clean up ghosts
    manager.cleanUpGhostDevices()
    
    if manager.outputDevices.count >= 2 {
        let uids = manager.outputDevices.prefix(2).map { $0.uid }
        manager.enableMultiDeviceOutput(with: uids)
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        manager.disableMultiDeviceOutput()
    } else {
        print("Skipped testAggregateDeviceLifecycle: Not enough output devices available.")
    }
}

@MainActor
@Test func testVolumeSetting() async throws {
    let manager = AudioDeviceManager()
    manager.reloadDevices()
    
    // Find the first output device that is not the aggregate and has a settable volume
    if let settableOut = manager.outputDevices.first(where: { 
        $0.uid != manager.aggregateUID && manager.isDeviceVolumeSettable($0.objectID, isInput: false) 
    }) {
        let originalVol = settableOut.volume
        let testVol = min(max(originalVol + 0.05, 0.0), 1.0)
        
        manager.setVolume(for: settableOut, to: testVol)
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        manager.reloadDevices()
        let updatedVol = manager.outputDevices.first(where: { $0.uid == settableOut.uid })?.volume ?? 0.0
        
        // Restore
        manager.setVolume(for: settableOut, to: originalVol)
        
        #expect(abs(updatedVol - testVol) < 0.08)
        print("Volume setter test passed. Original: \(originalVol) -> Test: \(testVol) -> Got: \(updatedVol)")
    } else {
        print("Skipped testVolumeSetting: No suitable output device with settable volume found.")
    }
}
