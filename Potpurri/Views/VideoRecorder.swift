import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Rec-knappen: öppnar kameran för film direkt (fram- eller bakkamera väljs i kameran).
/// Filmen sparas i Bilder.
struct RecordButton: View {
    @State private var recording = false
    @State private var message: String?
    @AppStorage(Feature.record.key) private var enabled = true

    var body: some View {
        if enabled { button }
    }

    private var button: some View {
        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                recording = true
            } else {
                message = "Kameran går inte att använda på den här enheten."
            }
        } label: {
            Image(systemName: "record.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spela in film")
        .fullScreenCover(isPresented: $recording) {
            VideoRecorder { saved in
                recording = false
                if saved { message = "Filmen är sparad i Bilder." }
            }
            .ignoresSafeArea()
        }
        .alert("Rec", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

/// iPadens egen kamera i filmläge.
private struct VideoRecorder: UIViewControllerRepresentable {
    /// true = en film spelades in och sparades.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 60 * 60
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            var saved = false
            if let url = info[.mediaURL] as? URL, UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(url.path) {
                UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
                saved = true
            }
            onFinish(saved)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(false)
        }
    }
}
