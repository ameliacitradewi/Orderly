//
//  SecurityScopedAccess.swift
//  Orderly
//

import Foundation

final class SecurityScopedAccess {

    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
