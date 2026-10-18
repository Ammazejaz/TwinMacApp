# Twin

A small native macOS launcher for opening a second account profile in an installed desktop app. Built with SwiftUI and AppKit, with no third-party build dependencies.

Twin 0.2 supports the specific ChatGPT and Claude Desktop builds listed below. It launches the installed apps; it does not bundle them or replace them with websites.

## Requirements

- Apple Silicon Mac running macOS 14 or newer.
- Xcode Command Line Tools with the Swift compiler. Swift 6.3.1 was used for local verification; the build uses Swift 5 language mode.
- A supported app installed separately if you want to use its second-account feature.

## Build and run

From this repository folder:

```sh
./build.sh
open dist/Twin.app
```

The build script creates `dist/Twin.app` and signs it locally with an ad hoc signature. You can also pass an output directory:

```sh
./build.sh /absolute/path/to/output
```

The app has not been notarized for public distribution. No API keys or network dependencies are needed to build it.

## Check profile preparation

```sh
./test.sh
```

This check uses synthetic application metadata and temporary folders inside `.build/`. It does not need Claude installed, launch another app, or access real account profiles. It verifies separate Code storage, the configured Cowork folder, Cowork's disabled setting, preservation of existing configuration, and rejection of unexpected paths.

It does not test authentication, Claude Code execution, or Cowork execution.

## Supported app versions

| App | Bundle identifier | Version |
| --- | --- | --- |
| ChatGPT desktop build | `com.openai.codex` | `26.1013.31256` |
| Claude Desktop | `com.anthropic.claudefordesktop` | `2.42304.0` |

Second-account launch is disabled for other versions. Review the app's actual profile and login behavior before changing these checks in `Sources/AccountProfiles.swift`.

Apps can be added through **Add an app**, but an app without a supported adapter cannot launch a separate account through Twin.

## Claude: first sign-in

Claude's browser login can return to the wrong desktop copy when several copies are running. The browser can also reuse its current account.

1. Finish active work and quit all Claude copies without signing out.
2. In Twin, select Claude and choose **Open second account**.
3. Keep this as the only Claude copy running during sign-in. Explicitly choose the other account in the browser.
4. Check the account shown inside Claude, then select **I verified my second account** in Twin.
5. **Open main account** becomes available after that confirmation.

Twin never confirms an account automatically. If you need to authenticate again, use the app's options menu → **Redo Claude sign-in setup**.

Claude second-account sign-in was manually confirmed working during local testing. This is not a general compatibility guarantee for other app versions or authentication methods. Separate ChatGPT processes and profile reuse were checked; distinct ChatGPT account authentication was not independently verified.

## Data separation and current limits

The second Claude profile has its own app-data folder, a separate global Code configuration directory, and a profile-owned Cowork work folder. **Cowork is disabled in the second copy.** Native Code execution with two profiles remains unverified. Claude in Chrome pairing is unavailable in the relocated profile.

These are account profiles, not separate macOS users or security sandboxes. If both copies select the same project folder, they can edit the same files. Project-local settings, worktrees, logs, permissions, helpers, and some background services can still be shared. See [profile behavior and limits](docs/PROFILES.md) before using the prototype for important work.

Twin stores runtime profiles under `~/Library/Application Support/Twin/Profiles/` and its own settings in its preferences. Removing an app from Twin does not delete its profile. The source repository contains no runtime account data.

## Repository layout

```text
Sources/
  AccountProfiles.swift       App compatibility and profile preparation
  ContentView.swift           Native interface
  LauncherModel.swift         Launching, process tracking, and sign-in setup
  TwinApp.swift               Application entry point and menu commands
Tests/
  ProfilePreparationCheck.swift
docs/
  PROFILES.md
build.sh
test.sh
```

Build output and local account data are excluded by `.gitignore`. This repository contains only Twin's source, scripts, tests, and documentation; no third-party app code or assets are bundled.
