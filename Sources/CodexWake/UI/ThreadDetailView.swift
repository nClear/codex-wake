import SwiftUI

struct ThreadDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isMoveSheetPresented = false
    @State private var pendingTrimMessage: PreviewMessage?
    @State private var pendingBranchMessage: PreviewMessage?
    @State private var isTrashConfirmationPresented = false

    var body: some View {
        Group {
            if let thread = model.selectedThread {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(thread)
                        metadata(thread)
                        actions(thread)
                        wakeReport
                        moveReport
                        trimReport
                        branchReport
                        preview
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a chat", systemImage: "text.bubble")
            }
        }
        .alert("Trim from here?", isPresented: isTrimConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                pendingTrimMessage = nil
            }
            Button("Trim", role: .destructive) {
                guard let message = pendingTrimMessage else { return }
                pendingTrimMessage = nil
                Task { await model.trimSelectedThread(from: message) }
            }
        } message: {
            Text("This deletes this user message and everything after it from the local Codex chat file. A backup will be created first. The first visible user message cannot be trimmed because Codex stores it as chat preview metadata.")
        }
        .alert("Branch from here?", isPresented: isBranchConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                pendingBranchMessage = nil
            }
            Button("Create Branch") {
                guard let message = pendingBranchMessage else { return }
                pendingBranchMessage = nil
                Task { await model.branchSelectedThread(from: message) }
            }
        } message: {
            Text("This creates a new Codex chat with the conversation history before this Codex turn. The original chat is not changed.")
        }
        .alert("Move chat to Trash?", isPresented: $isTrashConfirmationPresented) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.moveSelectedThreadToTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the chat JSONL file to macOS Trash when it exists, removes the chat from Codex metadata, and creates safety backups for local state files first.")
        }
    }

    private func header(_ thread: CodexThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(thread.shortTitle)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            Text(thread.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func metadata(_ thread: CodexThread) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            row("Project", thread.cwd)
            row("Rollout", thread.rolloutPath)
            row("Created", WakeDates.display(thread.createdAt))
            row("Updated", WakeDates.display(thread.updatedAt))
            row("Session index", WakeDates.display(thread.sessionIndexUpdatedAt))
            row("Session meta", WakeDates.display(thread.sessionMetaTimestamp))
            row("Thread source", thread.threadSource.isEmpty ? "NULL" : thread.threadSource)
            row("Archived", thread.archived ? "yes" : "no")
            row("File exists", thread.fileExists ? "yes" : "no")
        }
        .font(.system(size: 12))
        .textSelection(.enabled)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(3)
        }
    }

    private func actions(_ thread: CodexThread) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.wakeSelectedThread() }
            } label: {
                Label("Repair Index", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading || (!model.isDemoMode && !thread.needsRepair))
            .help(model.isDemoMode ? "Show a demo repair report without changing local files" : "Back up metadata and repair missing session_index.jsonl metadata")

            Button {
                isMoveSheetPresented = true
            } label: {
                Label("Move", systemImage: "arrow.right.folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading || model.moveTargetProjects.isEmpty || thread.archived || !thread.fileExists)
            .help("Move this chat to another known project")
            .sheet(isPresented: $isMoveSheetPresented) {
                MoveThreadSheet(isPresented: $isMoveSheetPresented)
                    .environmentObject(model)
            }

            Button {
                model.revealSelectedInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)

            Button {
                model.copySelectedPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)

            Button(role: .destructive) {
                isTrashConfirmationPresented = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading)
            .help("Move this chat file to macOS Trash and remove it from Codex metadata")
        }
    }

    @ViewBuilder
    private var wakeReport: some View {
        if let report = model.selectedWakeReport {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repair complete @ \(WakeDates.displayBackupStamp(report.timestamp))")
                    .font(.headline)
                Text("Backups")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(report.backups, id: \.self) { path in
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            .padding(12)
            .background(WakeColors.reportBackground(.green), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var moveReport: some View {
        if let report = model.selectedMoveReport {
            VStack(alignment: .leading, spacing: 8) {
                Text("Move complete")
                    .font(.headline)
                row("From", report.fromProject)
                row("To", report.toProject)
                if !report.backups.isEmpty {
                    Text("Backups")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(report.backups, id: \.self) { path in
                        Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(12)
            .background(WakeColors.reportBackground(.blue), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var trimReport: some View {
        if let report = model.selectedTrimReport {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trim complete @ \(WakeDates.displayBackupStamp(report.timestamp))")
                    .font(.headline)
                row("Deleted from line", "\(report.deletedFromLine)")
                row("Removed lines", "\(report.removedLineCount)")
                if !report.backups.isEmpty {
                    Text("Backups")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(report.backups, id: \.self) { path in
                        Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(12)
            .background(WakeColors.reportBackground(.orange), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var branchReport: some View {
        if let report = model.selectedBranchReport {
            VStack(alignment: .leading, spacing: 8) {
                Text("Branch created @ \(WakeDates.displayBackupStamp(report.timestamp))")
                    .font(.headline)
                row("New chat", report.title)
                row("New ID", report.newThreadID)
                row("Created before turn line", "\(report.createdFromLine)")
                row("Kept lines", "\(report.keptLineCount)")
                row("Rollout", report.rolloutPath)
                if !report.backups.isEmpty {
                    Text("Safety backups")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(report.backups, id: \.self) { path in
                        Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(12)
            .background(WakeColors.reportBackground(.purple), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.headline)
                if let count = model.preview?.messages.count, count > 0 {
                    Text("\(count) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let rawError = model.preview?.rawError {
                Text(rawError)
                    .foregroundStyle(.red)
            } else if model.isPreviewLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading full chat...")
                        .foregroundStyle(.secondary)
                }
            } else if let messages = model.preview?.messages, !messages.isEmpty {
                ForEach(messages) { message in
                    if isUserMessage(message) {
                        ThreadEditDivider(
                            isTrimDisabled: model.isLoading || !message.canTrimFromHere,
                            canBranch: message.canBranchFromHere && !model.isLoading
                        ) {
                            pendingTrimMessage = message
                        } onBranch: {
                            pendingBranchMessage = message
                        }
                    }
                    MessagePreview(message: message)
                }
            } else {
                Text("No message preview parsed yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isTrimConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingTrimMessage != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTrimMessage = nil
                }
            }
        )
    }

    private var isBranchConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingBranchMessage != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBranchMessage = nil
                }
            }
        )
    }

    private func isUserMessage(_ message: PreviewMessage) -> Bool {
        message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user"
    }
}

private struct MoveThreadSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var selectedProjectID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Move Chat")
                    .font(.title3.weight(.semibold))
                if let thread = model.selectedThread {
                    Text(thread.shortTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            List(model.moveTargetProjects, selection: $selectedProjectID) { project in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(project.totalCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(project.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .tag(project.id as String?)
            }
            .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Move") {
                    guard let selectedProject else { return }
                    isPresented = false
                    Task { await model.moveSelectedThread(to: selectedProject) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProject == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 380)
        .onAppear {
            selectedProjectID = model.moveTargetProjects.first?.id
        }
    }

    private var selectedProject: ProjectSummary? {
        guard let selectedProjectID else { return nil }
        return model.moveTargetProjects.first { $0.id == selectedProjectID }
    }
}

private struct ThreadEditDivider: View {
    let isTrimDisabled: Bool
    let canBranch: Bool
    let onTrim: () -> Void
    let onBranch: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.secondary.opacity(0.22))
                .frame(height: 1)
            if canBranch {
                Button("Branch from here", action: onBranch)
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .help("Create a new chat with the conversation history before this Codex turn. The original chat is not changed.")
            }
            Button("Trim from here", role: .destructive, action: onTrim)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .disabled(isTrimDisabled)
                .help(isTrimDisabled ? "The first visible user message cannot be trimmed because Codex stores it as chat preview metadata." : "Delete this user message and everything after it. A backup is created first.")
        }
        .padding(.top, 4)
        .padding(.bottom, -2)
    }
}

private struct MessagePreview: View {
    let message: PreviewMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayRole)
                    .font(.system(size: isAssistant ? 15 : 13, weight: isAssistant ? .bold : .semibold))
                    .foregroundStyle(headerColor)
                Spacer()
                if let timestamp = message.timestamp {
                    Text(timestamp)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text(message.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
    }

    private var normalizedRole: String {
        if message.isSteered { return "steered" }
        return message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isAssistant: Bool {
        normalizedRole == "assistant"
    }

    private var displayRole: String {
        switch normalizedRole {
        case "user":
            return "User"
        case "steered":
            return "Steered message"
        case "assistant":
            return "Assistant"
        default:
            return message.role.capitalized
        }
    }

    private var headerColor: Color {
        switch normalizedRole {
        case "user":
            return WakeColors.userMessageHeader
        case "steered":
            return WakeColors.steeredMessageHeader
        default:
            return .primary
        }
    }

    private var backgroundColor: Color {
        switch normalizedRole {
        case "user":
            return WakeColors.userMessageBackground
        case "steered":
            return WakeColors.steeredMessageBackground
        case "assistant":
            return WakeColors.panelBackground
        default:
            return WakeColors.sidebarBackground
        }
    }
}
