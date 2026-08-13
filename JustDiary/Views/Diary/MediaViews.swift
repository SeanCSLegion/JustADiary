import SwiftUI
import UIKit
import PhotosUI

struct PreviewItem: Identifiable {
    let id = UUID()
    var src: String
    var ratio: CGFloat
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
