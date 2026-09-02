//
//  AnalysisResult.swift
//  Orderly
//

import Foundation

struct AnalysisResult: Codable, Hashable, Sendable {
    let analyzedFolder: URL
    let totalFiles: Int
    let totalSize: Int64
    let fileTypes: [FileTypeSummary]
    let duplicateGroups: [DuplicateGroup]
    let candidates: [AnalysisCandidate]
    let analyzedAt: Date
}
