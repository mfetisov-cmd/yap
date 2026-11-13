import os

/// Yap's own messages, read with `log show --predicate 'subsystem == "local.yap.app"'`. NSLog lines from Yap never
/// reached that log, so its failures were invisible.
let yapLog = Logger(subsystem: "local.yap.app", category: "app")
