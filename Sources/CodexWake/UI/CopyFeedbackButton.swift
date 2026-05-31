import SwiftUI
import AppKit

struct CopyFeedbackButton: View {
    let text: String
    var help = "Copy"
    var label: String?
    var copiedLabel = "Copied"
    var showsCopiedLabel = false
    var usesPlainButtonStyle = true
    var normalForeground: Color = .secondary
    var normalOpacity = 1.0

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        styledButton
            .foregroundStyle(didCopy ? .green : normalForeground)
            .opacity(didCopy ? 1 : normalOpacity)
            .disabled(text.isEmpty)
            .help(didCopy ? copiedLabel : help)
            .onDisappear {
                resetTask?.cancel()
            }
    }

    @ViewBuilder
    private var styledButton: some View {
        if usesPlainButtonStyle {
            button.buttonStyle(.plain)
        } else {
            button
        }
    }

    private var button: some View {
        Button {
            copy()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                if let label {
                    Text(didCopy ? copiedLabel : label)
                } else if showsCopiedLabel && didCopy {
                    Text(copiedLabel)
                        .font(.caption2.weight(.medium))
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .frame(minWidth: label == nil && !(showsCopiedLabel && didCopy) ? 18 : nil)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        resetTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            didCopy = true
        }
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                didCopy = false
            }
        }
    }
}
