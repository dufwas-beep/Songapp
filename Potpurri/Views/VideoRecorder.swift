import AVFoundation
import Photos
import SwiftUI
import UIKit

/// Rec-knappen: startar och stoppar inspelningen. Kameran filmar i bakgrunden medan
/// appen används som vanligt – bilden syns i en liten flytande ruta (se `RecordingWindow`).
struct RecordButton: View {
    @AppStorage(Feature.record.key) private var enabled = true
    private var capture: VideoCapture { VideoCapture.shared }

    var body: some View {
        if enabled { button }
    }

    private var button: some View {
        Button {
            if capture.isRecording { capture.stop() } else { capture.start() }
        } label: {
            Image(systemName: capture.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(capture.isBusy)
        .accessibilityLabel(capture.isRecording ? "Stoppa inspelningen" : "Spela in film")
        .alert("Rec", isPresented: Binding(get: { capture.message != nil }, set: { if !$0 { capture.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(capture.message ?? "")
        }
    }
}

/// Den lilla rutan med kamerabilden medan det spelar in: röd prick och tid, dra för att
/// flytta, tryck för att göra den mindre eller större, ■ för att stoppa. När filmen är
/// sparad visas det en kort stund.
struct RecordingWindow: View {
    private var capture: VideoCapture { VideoCapture.shared }
    @AppStorage("recordingWindowSmall") private var small = false
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero

    private var size: CGSize {
        small ? CGSize(width: 160, height: 90) : CGSize(width: 288, height: 162)
    }

    var body: some View {
        Group {
            if capture.isRecording {
                window
                    .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                    .transition(.scale.combined(with: .opacity))
            } else if capture.savedNotice {
                Label("Filmen är sparad i Bilder", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: capture.isRecording)
        .animation(.easeInOut(duration: 0.25), value: capture.savedNotice)
    }

    private var window: some View {
        CameraPreview(session: capture.session)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    if let started = capture.started {
                        Text(started, style: .timer)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    capture.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: small ? 12 : 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: small ? 28 : 36, height: small ? 28 : 36)
                        .background(.red, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Stoppa inspelningen")
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(.red, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) { small.toggle() }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        drag = .zero
                    }
            )
    }
}

/// Kamerans bild.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        VideoCapture.shared.attachPreview(view.previewLayer)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// Själva inspelningen: framkameran och mikrofonen till en film som sparas i Bilder.
@Observable
final class VideoCapture {
    static let shared = VideoCapture()

    private(set) var isRecording = false
    /// Startar eller sparar just nu (knappen väntar under tiden).
    private(set) var isBusy = false
    private(set) var started: Date?
    /// "Filmen är sparad i Bilder" visas en kort stund.
    private(set) var savedNotice = false
    var message: String?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCaptureMovieFileOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "Potpurri.kamera")
    @ObservationIgnored private var camera: AVCaptureDevice?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var captureRotation: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var previewRotation: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var previewObservation: NSKeyValueObservation?
    @ObservationIgnored private let delegate = RecordingDelegate()

    func start() {
        guard !isRecording, !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            let video = await AVCaptureDevice.requestAccess(for: .video)
            let audio = await AVCaptureDevice.requestAccess(for: .audio)
            guard video else {
                isBusy = false
                message = "Potpurri får inte använda kameran. Slå på det i Inställningar → Potpurri."
                return
            }
            // Ljudet från soundboarden m.m. fortsätter att spela medan mikrofonen spelar in.
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try? AVAudioSession.sharedInstance().setActive(true)
            let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                queue.async {
                    let ready = self.configure(withAudio: audio)
                    if ready { self.session.startRunning() }
                    continuation.resume(returning: ready)
                }
            }
            guard ready else {
                isBusy = false
                restoreAudio()
                message = "Kameran gick inte att starta."
                AppLog.problem("Inspelningen kunde inte starta (kameran).")
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Potpurri-\(UUID().uuidString).mov")
            let angle = captureRotation?.videoRotationAngleForHorizonLevelCapture
            queue.async {
                if let connection = self.output.connection(with: .video) {
                    if let angle, connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                    // Framkameran filmar som man ser sig själv i en spegel.
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                }
                self.output.startRecording(to: url, recordingDelegate: self.delegate)
            }
            started = Date()
            isRecording = true
            isBusy = false
            if !audio {
                message = "Potpurri får inte använda mikrofonen, så filmen blir utan ljud. Slå på det i Inställningar → Potpurri."
            }
            AppLog.info("Inspelning startad\(audio ? "" : " (utan ljud)").")
        }
    }

    func stop() {
        guard isRecording else { return }
        isBusy = true
        queue.async {
            self.output.stopRecording()
        }
    }

    /// Bilden i rutan vrids rätt när iPaden vänds.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        guard let camera else { return }
        let rotation = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: layer)
        previewRotation = rotation
        previewObservation = rotation.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { rotation, _ in
            DispatchQueue.main.async {
                let angle = rotation.videoRotationAngleForHorizonLevelPreview
                if let connection = layer.connection, connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
    }

    /// Körs på kamerans kö.
    private func configure(withAudio audio: Bool) -> Bool {
        if configured { return true }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video),
              let cameraInput = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.beginConfiguration()
        session.automaticallyConfiguresApplicationAudioSession = false
        session.sessionPreset = .high
        guard session.canAddInput(cameraInput), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(cameraInput)
        if audio, let microphone = AVCaptureDevice.default(for: .audio),
           let microphoneInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(microphoneInput) {
            session.addInput(microphoneInput)
        }
        session.addOutput(output)
        session.commitConfiguration()
        self.camera = camera
        captureRotation = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        configured = true
        return true
    }

    /// Filmen är klar (även om inspelningen avbröts, t.ex. när appen lades undan).
    fileprivate func finished(_ url: URL, error: Error?) {
        queue.async {
            self.session.stopRunning()
        }
        let completed = error == nil
            || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        DispatchQueue.main.async {
            self.isRecording = false
            self.started = nil
            self.restoreAudio()
            guard completed else {
                self.isBusy = false
                self.message = "Inspelningen misslyckades: \(error?.localizedDescription ?? "okänt fel")"
                AppLog.problem("Inspelningen misslyckades: \(error?.localizedDescription ?? "okänt fel")")
                try? FileManager.default.removeItem(at: url)
                return
            }
            self.save(url)
        }
    }

    private func save(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.message = "Potpurri får inte spara i Bilder. Slå på det i Inställningar → Potpurri."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    self.isBusy = false
                    if success {
                        AppLog.info("Inspelningen sparad i Bilder.")
                        self.savedNotice = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.savedNotice = false }
                    } else {
                        self.message = "Filmen kunde inte sparas i Bilder: \(error?.localizedDescription ?? "okänt fel")"
                        AppLog.problem("Inspelningen kunde inte sparas i Bilder: \(error?.localizedDescription ?? "okänt fel")")
                    }
                }
            }
        }
    }

    /// Tillbaka till uppspelning som vanligt (samma som soundboarden ställer in).
    private func restoreAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
    }
}

private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        VideoCapture.shared.finished(outputFileURL, error: error)
    }
}
