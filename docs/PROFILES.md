# Profile behavior

Twin uses `NSWorkspace.OpenConfiguration` to start the installed application with app-specific arguments and child-process environment overrides. The environment of the already running main app is not changed.

## ChatGPT adapter

For the supported `com.openai.codex` build, the second profile receives a separate Electron user-data directory and a separate account-data directory through `CODEX_ELECTRON_USER_DATA_PATH`, `CODEX_HOME`, and `--user-data-dir`.

This adapter is specific to the checked installed build. Other apps named ChatGPT, including a different native app bundle, are not automatically compatible.

## Claude adapter

Claude uses a new `claude-v2` profile beneath the app's stored UUID. The older prototype's profile is preserved and not reused.

Before first launch, Twin creates:

- `app-data/` for `--user-data-dir`.
- `code-config/`, passed through `CLAUDE_CONFIG_DIR`.
- `work-files/` for Cowork's user-files location.

In the fresh `app-data/claude_desktop_config.json`, Twin sets:

```json
{
  "coworkUserFilesPath": "/absolute/path/to/this/profile/work-files",
  "preferences": {
    "secureVmFeaturesEnabled": false
  }
}
```

This disables Cowork in the second profile. The file is created only when absent. Existing configurations are validated without being overwritten; an unexpected work-folder path or enabled VM setting stops launch or reuse through Twin. Changes made directly in Claude remain outside Twin's control.

The supported app's packaged implementation was inspected to establish these settings and paths. No vendor implementation is included in this repository.

Anthropic documents [the Code configuration-directory override](https://code.claude.com/docs/en/env-vars#variables) and [transcript storage](https://code.claude.com/docs/en/sessions#where-transcripts-are-stored). These references explain Code's storage controls; they do not certify this launcher or its Desktop/Cowork adapter.

## Login routing

Claude has shared desktop URL-scheme handlers. Starting a second process alone does not ensure that a browser login callback reaches it. During first sign-in, Twin requires other Claude processes to be closed and holds the main-account action until the user checks the account and confirms it manually.

The confirmation records the user's check. It does not inspect the account or prove that Code/Cowork is isolated. New authentication can require repeating setup with only one Claude running.

## Process tracking

Twin records the PID and launch date for processes it starts. Matching both helps avoid activating an unrelated process after a PID is reused. A running process is not proof of a useful window or authenticated account.

Unrecognized Claude processes can block launch to avoid guessing which profile is running. The user can finish work, quit Claude copies, and reopen profiles through Twin.

## Scope of separation

Profile-owned configuration and data directories do not isolate the operating system. Explicitly selected project folders, project-local settings, worktrees, diagnostics, permissions, helpers, and background services can still be shared. Use different working directories when the accounts must not edit the same files.

Code execution with both accounts has not been verified. Cowork is deliberately disabled in the second profile. Do not describe this prototype as a full Code/Cowork sandbox.
