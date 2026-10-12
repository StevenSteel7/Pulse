import SwiftUI

struct DevicePairingControls: View {
    @ObservedObject var coordinator: PairingCoordinator
    var body: some View {
        HStack {
            if coordinator.identity != nil {
                Label("Device ready to pair", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(PulseTheme.gpuColor)
            } else if coordinator.recovery != nil {
                Label("Finish pairing", systemImage: "arrow.clockwise")
            } else if coordinator.invitation != nil {
                Label("Waiting for device…", systemImage: "antenna.radiowaves.left.and.right")
            } else {
                Text("Your devices").foregroundStyle(.secondary)
            }
            Spacer()
            Button(coordinator.invitation != nil || coordinator.recovery != nil ? "Review" : "Add device") { if coordinator.completedName != nil { coordinator.cancel() }; coordinator.isPresented = true }
                .buttonStyle(.bordered)
        }
        .font(.caption)
        .sheet(isPresented: $coordinator.isPresented) { AddDeviceView(coordinator: coordinator) }
    }
}

struct AddDeviceView: View {
    @ObservedObject var coordinator: PairingCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var platform: PairingPlatform = .linux
    @State private var host = ""
    @State private var port = 8843
    @State private var name = ""
    @State private var verified = false
    @State private var error: String?
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "lock.shield").foregroundStyle(PulseTheme.cpuColor)
                Text("Add a device").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }.disabled(coordinator.isApproving)
            }
            if let completed = coordinator.completedName {
                Label("\(completed) is connected", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(PulseTheme.gpuColor)
                Text("Use the widget or menu bar to switch between your saved devices.")
                Button("Add another device") { coordinator.cancel(); coordinator.isPresented = false }
            } else if coordinator.recovery != nil {
                Text("Finish the pending approval").font(.headline)
                Text("Pulse retained this device's credential so a dropped connection cannot lose it.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Retry confirmation") { Task { await coordinator.recover() } }
                        .buttonStyle(.borderedProminent).disabled(coordinator.isApproving)
                    Button("Discard attempt") { confirmDiscard = true }.disabled(coordinator.isApproving)
                }
            } else if let invitation = coordinator.invitation {
                Label("\(invitation.platform.rawValue) · \(invitation.host):\(String(invitation.port))", systemImage: "lock.fill")
                    .font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, invitation.expires - Int(context.date.timeIntervalSince1970))
                    Text(seconds > 0 ? "Pairing command expires in \(seconds / 60)m \(seconds % 60)s" : "Pairing command expired")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    coordinator.copyCommand()
                } label: {
                    Label("Copy \(invitation.platform.rawValue) install command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                Text("Run it on that device. Allow inbound TCP \(String(invitation.port)) in its firewall and cloud rules; forward the port if it sits behind a router.")
                    .font(.callout).foregroundStyle(.secondary)
                if let identity = coordinator.identity {
                    Divider()
                    Text("\(identity.hostname) wants to connect").font(.headline)
                    Text(identity.verificationCode)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Toggle("This code matches the one shown by the installer", isOn: $verified)
                    TextField("Give this device a name", text: $name).textFieldStyle(.roundedBorder)
                    Button("Approve & add device") { Task { await coordinator.approve(name: name) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!verified || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinator.isApproving)
                }
                Button("Cancel pairing") { coordinator.cancel(); verified = false }.disabled(coordinator.isApproving)
            } else {
                Text("Connect directly to a Windows PC or Linux server using its public IPv4 address. No relay or account is needed.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Device", selection: $platform) { ForEach(PairingPlatform.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                TextField("Public IPv4 address", text: $host).textFieldStyle(.roundedBorder)
                TextField("HTTPS port", value: $port, format: .number.grouping(.never)).textFieldStyle(.roundedBorder)
                Text("Windows needs Python 3.10+. Linux needs systemd and sudo. Installation creates an encrypted agent on port 8843 by default.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Generate & copy install command") {
                    do { try coordinator.begin(host: host, port: port, platform: platform); verified = false; error = nil }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!PairingInvitation.isPublicIPv4(host.trimmingCharacters(in: .whitespacesAndNewlines)) || !(1024...65535).contains(port))
            }
            if let message = coordinator.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if coordinator.isApproving { ProgressView().controlSize(.small) }
        }
        .padding(24)
        .frame(width: 480)
        .onChange(of: coordinator.identity?.fingerprint) { _, _ in verified = false }
        .confirmationDialog("Discard this approval attempt? If the device already accepted it, install a new pairing command there to replace the old credential.", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { coordinator.discardRecovery() }
        }
    }
}
