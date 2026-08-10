import Foundation

/// A unique path in a scratch directory that does not exist yet, for tests that
/// need somewhere to write output. The parent directory is created because
/// `FileManager.replaceItemAt` requires it to exist even though the destination
/// itself need not.
func tempURL() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("UnlatchTests", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")
}
