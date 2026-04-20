import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

// MARK: - PHPickerView
// Verwendet PHPickerViewController (iOS 14+) — benötigt KEINE Foto-Bibliothek-Berechtigung.
// Die Kamera-Option fragt erst beim Tippen auf "Foto aufnehmen".

struct ImagePickerView: UIViewControllerRepresentable {

    @Binding var image: UIImage?
    @Binding var isPresented: Bool
    var sourceType: UIImagePickerController.SourceType = .photoLibrary

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        if sourceType == .camera {
            // Kamera: AVCaptureDevice-Permission wird hier erst angefragt
            return makeCameraController(context: context)
        } else {
            // Foto-Bibliothek: PHPicker — keine Permission erforderlich
            return makePhotoPickerController(context: context)
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // MARK: - PHPicker (Bibliothek)

    private func makePhotoPickerController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    // MARK: - Kamera

    private func makeCameraController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            // Kein Kamera-Gerät (Simulator) → Bibliothek als Fallback
            return makePhotoPickerController(context: context)
        }
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.cameraDevice = .front
        return picker
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             PHPickerViewControllerDelegate,
                             UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {

        private let parent: ImagePickerView

        init(_ parent: ImagePickerView) { self.parent = parent }

        // PHPicker callback — Bild ZUERST laden, DANACH dismiss.
        // Andernfalls würde der Coordinator mit dem Sheet freigegeben, bevor
        // `provider.loadObject` seinen async-Callback feuert → Bild landet nie in der Binding.
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                parent.isPresented = false
                return
            }
            // Strong capture von self ist hier bewusst — hält den Coordinator so lange
            // am Leben bis das Bild angekommen ist.
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.parent.image = object as? UIImage
                    self.parent.isPresented = false
                }
            }
        }

        // UIImagePickerController callback (Kamera)
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let key: UIImagePickerController.InfoKey =
                info[.editedImage] != nil ? .editedImage : .originalImage
            parent.image = info[key] as? UIImage
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
