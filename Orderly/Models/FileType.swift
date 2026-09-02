//
//  FileType.swift
//  Orderly
//

import Foundation

enum FileType: String, Codable, Hashable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case document
    case archive
    case application
    case code
    case other

    static func from(fileExtension: String) -> FileType {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff":
            return .image

        case "mp4", "mov", "m4v", "avi", "mkv":
            return .video

        case "mp3", "wav", "m4a", "aac", "flac":
            return .audio

        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
             "txt", "rtf", "pages", "numbers", "key":
            return .document

        case "zip", "rar", "7z", "tar", "gz":
            return .archive

        case "app", "dmg", "pkg":
            return .application

        case "swift", "py", "js", "ts", "html", "css", "json",
             "xml", "c", "cpp", "h", "m":
            return .code

        default:
            return .other
        }
    }
}
