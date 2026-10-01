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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        if autosavedWindow !== window {
            window.setFrameAutosaveName("DanceFX.ControlPanel.Frame.v1")
            autosavedWindow = window
        }
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = .floating
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.isOpaque = !transparentBackground
        window.backgroundColor = transparentBackground ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = transparentBackground
        window.hasShadow = !transparentBackground
    }
}
