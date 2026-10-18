import AppKit

enum ProfileSupport {
    case chatGPT
    case claude
    case unavailable(String)

    var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    var explanation: String {
        switch self {
        case .chatGPT:
            return "Opens the installed ChatGPT app with a fresh app profile and separate local account storage. Sign in with your second account."
        case .claude:
            return "Uses a fresh Claude profile with its own Code configuration and work folder. Complete first sign-in while all other Claude copies are closed."
        case .unavailable(let message): return message
        }
    }

    var integrationNote: String {
        switch self {
        case .claude:
            return "Experimental: Cowork is disabled in the second profile. Code’s global storage is redirected, but selected project folders and some services can still be shared."
        default:
            return "Sign-in and desktop integrations need testing. Support is limited to the checked app version."
        }
    }
}

extension AppRecord {
    var profileSupport: ProfileSupport {
        switch bundleID {
        case "com.openai.codex" where version == "26.1013.31256": return .chatGPT
        case "com.anthropic.claudefordesktop" where version == "2.42304.0": return .claude
        case "com.openai.codex", "com.openai.chat", "com.anthropic.claudefordesktop":
            return .unavailable("Separate-account support hasn’t been checked for this installed version. You can still open the main account.")
        default:
            return .unavailable("This app has no checked adapter for separate accounts. Opening a second process alone would not separate its login.")
        }
    }
}

struct AccountProfilePlan {
    let root: URL
    let arguments: [String]
    let environment: [String: String]
    let directories: [URL]
    private let coworkFiles: URL?

    init(app: AppRecord, profilesRoot: URL) throws {
        let base = profilesRoot.appendingPathComponent(app.id.uuidString, isDirectory: true)
        if case .claude = app.profileSupport {
            root = base.appendingPathComponent("claude-v2", isDirectory: true)
        } else {
            root = base
        }
        let data = root.appendingPathComponent("app-data", isDirectory: true)
        switch app.profileSupport {
        case .chatGPT:
            let account = root.appendingPathComponent("account-data", isDirectory: true)
            arguments = ["--user-data-dir=\(data.path)"]
            // These overrides apply only to the newly launched child, never to the current account.
            environment = ["CODEX_ELECTRON_USER_DATA_PATH": data.path, "CODEX_HOME": account.path]
            directories = [data, account]
            coworkFiles = nil
        case .claude:
            let code = root.appendingPathComponent("code-config", isDirectory: true)
            let files = root.appendingPathComponent("work-files", isDirectory: true)
            arguments = ["--user-data-dir=\(data.path)"]
            environment = ["CLAUDE_CONFIG_DIR": code.path]
            directories = [data, code, files]
            coworkFiles = files
        case .unavailable(let message): throw ProfileError.unavailable(message)
        }
    }

    func prepare() throws {
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if let files = coworkFiles {
            let configURL = directories[0].appendingPathComponent("claude_desktop_config.json")
            if FileManager.default.fileExists(atPath: configURL.path) {
                try validateExistingConfiguration()
            } else {
                let object: [String: Any] = ["coworkUserFilesPath": files.path, "preferences": ["secureVmFeaturesEnabled": false]]
                let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: configURL, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            }
        }
    }

    func validateExistingConfiguration() throws {
        guard let files = coworkFiles else { return }
        let configURL = directories[0].appendingPathComponent("claude_desktop_config.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        let preferences = object?["preferences"] as? [String: Any]
        guard object?["coworkUserFilesPath"] as? String == files.path,
              preferences?["secureVmFeaturesEnabled"] as? Bool == false else {
            throw ProfileError.unavailable("This second profile no longer has the expected separate work folder and disabled Cowork setting. Twin has left its configuration unchanged.")
        }
    }
}

enum ProfileError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

struct ProfileProcess: Codable {
    let pid: pid_t
    let launchDate: Date

    @MainActor func application(for record: AppRecord) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: record.path).standardizedFileURL.path,
              let actualDate = app.launchDate, abs(actualDate.timeIntervalSince(launchDate)) < 0.1 else { return nil }
        return app
    }
}
