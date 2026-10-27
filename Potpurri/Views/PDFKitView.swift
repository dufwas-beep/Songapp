import ImageIO
import SwiftUI
import UIKit

/// Visar en PDF som en lång vertikal vy där alla sidor följer på varandra.
/// Sidorna ritas till bilder i skärmens upplösning och sparas på iPaden, så att låten
/// syns direkt och skarp i stället för suddig först.
/// Zoomen (nyp) sparas i förhållande till "hela bredden" och återställs nästa gång.
struct PDFPagesView: View {
    let url: URL
    var zoom: Double?
    var onZoom: ((Double) -> Void)?
    var onScrollView: ((UIScrollView) -> Void)?
    @Environment(\.displayScale) private var displayScale
    @Environment(Player.self) private var player
    @State private var pages: [Int: UIImage]
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
        let sizes = PDFPageRenderer.pageSizes(url)
        self.sizes = sizes
        // Redan ritad (förladdad): visa direkt.
        _pages = State(initialValue: PDFPageRenderer.shared.cachedPages(url, count: sizes.count))
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
                            if let page = pages[index] {
                                Image(uiImage: page)
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
                // Sida för sida, första sidan först – den syns direkt när den är klar.
                for index in sizes.indices {
                    guard !Task.isCancelled else { return }
                    if let page = await PDFPageRenderer.shared.page(url, index: index, pixelWidth: pixels) {
                        pages[index] = page
                    }
                    if index == 0 { player.finishSwitchTimer() }
                }
            }
        }
    }
}

/// Ritar PDF-sidor till bilder och sparar dem på iPaden (Caches/Sidor) som JPEG.
/// Hela biblioteket ritas en gång i bakgrunden; en låtlista som öppnas går före.
/// De senast visade sidorna hålls dessutom färdiga i minnet.
final class PDFPageRenderer: @unchecked Sendable {
    static let shared = PDFPageRenderer()
    private let lock = NSLock()
    private let memory = NSCache<NSString, Rendered>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var sizes: [URL: [CGSize]] = [:]
    private var queue: [URL] = []
    private var working = false
    private let folder: URL

    final class Rendered {
        let width: Int
        let image: UIImage
        init(width: Int, image: UIImage) {
            self.width = width
            self.image = image
        }
    }

    init() {
        // Ungefär åtta låtar à två sidor i full upplösning.
        memory.totalCostLimit = 400 * 1024 * 1024
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sidor", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Bredden (i pixlar) som låtvyn behöver – sparas så att förberedelsen vet den direkt.
    var preferredWidth: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "pdfPageWidth")
            return stored > 0 ? stored : 2048
        }
        set { UserDefaults.standard.set(newValue, forKey: "pdfPageWidth") }
    }

    /// Avrundas uppåt i steg om 256 pixlar så att små storleksändringar inte ritar om.
    static func pixelWidth(_ points: CGFloat, scale: CGFloat) -> Int {
        let pixels = Int((points * max(scale, 1)).rounded(.up))
        return min(max((pixels + 255) / 256 * 256, 512), 3328)
    }

    static func pageSizes(_ url: URL) -> [CGSize] {
        if let known = shared.lock.withLock({ shared.sizes[url] }) { return known }
        guard let document = CGPDFDocument(url as CFURL) else { return [] }
        let found: [CGSize] = (0..<document.numberOfPages).compactMap { index in
            guard let page = document.page(at: index + 1) else { return nil }
            let box = page.getBoxRect(.cropBox)
            return page.rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        }
        shared.lock.withLock { shared.sizes[url] = found }
        return found
    }

    func cachedPages(_ url: URL, count: Int) -> [Int: UIImage] {
        var pages: [Int: UIImage] = [:]
        for index in 0..<count {
            if let rendered = memory.object(forKey: Self.key(url, index)) { pages[index] = rendered.image }
        }
        return pages
    }

    /// En sida: ur minnet, från disken eller nyritad.
    func page(_ url: URL, index: Int, pixelWidth: Int) async -> UIImage? {
        let key = Self.key(url, index)
        if let rendered = memory.object(forKey: key), rendered.width >= pixelWidth { return rendered.image }
        let flightKey = "\(key)#\(pixelWidth)"
        let task: Task<UIImage?, Never> = lock.withLock {
            if let running = inFlight[flightKey] { return running }
            let task = Task.detached(priority: .userInitiated) { [self] () -> UIImage? in
                let file = diskURL(url, index)
                var image = Self.load(file, minWidth: pixelWidth)
                if image == nil, let rendered = Self.render(url, index: index, pixelWidth: pixelWidth) {
                    Self.save(rendered, to: file)
                    image = rendered
                }
                if let image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    memory.setObject(Rendered(width: Int(image.size.width), image: image), forKey: key, cost: cost)
                }
                lock.withLock { inFlight[flightKey] = nil }
                return image
            }
            inFlight[flightKey] = task
            return task
        }
        return await task.value
    }

    /// Nästa/förra låten läggs färdig i minnet.
    func preload(_ url: URL) {
        let width = preferredWidth
        Task.detached(priority: .utility) { [self] in
            for index in Self.pageSizes(url).indices {
                _ = await page(url, index: index, pixelWidth: width)
            }
        }
    }

    /// Ritar låtarna till disken i bakgrunden. `first` = före allt annat (t.ex. en låtlista).
    func prepare(_ urls: [URL], first: Bool = false) {
        let start: Bool = lock.withLock {
            let wanted = Set(urls)
            queue.removeAll(where: wanted.contains)
            if first { queue.insert(contentsOf: urls, at: 0) } else { queue.append(contentsOf: urls) }
            guard !working else { return false }
            working = true
            return true
        }
        guard start else { return }
        Task.detached(priority: .background) { [self] in
            while let url = lock.withLock({ queue.isEmpty ? nil : queue.removeFirst() }) {
                let width = preferredWidth
                for index in Self.pageSizes(url).indices {
                    let file = diskURL(url, index)
                    if Self.storedWidth(file) >= width { continue }
                    if let image = Self.render(url, index: index, pixelWidth: width) {
                        Self.save(image, to: file)
                    }
                    // Lämna plats åt det man gör i appen under tiden.
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
            lock.withLock { working = false }
        }
    }

    /// Tar bort de sparade sidorna när en låt tas bort.
    func removeCache(forFileNamed name: String) {
        let prefix = name + "-"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where file.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    private static func key(_ url: URL, _ index: Int) -> NSString {
        "\(url.lastPathComponent)-\(index)" as NSString
    }

    private func diskURL(_ url: URL, _ index: Int) -> URL {
        folder.appendingPathComponent("\(url.lastPathComponent)-\(index).jpg")
    }

    private static func storedWidth(_ file: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        return properties[kCGImagePropertyPixelWidth] as? Int ?? 0
    }

    /// Läser en sparad sida och packar upp den direkt (inte först när den visas).
    private static func load(_ file: URL, minWidth: Int) -> UIImage? {
        guard storedWidth(file) >= minWidth,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    private static func save(_ image: UIImage, to file: URL) {
        try? image.jpegData(compressionQuality: 0.85)?.write(to: file, options: .atomic)
    }

    private static func render(_ url: URL, index: Int, pixelWidth: Int) -> UIImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: index + 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let pageSize = rotated ? CGSize(width: box.height, height: box.width) : box.size
        guard pageSize.width > 0, pageSize.height > 0 else { return nil }
        let scale = CGFloat(pixelWidth) / pageSize.width
        let size = CGSize(width: CGFloat(pixelWidth), height: (pageSize.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            // Vrider och flyttar sidan rätt (sidans storlek = målrutan, så ingen skalning här).
            cg.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pageSize), rotate: 0, preserveAspectRatio: true))
            cg.interpolationQuality = .high
            cg.drawPDFPage(page)
        }
    }
}
