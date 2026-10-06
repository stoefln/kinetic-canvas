import SwiftUI

@main
struct KineticCanvasApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup("Kinetic Canvas — Real-Time Human Matting") {
            ContentView(controller: controller)
                .frame(minWidth: 300, minHeight: 140, alignment: .topLeading)
                .task { controller.start() }
                .onDisappear { controller.stop() }
        }
        .defaultSize(width: 760, height: 420)
        .commands {
            CommandGroup(after: .toolbar) {
                Menu("Windows") {
                    Button("Toggle Transparent Background") {
                        controller.controlPanelTransparent.toggle()
                    }
                }
            }
        }

        Window("Preset Library", id: "preset-library") {
            PresetLibraryView(controller: controller)
                .frame(minWidth: 240, minHeight: 300)
        }
        .defaultSize(width: 720, height: 560)
    }
}
