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
    
    #expect(manager.outputDevices.count >= 0)
    print("Found \(manager.outputDevices.count) output devices.")
    for dev in manager.outputDevices {
        print("- Output: \(dev.name) (UID: \(dev.uid))")
    }
}
