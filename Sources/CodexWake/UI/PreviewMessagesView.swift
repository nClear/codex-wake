import SwiftUI
import AppKit

struct PreviewMessagesView: View {
    let messages: [PreviewMessage]
    private let visibleConversationLimit = 6

    private var contextMessages: [PreviewMessage] {
        messages.filter(\.isContextMessage)
    }

    private var conversationMessages: [PreviewMessage] {
        messages.filter { !$0.isContextMessage }
    }

    private var foldedConversationMessages: [PreviewMessage] {
        guard conversationMessages.count > visibleConversationLimit else { return [] }
        return Array(conversationMessages.dropLast(visibleConversationLimit))
    }

    private var visibleConversationMessages: [PreviewMessage] {
        guard conversationMessages.count > visibleConversationLimit else { return conversationMessages }
        return Array(conversationMessages.suffix(visibleConversationLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !contextMessages.isEmpty {
                ContextPreviewDisclosure(messages: contextMessages)
            }

            if !foldedConversationMessages.isEmpty {
                OlderMessagesDisclosure(messages: foldedConversationMessages)
            }

            ForEach(visibleConversationMessages) { message in
                MessagePreview(message: message)
            }
        }
    }
}

private struct ContextPreviewDisclosure: View {
    let messages: [PreviewMessage]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 12)
                        Label("Context", systemImage: "curlybraces")
                            .font(.caption.weight(.semibold))
                        Text("\(messages.count) messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                CopyFeedbackButton(
                    text: messages.map(\.text).joined(separator: "\n\n"),
                    help: "Copy context",
                    showsCopiedLabel: true
                )
            }

            if isExpanded {
                ForEach(messages) { message in
                    MessagePreview(message: message, startsExpanded: false)
                }
            }
        }
        .padding(10)
        .liquidGlassSurface(
            in: RoundedRectangle.compactLiquidGlass,
            tint: Color.secondary.opacity(0.035),
            interactive: true,
            fallbackMaterial: .thinMaterial
        )
    }
}

private struct OlderMessagesDisclosure: View {
    let messages: [PreviewMessage]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12)
                    Label("\(messages.count) earlier messages", systemImage: "ellipsis.message")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(messages) { message in
                    MessagePreview(message: message)
                }
            }
        }
        .padding(10)
        .liquidGlassSurface(
            in: RoundedRectangle.compactLiquidGlass,
            tint: Color.secondary.opacity(0.035),
            interactive: true,
            fallbackMaterial: .thinMaterial
        )
    }
}

private struct MessagePreview: View {
    let message: PreviewMessage
    let startsExpanded: Bool
    @State private var isExpanded: Bool

    init(message: PreviewMessage, startsExpanded: Bool = true) {
        self.message = message
        self.startsExpanded = startsExpanded
        _isExpanded = State(initialValue: startsExpanded)
    }

    private var roleStyle: PreviewRoleStyle {
        PreviewRoleStyle(role: message.role, text: message.text)
    }

    private var shouldCollapse: Bool {
        roleStyle.isContext && message.text.count > 420
    }

    private var displayText: String {
        if shouldCollapse && !isExpanded {
            message.text.prefixString(420)
        } else {
            message.text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(roleStyle.accent)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                MarkdownPreviewText(
                    messageID: message.id,
                    text: displayText,
                    isMuted: roleStyle.isContext
                )
            }

            if shouldCollapse {
                Button(isExpanded ? "Show Less" : "Show More") {
                    isExpanded.toggle()
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(roleStyle.accent)
            }
        }
        .padding(12)
        .liquidGlassSurface(
            in: RoundedRectangle.compactLiquidGlass,
            tint: roleStyle.accent.opacity(roleStyle.isContext ? 0.035 : 0.08),
            interactive: true,
            fallbackMaterial: .thinMaterial
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(roleStyle.title, systemImage: roleStyle.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(roleStyle.accent)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 8)
            if let timestamp = message.timestamp {
                Text(Self.displayTimestamp(timestamp))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(timestamp)
            }
            CopyFeedbackButton(
                text: message.text,
                help: "Copy message",
                showsCopiedLabel: true,
                normalOpacity: 0.55
            )
        }
    }

    private static func displayTimestamp(_ timestamp: String) -> String {
        if let date = WakeDates.parseISO(timestamp) {
            return WakeDates.compactDisplay(date)
        }
        guard timestamp.count > 16 else { return timestamp }
        return String(timestamp.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

private struct MarkdownPreviewText: View {
    let messageID: String
    let text: String
    let isMuted: Bool

    private var blocks: [MarkdownPreviewBlock] {
        MarkdownPreviewBlock.blocks(from: text, messageID: messageID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(blocks) { block in
                switch block.kind {
                case .paragraph:
                    Text(block.attributedText)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(isMuted ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .heading(let level):
                    Text(block.plainText)
                        .font(level <= 2 ? .system(size: 14, weight: .semibold) : .system(size: 13, weight: .semibold))
                        .foregroundStyle(isMuted ? .secondary : .primary)
                        .textSelection(.enabled)
                case .listItem(let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(marker)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: marker == "•" ? nil : 22, alignment: .trailing)
                        Text(block.attributedText)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(isMuted ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                case .quote:
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 2)
                        Text(block.attributedText)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                case .code(let language):
                    VStack(alignment: .leading, spacing: 6) {
                        if let language, !language.isEmpty {
                            Text(language)
                                .font(.caption2.monospaced().weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(block.text)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(.quaternary, lineWidth: 0.5)
                    }
                }
            }
        }
    }
}

private struct MarkdownPreviewBlock: Identifiable {
    enum Kind {
        case paragraph
        case heading(level: Int)
        case listItem(marker: String)
        case quote
        case code(language: String?)
    }

    let id: String
    let kind: Kind
    let text: String

    var plainText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var attributedText: AttributedString {
        AttributedString.previewMarkdown(text)
    }

    static func blocks(from text: String, messageID: String) -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        var paragraphBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var isInCodeBlock = false

        func append(_ kind: Kind, text: String) {
            blocks.append(MarkdownPreviewBlock(id: "\(messageID)-block-\(blocks.count)", kind: kind, text: text))
        }

        func flushParagraph() {
            let content = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                append(.paragraph, text: content)
            }
            paragraphBuffer.removeAll()
        }

        func flushCode() {
            append(.code(language: codeLanguage), text: codeBuffer.joined(separator: "\n"))
            codeBuffer.removeAll()
            codeLanguage = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isInCodeBlock {
                    flushCode()
                    isInCodeBlock = false
                } else {
                    flushParagraph()
                    codeLanguage = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                    isInCodeBlock = true
                }
                continue
            }

            if isInCodeBlock {
                codeBuffer.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                append(.heading(level: heading.level), text: heading.text)
                continue
            }

            if let listItem = parseListItem(line) {
                flushParagraph()
                append(.listItem(marker: listItem.marker), text: listItem.text)
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                let quote = line.dropFirst().trimmingCharacters(in: .whitespaces)
                append(.quote, text: quote)
                continue
            }

            paragraphBuffer.append(rawLine)
        }

        if isInCodeBlock {
            flushCode()
        }
        flushParagraph()

        return blocks.isEmpty ? [MarkdownPreviewBlock(id: "\(messageID)-block-empty", kind: .paragraph, text: text)] : blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0, hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseListItem(_ line: String) -> (marker: String, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return ("•", String(line.dropFirst(2)))
        }
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].hasSuffix("."),
              parts[0].dropLast().allSatisfy(\.isNumber)
        else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

private extension AttributedString {
    static func previewMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct PreviewRoleStyle {
    let title: String
    let symbol: String
    let accent: Color
    let isContext: Bool

    init(role: String, text: String) {
        let normalizedRole = role.lowercased()
        let isContextMessage = PreviewMessage(id: "style", role: role, text: text, timestamp: nil).isContextMessage

        isContext = isContextMessage

        switch normalizedRole {
        case "user":
            if isContextMessage {
                title = "Context"
                symbol = "curlybraces"
                accent = .secondary
            } else {
                title = "You"
                symbol = "person.fill"
                accent = .blue
            }
        case "assistant":
            title = "Agent"
            symbol = "sparkles"
            accent = .green
        case "developer":
            title = "Context"
            symbol = "hammer.fill"
            accent = .secondary
        case "system":
            title = "Context"
            symbol = "gearshape.fill"
            accent = .secondary
        case "tool":
            title = "Tool"
            symbol = "wrench.and.screwdriver.fill"
            accent = .teal
        default:
            title = role.isEmpty ? "Message" : role.capitalized
            symbol = "bubble.left.and.text.bubble.right.fill"
            accent = .secondary
        }
    }
}
