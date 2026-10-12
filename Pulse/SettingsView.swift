import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [PulseSettings]
    @State private var selectedID: String
    @State private var showApiKey = false
    @State private var saveError: String?
    @State private var isRemoving = false
    @State private var confirmRemoval = false

    let onSave: ([PulseSettings], String) throws -> Void

    init(settings: PulseSettings, onSave: @escaping ([PulseSettings], String) throws -> Void) {
        _profiles = State(initialValue: SettingsStore.profiles())
        _selectedID = State(initialValue: settings.id)
        self.onSave = onSave
    }

    private var index: Int { profiles.firstIndex { $0.id == selectedID } ?? 0 }
    private var isValid: Bool {
        profiles.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.baseURL != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your systems").font(.title2.bold())
            Text("Choose a system to edit its connection. Switch systems directly on the widget.")
                .font(.callout).foregroundStyle(.secondary)

            Picker("System", selection: $selectedID) {
                ForEach(profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedID) { _, _ in showApiKey = false }

            Form {
                TextField("Name", text: $profiles[index].name)
                if profiles[index].certificateFingerprint != nil {
                    LabeledContent("Connection", value: "https://\(profiles[index].host):\(profiles[index].port)")
                    Label("Certificate verified · Keychain protected", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.green)
                } else {
                TextField("Host / IP", text: $profiles[index].host)
                TextField("Port", value: $profiles[index].port, format: .number.grouping(.never))
                Toggle("HTTPS", isOn: $profiles[index].useTLS)
                HStack {
                    if showApiKey {
                        TextField("API key", text: $profiles[index].apiKey)
                    } else {
                        SecureField("API key", text: $profiles[index].apiKey)
                    }
                    Button { showApiKey.toggle() } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showApiKey ? "Hide API key" : "Show API key")
                }
                }

            }
            .textFieldStyle(.roundedBorder)

            Text(profiles[index].certificateFingerprint != nil
                 ? "To change this device's address or certificate, add it again using a fresh pairing command."
                 : "This is a legacy manual connection. For a public IP, close Settings and use Add device to set up verified HTTPS.")
                .font(.caption).foregroundStyle(.secondary)
            Button(profiles[index].certificateFingerprint != nil ? "Revoke & remove device" : "Remove connection", role: .destructive) {
                confirmRemoval = true
            }
            .disabled(isRemoving)
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        let cleaned = profiles.map { profile -> PulseSettings in
                            var result = profile
                            result.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            result.host = result.host.trimmingCharacters(in: .whitespacesAndNewlines)
                            result.apiKey = result.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            return result
                        }
                        try onSave(cleaned, selectedID)
                        dismiss()
                    } catch { saveError = "Couldn't save: \(error.localizedDescription)" }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isRemoving)
            }
        }
        .padding(24)
        .frame(width: 440)
        .confirmationDialog("Remove this device? Paired devices must be online so Pulse can revoke their credential first.", isPresented: $confirmRemoval) {
            Button("Remove device", role: .destructive) {
                let profile = profiles[index]
                isRemoving = true
                Task {
                    defer { isRemoving = false }
                    do {
                        if profile.certificateFingerprint != nil { try await PairingProtocol.revoke(profile) }
                        try SettingsStore.remove(profile.id)
                        profiles = SettingsStore.profiles()
                        selectedID = profiles[0].id
                        try onSave(profiles, selectedID)
                    } catch { saveError = "Couldn't remove device: \(error.localizedDescription). Check its connection and retry." }
                }
            }
        }
    }
}
