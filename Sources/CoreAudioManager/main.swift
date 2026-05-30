import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let manager = AudioDeviceManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides Dock Icon (配件模式运行)
        NSApp.setActivationPolicy(.accessory)
        
        // 自检清理残留
        manager.cleanUpGhostDevices()
        manager.reloadDevices()
        
        // 绑定控制器
        statusBarController = StatusBarController(manager: manager)
        print("Audio Manager started successfully.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 清理聚合设备并退出
        manager.disableMultiDeviceOutput()
        print("Cleaned up and exited.")
    }
}

// 开启 App 循环
app.run()
