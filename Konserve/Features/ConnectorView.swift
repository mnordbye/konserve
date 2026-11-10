import KonserveCore
import SwiftUI

struct ConnectorView: View {
    @ObservedObject var model: ConnectorViewModel

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
        .task {
            await model.checkConfiguredServers()
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
        if model.servers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Server address (hostname or IP)", text: $model.manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .disabled(model.isBusy)
                    .onChange(of: model.manualAddress) { _ in
                        model.serverSelectionDidChange()
                    }
                if !model.recentServerAddresses.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent servers")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(model.recentServerAddresses, id: \.self) { address in
                            Button(address) {
                                model.useRecentServerAddress(address)
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                            .disabled(model.isBusy)
                        }
                    }
                }
            }
        } else {
            Picker("Server", selection: $model.selectedServerID) {
                ForEach(model.servers) { server in
                    Text(server.displayName).tag(server.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isBusy)
            .onChange(of: model.selectedServerID) { _ in
                model.serverSelectionDidChange()
            }
        }
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
            if case .noShares = model.connectionState {
                Text("No shares are available for this account on this server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Available shares")
                    .font(.headline)
                List(model.shares) { share in
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
                Button {
                    Task { await model.mountSelectedShares() }
                } label: {
                    Label("Mount selected", systemImage: "externaldrive.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedShareNames.isEmpty || model.isBusy)
            }
            Button("Use different credentials") {
                model.useDifferentCredentials()
            }
            .buttonStyle(.link)
            .font(.callout)
            .disabled(model.isBusy)
        }
    }

    private var serverAvailability: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Text("SERVER AVAILABILITY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
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
                        Text(label(for: model.availability[server.id] ?? .unchecked))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
