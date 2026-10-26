import Observation
import UIKit

/// Var låtbladet befinner sig just nu: scrollposition och bladets bredd. Notes och
/// hopplinjer ritas ovanpå bladet utifrån detta, så att de följer låten när den scrollar
/// och zoomas. Positioner sparas i förhållande till bladets bredd ("unit").
@MainActor
@Observable
final class SheetGeometry {
    private(set) var offset: CGPoint = .zero
    private(set) var unit: CGFloat = 1
    private(set) var viewHeight: CGFloat = 0

    @ObservationIgnored private(set) weak var scrollView: UIScrollView?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    func attach(_ scrollView: UIScrollView) {
        guard scrollView !== self.scrollView else { return }
        self.scrollView = scrollView
        observations = [
            scrollView.observe(\.contentOffset, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            },
            scrollView.observe(\.contentSize, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            },
            scrollView.observe(\.bounds, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            }
        ]
        update()
    }

    private func update() {
        guard let scrollView else { return }
        offset = scrollView.contentOffset
        let width = scrollView.contentSize.width > 0 ? scrollView.contentSize.width : scrollView.bounds.width
        unit = max(1, width)
        viewHeight = scrollView.bounds.height
    }

    /// Översta och nedersta synliga punkt i bladet, i förhållande till bredden.
    var visibleTop: Double {
        guard let scrollView else { return 0 }
        return Double(max(0, offset.y + scrollView.adjustedContentInset.top) / unit)
    }

    var visibleBottom: Double {
        Double((offset.y + viewHeight) / unit)
    }

    /// Scrolla så att en punkt i bladet hamnar högst upp på skärmen.
    func scroll(toTop y: Double, animated: Bool = true) {
        guard let scrollView else { return }
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(minY, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
        let target = min(max(CGFloat(y) * unit + minY, minY), maxY)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: animated)
    }
}
