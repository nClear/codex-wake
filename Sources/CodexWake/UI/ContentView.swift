import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var activePane: WakeFocusPane = .threads
    @State private var keyMonitor: Any?
    @State private var didClearInitialFocus = false
    @State private var isPaneIndicatorVisible = false
    @State private var paneIndicatorTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView(activePane: $activePane)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } content: {
            ThreadListView(activePane: $activePane)
                .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
        } detail: {
            ThreadDetailView(activePane: $activePane)
        }
        .overlay(alignment: .bottom) {
            if model.isLoading {
                ProgressView(model.status)
                    .padding(12)
                    .liquidGlassSurface(in: RoundedRectangle.liquidGlass, interactive: true)
                    .padding()
            }
        }
        .overlay(alignment: .topTrailing) {
            if isPaneIndicatorVisible {
                Label(activePane.title, systemImage: activePane.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .liquidGlassSurface(
                        in: RoundedRectangle.compactLiquidGlass,
                        interactive: true,
                        fallbackMaterial: .thinMaterial
                    )
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .liquidGlassBackground
        .onAppear {
            installKeyMonitorIfNeeded()
            clearInitialTextFocusIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
            paneIndicatorTask?.cancel()
        }
        .onChange(of: activePane) { _, _ in
            showPaneIndicator()
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control),
                  !isSheetPresented,
                  !isEditingText
            else { return event }

            switch event.keyCode {
            case 123:
                movePane(offset: -1)
                return nil
            case 124:
                movePane(offset: 1)
                return nil
            case 125 where activePane == .projects:
                _ = model.selectAdjacentProject(offset: 1)
                return nil
            case 126 where activePane == .projects:
                _ = model.selectAdjacentProject(offset: -1)
                return nil
            case 125 where activePane == .threads:
                postThreadNavigation(.offset(1))
                return nil
            case 126 where activePane == .threads:
                postThreadNavigation(.offset(-1))
                return nil
            case 125 where activePane == .detail:
                postDetailScroll(.step(1))
                return nil
            case 126 where activePane == .detail:
                postDetailScroll(.step(-1))
                return nil
            case 116 where activePane == .threads:
                postThreadNavigation(.offset(-5))
                return nil
            case 121 where activePane == .threads:
                postThreadNavigation(.offset(5))
                return nil
            case 116 where activePane == .detail:
                postDetailScroll(.page(-1))
                return nil
            case 121 where activePane == .detail:
                postDetailScroll(.page(1))
                return nil
            case 115 where activePane == .projects:
                _ = model.selectProjectBoundary(.first)
                return nil
            case 119 where activePane == .projects:
                _ = model.selectProjectBoundary(.last)
                return nil
            case 115 where activePane == .threads:
                postThreadNavigation(.first)
                return nil
            case 119 where activePane == .threads:
                postThreadNavigation(.last)
                return nil
            case 115 where activePane == .detail:
                postDetailScroll(.top)
                return nil
            case 119 where activePane == .detail:
                postDetailScroll(.bottom)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func movePane(offset: Int) {
        let panes: [WakeFocusPane] = [.projects, .threads, .detail]
        let currentIndex = panes.firstIndex(of: activePane) ?? 1
        let nextIndex = min(max(currentIndex + offset, 0), panes.count - 1)
        let nextPane = panes[nextIndex]
        activePane = nextPane
        clearEmptyTextFocus()
    }

    private func postThreadNavigation(_ action: WakeThreadNavigationAction) {
        NotificationCenter.default.post(name: .codexWakeNavigateThread, object: action)
    }

    private func postDetailScroll(_ action: WakeDetailScrollAction) {
        NotificationCenter.default.post(name: .codexWakeScrollDetail, object: action)
    }

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable && !model.searchText.isEmpty
        }
        if responder is NSTextField {
            return !model.searchText.isEmpty
        }
        return false
    }

    private var isSheetPresented: Bool {
        NSApp.keyWindow?.attachedSheet != nil
    }

    private func clearInitialTextFocusIfNeeded() {
        guard !didClearInitialFocus else { return }
        didClearInitialFocus = true

        for delay in [0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                clearEmptyTextFocus()
            }
        }
    }

    private func isTextResponder(_ responder: Any?) -> Bool {
        guard let responder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func clearEmptyTextFocus() {
        guard model.searchText.isEmpty,
              let window = NSApp.keyWindow,
              isTextResponder(window.firstResponder)
        else { return }
        window.makeFirstResponder(nil)
    }

    private func showPaneIndicator() {
        paneIndicatorTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            isPaneIndicatorVisible = true
        }
        paneIndicatorTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isPaneIndicatorVisible = false
            }
        }
    }
}
