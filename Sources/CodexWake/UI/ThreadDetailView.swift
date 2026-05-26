import SwiftUI

struct ThreadDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let thread = model.selectedThread {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(thread)
                        metadata(thread)
                        actions(thread)
                        wakeReport
                        preview
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a chat", systemImage: "text.bubble")
            }
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
                Label("Wake", systemImage: "alarm")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isLoading || thread.archived || !thread.fileExists)
            .help(model.isDemoMode ? "Show a demo wake report without changing local files" : "Back up metadata, update dates, and make the chat recent in Codex App")

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
        }
    }

    @ViewBuilder
    private var wakeReport: some View {
        if let report = model.wakeReport {
            VStack(alignment: .leading, spacing: 8) {
                Text("Wake complete")
                    .font(.headline)
                Text("Backups")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(report.backups, id: \.self) { path in
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
