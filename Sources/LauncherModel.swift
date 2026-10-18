import AppKit
import Combine
import UniformTypeIdentifiers

struct AppRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var path: String
    var name: String
    var bundleID: String

    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }
    var version: String { Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    init?(url: URL) {
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              bundle.executableURL != nil else { return nil }
        id = UUID()
        path = url.standardizedFileURL.path
        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        bundleID = identifier
    }
}

struct LaunchNotice {
    var title: String
    var message: String
    var isError: Bool
}

enum InstanceLaunchError: LocalizedError {
    case appMissing
    case noApplicationReturned
    var errorDescription: String? {
        switch self {
        case .appMissing: return "This application was moved or removed. Add it again from its current location."
        case .noApplicationReturned: return "macOS did not return a running application."
        }
    }
}

@MainActor
enum InstanceLauncher {
    static func open(url: URL, newInstance: Bool, activates: Bool = true, arguments: [String] = [], environment: [String: String] = [:]) async throws -> NSRunningApplication {
        guard FileManager.default.fileExists(atPath: url.path) else { throw InstanceLaunchError.appMissing }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = newInstance
        configuration.activates = activates
        configuration.addsToRecentItems = false
        configuration.arguments = arguments
        configuration.environment = environment
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: InstanceLaunchError.noApplicationReturned) }
            }
        }
    }

    static func running(_ record: AppRecord) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: record.path).standardizedFileURL.path
        }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var applications: [AppRecord] = []
    @Published var selectedID: UUID?
    @Published var runningCounts: [UUID: Int] = [:]
    @Published var busyID: UUID?
    @Published var notice: LaunchNotice?
    private var noticeAppID: UUID?
    private var observedExtraPID: pid_t?
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private let savedKey = "Twin.selectedApplications.v1"
    private var profileProcesses: [String: ProfileProcess] = [:]
    private let profileProcessesKey = "Twin.profileProcesses.v1"
    private var mainProcesses: [String: ProfileProcess] = [:]
    private let mainProcessesKey = "Twin.mainProcesses.v1"
    @Published private var verifiedClaudeProfiles: Set<String> = []
    private let verifiedClaudeKey = "Twin.verifiedClaudeProfiles.v2"

    var selectedApp: AppRecord? { applications.first { $0.id == selectedID } }

    init() {
        if let data = defaults.data(forKey: savedKey), let saved = try? JSONDecoder().decode([AppRecord].self, from: data) {
            applications = saved
        } else {
            for name in ["ChatGPT", "Claude"] {
                let paths = ["/Applications/\(name).app", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(name).app").path]
                if let app = paths.compactMap({ AppRecord(url: URL(fileURLWithPath: $0)) }).first { applications.append(app) }
            }
        }
        if let data = defaults.data(forKey: profileProcessesKey), let saved = try? JSONDecoder().decode([String: ProfileProcess].self, from: data) {
            profileProcesses = saved
        }
        if let data = defaults.data(forKey: mainProcessesKey), let saved = try? JSONDecoder().decode([String: ProfileProcess].self, from: data) {
            mainProcesses = saved
        }
        verifiedClaudeProfiles = Set(defaults.stringArray(forKey: verifiedClaudeKey) ?? [])
        save()
        selectedID = applications.first?.id
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func select(_ app: AppRecord) {
        selectedID = app.id
        clearNotice()
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an installed application"
        panel.prompt = "Add application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let record = AppRecord(url: url), record.bundleID != Bundle.main.bundleIdentifier else {
            notice = LaunchNotice(title: "Choose another application", message: "Select a Mac application other than Twin.", isError: true)
            return
        }
        if let existing = applications.first(where: { $0.path == record.path }) { select(existing); return }
        applications.append(record)
        select(record)
        save()
        refresh()
    }

    func remove(_ app: AppRecord) {
        applications.removeAll { $0.id == app.id }
        if selectedID == app.id { selectedID = applications.first?.id }
        clearNotice()
        save()
    }

    func refresh() {
        runningCounts = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, InstanceLauncher.running($0).count) })
        if let pid = observedExtraPID, let app = applications.first(where: { $0.id == noticeAppID }),
           !InstanceLauncher.running(app).contains(where: { $0.processIdentifier == pid }) {
            if selectedID == app.id {
                notice = LaunchNotice(title: "The additional instance closed", message: "\(app.name) no longer has that extra copy running. Check the current count above.", isError: true)
            }
            observedExtraPID = nil
        }
    }

    func launch(_ app: AppRecord, newInstance: Bool) {
        guard busyID == nil else { return }
        let key = processKey(app)
        if needsFirstSignIn(app), !InstanceLauncher.running(app).isEmpty {
            present(LaunchNotice(title: "Finish second-account sign-in first", message: "Keep only the second Claude copy open until you have checked its account and selected “I verified my second account” in Twin.", isError: true), for: app)
            return
        }
        if !newInstance {
            if let existing = mainProcesses[key]?.application(for: app) {
                existing.activate(options: [])
                present(LaunchNotice(title: "Main account opened", message: "Switched to your existing \(app.name) window.", isError: false), for: app)
                return
            }
        }
        busyID = app.id
        clearNotice()
        let previousPIDs = Set(InstanceLauncher.running(app).map(\.processIdentifier))
        Task {
            defer { busyID = nil; refresh() }
            do {
                // Always launch a new process here; a plain open could select the second account.
                let launched = try await InstanceLauncher.open(url: URL(fileURLWithPath: app.path), newInstance: true)
                if newInstance {
                    // A successful launch callback can precede the app's own singleton check.
                    try await Task.sleep(for: .seconds(4))
                    let running = InstanceLauncher.running(app)
                    let freshProcess = !previousPIDs.contains(launched.processIdentifier)
                    let stayedOpen = running.contains { $0.processIdentifier == launched.processIdentifier }
                    if freshProcess && stayedOpen {
                        let twoRunning = running.count >= 2
                        present(LaunchNotice(
                            title: twoRunning ? "A second instance is running" : "A new instance is running",
                            message: twoRunning ? "\(app.name) now has \(running.count) running copies. They may share the same account and settings." : "There was no other copy open. Open another instance again to run two copies.",
                            isError: false), for: app, extraPID: launched.processIdentifier)
                    } else {
                        present(LaunchNotice(title: "An extra instance did not stay open", message: "\(app.name) may allow only one running copy. macOS cannot override the app’s own restriction.", isError: true), for: app)
                    }
                } else {
                    try await Task.sleep(for: .seconds(4))
                    if !launched.isTerminated, let date = launched.launchDate {
                        mainProcesses[key] = ProfileProcess(pid: launched.processIdentifier, launchDate: date)
                        if let data = try? JSONEncoder().encode(mainProcesses) { defaults.set(data, forKey: mainProcessesKey) }
                    }
                    present(LaunchNotice(title: "Main profile requested", message: "Opened \(app.name) with its usual startup settings. Check the account shown in its window.", isError: false), for: app)
                }
            } catch {
                present(LaunchNotice(title: "Couldn’t open \(app.name)", message: error.localizedDescription, isError: true), for: app)
            }
        }
    }

    func launchSecondAccount(_ app: AppRecord) {
        guard busyID == nil else { return }
        guard app.profileSupport.isAvailable else {
            present(LaunchNotice(title: "This version needs a compatibility check", message: app.profileSupport.explanation, isError: true), for: app)
            return
        }
        clearNotice()
        let key = processKey(app)
        let existing = profileProcesses[key]?.application(for: app)
        if app.bundleID == "com.anthropic.claudefordesktop" {
            let running = InstanceLauncher.running(app)
            let mainPID = mainProcesses[key]?.application(for: app)?.processIdentifier
            let extraPID = existing?.processIdentifier
            let otherCopies = running.filter { $0.processIdentifier != extraPID }
            let unrecognized = running.filter { $0.processIdentifier != extraPID && $0.processIdentifier != mainPID }
            if needsFirstSignIn(app) && !otherCopies.isEmpty {
                present(LaunchNotice(title: "Quit other Claude copies before first sign-in", message: "Finish any work, then quit all other Claude copies without signing out. Open the second account here while it is the only Claude running. In the browser, explicitly choose your other account.", isError: true), for: app)
                return
            }
            if !needsFirstSignIn(app) && existing == nil && !unrecognized.isEmpty {
                present(LaunchNotice(title: "A Claude copy could not be identified", message: "To avoid reusing the wrong profile, finish your work and quit all Claude copies, then reopen them from Twin.", isError: true), for: app)
                return
            }
        }
        if let existing {
            do {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let plan = try AccountProfilePlan(app: app, profilesRoot: support.appendingPathComponent("Twin/Profiles", isDirectory: true))
                try plan.validateExistingConfiguration()
            } catch {
                present(LaunchNotice(title: "Profile settings need checking", message: error.localizedDescription, isError: true), for: app)
                return
            }
            existing.activate(options: [])
            present(LaunchNotice(title: "The saved profile process is running", message: "Brought it forward. Check the account shown in its window.", isError: false), for: app, extraPID: existing.processIdentifier)
            return
        }
        busyID = app.id
        let previousPIDs = Set(InstanceLauncher.running(app).map(\.processIdentifier))
        Task {
            defer { busyID = nil; refresh() }
            do {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let plan = try AccountProfilePlan(app: app, profilesRoot: support.appendingPathComponent("Twin/Profiles", isDirectory: true))
                try plan.prepare()
                let launched = try await InstanceLauncher.open(url: URL(fileURLWithPath: app.path), newInstance: true, arguments: plan.arguments, environment: plan.environment)
                try await Task.sleep(for: .seconds(5))
                guard !previousPIDs.contains(launched.processIdentifier),
                      InstanceLauncher.running(app).contains(where: { $0.processIdentifier == launched.processIdentifier }) else {
                    present(LaunchNotice(title: "The separate profile didn’t stay open", message: "The app did not keep the requested process running. Check its window for a launch error.", isError: true), for: app)
                    return
                }
                if let date = launched.launchDate {
                    profileProcesses[key] = ProfileProcess(pid: launched.processIdentifier, launchDate: date)
                    if let data = try? JSONEncoder().encode(profileProcesses) { defaults.set(data, forKey: profileProcessesKey) }
                }
                let message = needsFirstSignIn(app)
                    ? "Keep this as the only Claude running. Choose your other account during browser sign-in, check the account shown in Claude, then confirm it in Twin. Cowork is disabled in this profile."
                    : "A process was started for the second profile. Check the account shown in its window; Twin does not automatically verify sign-in."
                present(LaunchNotice(title: "Profile process started — check its account", message: message, isError: false), for: app, extraPID: launched.processIdentifier)
            } catch {
                present(LaunchNotice(title: "Couldn’t open a second account", message: error.localizedDescription, isError: true), for: app)
            }
        }
    }

    func needsFirstSignIn(_ app: AppRecord) -> Bool {
        app.bundleID == "com.anthropic.claudefordesktop" && !verifiedClaudeProfiles.contains(app.id.uuidString)
    }

    func canConfirmSecondAccount(_ app: AppRecord) -> Bool {
        needsFirstSignIn(app) && profileProcesses[processKey(app)]?.application(for: app) != nil && InstanceLauncher.running(app).count == 1
    }

    func confirmSecondAccount(_ app: AppRecord) {
        guard canConfirmSecondAccount(app) else { return }
        verifiedClaudeProfiles.insert(app.id.uuidString)
        defaults.set(Array(verifiedClaudeProfiles), forKey: verifiedClaudeKey)
        present(LaunchNotice(title: "Second account marked as checked by you", message: "You can now open the main account too. Code runtime remains unverified and Cowork stays disabled in the second profile.", isError: false), for: app)
    }

    func resetClaudeSignIn(_ app: AppRecord) {
        guard app.bundleID == "com.anthropic.claudefordesktop", busyID == nil else { return }
        verifiedClaudeProfiles.remove(app.id.uuidString)
        defaults.set(Array(verifiedClaudeProfiles), forKey: verifiedClaudeKey)
        present(LaunchNotice(title: "Claude sign-in setup reopened", message: "Finish your work and quit other Claude copies before signing in again. No profile data or credentials were deleted.", isError: false), for: app)
    }

    private func processKey(_ app: AppRecord) -> String {
        app.bundleID == "com.anthropic.claudefordesktop" ? app.id.uuidString + ".claude-v2" : app.id.uuidString
    }

    private func clearNotice() {
        notice = nil
        noticeAppID = nil
        observedExtraPID = nil
    }

    private func present(_ value: LaunchNotice, for app: AppRecord, extraPID: pid_t? = nil) {
        guard selectedID == app.id, applications.contains(where: { $0.id == app.id }) else { return }
        noticeAppID = app.id
        observedExtraPID = extraPID
        notice = value
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(applications) else { return }
        defaults.set(data, forKey: savedKey)
    }
}
