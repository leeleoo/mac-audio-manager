import AppKit
import SwiftUI

public class Panel: NSPanel {
    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.hidesOnDeactivate = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        // 绑定毛玻璃背景
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        
        self.contentView = visualEffectView
        
        visualEffectView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor)
        ])
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
}
