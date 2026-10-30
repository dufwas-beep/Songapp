import UIKit

/// Lager som ligger inne i låtbladets UIScrollView, så att markeringarna och det man ritat
/// scrollar och zoomar med låten. Positioner sparas i förhållande till bladets bredd.
@MainActor
final class AnnotationOverlay: UIView {
    struct HighlightItem: Equatable {
        let id: UUID
        let colorHex: String
        let x, y, width, height: Double
    }

    /// Ett streck från pennan. Punkterna (x, y, x, y …) och tjockleken i förhållande till
    /// bladets bredd.
    struct StrokeItem: Equatable {
        let id: UUID
        let colorHex: String
        let lineWidth: Double
        let points: [Double]
    }

    enum Pen: Equatable {
        case off
        /// Markeringspennan: raka, genomskinliga markeringar över en rad.
        case color(String)
        /// Pennan: rita fritt.
        case ink(String)
        case eraser
    }

    /// Pennans tjocklek i förhållande till bladets bredd.
    static let inkWidth = 0.0035

    var onAddHighlight: ((String, Double, Double, Double, Double) -> Void)?
    var onEraseHighlight: ((UUID) -> Void)?
    var onAddStroke: ((String, Double, [Double]) -> Void)?
    var onEraseStroke: ((UUID) -> Void)?

    private weak var scrollView: UIScrollView?
    private var sizeObservation: NSKeyValueObservation?
    private var offsetObservation: NSKeyValueObservation?
    private var highlights: [HighlightItem] = []
    private var highlightViews: [UUID: UIView] = [:]
    private var strokes: [StrokeItem] = []
    private var strokeLayers: [UUID: CAShapeLayer] = [:]
    private var pen: Pen = .off
    /// Suddets radie i punkter.
    private var eraserRadius: CGFloat = 22
    private let drawingView = UIView()
    private var drawStart: CGPoint?
    /// Strecket som ritas just nu (i lagrets punkter).
    private let liveInk = CAShapeLayer()
    private var livePoints: [CGPoint] = []
    /// Ringen som visar var suddet tar.
    private let eraserRing = UIView()
    /// Det som redan suddats under det här draget (så att det bara tas bort en gång).
    private var erased: Set<UUID> = []
    private lazy var penGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePen(_:)))

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        drawingView.isUserInteractionEnabled = false
        drawingView.layer.cornerRadius = 3
        drawingView.isHidden = true
        addSubview(drawingView)
        liveInk.fillColor = nil
        liveInk.lineCap = .round
        liveInk.lineJoin = .round
        layer.addSublayer(liveInk)
        eraserRing.isUserInteractionEnabled = false
        eraserRing.isHidden = true
        eraserRing.layer.borderWidth = 2
        eraserRing.layer.borderColor = UIColor.systemGray.cgColor
        eraserRing.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        addSubview(eraserRing)
        addGestureRecognizer(penGesture)
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

    func update(highlights: [HighlightItem], strokes: [StrokeItem], pen: Pen, eraserRadius: CGFloat) {
        keepOnTop()
        self.eraserRadius = eraserRadius
        if pen != self.pen {
            self.pen = pen
            applyPen()
        }
        var changed = false
        if highlights != self.highlights {
            changed = true
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
        }
        if strokes != self.strokes {
            changed = true
            self.strokes = strokes
            for (id, shape) in strokeLayers where !strokes.contains(where: { $0.id == id }) {
                shape.removeFromSuperlayer()
                strokeLayers[id] = nil
            }
            for item in strokes where strokeLayers[item.id] == nil {
                strokeLayers[item.id] = makeStrokeLayer(item)
            }
        }
        if changed { layoutItems() }
    }

    /// Strecket ritas i bladets enheter (0–1) och skalas sedan till bladets bredd, så att
    /// det följer med när man zoomar.
    private func makeStrokeLayer(_ item: StrokeItem) -> CAShapeLayer {
        let shape = CAShapeLayer()
        let path = UIBezierPath()
        var index = 0
        while index + 1 < item.points.count {
            let point = CGPoint(x: item.points[index], y: item.points[index + 1])
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            index += 2
        }
        if item.points.count == 2 {
            // En prick.
            path.addLine(to: CGPoint(x: item.points[0] + 0.0001, y: item.points[1]))
        }
        shape.path = path.cgPath
        shape.strokeColor = UIColor(hex: item.colorHex).cgColor
        shape.fillColor = nil
        shape.lineWidth = CGFloat(item.lineWidth)
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.anchorPoint = .zero
        shape.position = .zero
        shape.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.insertSublayer(shape, below: liveInk)
        return shape
    }

    private func layoutItems() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in highlights {
            guard let view = highlightViews[item.id] else { continue }
            view.frame = CGRect(x: item.x * unit, y: item.y * unit, width: item.width * unit, height: item.height * unit)
            view.backgroundColor = UIColor(hex: item.colorHex).withAlphaComponent(0.45)
        }
        for shape in strokeLayers.values {
            shape.setAffineTransform(CGAffineTransform(scaleX: unit, y: unit))
        }
        CATransaction.commit()
        bringSubviewToFront(drawingView)
        bringSubviewToFront(eraserRing)
    }

    // MARK: Pennan

    private func applyPen() {
        let drawing = pen != .off
        // Markeringspennan går på draget; pennan och suddet följer fingret direkt.
        if case .color = pen { penGesture.isEnabled = true } else { penGesture.isEnabled = false }
        // Med pennan på scrollar man med två fingrar; ett finger ritar.
        scrollView?.panGestureRecognizer.minimumNumberOfTouches = drawing ? 2 : 1
        liveInk.path = nil
        livePoints = []
        eraserRing.isHidden = true
    }

    /// Med pennan på tar lagret emot alla tryck; annars går de igenom till låten.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        pen != .off && bounds.contains(point) ? self : nil
    }

    @objc private func handlePen(_ gesture: UIPanGestureRecognizer) {
        guard case .color(let hex) = pen else { return }
        let point = gesture.location(in: self)
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
    }

    // MARK: Rita och sudda med fingret

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        switch pen {
        case .ink(let hex):
            livePoints = [point]
            liveInk.strokeColor = UIColor(hex: hex).cgColor
            liveInk.lineWidth = CGFloat(Self.inkWidth) * unit
            redrawLive()
        case .eraser:
            erased = []
            showEraser(at: point)
            erase(at: point)
        default:
            super.touchesBegan(touches, with: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        switch pen {
        case .ink:
            // Apple Pencil och snabba drag ger fler punkter än skärmen hinner rita.
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                let point = sample.location(in: self)
                if let last = livePoints.last, hypot(point.x - last.x, point.y - last.y) < 1.5 { continue }
                livePoints.append(point)
            }
            redrawLive()
        case .eraser:
            let point = touch.location(in: self)
            showEraser(at: point)
            erase(at: point)
        default:
            super.touchesMoved(touches, with: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch pen {
        case .ink(let hex):
            if !livePoints.isEmpty {
                let points = livePoints.flatMap { [Double($0.x / unit), Double($0.y / unit)] }
                onAddStroke?(hex, Self.inkWidth, points)
            }
            livePoints = []
            liveInk.path = nil
        case .eraser:
            eraserRing.isHidden = true
        default:
            super.touchesEnded(touches, with: event)
        }
    }

    /// T.ex. när två fingrar börjar scrolla: det påbörjade strecket slängs.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        livePoints = []
        liveInk.path = nil
        eraserRing.isHidden = true
        super.touchesCancelled(touches, with: event)
    }

    private func redrawLive() {
        let path = UIBezierPath()
        for (index, point) in livePoints.enumerated() {
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if livePoints.count == 1, let point = livePoints.first {
            path.addLine(to: CGPoint(x: point.x + 0.1, y: point.y))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liveInk.path = path.cgPath
        CATransaction.commit()
    }

    private func showEraser(at point: CGPoint) {
        eraserRing.isHidden = false
        eraserRing.frame = CGRect(x: point.x - eraserRadius, y: point.y - eraserRadius, width: eraserRadius * 2, height: eraserRadius * 2)
        eraserRing.layer.cornerRadius = eraserRadius
        bringSubviewToFront(eraserRing)
    }

    /// Tar bort markeringar och streck som suddet rör.
    private func erase(at point: CGPoint) {
        for (id, view) in highlightViews where !erased.contains(id) && view.frame.insetBy(dx: -eraserRadius, dy: -eraserRadius).contains(point) {
            erased.insert(id)
            onEraseHighlight?(id)
        }
        for item in strokes where !erased.contains(item.id) && reaches(item, point) {
            erased.insert(item.id)
            onEraseStroke?(item.id)
        }
    }

    /// Rör suddet vid strecket? Avståndet mäts till varje del av strecket.
    private func reaches(_ item: StrokeItem, _ point: CGPoint) -> Bool {
        let reach = eraserRadius + CGFloat(item.lineWidth) * unit / 2
        let p = CGPoint(x: point.x / unit, y: point.y / unit)
        let limit = reach / unit
        var previous: CGPoint?
        var index = 0
        while index + 1 < item.points.count {
            let current = CGPoint(x: item.points[index], y: item.points[index + 1])
            if Self.distance(from: p, to: previous ?? current, current) <= limit { return true }
            previous = current
            index += 2
        }
        return false
    }

    private static func distance(from p: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
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
