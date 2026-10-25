import Observation
import QuartzCore
import UIKit

/// Autoscroll som i OnSong: låten scrollar i jämn takt så att hela låten passerar på
/// låtens längd. Fungerar på alla låttyper eftersom den styr vyns UIScrollView direkt.
@MainActor
@Observable
final class Autoscroller {
    private(set) var isRunning = false
    /// Hur långt låten har kommit, 0–1 (ringen runt knappen).
    private(set) var progress: Double = 0
    /// Låtens längd i sekunder.
    var duration: TimeInterval = 180

    @ObservationIgnored private weak var scrollView: UIScrollView?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var linkTarget: DisplayLinkTarget?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    /// Exakt position (bråkdelar av punkter) så att långsam scroll blir jämn.
    @ObservationIgnored private var position: CGFloat = 0

    func attach(_ scrollView: UIScrollView) {
        guard scrollView !== self.scrollView else { return }
        stop()
        self.scrollView = scrollView
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateProgress()
            }
        }
        updateProgress()
    }

    func detach() {
        stop()
        observation = nil
        scrollView = nil
        progress = 0
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard let scrollView, maxOffset(scrollView) > minOffset(scrollView) else { return }
        // Står låten redan i slutet börjar den om från början.
        if progress >= 0.995 {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: minOffset(scrollView)), animated: false)
        }
        position = scrollView.contentOffset.y
        lastTimestamp = 0
        let target = DisplayLinkTarget { [weak self] link in
            MainActor.assumeIsolated {
                self?.tick(link)
            }
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        linkTarget = target
        isRunning = true
    }

    func stop() {
        link?.invalidate()
        link = nil
        linkTarget = nil
        isRunning = false
    }

    /// En skärmsida framåt (pedal/tangentbord). Returnerar false om låten redan är slut.
    func page(forward: Bool) -> Bool {
        guard let scrollView else { return false }
        let page = scrollView.bounds.height * 0.85
        let current = scrollView.contentOffset.y
        let minY = minOffset(scrollView)
        let maxY = maxOffset(scrollView)
        if forward && current >= maxY - 2 { return false }
        if !forward && current <= minY + 2 { return false }
        let target = forward ? min(maxY, current + page) : max(minY, current - page)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: true)
        position = target
        return true
    }

    private func tick(_ link: CADisplayLink) {
        guard let scrollView else {
            stop()
            return
        }
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0 else { return }
        // Medan fingret håller i låten väntar autoscrollen och fortsätter sedan därifrån.
        if scrollView.isTracking || scrollView.isDecelerating {
            position = scrollView.contentOffset.y
            return
        }
        if abs(scrollView.contentOffset.y - position) > 1 {
            position = scrollView.contentOffset.y
        }
        let minY = minOffset(scrollView)
        let maxY = maxOffset(scrollView)
        let speed = (maxY - minY) / CGFloat(max(duration, 1))
        position = min(maxY, position + speed * CGFloat(link.timestamp - lastTimestamp))
        scrollView.contentOffset.y = position
        if position >= maxY {
            stop()
        }
    }

    private func updateProgress() {
        guard let scrollView else {
            progress = 0
            return
        }
        let range = maxOffset(scrollView) - minOffset(scrollView)
        progress = range > 0 ? Double(min(1, max(0, (scrollView.contentOffset.y - minOffset(scrollView)) / range))) : 0
    }

    private func minOffset(_ scrollView: UIScrollView) -> CGFloat {
        -scrollView.adjustedContentInset.top
    }

    private func maxOffset(_ scrollView: UIScrollView) -> CGFloat {
        max(minOffset(scrollView), scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
    }
}

/// CADisplayLink kräver ett Objective-C-objekt som mål.
private final class DisplayLinkTarget: NSObject {
    let handler: (CADisplayLink) -> Void

    init(handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
    }

    @objc func tick(_ link: CADisplayLink) {
        handler(link)
    }
}
