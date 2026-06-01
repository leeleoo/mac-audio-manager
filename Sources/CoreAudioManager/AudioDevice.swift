import Foundation
import CoreAudio

public struct AudioDevice: Identifiable, Hashable, Sendable {
    public var id: String { uid }
    public var objectID: AudioObjectID
    public var name: String
    public var uid: String
    public var isInput: Bool
    public var volume: Float
    public var isMuted: Bool
    public var isVolumeSettable: Bool
    
    public init(objectID: AudioObjectID, name: String, uid: String, isInput: Bool, volume: Float, isMuted: Bool, isVolumeSettable: Bool) {
        self.objectID = objectID
        self.name = name
        self.uid = uid
        self.isInput = isInput
        self.volume = volume
        self.isMuted = isMuted
        self.isVolumeSettable = isVolumeSettable
    }
}
