//
//  BookmarkStore.swift
//  Orderly
//

import Foundation

final class BookmarkStore {

    private let bookmarkKey = "Orderly.selectedFolderBookmark"

    func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        UserDefaults.standard.set(
            bookmarkData,
            forKey: bookmarkKey
        )
    }

    func resolveBookmark() throws -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(
            forKey: bookmarkKey
        ) else {
            return nil
        }

        var isStale = false

        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try saveBookmark(for: url)
        }

        return url
    }

    func removeBookmark() {
        UserDefaults.standard.removeObject(
            forKey: bookmarkKey
        )
    }
}
