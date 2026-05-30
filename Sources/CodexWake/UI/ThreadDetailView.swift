import SwiftUI

struct ThreadDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isMoveSheetPresented = false

    var body: some View {
        Group {
            if let thread = model.selectedThread {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(thread)
                        metadata(thread)
                        actions(thread)
                        operationReport
                        preview
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a chat", systemImage: "text.bubble")
            }
        }
        .sheet(isPresented: $isMoveSheetPresented) {
            MoveThreadSheet(isPresented: $isMoveSheetPresented)
                .environmentObject(model)
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
                model.selectThread(thread)
                Task { await model.wakeSelectedThread() }
            } label: {
                Label("Wake", systemImage: "alarm")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading || thread.archived || !thread.fileExists)
            .help(model.isDemoMode ? "Show a demo wake report without changing local files" : "Back up metadata, update dates, and make the chat recent in Codex App")

            Button {
                model.selectThread(thread)
                isMoveSheetPresented = true
            } label: {
                Label("Move", systemImage: "arrow.right.folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading || model.moveTargetProjects.isEmpty || thread.archived || !thread.fileExists)
            .help("Move this chat to another known project")

            Button {
                model.selectThread(thread)
                model.revealSelectedInFinder()
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)

            Button {
                model.selectThread(thread)
                model.copySelectedPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(model.isDemoMode)
        }
    }

    @ViewBuilder
    private var operationReport: some View {
        if let report = model.selectedOperationReport {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(report.title)
                        .font(.headline)
                    Spacer()
                    Text(report.timestamp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(report.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if !report.changedFiles.isEmpty {
                    Text("Changed files")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(report.changedFiles, id: \.self) { path in
                        Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }

                if !report.backups.isEmpty {
                    Text("Backups")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(report.backups, id: \.self) { path in
                        Text(path).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }

                if !report.failures.isEmpty {
                    Text("Failures")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    ForEach(report.failures, id: \.self) { failure in
                        Text(failure).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .padding(12)
            .background(report.failures.isEmpty ? Color.green.opacity(0.08) : Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)
            if let rawError = model.preview?.rawError {
                Text(rawError)
                    .foregroundStyle(.red)
            } else if let messages = model.preview?.messages, !messages.isEmpty {
                ForEach(messages) { message in
                    MessagePreview(message: message)
                }
            } else {
                Text("No message preview parsed yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MoveThreadSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var selectedProjectID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedThreadCount > 1 ? "Move Chats" : "Move Chat")
                    .font(.title3.weight(.semibold))
                Text(selectionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                    Task { await model.moveSelectedThreads(to: selectedProject) }
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

    private var selectionSummary: String {
        if model.selectedThreadCount > 1 {
            return "\(model.selectedThreadCount) selected chats"
        }
        return model.selectedThread?.shortTitle ?? "No chat selected"
    }

    private var selectedProject: ProjectSummary? {
        guard let selectedProjectID else { return nil }
        return model.moveTargetProjects.first { $0.id == selectedProjectID }
    }
}

private struct MessagePreview: View {
    let message: PreviewMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(message.role)
                    .font(.caption.weight(.semibold))
                Spacer()
                if let timestamp = message.timestamp {
                    Text(timestamp)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text(message.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
