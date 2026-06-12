# Codex Keeper

Codex Keeper is the new name for Codex Wake. The GitHub repository is still named `codex-wake` during the transition so existing links, releases, and local checkouts continue to work.

Codex app 26.609 shows older chats directly in the sidebar, so Codex Keeper no longer treats age as a hidden-chat problem. The app is now focused on local chat maintenance: browsing, deep search, project moves, trimming, branching, trash, restore, backups, and metadata repair.

Another common pain: useful chats can end up attached to the wrong project, which makes them hard to find in the right workspace later.

Codex Keeper is an unofficial local macOS app for browsing, searching, repairing, moving, trashing, restoring, trimming, branching, and backing up Codex chats. It reads the local Codex data directory, shows chats grouped by project, supports metadata search and optional deep search through JSONL transcripts, can repair chats missing from `session_index.jsonl`, can move a chat from one known project to another, can move unwanted chats into its own restoreable app trash, and provides a local backup manager.

![Codex Keeper screenshot](assets/screenshot.png)

## Download

Download the latest macOS build from [Releases](https://github.com/nClear/codex-wake/releases).

The release build is signed with a Developer ID certificate and notarized by Apple.

See [CHANGELOG.md](CHANGELOG.md) for version history.

To install it:

1. Download the latest `Codex-Keeper-*-macOS.zip`.
2. Unzip the archive.
3. Move `Codex Keeper.app` to `/Applications`.
4. Open it.

## Latest In 0.2.0

- Renamed the app from **Codex Wake** to **Codex Keeper**.
- Added the new Codex Keeper icon.
- Kept the repository name, bundle id, executable name, and legacy `.codex-wake-trash` storage path for compatibility.
- Updated chat availability for Codex app 26.609, which now shows older chats in the sidebar.
- Old chats are now marked **Available** instead of **Hidden** when their metadata and JSONL file are present.
- The main workflow now emphasizes deep search, trim, branch, move, trash, restore, and backup maintenance.

## Demo Mode

Codex Keeper includes a screenshot-safe demo mode with synthetic projects and chats. It does not read or write `~/.codex`.

```sh
open -n "dist/Codex Keeper.app" --args --demo
```

You can also launch the app with:

```sh
CODEX_WAKE_DEMO=1 "dist/Codex Keeper.app/Contents/MacOS/CodexWake"
```

## Features

- Browse local Codex chat threads grouped by project.
- Search by title, first message, preview text, path, or thread id.
- Run optional deep search inside chat JSONL files.
- Preview messages from a selected thread without opening Codex.
- Repair index metadata for chats missing from `session_index.jsonl`.
- Repair multiple selected chats that need index metadata.
- Move a thread between known projects by updating its local project metadata.
- Move a thread to Codex Keeper's app trash and remove it from local Codex metadata.
- Restore a trashed thread from Codex Keeper's app trash.
- Permanently delete trashed threads after confirmation.
- Trim a thread from a selected user message, with a backup created first.
- Create a branch thread from a selected turn without changing the original.
- Create backups before every metadata-changing operation.
- View Codex Keeper backup files in the **Backups** section.
- Restore chat file backups from the **Backups** section.
- Move backup files to Codex Keeper's app trash before permanent cleanup.
- Reveal a thread JSONL file in Finder or copy its path.

## What It Reads

Codex Keeper reads local files from:

```text
~/.codex/state_5.sqlite
~/.codex/session_index.jsonl
~/.codex/sessions/**/*.jsonl
```

The app does not send chat content anywhere. There is no server component, telemetry, analytics, or network sync.

## Repair Index

**Repair Index** is a legacy recovery action for chats that exist in the Codex state database and on disk, but are missing from `session_index.jsonl`. This can happen after manual cleanup, format changes, or failed local maintenance.

When you repair a selected thread, Codex Keeper creates timestamped backups and then refreshes the metadata Codex uses for listing:

- `threads.thread_source = 'user'`
- `threads.updated_at` and `threads.updated_at_ms`
- `session_index.jsonl.updated_at`
- the first `session_meta` line in the thread JSONL file: `timestamp` and `payload.timestamp`

The chat messages themselves are not modified.

Backups are written next to the original files with a timestamp suffix.

## Batch Repair

In multi-select mode, **Repair Index** runs the same single-chat repair operation for each selected chat missing from `session_index.jsonl`, one by one. This is intentionally boring and conservative: each chat follows the already-tested repair path and gets its own backups.

Already available chats, archived chats, and chats with missing JSONL files are skipped.

## Move Operation

When you move a selected thread, Codex Keeper creates timestamped backups and updates the project path metadata Codex uses for grouping:

- `threads.cwd`
- the first `session_meta` line in the thread JSONL file: `payload.cwd`

After the move, Codex Keeper reloads the full thread list so project counts and filters reflect the new location.

## Move To Trash

When you move a selected thread to Trash, Codex Keeper creates timestamped backups, writes a restore manifest, and then removes the chat from the local Codex metadata used for listing:

- `threads` row in `state_5.sqlite`
- matching `session_index.jsonl` entry
- the thread JSONL file, moved to the legacy `~/.codex/.codex-wake-trash/threads/` path when it still exists

If the chat JSONL file is already missing, Codex Keeper cleans the metadata only. This is useful for removing projects that still appear in Codex Keeper after their local chat files were deleted elsewhere.

Each trashed chat gets a `manifest.json` file with the original path, thread id, project path, saved SQLite row, and session index entry needed for restore.

Trashed chats appear in the **Trash** section. From there you can restore a chat, reveal or copy the trashed file path, copy the original path, or permanently delete it.

## Trim And Branch

**Trim from here** creates a backup of the selected chat JSONL file, then removes the selected user message and everything after it from the local chat file. The first visible user message cannot be trimmed because Codex stores it as chat preview metadata.

**Branch from here** creates a new chat using the conversation history before the selected Codex turn. The original chat is not changed. Codex Keeper creates safety backups for the local state files before registering the new branch.

## Backups And Trash

Codex Keeper creates timestamped backup files before changing Codex metadata. The **Backups** section lists those backup files with their original path, size, kind, and creation time.

Chat file backups can be restored from the **Backups** section. Restoring replaces the current chat file with the selected restore point. The selected restore point stays in Backups.

Backup files and chats can be moved to Codex Keeper's app trash. This does not immediately delete them from disk. The on-disk folder remains `~/.codex/.codex-wake-trash` for compatibility with existing Codex Wake backups. When the app trash contains files, a **Trash** section appears in the sidebar where you can inspect them.

The **Empty Trash** action permanently deletes files from Codex Keeper's app trash and asks for confirmation first. After emptying trash, those backup files and trashed chats cannot be restored from inside Codex Keeper.

## Build

Requirements:

- macOS 14 or newer
- Swift 6 toolchain

Build the executable:

```sh
swift build
```

Build a macOS `.app` bundle:

```sh
./scripts/build-app.sh
```

The app bundle is written to:

```text
dist/Codex Keeper.app
```

## Safety Notes

Codex Keeper edits local Codex metadata when you press **Repair Index**, **Move**, **Move to Trash**, **Trim from here**, **Branch from here**, or **Restore Chat**. Keep Codex Desktop closed while changing chats if you want to avoid concurrent writes.

If something looks wrong after a repair or move operation, restore the backup files from the **Backups** section. If you moved a chat to Trash by mistake, restore it from the **Trash** section. Do not empty app trash until you are sure you no longer need those files.

## Status

Early utility. Tested on local Codex Desktop data, but the Codex storage format is private and may change.

## Disclaimer

Codex Keeper is unofficial and is not affiliated with OpenAI.

## License

MIT
