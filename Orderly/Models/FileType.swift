import Foundation
import FoundationModels

@Generable
nonisolated enum FileType: String, Codable, Hashable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case document
    case archive
    case application
    case code
    case artifact
    case other

    var tagName: String {
        switch self {
        case .document: return "Documents"
        case .image: return "Image"
        case .application: return "App Installer"
        case .code: return "Code"
        case .artifact: return "Artifacts"
        case .archive: return "ZIP Files"
        case .video: return "Video"
        case .audio: return "Audio"
        case .other: return "Others"
        }
    }

    static func from(fileExtension: String) -> FileType {
        ExtensionCatalog.category(for: fileExtension) ?? .other
    }
}
