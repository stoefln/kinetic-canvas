import AppKit
import SwiftUI

@MainActor
final class ProjectorOutputController: NSObject {
    typealias StatusHandler = @MainActor (_ message: String, _ connected: Bool) -> Void

    private let renderer: MetalRenderer
    private let controller: AppController
    private let statusHandler: StatusHandler
    private var outputWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?

    init(renderer: MetalRenderer, controller: AppController, statusHandler: @escaping StatusHandler) {
        self.renderer = renderer
        self.controller = controller
        self.statusHandler = statusHandler
        super.init()
    }

    func start() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        outputWindow?.close()
        outputWindow = nil
    }

    func refresh() {
        // NSScreen.screens starts with the display containing the menu bar. DanceFX
        // treats that as the operator display and prefers the first other one for output.
        // With no external display, the primary display becomes the local preview.
        guard let primaryScreen = NSScreen.screens.first else {
            outputWindow?.close()
            outputWindow = nil
            statusHandler("No display available", false)
            return
        }
        let externalScreen = NSScreen.screens.dropFirst().first
        let screen = externalScreen ?? primaryScreen

        if let outputWindow, outputWindow.screen == screen {
            outputWindow.setFrame(screen.frame, display: true)
            outputWindow.orderFrontRegardless()
        } else {
            outputWindow?.close()
            outputWindow = makeWindow(on: screen)
            outputWindow?.orderFrontRegardless()
        }

        if externalScreen != nil {
            statusHandler("Projector output: \(screen.localizedName)", true)
        } else {
            statusHandler("Local full-screen preview: \(screen.localizedName)", false)
        }
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.level = .normal
        window.contentView = NSHostingView(
            rootView: ProjectorContent(renderer: renderer, controller: controller)
                .background(Color.black)
                .ignoresSafeArea()
        )
        window.setFrame(screen.frame, display: true)
        return window
    }
}

private struct ProjectorContent: View {
    let renderer: MetalRenderer
    @ObservedObject var controller: AppController

    var body: some View {
        ZStack {
            MetalPreview(renderer: renderer)
            SampleLineOverlay(lines: controller.sampleLines,
                              visible: controller.activeEffects.contains(.lineSampler)
                                  && !controller.disabledEffects.contains(.lineSampler))
                .allowsHitTesting(false)
        }
    }
}
