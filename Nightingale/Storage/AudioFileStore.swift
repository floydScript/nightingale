import Foundation

/// 管理录音文件在沙盒中的路径与清理。
/// 声明为 `nonisolated` 因为这是纯文件 IO，需要从任意 context 调用
/// （录音回调、测试、MainActor UI 等）。
nonisolated final class AudioFileStore: @unchecked Sendable {

    private let baseDirectory: URL

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        ensureDirectoryExists(recordingsDirectory)
        ensureDirectoryExists(clipsDirectory)
    }

    /// 用默认 Documents 初始化。生产代码调用这个。
    convenience init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(baseDirectory: docs)
    }

    /// 整夜录音目录。
    var recordingsDirectory: URL {
        baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// 事件片段目录（Phase 1B 新增）。
    var clipsDirectory: URL {
        baseDirectory.appendingPathComponent("Clips", isDirectory: true)
    }

    /// 某个 session 的整夜音频 URL。
    func fullRecordingURL(for sessionID: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(sessionID.uuidString).m4a")
    }

    /// 某个 event 的 clip URL。
    func clipURL(for eventID: UUID) -> URL {
        clipsDirectory.appendingPathComponent("\(eventID.uuidString).m4a")
    }

    /// 从相对路径还原成绝对 URL。
    func url(fromRelativePath relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    /// 把绝对 URL 转成相对路径，用于持久化。
    func relativePath(for url: URL) -> String {
        let basePath = baseDirectory.path
        if url.path.hasPrefix(basePath) {
            return String(url.path.dropFirst(basePath.count).drop(while: { $0 == "/" }))
        }
        return url.path
    }

    /// 当前录音目录总占用字节数（含 clips 目录）。
    func totalBytesUsed() -> Int64 {
        bytesIn(recordingsDirectory) + bytesIn(clipsDirectory)
    }

    /// 清理超过 N 天未修改的整夜录音。保留 archivedIDs 里的文件。返回被删除的 session ID 列表。
    @discardableResult
    func cleanupOldRecordings(olderThan days: Int, archivedIDs: Set<UUID>) throws -> [UUID] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        let files = try FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )

        var removed: [UUID] = []
        for url in files {
            let filename = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: filename) else { continue }
            if archivedIDs.contains(id) { continue }

            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date()
            if modDate < cutoff {
                try FileManager.default.removeItem(at: url)
                removed.append(id)
            }
        }
        return removed
    }

    // MARK: - Private

    private func bytesIn(_ directory: URL) -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    private func ensureDirectoryExists(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
