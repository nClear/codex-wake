import Foundation

enum WakeFocusPane: Hashable {
    case projects
    case threads
    case detail

    var title: String {
        switch self {
        case .projects: "Projects"
        case .threads: "Chats"
        case .detail: "Preview"
        }
    }

    var symbolName: String {
        switch self {
        case .projects: "sidebar.left"
        case .threads: "text.bubble"
        case .detail: "doc.text.magnifyingglass"
        }
    }
}

enum WakeThreadNavigationAction {
    case offset(Int)
    case first
    case last
}

enum WakeDetailScrollAction {
    case step(Double)
    case page(Double)
    case top
    case bottom
}
