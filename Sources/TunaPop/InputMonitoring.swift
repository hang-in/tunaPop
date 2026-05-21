import Foundation
import IOKit.hid

// Input Monitoring 권한은 v1에서 사용하지 않습니다.
// Phase 11에서 pasteboard fallback 재도입 시 다시 활성화합니다.
// IOHIDCheckAccess는 .accessory + swift run 환경에서 부정확한 값을
// 반환하는 macOS Tahoe 버그가 있어 UI에서 제거된 상태입니다.
enum InputMonitoring {
    static var isTrusted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
