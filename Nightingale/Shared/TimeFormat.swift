import Foundation

enum TimeFormat {
    /// 把秒数格式化成 "m:ss" 或 "h:mm:ss"，负数返回 "0:00"。
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
