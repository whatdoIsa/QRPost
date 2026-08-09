import UIKit

/// 시스템 의미 그대로만 사용한다: 완료 = success, 실패 = error
/// (다른 의미로 재사용 금지 — 디자인 가이드 5-5)
@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
