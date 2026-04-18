import Foundation

/// 免费 Apple ID 开发者证书到期天数计算（Phase 1 Tail · T1.2）。
///
/// 免费开发者证书的 provisioning profile 生命周期为 7 天。App bundle 的
/// 创建时间（文件系统 `.creationDate`）大致对应本次部署/签名时刻。我们据此
/// 估算"还剩几天需要重新插回 Mac 部署"。
///
/// 不是严格意义上的证书有效期判断——真实的 profile 过期时间只在解 mobile-
/// provision 文件里才精确。但对自用 app、免费账号、固定 7 天周期，此近似足够。
enum CertExpiry {

    /// 免费证书标称的有效天数。
    static let totalDays: Int = 7

    /// 用 `Bundle.main` 的创建时间推算，返回当前剩余的"日历天数"（向下取整；最小 0）。
    /// 如果拿不到 creationDate（极罕见，如裸跑在 Simulator 上某些情况下），返回 nil。
    static func remainingDays(now: Date = Date()) -> Int? {
        guard let created = bundleCreationDate() else { return nil }
        let elapsed = now.timeIntervalSince(created)
        let remain = Double(totalDays) - elapsed / 86_400.0
        if remain < 0 { return 0 }
        return Int(remain.rounded(.down))
    }

    /// 读取 app bundle 的创建时间（文件系统元数据）。
    static func bundleCreationDate() -> Date? {
        let bundleURL = Bundle.main.bundleURL
        let attrs = try? FileManager.default.attributesOfItem(atPath: bundleURL.path)
        if let d = attrs?[.creationDate] as? Date {
            return d
        }
        // 旧 API 兼容：有时 Bundle.main.bundlePath 走 NSFileCreationDate
        if let d = attrs?[FileAttributeKey.creationDate] as? Date {
            return d
        }
        return nil
    }

    /// 给 UI 用的简短提示字符串。
    static func shortStatus(now: Date = Date()) -> String {
        if let d = remainingDays(now: now) {
            return "证书剩余 \(d) 天"
        }
        return "证书状态未知"
    }

    /// 是否应该在首页显示黄色 banner（剩余 ≤ 2 天）。
    static func shouldWarnOnHome(now: Date = Date()) -> Bool {
        guard let d = remainingDays(now: now) else { return false }
        return d <= 2
    }
}
