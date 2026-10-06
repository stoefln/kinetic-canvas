import AppKit
import SwiftUI

/// Applies Kinetic Canvas window chrome to a hosting window: dark appearance, the
/// shared transparent-background setting, an optional saved frame, and an
/// optional float-when-active level. Both the control panel and the preset
/// library use it, so toggling transparency affects every window.
struct WindowConfigurator: NSViewRepresentable {
    let transparentBackground: Bool
    /// Window frame autosave key. `nil` leaves the frame to SwiftUI.
    var autosaveName: String? = nil
    /// Float above other windows while Kinetic Canvas is the active app. The control
    /// panel wants this (it sits over the full-screen preview); the library does
    /// not.
    var floatsWhenActive: Bool = false

    func makeNSView(context: Context) -> NSView {
        let view = WindowConfiguratorProbe()
        view.transparentBackground = transparentBackground
        view.autosaveName = autosaveName
        view.floatsWhenActive = floatsWhenActive
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowConfiguratorProbe else { return }
        view.transparentBackground = transparentBackground
        view.autosaveName = autosaveName
        view.floatsWhenActive = floatsWhenActive
        view.configureWindow()
    }
}

private final class WindowConfiguratorProbe: NSView {
    var transparentBackground = false
    var autosaveName: String?
    var floatsWhenActive = false
    private weak var autosavedWindow: NSWindow?
    private var activationObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
        installActivationObservers()
    }

    deinit {
        activationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Re-asserts the float level whenever Kinetic Canvas gains or loses focus. `NSView`
    /// updates alone do not fire on Cmd-Tab.
    private func installActivationObservers() {
        guard floatsWhenActive, activationObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            activationObservers.append(center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.configureWindow()
            })
        }
    }

    func configureWindow() {
        guard let window else { return }
        if let autosaveName, autosavedWindow !== window {
            window.setFrameAutosaveName(autosaveName)
            autosavedWindow = window
        }
        window.appearance = NSAppearance(named: .darkAqua)
        if floatsWhenActive {
            // Float above the local full-screen preview while Kinetic Canvas is active,
            // but drop to a normal level when another app takes focus so the
            // panel does not stay on top after Cmd-Tab.
            window.level = NSApp.isActive ? .floating : .normal
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        }
        window.isOpaque = !transparentBackground
        window.backgroundColor = transparentBackground ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = transparentBackground
        window.hasShadow = !transparentBackground
    }
}
