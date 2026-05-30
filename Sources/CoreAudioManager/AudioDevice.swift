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
