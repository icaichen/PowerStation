import SwiftUI
import Cocoa
import Carbon
import Combine

// MARK: - Main App
@main
struct PowerStationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowManager = WindowManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(windowManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Window") {
                Button("Split Left") {
                    windowManager.splitWindow(.left)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])
                
                Button("Split Right") {
                    windowManager.splitWindow(.right)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])
                
                Button("Split Top") {
                    windowManager.splitWindow(.top)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])
                
                Button("Split Bottom") {
                    windowManager.splitWindow(.bottom)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])
                
                Divider()
                
                Button("Save Permanent Workstation") {
                    windowManager.saveWorkstation(temporary: false)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                
                Button("Save Temporary Workstation") {
                    windowManager.saveWorkstation(temporary: true)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(windowManager)
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupGlobalHotkeys()
        requestAccessibilityPermissions()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "⊞"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Window Manager", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    private func setupGlobalHotkeys() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .option]) {
                switch event.charactersIgnoringModifiers {
                case "s":
                    WindowManager.shared.saveWorkstation(temporary: false)
                case "t":
                    WindowManager.shared.saveWorkstation(temporary: true)
                default:
                    break
                }
            }
        }
    }
    
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    @objc func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    
    @objc func showPreferences() {
        // Create and show preferences window - this would need custom implementation
        print("Show preferences requested")
    }
}

// MARK: - Models
struct WindowInfo: Codable, Identifiable {
    let id = UUID()
    let appName: String
    let appBundleID: String
    let windowTitle: String
    var frame: CGRect
    let windowNumber: Int
    
    enum CodingKeys: String, CodingKey {
        case appName, appBundleID, windowTitle, frame, windowNumber
    }
}

struct Workstation: Codable, Identifiable {
    let id = UUID()
    var name: String
    var windows: [WindowInfo]
    var isTemporary: Bool
    var createdAt: Date
    var lastUsed: Date
    
    enum CodingKeys: String, CodingKey {
        case name, windows, isTemporary, createdAt, lastUsed
    }
}

enum SplitPosition {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case fullscreen, center
    
    func frame(for screen: NSScreen) -> CGRect {
        let screenFrame = screen.visibleFrame
        
        switch self {
        case .left:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY,
                         width: screenFrame.width / 2, height: screenFrame.height)
        case .right:
            return CGRect(x: screenFrame.midX, y: screenFrame.minY,
                         width: screenFrame.width / 2, height: screenFrame.height)
        case .top:
            return CGRect(x: screenFrame.minX, y: screenFrame.midY,
                         width: screenFrame.width, height: screenFrame.height / 2)
        case .bottom:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY,
                         width: screenFrame.width, height: screenFrame.height / 2)
        case .topLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.midY,
                         width: screenFrame.width / 2, height: screenFrame.height / 2)
        case .topRight:
            return CGRect(x: screenFrame.midX, y: screenFrame.midY,
                         width: screenFrame.width / 2, height: screenFrame.height / 2)
        case .bottomLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY,
                         width: screenFrame.width / 2, height: screenFrame.height / 2)
        case .bottomRight:
            return CGRect(x: screenFrame.midX, y: screenFrame.minY,
                         width: screenFrame.width / 2, height: screenFrame.height / 2)
        case .fullscreen:
            return screenFrame
        case .center:
            let width = screenFrame.width * 0.6
            let height = screenFrame.height * 0.6
            return CGRect(x: screenFrame.minX + (screenFrame.width - width) / 2,
                         y: screenFrame.minY + (screenFrame.height - height) / 2,
                         width: width, height: height)
        }
    }
}

struct LayoutPreset: Identifiable {
    let id = UUID()
    let name: String
    let windowCount: Int
    let positions: [SplitPosition]
    let icon: String
}

// MARK: - Window Manager
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    @Published var workstations: [Workstation] = []
    @Published var activeWindows: [WindowInfo] = []
    @Published var includeActiveAppsInSwitcher = true
    @Published var currentWorkstation: Workstation?
    
    let layoutPresets: [LayoutPreset] = [
        LayoutPreset(name: "Side by Side", windowCount: 2, positions: [.left, .right], icon: "rectangle.split.2x1"),
        LayoutPreset(name: "Top & Bottom", windowCount: 2, positions: [.top, .bottom], icon: "rectangle.split.1x2"),
        LayoutPreset(name: "Quarters", windowCount: 4, positions: [.topLeft, .topRight, .bottomLeft, .bottomRight], icon: "rectangle.split.2x2"),
        LayoutPreset(name: "Main + Sides", windowCount: 3, positions: [.left, .topRight, .bottomRight], icon: "rectangle.split.3x1"),
        LayoutPreset(name: "Grid", windowCount: 6, positions: [.topLeft, .topRight, .bottomLeft, .bottomRight, .top, .bottom], icon: "square.grid.3x2")
    ]
    
    private init() {
        loadWorkstations()
        refreshActiveWindows()
        setupWindowMonitoring()
    }
    
    // MARK: - Window Splitting
    func splitWindow(_ position: SplitPosition) {
        guard let frontWindow = NSWorkspace.shared.frontmostApplication,
              let screen = NSScreen.main else { return }
        
        let targetFrame = position.frame(for: screen)
        
        // Use Accessibility API to resize window
        if let app = NSRunningApplication(processIdentifier: frontWindow.processIdentifier) {
            moveWindow(app: app, to: targetFrame)
        }
    }
    
    private func moveWindow(app: NSRunningApplication, to frame: CGRect) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var windowElement: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowElement)
        
        if let window = windowElement {
            var cgPoint = CGPoint(x: frame.origin.x, y: frame.origin.y)
            var cgSize = CGSize(width: frame.width, height: frame.height)
            let position = AXValueCreate(.cgPoint, &cgPoint)
            let size = AXValueCreate(.cgSize, &cgSize)

            AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, position!)
            AXUIElementSetAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, size!)
        }
    }
    
    // MARK: - Workstation Management
    func saveWorkstation(temporary: Bool) {
        refreshActiveWindows()
        
        let workstation = Workstation(
            name: temporary ? "Temp \(Date().formatted())" : "Workstation \(workstations.count + 1)",
            windows: activeWindows,
            isTemporary: temporary,
            createdAt: Date(),
            lastUsed: Date()
        )
        
        workstations.append(workstation)
        saveWorkstations()
        
        if temporary {
            setupTemporaryWorkstationMonitoring(workstation)
        }
    }
    
    func loadWorkstation(_ workstation: Workstation) {
        currentWorkstation = workstation
        
        for windowInfo in workstation.windows {
            // Launch app if not running
            if !isAppRunning(bundleID: windowInfo.appBundleID) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: windowInfo.appBundleID) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
                }
            }
            
            // Restore window position
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.restoreWindowPosition(windowInfo)
            }
        }
        
        // Update last used
        if let index = workstations.firstIndex(where: { $0.id == workstation.id }) {
            workstations[index].lastUsed = Date()
            saveWorkstations()
        }
    }
    
    func deleteWorkstation(_ workstation: Workstation) {
        workstations.removeAll { $0.id == workstation.id }
        saveWorkstations()
    }
    
    func createWorkstationFromSelection(apps: [NSRunningApplication], layout: LayoutPreset, temporary: Bool) {
        var windows: [WindowInfo] = []
        
        for (index, app) in apps.enumerated() {
            guard index < layout.positions.count else { break }
            
            let position = layout.positions[index]
            let frame = position.frame(for: NSScreen.main ?? NSScreen.screens[0])
            
            let windowInfo = WindowInfo(
                appName: app.localizedName ?? "Unknown",
                appBundleID: app.bundleIdentifier ?? "",
                windowTitle: "",
                frame: frame,
                windowNumber: 0
            )
            
            windows.append(windowInfo)
        }
        
        let workstation = Workstation(
            name: "Custom Workstation",
            windows: windows,
            isTemporary: temporary,
            createdAt: Date(),
            lastUsed: Date()
        )
        
        workstations.append(workstation)
        saveWorkstations()
        loadWorkstation(workstation)
    }
    
    // MARK: - Helper Methods
    private func refreshActiveWindows() {
        activeWindows.removeAll()
        
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let windowNumber = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else { continue }
            
            let frame = CGRect(x: x, y: y, width: width, height: height)
            
            let windowInfo = WindowInfo(
                appName: ownerName,
                appBundleID: "",
                windowTitle: window[kCGWindowName as String] as? String ?? "",
                frame: frame,
                windowNumber: windowNumber
            )
            
            activeWindows.append(windowInfo)
        }
    }
    
    private func isAppRunning(bundleID: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
    
    private func restoreWindowPosition(_ windowInfo: WindowInfo) {
        // Implementation would use Accessibility API to restore window position
        // This is simplified for demonstration
    }
    
    private func setupWindowMonitoring() {
        // Monitor window close events for temporary workstations
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }
    
    private func setupTemporaryWorkstationMonitoring(_ workstation: Workstation) {
        // Monitor for closed windows in temporary workstations
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        // Remove temporary workstations if any app closes
        workstations.removeAll { station in
            guard station.isTemporary else { return false }
            
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                return station.windows.contains { $0.appBundleID == app.bundleIdentifier }
            }
            return false
        }
        saveWorkstations()
    }
    
    // MARK: - Persistence
    private func saveWorkstations() {
        if let encoded = try? JSONEncoder().encode(workstations) {
            UserDefaults.standard.set(encoded, forKey: "workstations")
        }
    }
    
    private func loadWorkstations() {
        if let data = UserDefaults.standard.data(forKey: "workstations"),
           let decoded = try? JSONDecoder().decode([Workstation].self, from: data) {
            workstations = decoded
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var windowManager: WindowManager
    @State private var selectedTab = 0
    @State private var searchText = ""
    
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: WorkstationListView()) {
                    Label("Workstations", systemImage: "rectangle.3.group")
                }
                
                NavigationLink(destination: AppSwitcherView()) {
                    Label("App Switcher", systemImage: "command")
                }
                
                NavigationLink(destination: WindowSplitterView()) {
                    Label("Window Splitter", systemImage: "rectangle.split.2x2")
                }
                
                NavigationLink(destination: WorkstationCreatorView()) {
                    Label("Create Workstation", systemImage: "plus.rectangle")
                }
            }
            .navigationTitle("Window Manager")
            .frame(minWidth: 200)
        } detail: {
            WorkstationListView()
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Workstation List View
struct WorkstationListView: View {
    @EnvironmentObject var windowManager: WindowManager
    @State private var selectedWorkstation: Workstation?
    
    var body: some View {
        VStack {
            HStack {
                Text("Workstations")
                    .font(.largeTitle)
                    .bold()
                
                Spacer()
                
                Button(action: { windowManager.saveWorkstation(temporary: false) }) {
                    Label("Save Current", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            if windowManager.workstations.isEmpty {
                VStack {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Workstations")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Press ⌘⌥S to save current window layout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                        ForEach(windowManager.workstations) { workstation in
                            WorkstationCard(workstation: workstation)
                                .onTapGesture {
                                    windowManager.loadWorkstation(workstation)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Workstation Card
struct WorkstationCard: View {
    let workstation: Workstation
    @EnvironmentObject var windowManager: WindowManager
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(workstation.name)
                        .font(.headline)
                    
                    if workstation.isTemporary {
                        Label("Temporary", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Button(action: { windowManager.deleteWorkstation(workstation) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(workstation.windows.prefix(3)) { window in
                    HStack {
                        Image(systemName: "app.dashed")
                            .font(.caption)
                        Text(window.appName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                
                if workstation.windows.count > 3 {
                    Text("+ \(workstation.windows.count - 3) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text("Last used: \(workstation.lastUsed, style: .relative)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Load") {
                    windowManager.loadWorkstation(workstation)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 2)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - App Switcher View
struct AppSwitcherView: View {
    @EnvironmentObject var windowManager: WindowManager
    @State private var runningApps: [NSRunningApplication] = []
    @State private var selectedApp: NSRunningApplication?
    
    var body: some View {
        VStack {
            HStack {
                Text("App Switcher")
                    .font(.largeTitle)
                    .bold()
                
                Spacer()
                
                Toggle("Include Active Apps", isOn: $windowManager.includeActiveAppsInSwitcher)
                    .toggleStyle(.switch)
            }
            .padding()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
                    // Show workstations
                    ForEach(windowManager.workstations) { workstation in
                        VStack {
                            Image(systemName: "rectangle.3.group.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.accentColor)
                            
                            Text(workstation.name)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 100, height: 100)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .onTapGesture {
                            windowManager.loadWorkstation(workstation)
                        }
                    }
                    
                    // Show running apps if enabled
                    if windowManager.includeActiveAppsInSwitcher {
                        ForEach(runningApps, id: \.processIdentifier) { app in
                            VStack {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                } else {
                                    Image(systemName: "app")
                                        .font(.system(size: 40))
                                }
                                
                                Text(app.localizedName ?? "Unknown")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 100, height: 100)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(10)
                            .onTapGesture {
                                app.activate()
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            refreshRunningApps()
        }
    }
    
    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.localizedName != nil
        }
    }
}

// MARK: - Window Splitter View
struct WindowSplitterView: View {
    @EnvironmentObject var windowManager: WindowManager
    
    let splitOptions: [(SplitPosition, String, String)] = [
        (.left, "Left Half", "rectangle.lefthalf.filled"),
        (.right, "Right Half", "rectangle.righthalf.filled"),
        (.top, "Top Half", "rectangle.tophalf.filled"),
        (.bottom, "Bottom Half", "rectangle.bottomhalf.filled"),
        (.topLeft, "Top Left", "rectangle.topleft.filled"),
        (.topRight, "Top Right", "rectangle.topright.filled"),
        (.bottomLeft, "Bottom Left", "rectangle.bottomleft.filled"),
        (.bottomRight, "Bottom Right", "rectangle.bottomright.filled"),
        (.fullscreen, "Fullscreen", "rectangle.fill"),
        (.center, "Center", "rectangle.center.inset.filled")
    ]
    
    var body: some View {
        VStack {
            Text("Window Splitter")
                .font(.largeTitle)
                .bold()
                .padding()
            
            Text("Click a position to move the frontmost window")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 20) {
                ForEach(splitOptions, id: \.1) { position, name, icon in
                    Button(action: { windowManager.splitWindow(position) }) {
                        VStack {
                            Image(systemName: icon)
                                .font(.system(size: 40))
                            Text(name)
                                .font(.caption)
                        }
                        .frame(width: 150, height: 100)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            
            Spacer()
        }
    }
}

// MARK: - Workstation Creator View
struct WorkstationCreatorView: View {
    @EnvironmentObject var windowManager: WindowManager
    @State private var selectedApps: Set<NSRunningApplication> = []
    @State private var runningApps: [NSRunningApplication] = []
    @State private var selectedLayout: LayoutPreset?
    @State private var isTemporary = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Workstation")
                .font(.largeTitle)
                .bold()
                .padding(.horizontal)
            
            // Step 1: Select Apps
            VStack(alignment: .leading) {
                Text("Step 1: Select Apps")
                    .font(.headline)
                    .padding(.horizontal)
                
                ScrollView(.horizontal) {
                    HStack(spacing: 15) {
                        ForEach(runningApps, id: \.processIdentifier) { app in
                            VStack {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                }
                                Text(app.localizedName ?? "Unknown")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .frame(width: 80, height: 80)
                            .background(selectedApps.contains(app) ? Color.accentColor.opacity(0.3) : Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedApps.contains(app) ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                if selectedApps.contains(app) {
                                    selectedApps.remove(app)
                                } else {
                                    selectedApps.insert(app)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Step 2: Select Layout
            if !selectedApps.isEmpty {
                VStack(alignment: .leading) {
                    Text("Step 2: Select Layout")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    let availableLayouts = windowManager.layoutPresets.filter { $0.windowCount == selectedApps.count }
                    
                    if availableLayouts.isEmpty {
                        Text("No preset layouts for \(selectedApps.count) windows. Windows will be arranged automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 15) {
                                ForEach(availableLayouts) { layout in
                                    VStack {
                                        Image(systemName: layout.icon)
                                            .font(.system(size: 30))
                                        Text(layout.name)
                                            .font(.caption)
                                    }
                                    .frame(width: 100, height: 80)
                                    .background(selectedLayout?.id == layout.id ? Color.accentColor.opacity(0.3) : Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedLayout?.id == layout.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        selectedLayout = layout
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            
            // Step 3: Save Options
            if !selectedApps.isEmpty {
                VStack(alignment: .leading) {
                    Text("Step 3: Save Options")
                        .font(.headline)
                    
                    Toggle("Temporary Workstation", isOn: $isTemporary)
                        .help("Temporary workstations are removed when any app is closed")
                    
                    HStack {
                        Button("Cancel") {
                            selectedApps.removeAll()
                            selectedLayout = nil
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Create Workstation") {
                            if let layout = selectedLayout {
                                windowManager.createWorkstationFromSelection(
                                    apps: Array(selectedApps),
                                    layout: layout,
                                    temporary: isTemporary
                                )
                            }
                            selectedApps.removeAll()
                            selectedLayout = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedLayout == nil && !windowManager.layoutPresets.filter { $0.windowCount == selectedApps.count }.isEmpty)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            
            Spacer()
        }
        .onAppear {
            refreshRunningApps()
        }
    }
    
    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.localizedName != nil
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @EnvironmentObject var windowManager: WindowManager
    @AppStorage("autoRestoreWorkstations") var autoRestore = true
    @AppStorage("showMenuBarIcon") var showMenuBarIcon = true
    @AppStorage("animateWindowMovement") var animateWindowMovement = true
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            HotkeysSettingsView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoRestoreWorkstations") var autoRestore = true
    @AppStorage("showMenuBarIcon") var showMenuBarIcon = true
    @AppStorage("animateWindowMovement") var animateWindowMovement = true
    @AppStorage("includeMininmizedWindows") var includeMinimized = true
    
    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Auto-restore permanent workstations on launch", isOn: $autoRestore)
                Toggle("Include minimized windows in workstations", isOn: $includeMinimized)
                Toggle("Animate window movements", isOn: $animateWindowMovement)
            }
            
            Section("Appearance") {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            }
        }
        .padding()
    }
}

struct HotkeysSettingsView: View {
    @AppStorage("savePermHotkey") var savePermHotkey = "⌘⌥S"
    @AppStorage("saveTempHotkey") var saveTempHotkey = "⌘⌥T"
    @AppStorage("switcherHotkey") var switcherHotkey = "⌥Tab"
    
    var body: some View {
        Form {
            Section("Window Management") {
                HStack {
                    Text("Save Permanent Workstation:")
                    Spacer()
                    Text(savePermHotkey)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text("Save Temporary Workstation:")
                    Spacer()
                    Text(saveTempHotkey)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text("App Switcher:")
                    Spacer()
                    Text(switcherHotkey)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                }
            }
            
            Text("Click on a hotkey to change it")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Window Manager")
                .font(.largeTitle)
                .bold()
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Features:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 5) {
                    Label("Window splitting like Moom/Magnet", systemImage: "rectangle.split.2x2")
                    Label("Workstation management", systemImage: "rectangle.3.group")
                    Label("Enhanced app switching", systemImage: "command")
                    Label("Permanent & temporary layouts", systemImage: "clock")
                }
                .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - App Switcher Overlay Window
class AppSwitcherWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        
        center()
    }
}

// MARK: - Extensions
extension NSScreen {
    var displayID: CGDirectDisplayID {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
