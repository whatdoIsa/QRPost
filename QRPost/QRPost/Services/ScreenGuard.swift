import UIKit

/// QR 재생 중 화면 조건 고정: 밝기 최대, 자동 잠금 방지.
/// 인식률은 화면 밝기에 직접 의존한다 (디자인 가이드 5-3)
@MainActor
enum ScreenGuard {
    private static var savedBrightness: CGFloat?

    static func engage() {
        let screen = activeScreen
        if savedBrightness == nil {
            savedBrightness = screen?.brightness
        }
        screen?.brightness = 1.0
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        if let savedBrightness {
            activeScreen?.brightness = savedBrightness
        }
        savedBrightness = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private static var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen
    }
}
