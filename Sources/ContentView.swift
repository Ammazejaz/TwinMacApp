import SwiftUI
import AppKit

private enum TwinStyle {
    static let accent = Color(red: 0.43, green: 0.36, blue: 0.91)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let line = Color.primary.opacity(0.08)
}

struct ContentView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 252)
            Rectangle()
                .fill(TwinStyle.line)
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(TwinStyle.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(TwinStyle.accent.gradient)
                    Image(systemName: "square.on.square")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Twin")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Two accounts. One Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 31)

            HStack {
                Text("YOUR APPS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                Spacer()
                Text("\(model.applications.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.applications) { app in
                        appRow(app)
                    }
                    if model.applications.isEmpty {
                        Text("Add an installed app\nto get started.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 13)
                    }
                }
                .padding(.horizontal, 12)
            }

            Button(action: model.addApplication) {
                Label("Add an app", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .help("Choose an installed application")
            .padding(.horizontal, 16)
            .padding(.bottom, 18)

            Rectangle().fill(TwinStyle.line).frame(height: 1)
            HStack(spacing: 7) {
                Image(systemName: "macwindow")
                    .font(.system(size: 11))
                Text("Made for your Mac")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func appRow(_ app: AppRecord) -> some View {
        let selected = model.selectedID == app.id
        return Button {
            model.select(app)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 31, height: 31)
                    .accessibilityHidden(true)
                Text(app.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if model.runningCounts[app.id, default: 0] > 0 {
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 5, height: 5)
                        .help("Running")
                }
                if selected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TwinStyle.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(selected ? TwinStyle.accent.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Open second account") { model.launchSecondAccount(app) }
                .disabled(!app.profileSupport.isAvailable || model.busyID != nil)
            Button("Open main account") { model.launch(app, newInstance: false) }
                .disabled(model.busyID != nil || needsClaudeFirstSignIn(app))
            Divider()
            Button("Remove from Twin", role: .destructive) { model.remove(app) }
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACCOUNT LAUNCHER")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: model.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh running apps")
                .accessibilityLabel("Refresh running apps")
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            if let app = model.selectedApp {
                ScrollView {
                    selectedApp(app)
                        .frame(maxWidth: 480)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 36)
                        .padding(.top, 22)
                        .padding(.bottom, 28)
                }
            } else {
                emptyDetail
            }
        }
    }

    private func selectedApp(_ app: AppRecord) -> some View {
        let runningCount = model.runningCounts[app.id, default: 0]
        let isBusy = model.busyID == app.id
        let canOpenSecondAccount = app.profileSupport.isAvailable && model.busyID == nil
        let isClaude = app.bundleID == "com.anthropic.claudefordesktop"
        let needsFirstSignIn = needsClaudeFirstSignIn(app)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 82, height: 82)
                    .accessibilityHidden(true)
                Spacer()
                Menu {
                    if app.bundleID == "com.anthropic.claudefordesktop" {
                        Button("Redo Claude sign-in setup") { model.resetClaudeSignIn(app) }
                            .disabled(model.busyID != nil)
                        Divider()
                    }
                    Button("Remove from Twin", role: .destructive) { model.remove(app) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 30, height: 26)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("App options")
            }
            .padding(.bottom, 16)

            Text(app.name)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 9) {
                if !app.version.isEmpty {
                    Text("Version \(app.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Circle().fill(.tertiary).frame(width: 3, height: 3)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(runningCount > 0 ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text(runningCount == 0 ? "Not running" : "\(runningCount) \(runningCount == 1 ? "instance" : "instances") running")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 27)

            Text(needsFirstSignIn ? "First sign-in" : "Use a second account.")
                .font(.system(size: 17, weight: .medium))
                .padding(.bottom, 7)
            Text(app.profileSupport.isAvailable
                 ? (needsFirstSignIn
                    ? "For the first sign-in, quit every Claude copy so the browser’s login link reaches this new profile."
                    : "Open \(app.name) with its own profile, then sign in to your other account.")
                 : "Twin cannot open a separate account for this app yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 23)

            Button {
                model.launchSecondAccount(app)
            } label: {
                HStack(spacing: 9) {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "plus.square.on.square")
                            .font(.system(size: 15, weight: .medium))
                    }
                    Text(isBusy ? "Opening…" : "Open second account")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(.white)
                .background(TwinStyle.accent.gradient, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canOpenSecondAccount)
            .opacity(canOpenSecondAccount ? 1 : 0.5)

            Button {
                model.launch(app, newInstance: false)
            } label: {
                HStack(spacing: 7) {
                    Text("Open main account")
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .medium))
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.busyID != nil || needsFirstSignIn)
            .help(needsFirstSignIn ? "Verify the second account before opening your main account." : "Open your usual app profile")
            .padding(.top, 5)

            if let notice = model.notice {
                noticeView(notice)
                    .padding(.top, 13)
            }

            VStack(alignment: .leading, spacing: 12) {
                if needsFirstSignIn {
                    claudeFirstSignIn(app)
                } else if isClaude && app.profileSupport.isAvailable {
                    infoRow(symbol: "person.crop.circle.badge.plus", title: "Account profiles", text: "Profiles keep account data separate. They are not a security boundary between apps or files on this Mac.")
                    infoRow(symbol: "info.circle", title: "Code and Cowork", text: "Code and Cowork haven’t been verified with two profiles. Cowork is disabled in this second copy.")
                    infoRow(symbol: "arrow.triangle.2.circlepath", title: "Desktop compatibility", text: "Claude in Chrome pairing is unavailable in this profile. App updates may affect compatibility.")
                } else if app.profileSupport.isAvailable {
                    infoRow(symbol: "person.crop.circle.badge.plus", title: "A separate sign-in", text: "The second account uses a separate profile. Sign in once, then reopen it here whenever you need it.")
                    infoRow(symbol: "info.circle", title: "Prototype compatibility", text: app.profileSupport.integrationNote)
                } else {
                    infoRow(symbol: "info.circle", title: "Separate accounts unavailable", text: app.profileSupport.explanation)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 19)
        }
    }

    private func needsClaudeFirstSignIn(_ app: AppRecord) -> Bool {
        app.bundleID == "com.anthropic.claudefordesktop" && model.needsFirstSignIn(app)
    }

    private func claudeFirstSignIn(_ app: AppRecord) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(TwinStyle.accent)
                Text("Set up your second account")
                    .font(.system(size: 12, weight: .semibold))
            }
            setupStep(1, "Finish your work and quit all Claude copies. Don’t sign out.")
            setupStep(2, "Click Open second account above.")
            setupStep(3, "Choose a different account in the browser when signing in.")
            setupStep(4, "Verify the account shown in the new Claude window, then confirm below.")
            Button {
                model.confirmSecondAccount(app)
            } label: {
                Text("I verified my second account")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canConfirmSecondAccount(app) || model.busyID != nil)
            Text("Twin waits for your confirmation; opening a process doesn’t verify a sign-in. Code and Cowork remain unverified, and Cowork is disabled in this second copy.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(TwinStyle.accent)
                .frame(width: 19, height: 19)
                .background(TwinStyle.accent.opacity(0.09), in: Circle())
                .accessibilityLabel("Step \(number)")
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private func infoRow(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func noticeView(_ notice: LaunchNotice) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? Color.orange : Color.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title).font(.system(size: 12, weight: .semibold))
                Text(notice.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background((notice.isError ? Color.orange : Color.green).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var emptyDetail: some View {
        VStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(TwinStyle.accent.opacity(0.08))
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 37, weight: .light))
                    .foregroundStyle(TwinStyle.accent)
            }
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
            Text("Keep two accounts close.")
                .font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("Choose an app in the sidebar, or add one\nfrom your Applications folder.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
            Button("Add an app", action: model.addApplication)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
