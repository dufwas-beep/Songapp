import PDFKit
import SwiftUI
import UIKit

/// Visar en PDF som en lång vertikal vy där alla sidor följer på varandra.
/// Sidorna ritas till bilder i bakgrunden i skärmens upplösning – nästa och förra låten
/// ritas i förväg – så att låten syns direkt och skarp i stället för suddig först.
/// Zoomen (nyp) sparas i förhållande till "hela bredden" och återställs nästa gång.
struct PDFPagesView: View {
    let url: URL
    var zoom: Double?
    var onZoom: ((Double) -> Void)?
    var onScrollView: ((UIScrollView) -> Void)?
    @Environment(\.displayScale) private var displayScale
    @State private var pages: [UIImage]
    @State private var liveZoom: CGFloat?
    @State private var zoomStart: CGFloat?
    private let sizes: [CGSize]

    /// Marginaler som i iPadens egen PDF-visning, så att markeringar och notes hamnar rätt.
    static let sideMargin: CGFloat = 4
    static let pageGap: CGFloat = 9.5

    init(url: URL, zoom: Double? = nil, onZoom: ((Double) -> Void)? = nil, onScrollView: ((UIScrollView) -> Void)? = nil) {
        self.url = url
        self.zoom = zoom
        self.onZoom = onZoom
        self.onScrollView = onScrollView
        sizes = PDFPageRenderer.pageSizes(url)
        // Redan ritad (förladdad): visa direkt.
        _pages = State(initialValue: PDFPageRenderer.shared.cachedPages(url) ?? [])
    }

    var body: some View {
        GeometryReader { proxy in
            let current = liveZoom ?? CGFloat(zoom ?? 1)
            let width = max(proxy.size.width * current, 1)
            let pageWidth = max(width - 2 * Self.sideMargin, 1)
            ScrollView([.vertical, .horizontal]) {
                VStack(spacing: Self.pageGap) {
                    ForEach(sizes.indices, id: \.self) { index in
                        let size = sizes[index]
                        let height = pageWidth * size.height / max(size.width, 1)
                        ZStack {
                            Color.white
                            if index < pages.count {
                                Image(uiImage: pages[index])
                                    .resizable()
                                    .interpolation(.high)
                            }
                        }
                        .frame(width: pageWidth, height: height)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    }
                }
                .padding(.horizontal, Self.sideMargin)
                .padding(.vertical, Self.pageGap / 2)
                .frame(width: width)
                .background {
                    if let onScrollView { ScrollViewFinder(onFound: onScrollView) }
                }
            }
            // Nyp med två fingrar för att zooma – sparas per låt.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = zoomStart ?? current
                        zoomStart = start
                        liveZoom = min(max(start * value.magnification, 1), 3)
                    }
                    .onEnded { _ in
                        if let liveZoom { onZoom?(Double(liveZoom)) }
                        liveZoom = nil
                        zoomStart = nil
                    }
            )
            // Ritas om i högre upplösning när man har zoomat in.
            .task(id: PDFPageRenderer.pixelWidth(proxy.size.width * CGFloat(zoom ?? 1), scale: displayScale)) {
                let pixels = PDFPageRenderer.pixelWidth(proxy.size.width * CGFloat(zoom ?? 1), scale: displayScale)
                // Nästa låt ritas i förväg i samma storlek (utan zoom).
                guard proxy.size.width > 10 else { return }
                PDFPageRenderer.shared.preferredWidth = max(PDFPageRenderer.shared.preferredWidth, PDFPageRenderer.pixelWidth(proxy.size.width, scale: displayScale))
                let rendered = await PDFPageRenderer.shared.pages(for: url, pixelWidth: pixels)
                if !rendered.isEmpty { pages = rendered }
            }
        }
    }
}

/// Ritar PDF-sidor till bilder i bakgrunden och håller de senaste låtarna i minnet.
final class PDFPageRenderer: @unchecked Sendable {
    static let shared = PDFPageRenderer()
    private let lock = NSLock()
    private let cache = NSCache<NSURL, Rendered>()
    private var inFlight: [String: Task<[UIImage], Never>] = [:]
    private var _preferredWidth: Int = 1536
    private var sizes: [URL: [CGSize]] = [:]

    final class Rendered {
        let width: Int
        let pages: [UIImage]
        init(width: Int, pages: [UIImage]) {
            self.width = width
            self.pages = pages
        }
    }

    init() {
        // Ungefär sex låtar à två sidor i full upplösning.
        cache.totalCostLimit = 400 * 1024 * 1024
    }

    /// Bredden (i pixlar) som låtvyn senast behövde – används när nästa låt ritas i förväg.
    var preferredWidth: Int {
        get { lock.withLock { _preferredWidth } }
        set { lock.withLock { _preferredWidth = newValue } }
    }

    /// Avrundas uppåt i steg om 256 pixlar så att små storleksändringar inte ritar om.
    static func pixelWidth(_ points: CGFloat, scale: CGFloat) -> Int {
        let pixels = Int((points * max(scale, 1)).rounded(.up))
        return min(max((pixels + 255) / 256 * 256, 512), 3328)
    }

    static func pageSizes(_ url: URL) -> [CGSize] {
        if let known = shared.lock.withLock({ shared.sizes[url] }) { return known }
        guard let document = PDFCache.shared.document(for: url) else { return [] }
        let found: [CGSize] = (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let box = page.bounds(for: .cropBox)
            return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        }
        shared.lock.withLock { shared.sizes[url] = found }
        return found
    }

    func cachedPages(_ url: URL) -> [UIImage]? {
        cache.object(forKey: url as NSURL)?.pages
    }

    func pages(for url: URL, pixelWidth: Int) async -> [UIImage] {
        if let cached = cache.object(forKey: url as NSURL), cached.width >= pixelWidth { return cached.pages }
        let key = "\(url.path)#\(pixelWidth)"
        let task: Task<[UIImage], Never> = lock.withLock {
            if let running = inFlight[key] { return running }
            let task = Task.detached(priority: .userInitiated) { [self] () -> [UIImage] in
                let pages = Self.render(url, pixelWidth: pixelWidth)
                let cost = pages.reduce(0) { $0 + Int($1.size.width * $1.size.height * 4) }
                if !pages.isEmpty {
                    cache.setObject(Rendered(width: pixelWidth, pages: pages), forKey: url as NSURL, cost: cost)
                }
                lock.withLock { inFlight[key] = nil }
                return pages
            }
            inFlight[key] = task
            return task
        }
        return await task.value
    }

    /// Ritar nästa/förra låten i förväg.
    func preload(_ url: URL) {
        let width = preferredWidth
        if let cached = cache.object(forKey: url as NSURL), cached.width >= width { return }
        Task.detached(priority: .utility) { [self] in
            _ = await pages(for: url, pixelWidth: width)
        }
    }

    private static func render(_ url: URL, pixelWidth: Int) -> [UIImage] {
        // Egen kopia av dokumentet: PDFKit ska inte användas från två trådar samtidigt.
        guard let document = CGPDFDocument(url as CFURL) else { return [] }
        var images: [UIImage] = []
        for number in 1...max(document.numberOfPages, 1) {
            guard let page = document.page(at: number) else { continue }
            let box = page.getBoxRect(.cropBox)
            let rotated = page.rotationAngle % 180 != 0
            let pageSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
            guard pageSize.width > 0, pageSize.height > 0 else { continue }
            let scale = CGFloat(pixelWidth) / pageSize.width
            let size = CGSize(width: CGFloat(pixelWidth), height: (pageSize.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let cg = context.cgContext
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: scale, y: -scale)
                // Vrider och flyttar sidan rätt (sidans storlek = målrutan, så ingen skalning här).
                cg.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pageSize), rotate: 0, preserveAspectRatio: true))
                cg.interpolationQuality = .high
                cg.setRenderingIntent(.defaultIntent)
                cg.drawPDFPage(page)
            }
            images.append(image)
        }
        return images
    }
}
