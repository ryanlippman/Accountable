import SwiftUI
import UIKit
import Vision
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

/// Reads the text in photos, screenshots and scanned pages, on the device.
enum TextScanner {
    /// Text from every image, top to bottom, one line per printed line.
    static func read(_ images: [UIImage]) async -> String {
        var pages: [String] = []
        for image in images {
            if let text = await read(image), !text.isEmpty { pages.append(text) }
        }
        return pages.joined(separator: "\n\n")
    }

    private static func read(_ image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
                try? handler.perform([request])
                let obs = request.results ?? []
                // Reading order: rows top to bottom, then left to right within a row.
                let lines = obs
                    .compactMap { o -> (CGRect, String)? in
                        guard let s = o.topCandidates(1).first?.string else { return nil }
                        return (o.boundingBox, s)
                    }
                    .sorted { a, b in
                        if abs(a.0.midY - b.0.midY) > min(a.0.height, b.0.height) * 0.5 { return a.0.midY > b.0.midY }
                        return a.0.minX < b.0.minX
                    }
                    .map { $0.1 }
                c.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

#if !targetEnvironment(macCatalyst)
/// Apple's document camera: finds the page edges, flattens it and cleans it up. Great for whiteboards and handouts.
struct DocumentScanner: UIViewControllerRepresentable {
    let done: ([UIImage]) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done([]) }
    }
}
#else
/// The document camera needs a phone or tablet. On the Mac, use photos and screenshots instead.
struct DocumentScanner: View {
    let done: ([UIImage]) -> Void
    static var isAvailable: Bool { false }
    var body: some View { EmptyView() }
}
#endif
