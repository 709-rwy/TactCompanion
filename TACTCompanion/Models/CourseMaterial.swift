import Foundation

struct CourseMaterial: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case pdf
        case html
        case folder
        case other

        var systemImage: String {
            switch self {
            case .pdf:
                return "doc.richtext"
            case .html:
                return "globe"
            case .folder:
                return "folder.fill"
            case .other:
                return "doc"
            }
        }
    }

    let id: String
    let title: String
    let url: URL
    let kind: Kind
    var children: [CourseMaterial] = []
}
