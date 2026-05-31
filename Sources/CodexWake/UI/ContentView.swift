import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } content: {
            switch model.selectedSection {
            case .chats:
                ThreadListView()
                    .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
            case .backups:
                BackupListView()
                    .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
            case .backupTrash:
                BackupTrashListView()
                    .navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
            }
        } detail: {
            switch model.selectedSection {
            case .chats:
                if model.isSelectingThreads {
                    ThreadSelectionDetailView()
                } else {
                    ThreadDetailView()
                }
            case .backups:
                BackupDetailView()
            case .backupTrash:
                BackupTrashDetailView()
            }
        }
        .overlay(alignment: .bottom) {
            if model.isLoading {
                ProgressView(model.status)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}
