//
//  RootView.swift
//  QRPost
//
//  보내기/받기 2탭 루트 — 설정 화면 없음 (기획 확정 사항)
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("보내기", systemImage: "arrow.up.circle.fill") {
                SendView()
            }
            Tab("받기", systemImage: "qrcode.viewfinder") {
                ReceivePlaceholderView()
            }
        }
        .tint(QP.ColorToken.accent)
    }
}

struct ReceivePlaceholderView: View {
    var body: some View {
        VStack(spacing: QP.Spacing.sm) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 42))
                .foregroundStyle(QP.ColorToken.textSecondary)
            Text("상대 화면의 QR에 카메라를 비추면\n자동으로 수신이 시작돼요")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(QP.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QP.ColorToken.background)
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
