import Cocoa

class MenubarTimerApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var timersFilePath: String = ""
    var timers: [(id: String, fireDate: Date, message: String)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Determine timers.json path from args or environment
        if CommandLine.arguments.count > 1 {
            timersFilePath = CommandLine.arguments[1] + "/timers.json"
        } else if let cache = ProcessInfo.processInfo.environment["alfred_workflow_cache"] {
            timersFilePath = cache + "/timers.json"
        } else {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        loadTimers()

        if timers.isEmpty {
            NSApp.terminate(nil)
            return
        }

        updateDisplay()

        // Update every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer!, forMode: .common)

        // Watch the file for external changes (timer added/deleted by Alfred)
        startFileWatcher()
    }

    // MARK: - File watching

    var fileWatcherSource: DispatchSourceFileSystemObject?
    var fileCheckTimer: Timer?

    func startFileWatcher() {
        // Poll-based check every 2 seconds as a reliable fallback
        fileCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.loadTimers()
            self?.updateDisplay()
        }
    }

    // MARK: - Timer data

    func loadTimers() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: timersFilePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            timers = []
            return
        }

        let now = Date()
        timers = json.compactMap { (key, value) -> (id: String, fireDate: Date, message: String)? in
            guard let ms = Double(key) else { return nil }
            let fireDate = Date(timeIntervalSince1970: ms / 1000.0)
            if fireDate <= now { return nil }

            var message = "Timer"
            if let dict = value as? [String: Any] {
                if let msg = dict["message"] as? String, !msg.isEmpty {
                    message = msg
                } else if let intervals = dict["intervals"] as? [[String: Any]],
                          let first = intervals.first,
                          let msg = first["message"] as? String, !msg.isEmpty {
                    message = msg
                }
            }
            return (id: key, fireDate: fireDate, message: message)
        }.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Display

    func tick() {
        // Reload timers to catch any that have fired
        loadTimers()

        if timers.isEmpty {
            NSApp.terminate(nil)
            return
        }
        updateDisplay()
    }

    func updateDisplay() {
        guard let nearest = timers.first else {
            statusItem.button?.title = ""
            NSApp.terminate(nil)
            return
        }

        let remaining = Int(nearest.fireDate.timeIntervalSinceNow)
        if remaining <= 0 {
            // Timer has fired, reload
            loadTimers()
            if timers.isEmpty {
                NSApp.terminate(nil)
                return
            }
            updateDisplay()
            return
        }

        let display = formatTime(remaining)
        statusItem.button?.title = "\u{23F1} \(display)"

        // Build dropdown menu
        let menu = NSMenu()

        for t in timers {
            let secs = max(0, Int(t.fireDate.timeIntervalSinceNow))
            let timeStr = formatTime(secs)
            let item = NSMenuItem(title: "\(t.message)  \u{2014}  \(timeStr)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Hide Menu Timer", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func formatTime(_ totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// --- Main ---
let app = NSApplication.shared
let delegate = MenubarTimerApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No dock icon
app.run()
