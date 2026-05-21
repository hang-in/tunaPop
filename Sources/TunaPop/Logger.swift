import Foundation
import os

enum Log {
    private static let subsystem = "app.tunapop"

    static let selection = os.Logger(subsystem: subsystem, category: "selection")
    static let popup = os.Logger(subsystem: subsystem, category: "popup")
    static let network = os.Logger(subsystem: subsystem, category: "network")
    static let permissions = os.Logger(subsystem: subsystem, category: "permissions")
    static let system = os.Logger(subsystem: subsystem, category: "system")

    static var isVerbose: Bool {
        UserDefaults.standard.bool(forKey: "verboseLogging")
    }

    static func setVerbose(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "verboseLogging")
    }
}
