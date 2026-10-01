import SwiftUI

@main
struct DanceFXApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup("DanceFX — Real-Time Human Matting") {
            ContentView(controller: controller)
                .frame(minWidth: 300, minHeight: 140, alignment: .topLeading)
                .task { controller.start() }
                .onDisappear { controller.stop() }
        }
        .defaultSize(width: 760, height: 420)
        .commands {
            CommandGroup(after: .toolbar) {
                Menu("Control Panel") {
                    Button("Toggle Transparent Background") {
                        controller.controlPanelTransparent.toggle()
                    }
                }
            }
        }

        Window("Preset Library", id: "preset-library") {
            PresetLibraryView(controller: controller)
                .frame(minWidth: 620, minHeight: 440)
        }
        .defaultSize(width: 980, height: 690)
    }
}
