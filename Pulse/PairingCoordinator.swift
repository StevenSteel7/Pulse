import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class PairingCoordinator: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var invitation: PairingInvitation?
    @Published private(set) var identity: PairingIdentity?
    @Published private(set) var message: String?
    @Published private(set) var isApproving = false
    @Published private(set) var completedName: String?
    @Published private(set) var recovery: PulseSettings?
    var onPaired: ((String) -> Void)?
    private var task: Task<Void, Never>?
    private var clipboardChange: Int?
    private var generation = UUID()

    init() {
        if let data = try? Data(contentsOf: SettingsStore.pendingApprovalFile) {
            recovery = try? JSONDecoder().decode(PulseSettings.self, from: data)
        }
    }

    func begin(host: String, port: Int, platform: PairingPlatform) throws {
        guard recovery == nil else { throw PairingFailure.rejected }
        cancel()
        completedName = nil
        let invitation = try PairingInvitation(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port, platform: platform)
        self.invitation = invitation
        message = "Run the copied command on your \(platform.rawValue) device. Pulse is waiting for its HTTPS endpoint."
        copyCommand()
        let generation = self.generation
        task = Task { [weak self] in
            while let self, !Task.isCancelled, self.generation == generation {
                if Date().timeIntervalSince1970 >= Double(invitation.expires) {
                    self.message = PairingFailure.expired.localizedDescription
                    self.identity = nil
                    self.clearClipboard()
                    return
                }
                do {
                    let identity = try await PairingProtocol.probe(invitation)
                    guard !Task.isCancelled, self.generation == generation else { return }
                    if self.identity == nil {
                        self.identity = identity
                        self.message = "Device ready to pair. Compare the verification code with the installer before approving."
                        self.notifyReady(identity)
                    } else if self.identity?.fingerprint != identity.fingerprint || self.identity?.deviceID != identity.deviceID {
                        self.identity = nil
                        self.message = PairingFailure.identityMismatch.localizedDescription
                        return
                    }
                } catch {
                    guard !Task.isCancelled, self.generation == generation else { return }
                    // An earlier ready result must not leave approval enabled
                    // after identity verification starts failing.
                    self.identity = nil
                    self.message = (error as? PairingFailure)?.localizedDescription ?? "Waiting for the device. Check installation, public IP, and inbound TCP \(invitation.port)."
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func copyCommand() {
        guard let invitation, Date().timeIntervalSince1970 < Double(invitation.expires) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(invitation.command, forType: .string)
        clipboardChange = NSPasteboard.general.changeCount
    }

    private func clearClipboard() {
        if clipboardChange == NSPasteboard.general.changeCount { NSPasteboard.general.clearContents() }
        clipboardChange = nil
    }

    func cancel() {
        completedName = nil
        generation = UUID()
        task?.cancel()
        task = nil
        invitation = nil
        identity = nil
        message = nil
        clearClipboard()
    }

    func approve(name: String) async {
        guard !isApproving, let invitation, let identity else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isApproving = true
        task?.cancel()
        defer { isApproving = false }
        let id = "device-\(identity.deviceID)"
        let profile = PulseSettings(id: id, name: name, host: invitation.host, port: invitation.port,
                                    apiKey: PairingProtocol.randomSecret(), useTLS: true, certificateFingerprint: identity.fingerprint)
        do {
            // Save a durable recovery record BEFORE consuming the remote token.
            // A lost response or app exit must not strand the device's credential.
            try CredentialStore.save(profile.apiKey, id: id)
            try JSONEncoder().encode(profile).write(to: SettingsStore.pendingApprovalFile, options: .atomic)
            recovery = profile
            do { try await PairingProtocol.approve(invitation, profile: profile) }
            catch {
                // A committed approval may have lost its response. Authentication
                // with the new credential proves whether it actually succeeded.
                _ = try await StatsClient.fetch(settings: profile, timeout: 5)
            }
            try finish(profile)
        } catch {
            message = "Approval couldn't be completed: \(error.localizedDescription). Use Retry confirmation; the new credential is safely retained."
        }
    }

    func recover() async {
        guard let recovery, !isApproving else { return }
        isApproving = true
        defer { isApproving = false }
        do {
            if let invitation { try? await PairingProtocol.approve(invitation, profile: recovery) }
            _ = try await StatsClient.fetch(settings: recovery, timeout: 5)
            try finish(recovery)
        } catch { message = "Couldn't confirm the device yet. Check its connection and retry. If it never accepted approval, discard this attempt and install a new pairing command." }
    }

    func discardRecovery() {
        // If approval already succeeded remotely, the old credential remains
        // only until a new enrollment is installed on that same device.
        guard let recovery, !isApproving else { return }
        do {
            try FileManager.default.removeItem(at: SettingsStore.pendingApprovalFile)
            if !SettingsStore.profiles().contains(where: { $0.id == recovery.id }) { try CredentialStore.delete(recovery.id) }
            self.recovery = nil
            cancel()
        } catch { message = error.localizedDescription }
    }

    private func finish(_ profile: PulseSettings) throws {
        var profiles = SettingsStore.profiles()
        profiles.removeAll { $0.id == profile.id }
        // Empty legacy placeholders don't need to occupy new device slots.
        profiles.removeAll { !$0.isConfigured && ($0.id == "pc" || $0.id == "vps") }
        profiles.append(profile)
        try SettingsStore.saveProfiles(profiles)
        try SettingsStore.select(profile.id)
        try FileManager.default.removeItem(at: SettingsStore.pendingApprovalFile)
        recovery = nil
        cancel()
        completedName = profile.name
        onPaired?(profile.id)
    }

    private func notifyReady(_ identity: PairingIdentity) {
        // In-app notices work regardless of system notification authorization.
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Device ready to pair"
            content.body = "\(identity.hostname) is waiting. Open Pulse → Advanced to verify and name it."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "pulse-pairing", content: content, trigger: nil))
        }
    }
}
