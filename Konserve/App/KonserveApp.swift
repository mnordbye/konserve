import AppKit
import SwiftUI

@main
struct KonserveApp: App {
    @StateObject private var model = ConnectorViewModel()

    init() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL)
        else {
            fatalError("The bundled AppIcon.icns resource could not be loaded.")
        }
        NSApplication.shared.applicationIconImage = icon
    }

    var body: some Scene {
        Window("Konserve", id: "main") {
            ConnectorView(model: model)
                .frame(width: 420, height: 560)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 560)
    }
}
