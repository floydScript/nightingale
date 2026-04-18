import XCTest
@testable import Nightingale

final class AudioFileStoreTests: XCTestCase {

    var tempRoot: URL!
    var store: AudioFileStore!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = AudioFileStore(baseDirectory: tempRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testRecordingsURLIsCreated() {
        let url = store.recordingsDirectory
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testFullRecordingURLIncludesID() {
        let id = UUID()
        let url = store.fullRecordingURL(for: id)
        XCTAssertTrue(url.path.hasSuffix("Recordings/\(id.uuidString).m4a"))
    }

    func testCleanupRemovesOldFilesButKeepsArchived() throws {
        let oldID = UUID()
        let newID = UUID()
        let archivedID = UUID()

        let oldURL = store.fullRecordingURL(for: oldID)
        let newURL = store.fullRecordingURL(for: newID)
        let archivedURL = store.fullRecordingURL(for: archivedID)
        for url in [oldURL, newURL, archivedURL] {
            FileManager.default.createFile(atPath: url.path, contents: Data([0x01]))
        }

        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 3600)
        try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: oldURL.path)
        try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: archivedURL.path)

        let removed = try store.cleanupOldRecordings(olderThan: 7, archivedIDs: [archivedID])

        XCTAssertEqual(removed, [oldID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedURL.path))
    }

    func testTotalBytesUsed() {
        let id = UUID()
        let url = store.fullRecordingURL(for: id)
        let data = Data(count: 1024)
        FileManager.default.createFile(atPath: url.path, contents: data)

        XCTAssertEqual(store.totalBytesUsed(), 1024)
    }
}
