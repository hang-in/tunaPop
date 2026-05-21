import AppKit
import Foundation

enum SelectionPayload: Equatable, @unchecked Sendable {
    case text(String)
    case image(NSImage)

    var preview: String {
        switch self {
        case .text(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            return "Image selection"
        }
    }
}

extension SelectionPayload {
    var imageBase64PNG: String? {
        guard case .image(let image) = self,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        return png.base64EncodedString()
    }
}
