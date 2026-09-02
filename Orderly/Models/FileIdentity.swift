//
//  FileIdentity.swift
//  Orderly
//
//  ClutterBot Data Model v1 — stable internal identity separate from filesystem path.
//  originalURL captures location at registration time; resourceIdentifier enables stronger recovery when available.
//

import Foundation

struct FileIdentity: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    let originalURL: URL

    let resourceIdentifier: String?

    init(
        id: UUID = UUID(),
        originalURL: URL,
        resourceIdentifier: String? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.resourceIdentifier = resourceIdentifier
    }
}
