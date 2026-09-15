import Foundation
import os

nonisolated enum Log {
    static let app = Logger(subsystem: "com.cov.justdiary", category: "app")
    static let db = Logger(subsystem: "com.cov.justdiary", category: "db")
    static let backup = Logger(subsystem: "com.cov.justdiary", category: "backup")
    static let location = Logger(subsystem: "com.cov.justdiary", category: "location")
    static let editor = Logger(subsystem: "com.cov.justdiary", category: "editor")
    static let map = Logger(subsystem: "com.cov.justdiary", category: "map")
    static let search = Logger(subsystem: "com.cov.justdiary", category: "search")
}
