import Foundation

/// 免费 Apple ID 开发者证书到期天数（Phase 1 Tail · T1.2）。
///
/// **正确数据源**：app bundle 内嵌的 `embedded.mobileprovision` 文件里的
/// `ExpirationDate` 字段。这才是真实的 provisioning profile 过期时间。
///
/// 原先用 `Bundle.main.bundleURL.creationDate` 推算——在 iOS 真机上这个
/// 值不可靠（常返回 epoch 0 或很久以前），导致过去总是显示"剩余 0 天"。
///
/// Simulator 没有 mobileprovision 文件，在模拟器上 `remainingDays` 会返回 nil。
enum CertExpiry {

    static let totalDays: Int = 7

    /// 解析 embedded.mobileprovision 拿到真实 ExpirationDate；拿不到返回 nil。
    static func expiryDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        // mobileprovision 是 CMS (PKCS#7) 签名包，内嵌 XML plist 作为明文。
        // 找 <?xml ... </plist> 抽出来解析即可。
        guard let xmlStart = "<?xml".data(using: .utf8),
              let xmlEnd = "</plist>".data(using: .utf8),
              let startRange = data.range(of: xmlStart),
              let endRange = data.range(of: xmlEnd, in: startRange.upperBound..<data.count) else {
            return nil
        }

        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }
        return plist["ExpirationDate"] as? Date
    }

    static func remainingDays(now: Date = Date()) -> Int? {
        guard let expiry = expiryDate() else { return nil }
        let remain = expiry.timeIntervalSince(now) / 86_400.0
        if remain < 0 { return 0 }
        return Int(remain.rounded(.down))
    }

    static func shortStatus(now: Date = Date()) -> String {
        if let d = remainingDays(now: now) {
            return "证书剩余 \(d) 天"
        }
        return "证书状态未知（模拟器或非免费证书）"
    }

    static func shouldWarnOnHome(now: Date = Date()) -> Bool {
        guard let d = remainingDays(now: now) else { return false }
        return d <= 2
    }

    /// 保留给老调用点 / 既有测试的 legacy 入口——实际不用于证书判断。
    /// 仅在未来要诊断 bundle 元数据时有用。
    static func bundleCreationDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundleURL.path)
        return attrs?[.creationDate] as? Date
    }
}
