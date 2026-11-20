import KonserveCore
import SwiftUI

struct ConnectorView: View {
    @ObservedObject var model: ConnectorViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                serverField
                switch model.connectionState {
                case .shares, .noShares, .mounting, .mounted:
                    shareContent
                case .failed where !model.availableShares.isEmpty:
                    shareContent
                default:
                    credentialsForm
                }
                if model.isBusy {
                    ProgressView(model.statusMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if case .failed(let message) = model.connectionState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !model.statusMessage.isEmpty {
                    Text(model.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            Spacer(minLength: 0)
            serverAvailability
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.checkConfiguredServers()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await model.checkConfiguredServers()
            }
        }
        .sheet(isPresented: $showingSettings) {
            ServerSettingsView(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Konserve")
                    .font(.title2.weight(.semibold))
                Text("Connect to a server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var serverField: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.servers.isEmpty {
                Group {
                    if model.servers.count == 1 {
                        HStack {
                            Spacer()
                            configuredServerButton(model.servers[0])
                            Spacer()
                        }
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            alignment: .center,
                            spacing: 16
                        ) {
                            ForEach(model.servers) { server in
                                configuredServerButton(server)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
            TextField("Server address (hostname or IP)", text: $model.manualAddress)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .disabled(model.isBusy)
                .onChange(of: model.manualAddress) { _ in
                    model.manualAddressDidChange()
                }
        }
    }

    private func configuredServerButton(_ server: SMBServer) -> some View {
        Button {
            Task { await model.connectToConfiguredServer(server) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(color(for: model.availability[server.id] ?? .unchecked))
                    .frame(width: 9, height: 9)
                    .accessibilityLabel(label(for: model.availability[server.id] ?? .unchecked))
                Text(server.displayName)
                    .lineLimit(1)
            }
            .frame(minWidth: 150)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal, 4)
        .disabled(model.isBusy)
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Username", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .autocorrectionDisabled()
                .disabled(model.isBusy)
                .onChange(of: model.username) { _ in
                    model.usernameDidChange()
                }
                .onSubmit {
                    model.loadRememberedCredentials()
                }
            SecureField("Password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .disabled(model.isBusy)
            Toggle("Remember credentials", isOn: $model.rememberCredentials)
                .font(.callout)
                .disabled(model.isBusy)
            Toggle("Remember Server", isOn: $model.addToConfiguration)
                .font(.callout)
                .disabled(model.isBusy || !model.canAddCurrentServer)
            Button {
                Task { await model.connect() }
            } label: {
                Label("Connect", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var shareContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Available shares")
                    .font(.headline)
                Spacer()
                Button {
                    model.returnToConnectionForm()
                } label: {
                    Label("Back", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Back to server connection")
                .disabled(model.isBusy)
            }
            if case .noShares = model.connectionState {
                Text("No shares are available for this account on this server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List(model.shares.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }) { share in
                    Toggle(share.name, isOn: Binding(
                        get: { model.selectedShareNames.contains(share.name) },
                        set: { selected in
                            if selected {
                                model.selectedShareNames.insert(share.name)
                            } else {
                                model.selectedShareNames.remove(share.name)
                            }
                        }
                    ))
                }
                .listStyle(.inset)
                .frame(minHeight: 140, maxHeight: 210)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    Task { await model.mountSelectedShares() }
                } label: {
                    Label("Mount selected", systemImage: "externaldrive.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedShareNames.isEmpty || model.isBusy)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var serverAvailability: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Text("AVAILABLE SERVERS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("Configure servers")
                }
                .buttonStyle(.borderless)
            }
            if model.servers.isEmpty {
                Text("Add a server in the sidecar configuration to monitor availability.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.servers) { server in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: model.availability[server.id] ?? .unchecked))
                            .frame(width: 8, height: 8)
                            .accessibilityLabel(label(for: model.availability[server.id] ?? .unchecked))
                        Text(server.displayName)
                            .font(.caption)
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.35))
    }

    private func color(for availability: ServerAvailability) -> Color {
        switch availability {
        case .unchecked, .unavailable: .gray
        case .checking: .yellow
        case .reachable: .green
        case .error: .red
        }
    }

    private func label(for availability: ServerAvailability) -> String {
        switch availability {
        case .unchecked: "Not checked"
        case .checking: "Checking"
        case .reachable: "Reachable"
        case .unavailable: "Unavailable"
        case .error: "Connection error"
        }
    }
}
