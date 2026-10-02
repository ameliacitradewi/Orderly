import Foundation
import PDFKit

struct PDFTextObservation: Sendable, Equatable {
    let pageCount: Int
    let extractedCharacterCount: Int
    let excerpt: String
    let truncated: Bool
}

struct PDFTextExtractor {
    func inspectPDF(
        at url: URL,
        maxExcerptCharacters: Int
    ) throws -> PDFTextObservation {
        guard let document = PDFDocument(url: url) else {
            throw PDFTextExtractorError.cannotOpenPDF
        }

        var extracted = ""
        extracted.reserveCapacity(min(maxExcerptCharacters, 8_192))
        var totalCharacters = 0

        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string else {
                continue
            }

            totalCharacters += text.count

            if extracted.count < maxExcerptCharacters {
                if !extracted.isEmpty && extracted.count < maxExcerptCharacters {
                    extracted.append("\n")
                }

                let remaining = maxExcerptCharacters - extracted.count
                if remaining > 0 {
                    extracted.append(contentsOf: text.prefix(remaining))
                }
            }
        }

        return PDFTextObservation(
            pageCount: document.pageCount,
            extractedCharacterCount: totalCharacters,
            excerpt: extracted,
            truncated: totalCharacters > extracted.count
        )
    }
}

enum PDFTextExtractorError: LocalizedError {
    case cannotOpenPDF

    var errorDescription: String? {
        "The PDF could not be opened for content inspection."
    }
}
