import SwiftUI

/// 全局颜色 / 字号常量。深色夜用风格。
enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.08)
    static let surfaceElevated = Color(white: 0.14)
    static let accent = Color(red: 0.55, green: 0.72, blue: 1.0)
    static let accentSecondary = Color(red: 0.85, green: 0.72, blue: 1.0)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    static let textTertiary = Color(white: 0.45)
    static let danger = Color(red: 1.0, green: 0.45, blue: 0.45)

    static let cornerRadius: CGFloat = 14
    static let padding: CGFloat = 16
}
