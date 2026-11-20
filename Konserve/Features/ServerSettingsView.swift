import AppKit
import KonserveCore
import SwiftUI
import UniformTypeIdentifiers

struct ServerSettingsView: View {
    @ObservedObject var model: ConnectorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingServer: SMBServer?
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var serverToDelete: SMBServer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Configured Servers")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    editingServer = nil
                    showingEditor = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if model.servers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No Configured Servers")
                        .font(.headline)
                    Text("Add a server to monitor its availability.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.servers) { server in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.displayName)
                                    .font(.headline)
                                Text(endpointSummary(for: server))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Edit") {
                                editingServer = server
                                showingEditor = true
                            }
                            .buttonStyle(.borderless)
                            Button {
                                serverToDelete = server
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Delete \(server.displayName)")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Text("Config File Location: \(model.configurationFileURL.path)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Change…") {
                    chooseConfigurationLocation()
                }
                .controlSize(.small)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520, height: 420)
        .sheet(isPresented: $showingEditor) {
            ServerEditorView(server: editingServer) { server in
                var servers = model.servers
                if let editingServer,
                   let index = servers.firstIndex(where: { $0.id == editingServer.id }) {
                    servers[index] = server
                } else {
                    servers.append(server)
                }
                if model.saveServers(servers) {
                    showingEditor = false
                }
            }
        }
        .confirmationDialog(
            "Delete \(serverToDelete?.displayName ?? "server")?",
            isPresented: $showingDeleteConfirmation,
            presenting: serverToDelete
        ) { server in
            Button("Delete", role: .destructive) {
                model.deleteServer(server)
                serverToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                serverToDelete = nil
            }
        } message: { server in
            Text("This removes the server from the shared sidecar configuration.")
        }
    }

    private func chooseConfigurationLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = model.configurationFileURL.deletingLastPathComponent()
        panel.prompt = "Select"
        panel.message = "Choose an existing servers.json file, or a folder to store the configuration in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.changeConfigurationLocation(to: url)
    }

    private func endpointSummary(for server: SMBServer) -> String {
        server.endpoints.map { "\($0.host):\($0.port)" }.joined(separator: " → ")
    }
}

private struct ServerEditorView: View {
    let server: SMBServer?
    let onSave: (SMBServer) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var endpointDrafts: [EndpointDraft]
    @State private var usesFallbackHosts: Bool
    @State private var errorMessage = ""

    init(server: SMBServer?, onSave: @escaping (SMBServer) -> Void) {
        self.server = server
        self.onSave = onSave
        _displayName = State(initialValue: server?.displayName ?? "")
        _endpointDrafts = State(initialValue: server?.endpoints.map(EndpointDraft.init) ?? [EndpointDraft()])
        _usesFallbackHosts = State(initialValue: (server?.endpoints.count ?? 1) > 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(server == nil ? "Add Server" : "Edit Server")
                .font(.title2.weight(.semibold))

            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)

            if usesFallbackHosts {
                Text("Hostnames are tried in the order shown.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List {
                    ForEach($endpointDrafts) { endpoint in
                        endpointRow(endpoint, removable: endpointDrafts.count > 1)
                    }
                    .onMove { endpointDrafts.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
                .frame(minHeight: 120)

                Button {
                    endpointDrafts.append(EndpointDraft())
                } label: {
                    Label("Add fallback hostname", systemImage: "plus")
                }
                .buttonStyle(.link)
            } else {
                endpointRow($endpointDrafts[0], removable: false)
            }

            Toggle("Multiple Hostnames", isOn: $usesFallbackHosts)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560, height: 440)
    }

    private func save() {
        do {
            let drafts = usesFallbackHosts ? endpointDrafts : Array(endpointDrafts.prefix(1))
            let endpoints = try drafts.map { try $0.endpoint() }
            let saved = try SMBServer(
                id: server?.id ?? UUID().uuidString,
                displayName: displayName,
                endpoints: endpoints
            )
            onSave(saved)
        } catch SMBModelError.noEndpoints {
            errorMessage = "Add at least one endpoint."
        } catch SMBModelError.invalidPort {
            errorMessage = "Enter a valid port between 1 and 65535."
        } catch {
            errorMessage = "Enter a valid display name and hostname."
        }
    }

    private func endpointRow(
        _ endpoint: Binding<EndpointDraft>,
        removable: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if usesFallbackHosts {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
            }
            TextField("Hostname or IP address", text: endpoint.host)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            TextField("Port", text: endpoint.port)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            if removable {
                Button {
                    endpointDrafts.removeAll { $0.id == endpoint.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Remove hostname")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct EndpointDraft: Identifiable {
    let id = UUID()
    var host: String
    var port: String

    init(host: String = "", port: String = "445") {
        self.host = host
        self.port = port
    }

    init(endpoint: SMBEndpoint) {
        self.init(host: endpoint.host, port: String(endpoint.port))
    }

    func endpoint() throws -> SMBEndpoint {
        guard let port = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SMBModelError.invalidPort
        }
        return try SMBEndpoint(host: host, port: port)
    }
}
