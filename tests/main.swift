import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

try FileManager.default.createDirectory(at: SharedContainer.directory!, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: SharedContainer.legacyDirectory) }
let old = Data(#"{"host":"192.168.1.54","port":8801,"apiKey":"old-secret"}"#.utf8)
try old.write(to: SharedContainer.legacySettingsFile)
let migrated = SettingsStore.profiles()
check(migrated.count == 2, "Two system profiles")
check(migrated[0].apiKey == "old-secret", "Preserve old API key")
check(migrated[0].id == "pc", "Old settings migrate to PC")
try SettingsStore.saveProfiles(migrated)
try SettingsStore.select("vps")
check(SettingsStore.load().id == "vps", "Selection is visible across store reads")
var vps = SettingsStore.load()
vps.apiKey = "vps-secret"
try SettingsStore.save(vps)
check(SettingsStore.profiles()[0].apiKey == "old-secret", "Editing VPS preserves PC credentials")
check(SettingsStore.load().apiKey == "vps-secret", "VPS key saved")
try SettingsStore.select("invalid")
check(SettingsStore.load().id == "vps", "Unknown selection doesn't replace valid system")

let stats = try JSONDecoder().decode(StatsResponse.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
check(stats.cpu.logicalCores == 4 && stats.memory.totalGB == 24, "Decode real Linux agent contract")
check(!stats.gpu.available && stats.gpu.utilizationPercent == nil, "Missing GPU decodes cleanly")
let pc = migrated[0]
SharedStore.save(.placeholder, settings: pc, fetchedAt: Date(timeIntervalSince1970: 100))
check(SharedStore.load(settings: vps) == nil, "VPS never reads PC snapshot")
SharedStore.save(stats, settings: vps, fetchedAt: Date(timeIntervalSince1970: 200))
check(SharedStore.load(settings: pc)?.stats.hostname == "SIXDX", "PC cache remains intact")
check(SharedStore.load(settings: vps)?.stats == stats, "VPS cache holds Linux stats")
SharedStore.save(.placeholder, settings: vps, fetchedAt: Date(timeIntervalSince1970: 150))
check(SharedStore.load(settings: vps)?.stats == stats, "Late stale response cannot overwrite newer cache")
vps.host = "another-host"
check(SharedStore.load(settings: vps) == nil, "Changed endpoint starts with empty cache")
for i in 0..<50 { SharedStore.save(stats, settings: vps, fetchedAt: Date(timeIntervalSince1970: Double(i))) }
check(SharedStore.load(settings: vps)?.history.count == 40, "History stays bounded")
check(SharedStore.load(settings: pc)?.history.count == 1, "Histories remain separate")
var invalid = vps
invalid.host = "https://example.com"
check(invalid.baseURL == nil, "Reject scheme in host")
invalid.host = "host/path"
check(invalid.baseURL == nil, "Reject path in host")
invalid.host = "host"
invalid.port = 0
check(invalid.baseURL == nil, "Reject invalid port")
vps.useTLS = true
check(vps.baseURL?.scheme == "https", "HTTPS reverse proxy support")
SharedStore.resetSnapshotCache()
check(SharedStore.load(settings: pc) == nil && SharedStore.load(settings: vps) == nil, "Reset removes both caches")
check(SettingsStore.profiles()[0].apiKey == "old-secret", "Reset never removes settings")
print("PASS: migration, selection, Linux decoding, isolated caches, stale responses, history limits, URL validation")

let profileJSON = try String(contentsOf: SharedContainer.directory!.appendingPathComponent("systems.json"), encoding: .utf8)
check(!profileJSON.contains("old-secret") && !profileJSON.contains("vps-secret"), "Profile JSON never stores secrets")
var third = PulseSettings(id: "device-third", name: "Second server", host: "8.8.8.8", port: 8843, apiKey: "third-secret", useTLS: true, certificateFingerprint: String(repeating: "a", count: 64))
try SettingsStore.save(third)
check(SettingsStore.profiles().count == 3, "Dynamic device list")
check(SettingsStore.profiles().last?.certificateFingerprint == third.certificateFingerprint, "Certificate pin persisted")
try SettingsStore.select(third.id)
check(SettingsStore.load().id == third.id, "Select arbitrary paired device")
try SettingsStore.remove(third.id)
check(SettingsStore.profiles().count == 2 && CredentialStore.values[third.id] == nil, "Remove profile and credential")
print("PASS: Keychain-only profile serialization and dynamic device selection")

SharedStore.save(stats, settings: pc)
SharedStore.markUnreachable(settings: pc)
check(SharedStore.load(settings: pc)?.isReachable == false, "Offline status reaches widgets without exposing credentials")
var redacted = pc
redacted.apiKey = ""
check(redacted.cacheKey == pc.cacheKey, "Widget cache identity doesn't require an API key")
