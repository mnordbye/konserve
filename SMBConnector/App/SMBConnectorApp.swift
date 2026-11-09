import SwiftUI

@main
struct SMBConnectorApp: App {
    @StateObject private var model = ConnectorViewModel()

    var body: some Scene {
        Window("SMB Connector", id: "main") {
            ConnectorView(model: model)
                .frame(width: 420, height: 560)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 560)
    }
}
