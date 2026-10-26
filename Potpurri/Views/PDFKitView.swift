import PDFKit
import SwiftUI

/// Visar en PDF som en lång vertikal vy där alla sidor följer på varandra.
/// Zoomen (nyp) sparas i förhållande till "hela bredden" och återställs nästa gång.
struct PDFKitView: UIViewRepresentable {
    let url: URL
    var zoom: Double?
    var onZoom: ((Double) -> Void)?
    var onScrollView: ((UIScrollView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = .systemBackground
        view.document = PDFCache.shared.document(for: url)
        context.coordinator.observe(view, onZoom: onZoom)
        restoreZoom(in: view)
        reportScrollView(of: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onZoom = onZoom
        if view.document?.documentURL != url {
            view.document = PDFCache.shared.document(for: url)
            restoreZoom(in: view)
            reportScrollView(of: view)
        }
    }

    private func restoreZoom(in view: PDFView) {
        guard let zoom, zoom > 0, abs(zoom - 1) > 0.01 else { return }
        DispatchQueue.main.async {
            let fit = view.scaleFactorForSizeToFit
            guard fit > 0 else { return }
            view.autoScales = false
            view.scaleFactor = fit * CGFloat(zoom)
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

    @MainActor
    final class Coordinator: NSObject {
        var onZoom: ((Double) -> Void)?
        private var token: NSObjectProtocol?

        func observe(_ view: PDFView, onZoom: ((Double) -> Void)?) {
            self.onZoom = onZoom
            token = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let view, !view.autoScales else { return }
                    let fit = view.scaleFactorForSizeToFit
                    guard fit > 0 else { return }
                    self?.onZoom?(Double(view.scaleFactor / fit))
                }
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
