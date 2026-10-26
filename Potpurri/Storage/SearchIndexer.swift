import Foundation
import PDFKit
import UIKit
import Vision

/// Läser ut låttexten ur PDF:er och bilder så att sökfältet hittar låtar på textrader.
/// Word-PDF:er har riktig text; bilder och inskannade blad textigenkänns i iPaden
/// (Apples textigenkänning, utan internet). Körs i bakgrunden med statusfältet.
@MainActor
enum SearchIndexer {
    static func run(songs: [Song], progress: TaskProgress) async {
        let pending = songs.filter { $0.searchText == nil && ($0.kind == .pdf || $0.kind == .image) && $0.hasFile }
        guard !pending.isEmpty, !progress.isRunning else { return }
        progress.start("Indexerar låttext", total: pending.count)
        for song in pending {
            progress.currentName = song.title
            let url = song.fileURL
            let kind = song.kind
            let text = await Task.detached(priority: .utility) {
                extractText(from: url, kind: kind)
            }.value
            song.searchText = text
            progress.done += 1
        }
        progress.finish()
    }

    nonisolated static func extractText(from url: URL, kind: SongKind) -> String {
        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: url) else { return "" }
            let text = document.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 { return text }
            // Inskannad PDF utan text: textigenkänn de första sidorna.
            return (0..<min(document.pageCount, 3)).compactMap { index -> String? in
                guard let page = document.page(at: index) else { return nil }
                let image = page.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox)
                return recognize(image.cgImage)
            }.joined(separator: "\n")
        case .image:
            return recognize(UIImage(contentsOfFile: url.path)?.cgImage)
        case .text, .note:
            return ""
        }
    }

    /// Apples textigenkänning (svenska och engelska).
    nonisolated static func recognize(_ image: CGImage?) -> String {
        guard let image else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["sv-SE", "en-US"]
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
