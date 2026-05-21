import AppKit
import Foundation

enum ActionBarPosition: String, CaseIterable, Codable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    func origin(forAnchor anchor: CGPoint, barSize: CGSize, offset: CGFloat = 12) -> CGPoint {
        let raw: CGPoint
        switch self {
        case .topRight:
            raw = CGPoint(x: anchor.x + offset, y: anchor.y + offset)
        case .top:
            raw = CGPoint(x: anchor.x - barSize.width / 2, y: anchor.y + offset)
        case .topLeft:
            raw = CGPoint(x: anchor.x - barSize.width - offset, y: anchor.y + offset)
        case .right:
            raw = CGPoint(x: anchor.x + offset, y: anchor.y - barSize.height / 2)
        case .left:
            raw = CGPoint(x: anchor.x - barSize.width - offset, y: anchor.y - barSize.height / 2)
        case .bottomRight:
            raw = CGPoint(x: anchor.x + offset, y: anchor.y - barSize.height - offset)
        case .bottom:
            raw = CGPoint(x: anchor.x - barSize.width / 2, y: anchor.y - barSize.height - offset)
        case .bottomLeft:
            raw = CGPoint(x: anchor.x - barSize.width - offset, y: anchor.y - barSize.height - offset)
        }

        guard let visible = NSScreen.main?.visibleFrame else { return raw }
        let margin: CGFloat = 12
        let minX = visible.minX + margin
        let maxX = visible.maxX - barSize.width - margin
        let minY = visible.minY + margin
        let maxY = visible.maxY - barSize.height - margin
        let clampedX = min(max(raw.x, minX), max(minX, maxX))
        let clampedY = min(max(raw.y, minY), max(minY, maxY))
        return CGPoint(x: clampedX, y: clampedY)
    }
}
