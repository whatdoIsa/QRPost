import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QRPostCore

struct SendView: View {
    @State private var model = SendModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingFile = false
    @State private var isStreaming = false

    var body: some View {
        NavigationStack {
            VStack(spacing: QP.Spacing.md) {
                Spacer()
                if let payload = model.payload {
                    selectedFileCard(payload)
                    if model.hasQualityChoice {
                        qualityPicker
                    }
                } else {
                    filePickerArea
                }
                Spacer()
                if model.payload != nil {
                    Button("재생 시작") {
                        model.startStreaming()
                        isStreaming = true
                    }
                    .buttonStyle(QPPrimaryButtonStyle())
                    .padding(.horizontal, QP.Spacing.md)
                    .padding(.bottom, QP.Spacing.sm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(QP.ColorToken.background)
            .navigationTitle("큐알포스트")
            .fullScreenCover(isPresented: $isStreaming) {
                if let session = model.activeSession {
                    QRStreamView(session: session)
                }
            }
            .alert("보낼 수 없어요", isPresented: .init(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                await model.load(photoItem: photoItem)
            }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.item]) { result in
            model.load(fileResult: result)
        }
    }

    // MARK: - 파일 선택

    private var filePickerArea: some View {
        VStack(spacing: QP.Spacing.md) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(QP.ColorToken.accent)
            Text("파일 선택")
                .font(.body.weight(.medium))
                .foregroundStyle(QP.ColorToken.textPrimary)
            Text("사진 · 영상 · 모든 파일 (최대 64MB)")
                .font(.footnote)
                .foregroundStyle(QP.ColorToken.textSecondary)
            HStack(spacing: QP.Spacing.sm) {
                PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) {
                    Label("사진 보관함", systemImage: "photo.on.rectangle")
                }
                Button {
                    isImportingFile = true
                } label: {
                    Label("파일", systemImage: "folder")
                }
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.bordered)
            .tint(QP.ColorToken.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(QP.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: QP.Radius.sheet))
        .overlay(
            RoundedRectangle(cornerRadius: QP.Radius.sheet)
                .strokeBorder(QP.ColorToken.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .padding(.horizontal, QP.Spacing.md)
    }

    private func selectedFileCard(_ payload: SendModel.Payload) -> some View {
        HStack(spacing: QP.Spacing.sm + 4) {
            Image(systemName: payload.isImage ? "photo" : "doc")
                .font(.system(size: 20))
                .foregroundStyle(QP.ColorToken.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(payload.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(QP.ColorToken.textPrimary)
                    .lineLimit(1)
                Text(SendModel.formatBytes(payload.data.count))
                    .font(.footnote)
                    .qpMetric()
                    .foregroundStyle(QP.ColorToken.textSecondary)
            }
            Spacer()
            Button {
                model.clearPayload()
                photoItem = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(QP.ColorToken.textSecondary)
                    .frame(width: QP.minTapTarget, height: QP.minTapTarget)
            }
            .accessibilityLabel("파일 선택 취소")
        }
        .padding(QP.Spacing.md)
        .background(QP.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: QP.Radius.card))
        .padding(.horizontal, QP.Spacing.md)
    }

    // MARK: - 화질 선택

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: QP.Spacing.sm) {
            Text("화질 선택")
                .font(.footnote)
                .foregroundStyle(QP.ColorToken.textSecondary)
                .padding(.horizontal, 2)
            ForEach(SendModel.Quality.allCases) { quality in
                qualityOption(quality)
            }
        }
        .padding(.horizontal, QP.Spacing.md)
    }

    private func qualityOption(_ quality: SendModel.Quality) -> some View {
        let isSelected = model.quality == quality
        return Button {
            model.quality = quality
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(QP.ColorToken.textPrimary)
                    if let bytes = model.byteCount(for: quality), let seconds = model.estimatedSeconds(for: quality) {
                        Text("\(SendModel.formatBytes(bytes)) · \(SendModel.formatDuration(seconds))")
                            .font(.footnote)
                            .qpMetric()
                            .foregroundStyle(QP.ColorToken.textSecondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(QP.ColorToken.accent)
                }
            }
            .padding(QP.Spacing.md)
            .background(isSelected ? QP.ColorToken.surface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: QP.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: QP.Radius.card)
                    .strokeBorder(
                        isSelected ? QP.ColorToken.accent : QP.ColorToken.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

}

#Preview {
    SendView()
        .preferredColorScheme(.dark)
}
