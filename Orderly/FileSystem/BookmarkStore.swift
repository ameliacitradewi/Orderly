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


}
