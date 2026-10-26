import UIKit

/// Lager som ligger inne i låtbladets UIScrollView, så att markeringarna scrollar och
/// zoomar med låten. Positioner sparas i förhållande till bladets bredd.
@MainActor
final class AnnotationOverlay: UIView {
    struct HighlightItem: Equatable {
        let id: UUID
        let colorHex: String
        let x, y, width, height: Double
    }

    enum Pen: Equatable {
        case off
        case color(String)
        case eraser
    }

    var onAddHighlight: ((String, Double, Double, Double, Double) -> Void)?
    var onEraseHighlight: ((UUID) -> Void)?

    private weak var scrollView: UIScrollView?
    private var sizeObservation: NSKeyValueObservation?
    private var offsetObservation: NSKeyValueObservation?
    private var highlights: [HighlightItem] = []
    private var highlightViews: [UUID: UIView] = [:]
    private var pen: Pen = .off
    private let drawingView = UIView()
    private var drawStart: CGPoint?
    private lazy var penGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePen(_:)))
    private lazy var eraseTap = UITapGestureRecognizer(target: self, action: #selector(handleEraseTap(_:)))

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        drawingView.isUserInteractionEnabled = false
        drawingView.layer.cornerRadius = 3
        drawingView.isHidden = true
        addSubview(drawingView)
        addGestureRecognizer(penGesture)
        addGestureRecognizer(eraseTap)
    }

    required init?(coder: NSCoder) { nil }

    /// Bladets bredd som allt räknas i förhållande till.
    private var unit: CGFloat {
        max(1, bounds.width)
    }

    func attach(to scrollView: UIScrollView) {
        guard scrollView !== self.scrollView else { return }
        removeFromSuperview()
        self.scrollView = scrollView
        scrollView.addSubview(self)
        sizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateFrame() }
        }
        // SwiftUI kan lägga sitt innehåll överst igen; markeringarna ska alltid synas.
        offsetObservation = scrollView.observe(\.contentOffset, options: []) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.keepOnTop() }
        }
        updateFrame()
        applyPen()
    }

    private func keepOnTop() {
        guard let scrollView, scrollView.subviews.last !== self else { return }
        scrollView.bringSubviewToFront(self)
    }

    private func updateFrame() {
        guard let scrollView else { return }
        let size = scrollView.contentSize
        frame = CGRect(x: 0, y: 0, width: size.width > 0 ? size.width : scrollView.bounds.width, height: max(size.height, scrollView.bounds.height))
        scrollView.bringSubviewToFront(self)
        layoutItems()
    }

    func update(highlights: [HighlightItem], pen: Pen) {
        keepOnTop()
        if pen != self.pen {
            self.pen = pen
            applyPen()
        }
        guard highlights != self.highlights else { return }
        self.highlights = highlights
        for (id, view) in highlightViews where !highlights.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            highlightViews[id] = nil
        }
        for item in highlights where highlightViews[item.id] == nil {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.layer.cornerRadius = 3
            insertSubview(view, at: 0)
            highlightViews[item.id] = view
        }
        layoutItems()
    }

    private func layoutItems() {
        for item in highlights {
            guard let view = highlightViews[item.id] else { continue }
            view.frame = CGRect(x: item.x * unit, y: item.y * unit, width: item.width * unit, height: item.height * unit)
            view.backgroundColor = UIColor(hex: item.colorHex).withAlphaComponent(0.45)
        }
        bringSubviewToFront(drawingView)
    }

    // MARK: Pennan

    private func applyPen() {
        let drawing = pen != .off
        penGesture.isEnabled = drawing
        eraseTap.isEnabled = pen == .eraser
        // Med pennan på scrollar man med två fingrar; ett finger ritar.
        scrollView?.panGestureRecognizer.minimumNumberOfTouches = drawing ? 2 : 1
    }

    /// Med pennan på tar lagret emot alla tryck; annars går de igenom till låten.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        pen != .off && bounds.contains(point) ? self : nil
    }

    @objc private func handlePen(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch pen {
        case .eraser:
            erase(at: point)
        case .color(let hex):
            // Ett drag blir alltid en rak, vågrät markering över raden där det började.
            let lineHeight = unit * 0.032
            switch gesture.state {
            case .began:
                drawStart = point
                drawingView.backgroundColor = UIColor(hex: hex).withAlphaComponent(0.45)
                drawingView.isHidden = false
                fallthrough
            case .changed:
                guard let start = drawStart else { return }
                drawingView.frame = CGRect(x: min(start.x, point.x), y: start.y - lineHeight / 2, width: max(abs(point.x - start.x), 4), height: lineHeight)
            case .ended:
                drawingView.isHidden = true
                let rect = drawingView.frame
                if rect.width > 12 {
                    onAddHighlight?(hex, Double(rect.minX / unit), Double(rect.minY / unit), Double(rect.width / unit), Double(rect.height / unit))
                }
                drawStart = nil
            default:
                drawingView.isHidden = true
                drawStart = nil
            }
        case .off:
            break
        }
    }

    @objc private func handleEraseTap(_ gesture: UITapGestureRecognizer) {
        erase(at: gesture.location(in: self))
    }

    private func erase(at point: CGPoint) {
        for (id, view) in highlightViews where view.frame.insetBy(dx: -6, dy: -10).contains(point) {
            onEraseHighlight?(id)
        }
    }
}

extension UIColor {
    /// "FFE873" → färg.
    convenience init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0xFFE873
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
