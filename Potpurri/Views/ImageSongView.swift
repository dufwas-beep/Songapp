import SwiftUI
import UIKit

/// Visar ett låtblad som är en bild (JPG, PNG, HEIC …), anpassad till skärmens bredd.
struct ImageSongView: View {
    let url: URL
    /// Sparad zoom (1 = hela bredden) och var den ska sparas när man nyper.
    var zoom: Double?
    var onZoom: ((Double) -> Void)?
    var onScrollView: ((UIScrollView) -> Void)?
    @State private var image: UIImage?
    @Environment(Player.self) private var player

    init(url: URL, zoom: Double? = nil, onZoom: ((Double) -> Void)? = nil, onScrollView: ((UIScrollView) -> Void)? = nil) {
        self.url = url
        self.zoom = zoom
        self.onZoom = onZoom
        self.onScrollView = onScrollView
        // Redan inläst (t.ex. förladdad som nästa låt): visa direkt utan väntan.
        _image = State(initialValue: ImageCache.shared.cached(url))
    }
    @State private var loaded = false
    @State private var liveZoom: CGFloat?
    @State private var zoomStart: CGFloat?

    var body: some View {
        Group {
            if let image {
                GeometryReader { proxy in
                    let current = liveZoom ?? CGFloat(zoom ?? 1)
                    ScrollView([.vertical, .horizontal]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width * current)
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
                }
            } else if loaded {
                ContentUnavailableView("Bilden kunde inte öppnas", systemImage: "photo")
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = await ImageCache.shared.image(for: url)
            loaded = true
            player.finishSwitchTimer()
        }
    }
}
