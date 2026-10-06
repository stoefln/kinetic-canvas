import MetalKit
import SwiftUI

struct MetalPreview: NSViewRepresentable {
    let renderer: MetalRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = renderer
        renderer.attach(view: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
}
