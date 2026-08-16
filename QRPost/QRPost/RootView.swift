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
                ReceiveView()
            }
        }
        .tint(QP.ColorToken.accent)
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
