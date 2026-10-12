import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [PulseSettings]
    @State private var selectedID: String
    @State private var showApiKey = false
    @State private var saveError: String?

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
            .pickerStyle(.segmented)
            .onChange(of: selectedID) { _, _ in showApiKey = false }

            Form {
                TextField("Name", text: $profiles[index].name)
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
            .textFieldStyle(.roundedBorder)

            Text(selectedID == "vps"
                 ? "For the default SSH tunnel, use 127.0.0.1, port 8802, and the key printed by the Linux installer. A direct VPN connection uses the VPS VPN address and port 8801."
                 : "Use your Windows agent's address, port, and API key. Your existing connection is preserved.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Leave the API key empty for a system you haven't set up yet.")
                .font(.caption2).foregroundStyle(.secondary)
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
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
