# Changelog

All notable changes to Codex Keeper, formerly Codex Wake, are documented here.

## 0.2.0 - 2026-06-12

- Renamed the app from **Codex Wake** to **Codex Keeper**.
- Added the new Codex Keeper app icon.
- Updated the app bundle name, sidebar title, window title, README, release copy, and user-facing maintenance messages.
- Kept the repository name `codex-wake`, bundle identifier `app.codexwake.CodexWake`, executable name `CodexWake`, and legacy `.codex-wake-trash` storage path for compatibility.
- Positioned the app as a local Codex chat maintenance tool while preserving existing backup, trash, repair, trim, branch, and restore workflows.

## 0.1.6 - 2026-06-12

- Updated chat availability behavior for Codex app 26.609, which now shows older chats directly in the sidebar.
- Old chats are no longer marked hidden only because they are older than one week.
- Replaced the primary **Wake** workflow with **Repair Index** for chats missing from `session_index.jsonl`.
- Updated project and selection summaries from **Shown/Hidden** to **Available/Repair**.
- Updated README copy to position Codex Wake as a local chat maintenance tool for deep search, trim, branch, move, trash, restore, backups, and metadata repair.

## 0.1.5 - 2026-06-12

- Added safe **Move to Trash** support for chats, including selected chats.
- Moving a chat to Trash removes it from Codex metadata and moves the JSONL file into Codex Wake's own app trash when the file still exists.
- Added trashed chat restore and permanent delete actions in the **Trash** section.
- Missing chat files can now be cleaned from Codex metadata so empty/deleted projects disappear after refresh.
- Added optional `CODEX_WAKE_SCRATCH_PATH` support to the app build script for clean Swift builds.

## 0.1.4 - 2026-06-05

- Added **Trim from here** for cutting a local chat back to an earlier user message, with a backup created first.
- Added **Branch from here** for creating a new chat from an earlier Codex turn without changing the original.
- Added chat backup restore from the Backup Manager.
- Improved full-chat preview loading and turn-aware branch points.
- Added adaptive dark mode colors.

## 0.1.3 - 2026-05-31

- Improved chat title and visibility status detection using `session_index.jsonl`.
- Added multi-select mode for chat actions.
- Added batch **Wake** for selected chats, with confirmation.
- Added context menu actions for chat rows.
- Added Backup Manager for viewing backup files created by Codex Wake.
- Added app trash for backup files, with a separate **Trash** section and confirmed permanent cleanup.
- Improved wake feedback and 7-day visibility handling.

## 0.1.2 - 2026-05-31

- Improved chat preview readability.
- Hid noisy technical instruction blocks from previews.
- Improved project sorting and chat sorting.
- Added created and last-message dates to chat rows.
- Prepared signed and notarized macOS release build.

## 0.1.1 - 2026-05-26

- Added screenshot-safe demo mode with synthetic projects and chats.
- Added project move support for moving chats between known project folders.
- Updated README screenshot.
- Updated app icon and release build packaging.

## 0.1.0 - 2026-05-25

- Initial public release.
- Browsed local Codex chat threads grouped by project.
- Added metadata search and optional deep search through JSONL transcripts.
- Added chat preview.
- Added **Wake** operation for making hidden older chats appear again in the Codex sidebar.
- Added backup creation before metadata changes.
- Added Finder reveal and copy-path actions.
