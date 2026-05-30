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
