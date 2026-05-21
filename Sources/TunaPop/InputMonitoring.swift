import IOKit.hid

enum InputMonitoring {
    static var isTrusted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
