import SwiftUI

/// 비컨(Beacon) 디자인 토큰 — docs/디자인-가이드.md 2장 참조.
/// 색·간격·모서리는 반드시 이 토큰을 통해서만 사용한다.
enum QP {
    enum ColorToken {
        static let background = Color("QPBackground")
        static let surface = Color("QPSurface")
        static let surfaceHigh = Color("QPSurfaceHigh")
        static let accent = Color("QPAccent")
        static let textPrimary = Color("QPTextPrimary")
        static let textSecondary = Color("QPTextSecondary")
        static let border = Color("QPBorder")
        // 파괴적 액션(중단·취소)은 시스템 red를 버튼 role로 사용 — 별도 토큰 없음
    }

    /// 8pt 그리드 간격
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let card: CGFloat = 12
        static let sheet: CGFloat = 18
        /// CTA는 캡슐 — 높이 50pt 기준
        static let capsule: CGFloat = 25
    }

    /// 최소 터치 타깃 (HIG)
    static let minTapTarget: CGFloat = 44
}

extension Text {
    /// 계기판 숫자 스타일 — %, KB/s, 블록 수, 경과 시간에 적용
    func qpMetric() -> Text {
        self.monospacedDigit()
    }
}

/// 앰버 CTA 캡슐 버튼 — 화면당 1개만 사용 (프로미넌트 규칙)
struct QPPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(QP.ColorToken.accent)
            .foregroundStyle(QP.ColorToken.background)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// 보조 버튼 — 테두리형
struct QPSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(QP.ColorToken.textPrimary)
            .overlay(Capsule().strokeBorder(QP.ColorToken.border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
