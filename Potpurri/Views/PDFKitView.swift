import PDFKit
import SwiftUI

/// Visar en PDF som en lång vertikal vy där alla sidor följer på varandra.
struct PDFKitView: UIViewRepresentable {
    let url: URL
    var onScrollView: ((UIScrollView) -> Void)?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .systemBackground
        view.document = PDFCache.shared.document(for: url)
        reportScrollView(of: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFCache.shared.document(for: url)
            reportScrollView(of: view)
        }
    }

    /// PDFView har en egen UIScrollView inuti; den används av autoscroll och pedalen.
    private func reportScrollView(of view: PDFView) {
        guard let onScrollView else { return }
        DispatchQueue.main.async {
            if let scrollView = Self.findScrollView(in: view) {
                onScrollView(scrollView)
            }
        }
    }

    private static func findScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}
