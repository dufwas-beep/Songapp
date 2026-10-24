import SwiftUI
import UIKit

/// Visar ett låtblad som är en bild (JPG, PNG, HEIC …), anpassad till skärmens bredd.
struct ImageSongView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            } else if loaded {
                ContentUnavailableView("Bilden kunde inte öppnas", systemImage: "photo")
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = UIImage(contentsOfFile: url.path)
            loaded = true
        }
    }
}
