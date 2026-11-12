import Foundation
let group = ProcessInfo.processInfo.environment["XTOOL_APP_GROUP_ID"] ?? "group.com.champ.hermes"
guard group == "group.0123456789abcdef" else { fatalError("App Group environment did not propagate") }
print("Swift App Group environment: PASS")
