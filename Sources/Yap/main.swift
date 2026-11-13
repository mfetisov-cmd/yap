import Foundation

// Fixed launcher; the app itself is YapCore. The downloadable app carries YapCore inside the bundle, in
// Contents/Frameworks. The developer install made by build.sh has no copy inside and loads it from Application
// Support, so a rebuild replaces only that library and macOS keeps the microphone and Accessibility permissions,
// which it ties to this binary.
let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent("YapCore.dylib").path
let installed = NSString(string: "~/Library/Application Support/Yap/YapCore.dylib").expandingTildeInPath
let library = bundled.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil } ?? installed
guard let handle = dlopen(library, RTLD_NOW), let entry = dlsym(handle, "yap_run") else {
    let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
    fatalError("Yap: cannot load \(library): \(reason)")
}
typealias Run = @convention(c) () -> Void
unsafeBitCast(entry, to: Run.self)()
