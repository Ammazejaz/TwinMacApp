import AppKit

@main
struct ProfilePreparationCheck {
    @MainActor static func main() throws {
        let scratch = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/profile-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        // Test metadata only. No vendor app is read or launched by this check.
        let fixture = scratch.appendingPathComponent("Claude.app", isDirectory: true)
        let contents = fixture.appendingPathComponent("Contents", isDirectory: true)
        let executable = contents.appendingPathComponent("MacOS/Claude")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.anthropic.claudefordesktop",
            "CFBundleName": "Claude",
            "CFBundleExecutable": "Claude",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "2.42304.0"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data().write(to: executable)
        guard let claude = AppRecord(url: fixture) else {
            fatalError("The synthetic app metadata could not be loaded")
        }
        let plan = try AccountProfilePlan(app: claude, profilesRoot: scratch)
        guard let codePath = plan.environment["CLAUDE_CONFIG_DIR"] else {
            fatalError("Regression: Claude Code still falls back to shared global storage")
        }
        precondition(codePath.hasPrefix(plan.root.path + "/"))
        precondition(plan.root.lastPathComponent == "claude-v2")
        try plan.prepare()
        let config = plan.root.appendingPathComponent("app-data/claude_desktop_config.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        precondition(object["coworkUserFilesPath"] as? String == plan.root.appendingPathComponent("work-files").path)
        precondition((object["preferences"] as? [String: Any])?["secureVmFeaturesEnabled"] as? Bool == false)
        precondition(FileManager.default.fileExists(atPath: codePath))

        object["preserveThisSetting"] = "regression-check"
        try JSONSerialization.data(withJSONObject: object).write(to: config)
        try plan.prepare()
        let unchanged = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        precondition(unchanged["preserveThisSetting"] as? String == "regression-check")

        object["coworkUserFilesPath"] = scratch.appendingPathComponent("different-shared-folder").path
        let changed = try JSONSerialization.data(withJSONObject: object)
        try changed.write(to: config)
        do {
            try plan.prepare()
            fatalError("Regression: an unexpected Cowork location was accepted")
        } catch ProfileError.unavailable { }
        let afterRejection = try Data(contentsOf: config)
        precondition(afterRejection == changed)
        print("PASS: separate Code root; profile-owned Cowork path; Cowork disabled; existing configuration preserved; changed paths rejected")
    }
}
