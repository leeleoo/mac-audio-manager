import AppKit
import SwiftUI

@MainActor
public class StatusBarController {
    private var statusItem: NSStatusItem
    private var panel: Panel
    private var manager: AudioDeviceManager
    private var hostingView: NSHostingView<ContentView>
    
    public init(manager: AudioDeviceManager) {
        self.manager = manager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        self.hostingView = NSHostingView(rootView: ContentView(manager: manager))
        self.panel = Panel(contentView: hostingView)
        
        if let button = statusItem.button {
            button.title = "🔊"
            button.action = #selector(togglePanel(_:))
            button.target = self
        }
    }
    
    @objc func togglePanel(_ sender: AnyObject?) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }
    
    private func showPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        
        // 打开时自动重装设备 data
        manager.reloadDevices()
        
        // Dynamically compute the panel's fitting height, capped at a maximum of 500pt
        let fittingHeight = hostingView.fittingSize.height
        let targetHeight = min(max(fittingHeight, 150), 500)
        
        // Adjust panel's height dynamically
        var panelFrame = panel.frame
        panelFrame.size.height = targetHeight
        panel.setFrame(panelFrame, display: true)
        
        // 计算定位，使其垂直挂在菜单栏按钮中心正下方
        let buttonFrame = window.convertToScreen(button.frame)
        let panelSize = panel.frame.size
        
        let x = buttonFrame.origin.x + (buttonFrame.size.width / 2) - (panelSize.width / 2)
        let y = buttonFrame.origin.y - panelSize.height - 4
        
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
