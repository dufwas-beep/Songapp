import Foundation
import MetricKit
import UIKit

/// Appens logg i klartext: vad som hänt, fel, frysningar och krascher. Läses under
/// Inställningar → Logg och kan skickas vidare därifrån.
///
/// - Varje händelse får en rad med tid. Problem markeras: ⚠️ fel, 🧊 frysning, 💥 krasch.
/// - En vakt märker när appen slutar svara i mer än två sekunder och skriver vad som
///   hände senast, även om appen sedan måste stängas.
/// - Kraschar skrivs direkt till filen innan appen stängs.
/// - Startar appen och förra körningen inte avslutades ordentligt står det också.
enum AppLog {
    static let url: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Potpurri-logg.txt")
    }()

    private static let queue = DispatchQueue(label: "Potpurri.log")
    /// Filen är öppen hela tiden, så att en krasch kan skrivas utan att något annat behövs.
    private static var fileDescriptor: Int32 = -1
    /// Det senaste som hände – skrivs med när appen hänger sig eller kraschar.
    private static var lastEvent = "–"
    private static let runningKey = "appLogRunning"
    private static let metrics = MetricsReceiver()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "d MMM HH:mm:ss"
        return formatter
    }()

    // MARK: Skriva

    /// En vanlig händelse, t.ex. "Öppnar låten X".
    static func info(_ message: String) {
        add(message)
    }

    /// Något som gick fel men där appen fortsätter.
    static func problem(_ message: String) {
        add("⚠️ " + message)
    }

    private static func add(_ message: String) {
        let line = timeFormatter.string(from: Date()) + "  " + message + "\n"
        queue.async {
            lastEvent = message
            writeRaw(line)
        }
    }

    private static func writeRaw(_ text: String) {
        guard fileDescriptor >= 0 else { return }
        var bytes = Array(text.utf8)
        _ = write(fileDescriptor, &bytes, bytes.count)
    }

    // MARK: Läsa

    /// Loggens rader, de senaste sist.
    static func lines(limit: Int = 1500) -> [String] {
        queue.sync {}
        guard let data = try? Data(contentsOf: url) else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        return Array(text.split(separator: "\n", omittingEmptySubsequences: false).suffix(limit).map(String.init))
    }

    /// Väntar tills allt är skrivet, så att filen kan delas.
    static func flush() {
        queue.sync {}
    }

    static func clear() {
        queue.sync {
            if fileDescriptor >= 0 { ftruncate(fileDescriptor, 0) }
        }
        info("Loggen rensades.")
    }

    // MARK: Start

    /// Anropas en gång när appen startar.
    static func start() {
        queue.sync {
            trimIfLarge()
            fileDescriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        }
        let bundleInfo = Bundle.main.infoDictionary
        let version = bundleInfo?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundleInfo?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        add("——— Potpurri startar (version \(version), bygge \(build), \(device.model), \(device.systemName) \(device.systemVersion))")

        if UserDefaults.standard.bool(forKey: runningKey) {
            problem("Förra gången avslutades appen oväntat medan den var öppen: den kraschade, frös och stängdes, eller stoppades från Xcode. Se raderna närmast ovanför.")
        }
        UserDefaults.standard.set(true, forKey: runningKey)

        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(false, forKey: runningKey)
            add("Appen gick till bakgrunden.")
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(true, forKey: runningKey)
            add("Appen öppnades igen.")
        }
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            problem("Minnet håller på att ta slut (systemet varnade).")
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            UserDefaults.standard.set(false, forKey: runningKey)
        }

        installCrashHandlers()
        startWatchdog()
        MXMetricManager.shared.add(metrics)
    }

    /// Håller loggen liten: över 400 kB sparas bara den senaste halvan.
    private static func trimIfLarge() {
        guard let data = try? Data(contentsOf: url), data.count > 400_000 else { return }
        var tail = data.suffix(200_000)
        // Börja på en hel rad.
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
            tail = tail[tail.index(after: newline)...]
        }
        try? Data(tail).write(to: url)
    }

    // MARK: Frysningar

    /// Frågar appen var halvsekund om den svarar. Gör den inte det på två sekunder skrivs
    /// det i loggen tillsammans med var i koden appen står (upp till tre gånger under
    /// samma frysning), och när den svarar igen skrivs hur länge den hängde.
    private static func startWatchdog() {
        mainThreadPort = mach_thread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(pthread_self()))
        mainStack = (top - UInt(pthread_get_stacksize_np(pthread_self())))...top
        let thread = Thread {
            while true {
                let answered = DispatchSemaphore(value: 0)
                let started = Date()
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 2) == .timedOut {
                    let event = queue.sync { lastEvent }
                    add("🧊 Appen har frusit – den har inte svarat på 2 sekunder. Senast hände: \(event)\n" + mainThreadStack())
                    var samples = 1
                    while answered.wait(timeout: .now() + 1) == .timedOut {
                        if samples < 3 {
                            samples += 1
                            add("🧊 Fortfarande frusen efter \(String(format: "%.1f", Date().timeIntervalSince(started))) s, nu här:\n" + mainThreadStack())
                        }
                    }
                    let seconds = Date().timeIntervalSince(started)
                    add("🧊 Appen svarar igen efter \(String(format: "%.1f", seconds)) sekunder.")
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        thread.name = "Potpurri.vakt"
        thread.qualityOfService = .utility
        thread.start()
    }

    private static var mainThreadPort: thread_t = 0
    /// Huvudtrådens minnesområde – vakten läser aldrig utanför det.
    private static var mainStack: ClosedRange<UInt> = 0...0

    /// Var huvudtråden (den som ritar skärmen) står just nu, som läsbara rader.
    /// Tråden stoppas ett ögonblick medan adresserna läses (inget får skapas i minnet då,
    /// eftersom den stoppade tråden kan hålla minneslåset).
    private static func mainThreadStack() -> String {
        #if arch(arm64)
        guard mainThreadPort != 0 else { return "" }
        let capacity = 48
        let addresses = UnsafeMutablePointer<UInt>.allocate(capacity: capacity)
        defer { addresses.deallocate() }
        var found = 0
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        guard thread_suspend(mainThreadPort) == KERN_SUCCESS else { return "" }
        let result = withUnsafeMutablePointer(to: &state) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThreadPort, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            // Systemets delar kan ha signerade adresser – de övre bitarna tas bort.
            let mask: UInt = 0x0000_000F_FFFF_FFFF
            addresses[0] = UInt(state.__pc) & mask
            addresses[1] = UInt(state.__lr) & mask
            found = 2
            var frame = UInt(state.__fp) & mask
            let stack = mainStack
            while found < capacity, frame % 8 == 0, stack.contains(frame), stack.contains(frame + 16) {
                guard let pointer = UnsafePointer<UInt>(bitPattern: frame) else { break }
                let next = pointer[0] & mask
                let returnAddress = pointer[1] & mask
                if returnAddress == 0 { break }
                addresses[found] = returnAddress
                found += 1
                if next <= frame { break }
                frame = next
            }
        }
        thread_resume(mainThreadPort)
        let lines = (0..<found).map { describe(addresses[$0]) }
        return lines.enumerated().map { "    \($0.offset)  \($0.element)" }.joined(separator: "\n")
        #else
        return ""
        #endif
    }

    /// En adress som "▶ Potpurri  LibraryView.body.getter" (▶ = appens egen kod).
    private static func describe(_ address: UInt) -> String {
        var info = Dl_info()
        guard let pointer = UnsafeRawPointer(bitPattern: address), dladdr(pointer, &info) != 0 else {
            return "0x" + String(address, radix: 16)
        }
        let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
        let own = image.hasPrefix("Potpurri")
        var symbol = "0x" + String(address, radix: 16)
        if let name = info.dli_sname {
            symbol = demangle(name)
        }
        let line = (own ? "▶ " : "  ") + image + "  " + symbol
        return line.count > 220 ? String(line.prefix(220)) + "…" : line
    }

    private static func demangle(_ name: UnsafePointer<CChar>) -> String {
        if let readable = _swiftDemangle(name, UInt(strlen(name)), nil, nil, 0) {
            defer { free(readable) }
            return String(cString: readable)
        }
        return String(cString: name)
    }

    // MARK: Krascher

    private static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(30).joined(separator: "\n")
            AppLog.writeCrash("Ett fel som inte fångades: \(exception.name.rawValue) – \(exception.reason ?? "")", stack: stack)
        }
        for number in [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGFPE, SIGTRAP] {
            signal(number) { received in
                AppLog.writeCrash(AppLog.explanation(ofSignal: received), stack: Thread.callStackSymbols.prefix(30).joined(separator: "\n"))
                // Låt systemet avsluta appen som vanligt.
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }

    /// Skrivs direkt till filen, utan kön (den kan vara låst av tråden som kraschade).
    private static func writeCrash(_ reason: String, stack: String) {
        let time = timeFormatter.string(from: Date())
        let text = "\(time)  💥 KRASCH: \(reason)\n    Senast hände: \(lastEvent)\n    Var i koden (översta raderna är närmast felet):\n\(stack)\n"
        writeRaw(text)
        UserDefaults.standard.set(false, forKey: runningKey)
    }

    private static func explanation(ofSignal number: Int32) -> String {
        switch number {
        case SIGTRAP, SIGILL: return "programfel i appen, t.ex. ett värde som saknades eller en lista som tog slut (\(number == SIGTRAP ? "SIGTRAP" : "SIGILL"))"
        case SIGABRT: return "appen avbröts av ett fel, ofta i systemets egna delar (SIGABRT)"
        case SIGSEGV, SIGBUS: return "appen läste minne den inte fick (\(number == SIGSEGV ? "SIGSEGV" : "SIGBUS"))"
        case SIGFPE: return "räknefel, t.ex. division med noll (SIGFPE)"
        default: return "signal \(number)"
        }
    }

    /// Systemets egna rapporter om krascher och frysningar (kommer oftast vid nästa start).
    private final class MetricsReceiver: NSObject, MXMetricManagerSubscriber {
        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            for payload in payloads {
                for crash in payload.crashDiagnostics ?? [] {
                    let reason = crash.terminationReason ?? crash.exceptionType.map { "undantag \($0)" } ?? crash.signal.map { "signal \($0)" } ?? "okänd orsak"
                    AppLog.add("💥 Systemets kraschrapport (\(payload.timeStampEnd.formatted(date: .abbreviated, time: .shortened))): \(reason)\n" + Self.stack(crash.callStackTree))
                }
                for hang in payload.hangDiagnostics ?? [] {
                    AppLog.add("🧊 Systemets frysrapport: appen hängde \(hang.hangDuration.formatted())\n" + Self.stack(hang.callStackTree))
                }
            }
        }

        private static func stack(_ tree: MXCallStackTree) -> String {
            String(String(decoding: tree.jsonRepresentation(), as: UTF8.self).prefix(4000))
        }
    }
}

/// Swifts egen funktion som gör om interna namn ("$s8Potpurri…") till läsbara.
@_silgen_name("swift_demangle")
private func _swiftDemangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: UInt,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<UInt>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
