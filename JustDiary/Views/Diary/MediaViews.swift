import SwiftUI
import UIKit
import PhotosUI

struct PreviewItem: Identifiable {
    let id = UUID()
    var src: String
    var ratio: CGFloat
}

// MARK: - Diary parts rendering (text chunks + native image views)

struct DiaryImageView: View {
    var src: String
    var displayW: CGFloat
    var displayH: CGFloat
    var onTap: (() -> Void)? = nil

    /// Fills the column, keeping the picture's aspect ratio.
    ///
    /// The width used to be capped at the *stored* width while the surrounding
    /// aspect-ratio box was sized from the column: in landscape the box was as
    /// tall as a full-width picture while the picture stayed portrait-sized, so
    /// an image came out small and centred inside big empty bands. The stored
    /// pair is only the aspect ratio here — the layout decides the width.
    var body: some View {
        Group {
            if let image = DiaryImageStore.shared.image(for: src, maxPixel: max(displayW, displayH) * 3) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.image, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.tap()
                        onTap?()
                    }
            } else {
                // A missing file keeps its slot instead of reflowing the entry.
                Color.clear
            }
        }
        .aspectRatio(max(displayW, 1) / max(displayH, 1), contentMode: .fit)
        .accessibilityAddTraits(.isImage)
    }
}

struct DiaryPartsView: View {
    var parts: [ContentPart]
    var keyword: String = ""
    var onToggleTodo: ((Int, Int) -> Void)? = nil
    var onImageTap: ((String, CGFloat) -> Void)? = nil
    var onTapText: (() -> Void)? = nil

    private struct Chunk: Identifiable {
        var id: Int { offset }
        var parts: [ContentPart]
        var offset: Int
        var image: ContentPart?
    }

    var body: some View {
        let chunks = Self.buildChunks(parts)
        // No stack spacing: every chunk boundary is an image, and an image
        // carries its own spacing (`EditorDesignSize.imageSpacing`) so the
        // reader and the editor share the same rhythm around pictures. A stack
        // gap here would land on top of it.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(chunks) { chunk in
                if let img = chunk.image, let src = img.src {
                    let w = max(1, CGFloat(img.w ?? 300))
                    let h = max(1, CGFloat(img.h ?? 200))
                    DiaryImageView(src: src, displayW: w, displayH: h) {
                        onImageTap?(src, h / w)
                    }
                    .padding(.vertical, EditorDesignSize.imageSpacing)
                } else {
                    ReadTextView(parts: chunk.parts,
                                 keyword: keyword,
                                 onToggleTodo: { pi, ii in onToggleTodo?(pi + chunk.offset, ii) },
                                 onTapText: onTapText,
                                 textContainerInset: UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0))
                }
            }
        }
    }

    private static func buildChunks(_ parts: [ContentPart]) -> [Chunk] {
        var chunks: [Chunk] = []
        var current: [ContentPart] = []
        var currentStart = 0
        for (i, part) in parts.enumerated() {
            if part.style == ContentPartStyle.image {
                if !current.isEmpty {
                    chunks.append(Chunk(parts: current, offset: currentStart, image: nil))
                    current = []
                }
                chunks.append(Chunk(parts: [], offset: i, image: part))
            } else {
                if current.isEmpty { currentStart = i }
                current.append(part)
            }
        }
        if !current.isEmpty {
            chunks.append(Chunk(parts: current, offset: currentStart, image: nil))
        }
        return chunks
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.parent.onPicked(image)
                    }
                }
            }
        }
    }
}

struct ImagePreviewView: View {
    let item: PreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.opacity(max(0, 1 - abs(dragOffset.height) / 600))
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            if let image = DiaryImageStore.shared.image(for: item.src, maxPixel: 1600) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(max(0.6, 1 - abs(dragOffset.height) / 800))
                    .offset(dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                let velocity = value.predictedEndTranslation.height
                                if abs(value.translation.height) > 140 || abs(velocity) > 900 {
                                    dismiss()
                                } else {
                                    withAnimation(.diaryQuick) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    )
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction {
            dismiss()
        }
    }
}
