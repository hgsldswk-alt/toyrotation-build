import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit

enum D {
    static let paper = Color(red: 0.984, green: 0.969, blue: 0.945)
    static let card = Color.white
    static let ink = Color(red: 0.176, green: 0.141, blue: 0.110)
    static let muted = Color(red: 0.478, green: 0.416, blue: 0.361)
    static let line = Color(red: 0.918, green: 0.875, blue: 0.824)
    static let coral = Color(red: 0.878, green: 0.404, blue: 0.247)
    static let pale = Color(red: 0.965, green: 0.906, blue: 0.863)
    static let green = Color(red: 0.373, green: 0.604, blue: 0.361)
}

struct PrimaryButton: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(filled ? .white : D.ink)
            .background((filled ? D.coral : D.pale).opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 18))
    }
}

extension View {
    func cardBox() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(D.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(D.line))
    }
}

struct BinPhoto: View {
    let image: UIImage?
    var caption: String = ""
    var height: CGFloat = 92

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [D.pale, D.line], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "shippingbox.fill").font(.title).foregroundStyle(D.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

enum QR {
    static var link: String {
        let id = (Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return id.isEmpty || id.hasPrefix("$") ? "https://hgsldswk-alt.github.io/toyrotation-support/" : "https://apps.apple.com/app/id\(id)"
    }

    static func image() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
