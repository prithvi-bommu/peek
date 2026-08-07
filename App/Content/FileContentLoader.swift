import Foundation
import PDFKit
import AppKit
import UniformTypeIdentifiers

/// Reads a file and produces PromptContent for the providers.
/// Implements the PDF hybrid strategy (PRD §9): extract text; if the yield is
/// suspiciously low for the page count (scanned PDF), rasterize pages instead.
enum FileContentLoader {

    enum LoadError: LocalizedError {
        case unsupportedType(String)
        case unreadable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext): "Unsupported file type: .\(ext)"
            case .unreadable(let reason): "Couldn't read the file: \(reason)"
            case .empty: "The file appears to be empty."
            }
        }
    }

    private static let textExtensions: Set<String> = ["txt", "md", "csv"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    /// Character budget sent to the model (~30k chars ≈ 8k tokens). Larger
    /// files are truncated head+tail so both intro and conclusion survive.
    private static let maxChars = 30_000

    static func load(url: URL) throws -> PromptContent {
        let ext = url.pathExtension.lowercased()
        var content = PromptContent(fileName: url.lastPathComponent)

        switch ext {
        case _ where textExtensions.contains(ext):
            let raw = try String(contentsOf: url, encoding: .utf8)
            content.text = truncate(raw)

        case "rtf":
            let data = try Data(contentsOf: url)
            guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
                throw LoadError.unreadable("invalid RTF")
            }
            content.text = truncate(attributed.string)

        case "pdf":
            content = try loadPDF(url: url, into: content)

        case _ where imageExtensions.contains(ext):
            let data = try Data(contentsOf: url)
            content.images = [(mimeType: mimeType(for: ext), base64: data.base64EncodedString())]

        default:
            throw LoadError.unsupportedType(ext)
        }

        guard !content.isEmpty else { throw LoadError.empty }
        return content
    }

    // MARK: - PDF hybrid (PRD §9)

    private static func loadPDF(url: URL, into base: PromptContent) throws -> PromptContent {
        var content = base
        guard let doc = PDFDocument(url: url) else {
            throw LoadError.unreadable("invalid or encrypted PDF")
        }
        let pageCount = max(doc.pageCount, 1)
        let text = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")

        // Heuristic: a real text PDF yields well over 200 chars/page.
        // Below that, assume scanned → rasterize pages for a vision model.
        if text.count / pageCount >= 200 {
            content.text = truncate(text)
        } else {
            let pagesToSend = min(doc.pageCount, 8) // cap payload size
            for i in 0..<pagesToSend {
                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2.0
                let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
                let image = page.thumbnail(of: size, for: .mediaBox)
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:])
                else { continue }
                content.images.append((mimeType: "image/png", base64: png.base64EncodedString()))
            }
            if !text.isEmpty { content.text = truncate(text) } // whatever OCR-able text exists
        }
        return content
    }

    // MARK: - Helpers

    private static func truncate(_ s: String) -> String {
        guard s.count > maxChars else { return s }
        let head = s.prefix(maxChars * 3 / 4)
        let tail = s.suffix(maxChars / 4)
        return "\(head)\n\n[... truncated ...]\n\n\(tail)"
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "heic": "image/heic"
        default: "application/octet-stream"
        }
    }
}
