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
                SendPlaceholderView()
            }
            Tab("받기", systemImage: "qrcode.viewfinder") {
                ReceivePlaceholderView()
            }
        }
        .tint(QP.ColorToken.accent)
    }
}

struct SendPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                VStack(spacing: QP.Spacing.sm) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 26))
                        .foregroundStyle(QP.ColorToken.accent)
                    Text("파일 선택")
                        .font(.body.weight(.medium))
                        .foregroundStyle(QP.ColorToken.textPrimary)
                    Text("사진 · 영상 · 모든 파일 (최대 64MB)")
                        .font(.footnote)
                        .foregroundStyle(QP.ColorToken.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(QP.ColorToken.surface)
                .clipShape(RoundedRectangle(cornerRadius: QP.Radius.card + 4))
                .overlay(
                    RoundedRectangle(cornerRadius: QP.Radius.card + 4)
                        .strokeBorder(QP.ColorToken.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .padding(.horizontal, QP.Spacing.md)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(QP.ColorToken.background)
            .navigationTitle("큐알포스트")
        }
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
