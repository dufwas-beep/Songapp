import UIKit

/// Lager som ligger inne i låtbladets UIScrollView, så att lappar och markeringar
/// scrollar och zoomar med låten. Positioner sparas i förhållande till bladets bredd.
@MainActor
final class AnnotationOverlay: UIView {
    struct NoteItem: Equatable {
        let id: UUID
        let text: String
        let colorHex: String
        let x, y, width, height: Double
    }

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

    var onMoveNote: ((UUID, Double, Double) -> Void)?
    var onResizeNote: ((UUID, Double, Double) -> Void)?
    var onTapNote: ((UUID) -> Void)?
    var onAddHighlight: ((String, Double, Double, Double, Double) -> Void)?
    var onEraseHighlight: ((UUID) -> Void)?

    private weak var scrollView: UIScrollView?
    private var sizeObservation: NSKeyValueObservation?
    private var notes: [NoteItem] = []
    private var highlights: [HighlightItem] = []
    private var noteViews: [UUID: NoteView] = [:]
    private var highlightViews: [UUID: UIView] = [:]
    private var notesHidden = false
    private var locked = false
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
        updateFrame()
        applyPen()
    }

    private func updateFrame() {
        guard let scrollView else { return }
        let size = scrollView.contentSize
        frame = CGRect(x: 0, y: 0, width: size.width > 0 ? size.width : scrollView.bounds.width, height: max(size.height, scrollView.bounds.height))
        scrollView.bringSubviewToFront(self)
        layoutItems()
    }

    func update(notes: [NoteItem], highlights: [HighlightItem], notesHidden: Bool, locked: Bool, pen: Pen) {
        let changed = notes != self.notes || highlights != self.highlights || notesHidden != self.notesHidden || locked != self.locked
        self.notes = notes
        self.highlights = highlights
        self.notesHidden = notesHidden
        self.locked = locked
        if pen != self.pen {
            self.pen = pen
            applyPen()
        }
        if changed { syncViews() }
    }

    private func syncViews() {
        for (id, view) in noteViews where !notes.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            noteViews[id] = nil
        }
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
        for item in notes {
            let view = noteViews[item.id] ?? makeNoteView(item.id)
            view.isEditable = !locked
            view.configure(text: item.text, color: UIColor(hex: item.colorHex))
            view.isHidden = notesHidden
        }
        layoutItems()
    }

    private func makeNoteView(_ id: UUID) -> NoteView {
        let view = NoteView()
        view.onMoved = { [weak self] frame in
            guard let self else { return }
            self.onMoveNote?(id, Double(frame.minX / self.unit), Double(frame.minY / self.unit))
        }
        view.onResized = { [weak self] frame in
            guard let self else { return }
            self.onResizeNote?(id, Double(frame.width / self.unit), Double(frame.height / self.unit))
        }
        view.onTap = { [weak self] in self?.onTapNote?(id) }
        addSubview(view)
        noteViews[id] = view
        return view
    }

    private func layoutItems() {
        for item in highlights {
            guard let view = highlightViews[item.id] else { continue }
            view.frame = CGRect(x: item.x * unit, y: item.y * unit, width: item.width * unit, height: item.height * unit)
            view.backgroundColor = UIColor(hex: item.colorHex).withAlphaComponent(0.45)
        }
        for item in notes {
            guard let view = noteViews[item.id], !view.isInteracting else { continue }
            view.frame = CGRect(x: item.x * unit, y: item.y * unit, width: item.width * unit, height: item.height * unit)
        }
        bringSubviewToFront(drawingView)
    }

    /// Översta synliga punkten i bladet, i förhållande till bredden (för nya lappar).
    var visibleTop: Double {
        guard let scrollView else { return 0 }
        return Double(max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top) / unit)
    }

    /// Bladets bredd i punkter (för att räkna om lappar mellan "följer sidan" och "fast").
    var contentWidth: CGFloat {
        unit
    }

    // MARK: Pennan

    private func applyPen() {
        let drawing = pen != .off
        penGesture.isEnabled = drawing
        eraseTap.isEnabled = pen == .eraser
        // Med pennan på scrollar man med två fingrar; ett finger ritar.
        scrollView?.panGestureRecognizer.minimumNumberOfTouches = drawing ? 2 : 1
    }

    /// Med pennan på tar lagret emot alla tryck; annars bara lapparna.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if pen != .off { return bounds.contains(point) ? self : nil }
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
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

/// En lapp: dra för att flytta, dra i hörnet för att ändra storlek, tryck för att redigera.
/// Texten krymper eller växer så att allt alltid får plats.
@MainActor
final class NoteView: UIView {
    var onMoved: ((CGRect) -> Void)?
    var onResized: ((CGRect) -> Void)?
    var onTap: (() -> Void)?
    var isEditable = true
    private(set) var isInteracting = false

    private let label = UILabel()
    private let handle = UIView()
    private var text = ""
    private var startFrame = CGRect.zero

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 3)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .black
        addSubview(label)
        handle.backgroundColor = .clear
        addSubview(handle)
        let corner = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 26, y: 12))
        path.addLine(to: CGPoint(x: 26, y: 26))
        path.addLine(to: CGPoint(x: 12, y: 26))
        corner.path = path.cgPath
        corner.strokeColor = UIColor.black.withAlphaComponent(0.45).cgColor
        corner.fillColor = UIColor.clear.cgColor
        corner.lineWidth = 2
        handle.layer.addSublayer(corner)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(move(_:))))
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resize(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityHint = "Tryck för att redigera"
    }

    required init?(coder: NSCoder) { nil }

    func configure(text: String, color: UIColor) {
        backgroundColor = color
        if text != self.text {
            self.text = text
            accessibilityLabel = "Lapp: \(text)"
            setNeedsLayout()
        }
        handle.isHidden = !isEditable
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        handle.frame = CGRect(x: bounds.width - 32, y: bounds.height - 32, width: 32, height: 32)
        let area = bounds.insetBy(dx: 8, dy: 6)
        label.frame = area
        label.font = .systemFont(ofSize: Self.fittingSize(for: text, in: area.size), weight: .semibold)
        label.text = text
    }

    /// Största textstorlek där all text (med användarens radbrytningar) får plats.
    static func fittingSize(for text: String, in size: CGSize) -> CGFloat {
        guard !text.isEmpty, size.width > 0, size.height > 0 else { return 16 }
        var low: CGFloat = 6
        var high: CGFloat = 120
        while high - low > 0.5 {
            let mid = (low + high) / 2
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: mid, weight: .semibold)],
                context: nil
            )
            if rect.height <= size.height && rect.width <= size.width { low = mid } else { high = mid }
        }
        return low
    }

    @objc private func tapped() {
        if isEditable { onTap?() }
    }

    @objc private func move(_ gesture: UIPanGestureRecognizer) {
        guard isEditable, let parent = superview else { return }
        switch gesture.state {
        case .began:
            isInteracting = true
            startFrame = frame
        case .changed:
            let t = gesture.translation(in: parent)
            frame.origin = CGPoint(x: max(0, min(parent.bounds.width - frame.width, startFrame.minX + t.x)), y: max(0, startFrame.minY + t.y))
        case .ended, .cancelled:
            isInteracting = false
            onMoved?(frame)
        default:
            break
        }
    }

    @objc private func resize(_ gesture: UIPanGestureRecognizer) {
        guard isEditable, let parent = superview else { return }
        switch gesture.state {
        case .began:
            isInteracting = true
            startFrame = frame
        case .changed:
            let t = gesture.translation(in: parent)
            frame.size = CGSize(width: max(70, startFrame.width + t.x), height: max(44, startFrame.height + t.y))
            setNeedsLayout()
        case .ended, .cancelled:
            isInteracting = false
            onResized?(frame)
        default:
            break
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
