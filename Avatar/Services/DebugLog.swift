import Foundation

/// Debug-only console logger. The autoclosure keeps string interpolation
/// out of Release binaries, so `dlog("count=\(arr.count)")` costs nothing
/// when DEBUG is undefined.
@inline(__always)
func dlog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
