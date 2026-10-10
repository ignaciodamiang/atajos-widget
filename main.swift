import AppKit
import SwiftUI

let stateURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AtajosWidget/content.json")

final class Model: ObservableObject {
    @Published var content = Content(title: "Atajos útiles", shortcuts: [])
    @Published var collapsed = false
    @Published var activeApp = ApplicationContext.general
    private var lastData: Data?
    var visibleShortcuts: [Shortcut] { Shortcut.visible(content.shortcuts, for: activeApp.bundleIdentifier) }
    @discardableResult func reload() -> Bool {
        guard let data = try? Data(contentsOf: stateURL), data != lastData,
              let decoded = try? JSONDecoder().decode(Content.self, from: data) else { return false }
        lastData = data; content = decoded
        return true
    }
}

struct Widget: View {
    @ObservedObject var model: Model
    @ObservedObject var keyboard: KeyboardPreview
    @ObservedObject var naming: KeyboardNaming
    @ObservedObject var practice: ShortcutPractice
    let onCollapse: () -> Void
    let onHide: () -> Void
    let expandedHeight: CGFloat

    private var shortcuts: [Shortcut] { model.visibleShortcuts }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "command").foregroundStyle(.mint)
                Text(model.content.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                Button(action: onCollapse) { Image(systemName: model.collapsed ? "chevron.down" : "chevron.up") }
                    .buttonStyle(.plain).help("Plegar o desplegar")
                Button(action: onHide) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Ocultar; reabrí desde el ícono ⌘ de la barra superior")
            }
            if !model.collapsed {
                HStack(spacing: 6) {
                    Image(systemName: "app").foregroundStyle(.mint)
                    Text(model.activeApp.name).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(shortcuts.contains(where: \.isAppSpecific) ? "App + generales" : "Generales")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }.font(.system(size: 11, weight: .medium))
                KeyboardGuide(keyboard: keyboard, naming: naming)
                if let session = practice.session {
                    PracticeGuide(session: session, labels: naming.labels, onCancel: { practice.cancel() })
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                            if index == 0 || shortcuts[index - 1].category != shortcut.category || shortcuts[index - 1].isAppSpecific != shortcut.isAppSpecific {
                                Text(shortcut.category.uppercased())
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.top, 6)
                            }
                            let available = keyboard.isListening && !shortcut.resolvedCombinations.isEmpty
                            ShortcutRow(shortcut: shortcut, labels: naming.labels, available: available) {
                                if keyboard.canIntercept {
                                    practice.begin(shortcut, isListening: keyboard.canIntercept, modifiers: keyboard.modifiers, keys: keyboard.keys)
                                } else { keyboard.requestInterceptionPermission() }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18).frame(width: 330, height: model.collapsed ? 58 : expandedHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .preferredColorScheme(.dark)
    }
}

struct ShortcutRow: View {
    let shortcut: Shortcut
    let labels: KeyboardLabels
    let available: Bool
    let onPractice: () -> Void
    private var row: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(shortcut.action).font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(labels.text(for: shortcut))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.8)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .frame(maxWidth: 148, alignment: .trailing)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        }.foregroundStyle(.primary).contentShape(Rectangle())
    }
    var body: some View {
        Group {
            if available {
                Button(action: onPractice) { row }.buttonStyle(.plain)
            } else { row }
        }
        .help(available ? "Practicar este atajo sin ejecutar su acción; macOS puede pedir Accesibilidad." : (shortcut.resolvedCombinations.isEmpty ? "Este atajo se muestra como referencia; su combinación no admite práctica." : "Para practicar, habilitá Monitoreo de entrada desde el menú ⌘."))
        .accessibilityLabel(shortcut.action + ", " + labels.text(for: shortcut, fullNames: true))
    }
}

struct KeyboardGuide: View {
    @ObservedObject var keyboard: KeyboardPreview
    @ObservedObject var naming: KeyboardNaming
    private var currentCombination: [String] {
        naming.labels.combination(modifiers: keyboard.modifiers, keys: keyboard.keys)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TECLAS EN VIVO").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(ModifierKey.allCases) { key in
                    let pressed = keyboard.modifiers.contains(key)
                    VStack(spacing: 3) {
                        Text(key.symbol).font(.system(size: 18, weight: .semibold))
                        Text(naming.labels.name(key)).font(.system(size: 9, weight: .medium))
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8).frame(height: 22)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .foregroundStyle(pressed ? Color.black : Color.white.opacity(0.8))
                    .background(pressed ? Color.mint : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(naming.labels.name(key) + (pressed ? ": presionada" : ": suelta"))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TECLAS PRESIONADAS")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                Text(currentCombination.isEmpty ? "Ninguna tecla presionada" : currentCombination.joined(separator: " + "))
                    .font(.system(size: 13, weight: currentCombination.isEmpty ? .regular : .semibold))
                    .foregroundStyle(currentCombination.isEmpty ? Color.secondary : Color.mint)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 36, alignment: .topLeading)
        }.padding(10).fixedSize(horizontal: false, vertical: true)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PracticeGuide: View {
    let session: PracticeSession
    let labels: KeyboardLabels
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(session.succeeded ? "Correcto" : "PRACTICAR", systemImage: session.succeeded ? "checkmark.circle.fill" : "keyboard")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(session.succeeded ? Color.mint : Color.secondary)
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Cancelar práctica").accessibilityLabel("Cancelar práctica")
            }
            Text(session.shortcut.action).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Text(labels.text(for: session.shortcut, fullNames: true))
                .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                .foregroundStyle(session.succeeded ? Color.mint : Color.primary)
            if session.waitingForRelease {
                Text("Soltá las teclas para empezar").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(session.succeeded ? "Teclas liberadas" : "Teclas bloqueadas hasta acertar · Esc cancela")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).fixedSize(horizontal: false, vertical: true)
        .background(session.succeeded ? Color.mint.opacity(0.12) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = Model()
    let keyboard = KeyboardPreview()
    let naming = KeyboardNaming()
    let practice = ShortcutPractice()
    var panel: NSPanel!
    var status: NSStatusItem!
    var timer: Timer?
    var activationObserver: NSObjectProtocol?
    var keyboardMenu: NSMenu?
    var expandedHeight: CGFloat = 620
    var readyToReport = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtimeURL = stateURL.deletingLastPathComponent().appendingPathComponent("runtime.json")
        let previous = (try? Data(contentsOf: runtimeURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        model.collapsed = (UserDefaults.standard.object(forKey: "Collapsed") as? Bool) ?? (previous["collapsed"] as? Bool) ?? false
        model.reload()
        updateActiveApp(NSWorkspace.shared.frontmostApplication)
        expandedHeight = min(620, (NSScreen.main?.visibleFrame.height ?? 700) - 48)
        let height: CGFloat = model.collapsed ? 58 : expandedHeight
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Atajos"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        let hosting = NSHostingView(rootView: Widget(model: model, keyboard: keyboard, naming: naming, practice: practice,
                                                    onCollapse: { [weak self] in self?.toggleCollapse() }, onHide: { [weak self] in self?.hide() }, expandedHeight: expandedHeight))
        hosting.sizingOptions = []
        panel.contentView = hosting
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 354, y: frame.maxY - height - 24))
        }
        panel.setFrameAutosaveName("AtajosWidgetPosition")
        var savedFrame = panel.frame
        if CommandLine.arguments.contains("--restore-window-state"), let frame = previous["frame"] as? [String: Double],
           let x = frame["x"], let y = frame["y"], let savedHeight = frame["height"] {
            savedFrame = NSRect(x: x, y: y, width: 330, height: savedHeight)
        }
        savedFrame.origin.y += savedFrame.height - height
        savedFrame.size = NSSize(width: 330, height: height)
        panel.setFrame(savedFrame, display: true)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) { panel.center() }
        if !CommandLine.arguments.contains("--restore-window-state") || (previous["visible"] as? Bool) != false { panel.orderFrontRegardless() }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Atajos")
        let menu = NSMenu()
        menu.addItem(withTitle: "Mostrar atajos", action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: "Ocultar", action: #selector(hide), keyEquivalent: "")
        menu.addItem(withTitle: "Plegar / desplegar", action: #selector(toggleCollapse), keyEquivalent: "")
        menu.addItem(withTitle: "Habilitar detección de atajos…", action: #selector(enableKeyboardPreview), keyEquivalent: "")
        menu.addItem(withTitle: "Permitir práctica con teclas bloqueadas…", action: #selector(enableBlockingPractice), keyEquivalent: "")
        let referenceItem = NSMenuItem(title: "Teclado de referencia", action: nil, keyEquivalent: "")
        let referenceMenu = NSMenu()
        for (index, reference) in KeyboardReference.allCases.enumerated() {
            let item = NSMenuItem(title: reference.title, action: #selector(selectKeyboard(_:)), keyEquivalent: "")
            item.tag = index; item.target = self
            referenceMenu.addItem(item)
        }
        referenceItem.submenu = referenceMenu; keyboardMenu = referenceMenu
        menu.addItem(referenceItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        naming.onChange = { [weak self] in self?.updateKeyboardMenu(); self?.reportState() }
        naming.start()
        updateKeyboardMenu()
        keyboard.onStatusChange = { [weak self] in
            guard let self = self else { return }
            self.practice.validate(content: self.model.content, context: self.model.activeApp, isListening: self.keyboard.canIntercept)
            self.reportState()
        }
        keyboard.onStateChange = { [weak self] in
            guard let self = self else { return }
            self.practice.reconcile(modifiers: self.keyboard.modifiers, keys: self.keyboard.keys)
        }
        keyboard.onKeyDown = { [weak self] press in self?.practice.receive(press) }
        keyboard.shouldBlock = { [weak self] in self?.practice.isBlocking ?? false }
        keyboard.onCancelPractice = { [weak self] in self?.practice.cancel() }
        practice.onChange = { [weak self] in self?.reportState() }
        keyboard.start()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            self?.updateActiveApp(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        readyToReport = true
        reportState()
        timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.model.reload() {
                self.practice.validate(content: self.model.content, context: self.model.activeApp, isListening: self.keyboard.canIntercept)
                self.reportState()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        if CommandLine.arguments.contains("--enable-key-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.keyboard.requestPermission() }
        }
        if CommandLine.arguments.contains("--enable-blocking-practice") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.keyboard.requestInterceptionPermission() }
        }
    }

    func updateActiveApp(_ app: NSRunningApplication?) {
        let candidate = app.map { ApplicationContext(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName ?? "Aplicación") }
        let resolved = ApplicationContext.resolved(candidate, ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.nacho.atajos-widget", previous: model.activeApp)
        guard resolved != model.activeApp else { return }
        model.activeApp = resolved
        practice.validate(content: model.content, context: resolved, isListening: keyboard.canIntercept)
        reportState()
    }
    func updateKeyboardMenu() {
        for item in keyboardMenu?.items ?? [] {
            item.state = KeyboardReference.allCases[item.tag] == naming.reference ? .on : .off
        }
    }
    @objc func selectKeyboard(_ sender: NSMenuItem) { naming.select(KeyboardReference.allCases[sender.tag]) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    @objc func show() { panel?.orderFrontRegardless(); reportState() }
    @objc func hide() { practice.cancel(); panel.orderOut(nil); reportState() }
    @objc func enableKeyboardPreview() { keyboard.requestPermission() }
    @objc func enableBlockingPractice() { keyboard.requestInterceptionPermission() }
    @objc func toggleCollapse() {
        practice.cancel()
        model.collapsed.toggle()
        var frame = panel.frame
        let height: CGFloat = model.collapsed ? 58 : expandedHeight
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        reportState()
    }
    func windowDidMove(_ notification: Notification) { reportState() }
    func reportState() {
        guard readyToReport, let panel = panel else { return }
        UserDefaults.standard.set(model.collapsed, forKey: "Collapsed")
        let state: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "title": model.content.title,
            "shortcut_count": model.content.shortcuts.count,
            "visible_shortcut_count": model.visibleShortcuts.count,
            "active_app": ["bundle_identifier": model.activeApp.bundleIdentifier.map { $0 as Any } ?? NSNull(), "name": model.activeApp.name],
            "keyboard_reference": naming.reference.rawValue,
            "fn_key_name": naming.labels.functionName,
            "visible": panel.isVisible,
            "collapsed": model.collapsed,
            "floating": panel.level == .floating,
            "keyboard_preview": ["modifiers": true, "input_permission": keyboard.hasInputPermission, "accessibility_permission": keyboard.hasAccessibilityPermission, "combinations": keyboard.isListening, "can_block_shortcuts": keyboard.canIntercept],
            "practice": ["active": practice.session != nil, "blocking": keyboard.canIntercept && practice.isBlocking, "succeeded": practice.session?.succeeded ?? false],
            "window_id": panel.windowNumber,
            "frame": ["x": panel.frame.origin.x, "y": panel.frame.origin.y, "width": panel.frame.width, "height": panel.frame.height]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: stateURL.deletingLastPathComponent().appendingPathComponent("runtime.json"), options: .atomic)
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        practice.cancel(); timer?.invalidate(); keyboard.stop(); naming.stop()
        if let observer = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
