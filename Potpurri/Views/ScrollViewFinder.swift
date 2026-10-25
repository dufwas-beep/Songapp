import SwiftUI
import UIKit

/// Hittar den UIScrollView som en SwiftUI-ScrollView bygger på, så att autoscroll och
/// pedalen kan styra den. Läggs som bakgrund inne i ScrollView-innehållet.
struct ScrollViewFinder: UIViewRepresentable {
    let onFound: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.onFound = onFound
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {
        view.onFound = onFound
    }

    final class FinderView: UIView {
        var onFound: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                var view = self?.superview
                while let current = view {
                    if let scrollView = current as? UIScrollView {
                        self?.onFound?(scrollView)
                        return
                    }
                    view = current.superview
                }
            }
        }
    }
}
