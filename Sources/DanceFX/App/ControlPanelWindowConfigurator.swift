import AppKit
import SwiftUI

struct ControlPanelWindowConfigurator: NSViewRepresentable {
    let transparentBackground: Bool

    func makeNSView(context: Context) -> NSView {
        let view = ControlPanelWindowProbe()
        view.transparentBackground = transparentBackground
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ControlPanelWindowProbe else { return }
        view.transparentBackground = transparentBackground
        view.configureWindow()
    }
}

private final class ControlPanelWindowProbe: NSView {
    var transparentBackground = false
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

    /// Re-asserts the level whenever DanceFX gains or loses focus. `NSView`
    /// updates alone do not fire on Cmd-Tab.
    private func installActivationObservers() {
        guard activationObservers.isEmpty else { return }
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
        if autosavedWindow !== window {
            window.setFrameAutosaveName("DanceFX.ControlPanel.Frame.v1")
            autosavedWindow = window
        }
        window.appearance = NSAppearance(named: .darkAqua)
        // Float above the local full-screen preview while DanceFX is the active
        // app, but drop to a normal level when another app takes focus so the
        // panel does not stay on top after Cmd-Tab.
        window.level = NSApp.isActive ? .floating : .normal
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.isOpaque = !transparentBackground
        window.backgroundColor = transparentBackground ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = transparentBackground
        window.hasShadow = !transparentBackground
    }
}
