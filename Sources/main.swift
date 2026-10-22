import AppKit
import Foundation
import Darwin

struct QuotaWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Int? {
        guard let value = usedPercent, value.isFinite else { return nil }
        return Int(max(0, min(100, 100 - value)).rounded())
    }
}
struct QuotaBucket: Decodable { let primary: QuotaWindow?; let secondary: QuotaWindow? }
enum ResetCategory: Int, CaseIterable {
    case fiveHour, weekly, full
    var label: String {
        switch self {
        case .fiveHour: return "5 小时重置次数"
        case .weekly: return "每周重置次数"
        case .full: return "完全重置次数"
        }
    }
}
struct ResetCredit: Decodable {
    let resetType: String?
    let status: String?
    let title: String?
    var category: ResetCategory? {
        // The protocol currently exposes one broad reset type. Require an explicit
        // scope in its display title; never derive scope from the aggregate count.
        guard resetType == "codexRateLimits", let title = title else { return nil }
        let name = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "full reset (weekly + 5 hr)", "完全重置（每周 + 5 小时）", "完全重置（每周 + 5小时）": return .full
        case "5 hr reset", "5-hour reset", "5 小时重置": return .fiveHour
        case "weekly reset", "每周重置": return .weekly
        default: return nil
        }
    }
}
struct ResetCredits: Decodable {
    let availableCount: Int?
    let credits: [ResetCredit]?
    var total: Int? { availableCount.flatMap { $0 >= 0 ? $0 : nil } }
    var categoryCounts: [Int]? {
        guard let total = total else { return nil }
        if total == 0 { return [0, 0, 0] }
        guard let credits = credits else { return nil }
        let available = credits.filter { $0.status == "available" }
        guard available.count == total else { return nil }
        var counts = [0, 0, 0]
        for credit in available {
            guard let category = credit.category else { return nil }
            counts[category.rawValue] += 1
        }
        return counts
    }
}
struct QuotaResponse: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    let rateLimitResetCredits: ResetCredits?
    var codex: QuotaBucket? { rateLimitsByLimitId?["codex"] ?? rateLimits }
}
struct Formatter {
    static let zone = TimeZone(identifier: "Asia/Shanghai")!
    static func resetMenuTitles(_ credits: ResetCredits?, loading: Bool) -> [String] {
        let unavailable = loading ? "查询中…" : (credits?.total == nil ? "未提供" : "未提供明细")
        let counts = credits?.categoryCounts
        return ResetCategory.allCases.map { category in
            let value = counts.map { "\($0[category.rawValue]) 次" } ?? unavailable
            return "\(category.label)：\(value)"
        }
    }

    static func segment(_ window: QuotaWindow?, weekly: Bool, twelveHour: Bool) -> String {
        guard let window = window, let remaining = window.remaining else { return "--%(--:--)" }
        guard let reset = window.resetsAt else { return "\(remaining)%(--)" }
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = zone
        date.dateFormat = weekly ? "MM/dd" : (twelveHour ? "h:mm a" : "HH:mm")
        return "\(remaining)%(\(date.string(from: Date(timeIntervalSince1970: reset))))"
    }
    static func detail(_ window: QuotaWindow?, name: String) -> String {
        guard let window = window, let remaining = window.remaining else { return "\(name)：暂未提供数据" }
        let date = DateFormatter(); date.locale = Locale(identifier: "zh_CN"); date.timeZone = zone; date.dateFormat = "MM月dd日 HH:mm"
        let reset = window.resetsAt.map { date.string(from: Date(timeIntervalSince1970: $0)) } ?? "未知"
        return "\(name)：剩余 \(remaining)%，重置于 \(reset)（北京时间）"
    }
    static func resetLabel(_ window: QuotaWindow?, weekly: Bool, twelveHour: Bool) -> String {
        guard let reset = window?.resetsAt else { return "--" }
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = zone
        date.dateFormat = weekly ? "MM/dd" : (twelveHour ? "h:mma" : "HH:mm")
        return date.string(from: Date(timeIntervalSince1970: reset))
    }
}

func menuBarImage(primary: QuotaWindow?, secondary: QuotaWindow?, twelveHour: Bool, stale: Bool, showPrimary: Bool = true, showSecondary: Bool = true) -> NSImage {
    let topFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    let bottomFont = NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .regular)
    let selected = [showPrimary ? 0 : nil, showSecondary ? 1 : nil].compactMap { $0 }
    let allTops = [primary, secondary].map { $0?.remaining.map { "\($0)%" } ?? "--%" }
    let allBottoms = [Formatter.resetLabel(primary, weekly: false, twelveHour: twelveHour), Formatter.resetLabel(secondary, weekly: true, twelveHour: twelveHour)]
    let tops = selected.map { allTops[$0] }, bottoms = selected.map { allBottoms[$0] }
    let widths = zip(tops, bottoms).map { top, bottom in
        ceil(max((top as NSString).size(withAttributes: [.font: topFont]).width,
                 (bottom as NSString).size(withAttributes: [.font: bottomFont]).width))
    }
    let gap: CGFloat = 7
    let size = NSSize(width: widths.reduce(0, +) + gap * CGFloat(max(0, selected.count - 1)), height: 22)
    let image = NSImage(size: size, flipped: false) { _ in
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let ink = NSColor.black.withAlphaComponent(stale ? 0.5 : 1)
        for index in selected.indices {
            let x = widths.prefix(index).reduce(0, +) + CGFloat(index) * gap
            (tops[index] as NSString).draw(in: NSRect(x: x, y: 9, width: widths[index], height: 13), withAttributes: [.font: topFont, .foregroundColor: ink, .paragraphStyle: paragraph])
            (bottoms[index] as NSString).draw(in: NSRect(x: x, y: 0, width: widths[index], height: 9), withAttributes: [.font: bottomFont, .foregroundColor: ink, .paragraphStyle: paragraph])
        }
        if selected.count == 2 {
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let divider = NSBezierPath(); divider.lineWidth = 0.5
            divider.move(to: NSPoint(x: widths[0] + gap / 2, y: 3)); divider.line(to: NSPoint(x: widths[0] + gap / 2, y: 19)); divider.stroke()
        }
        return true
    }
    image.isTemplate = true
    return image
}

final class QuotaClient {
    var onUpdate: ((QuotaBucket) -> Void)?
    var onResetCredits: ((ResetCredits?) -> Void)?
    var onStatus: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private let readQueue = DispatchQueue(label: "local.marble.quota.read")
    private var requestID = 10
    private var pending: Int?
    private var pendingAt: Date?
    private var initialized = false
    private var stopping = false
    private var failures = 0
    private var retryAt = Date.distantPast
    private var timer: Timer?
    private var generation = 0
    private var startedAt: Date?
    private var latest: QuotaBucket?

    static func executableCandidates(environment: [String: String], home: URL, preferred: String?) -> [String] {
        // An explicit override is authoritative; never silently run a different CLI.
        if let override = environment["MARBLE_CODEX_PATH"], !override.isEmpty { return [override] }
        if let preferred = preferred, !preferred.isEmpty { return [preferred] }
        var candidates = [".local/bin/codex", ".npm-global/bin/codex", ".npm/bin/codex", ".volta/bin/codex", ".asdf/shims/codex"].map { home.appendingPathComponent($0).path }
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"]
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        candidates += paths.map { URL(fileURLWithPath: $0).appendingPathComponent("codex").path }
        return candidates
    }
    static func executable() -> String? {
        let fm = FileManager.default
        return executableCandidates(environment: ProcessInfo.processInfo.environment, home: fm.homeDirectoryForCurrentUser,
            preferred: UserDefaults.standard.string(forKey: "codexExecutablePath")).first { path in
                var directory: ObjCBool = false
                return path.hasPrefix("/") && fm.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue && fm.isExecutableFile(atPath: path)
            }
    }
    // The helper inherits only runtime, Codex configuration and proxy settings.
    // Never pass unrelated API keys, GitHub tokens or application credentials.
    static func childEnvironment(_ source: [String: String], executable: String? = nil) -> [String: String] {
        let allowed = Set(["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE",
                           "CODEX_HOME", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                           "http_proxy", "https_proxy", "all_proxy", "no_proxy",
                           "SSL_CERT_FILE", "SSL_CERT_DIR"])
        var result = source.filter { allowed.contains($0.key) }
        // npm/nvm launchers use /usr/bin/env node; include the selected CLI's
        // own bin directory without inheriting unrelated environment variables.
        var paths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let executable = executable, executable.hasPrefix("/") {
            paths.append(URL(fileURLWithPath: executable).deletingLastPathComponent().path)
        }
        paths += ["/opt/homebrew/bin", "/usr/local/bin"]
        result["PATH"] = paths.joined(separator: ":")
        return result
    }
    static func permitsMethod(_ method: String) -> Bool {
        ["initialize", "initialized", "account/rateLimits/read"].contains(method)
    }
    func start() {
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
    }
    func refresh() {
        if process == nil { retryAt = .distantPast; connect() }
        else if initialized && pending == nil { requestLimits() }
    }
    private func connect() {
        guard !stopping, process == nil, Date() >= retryAt else { return }
        guard let executable = Self.executable() else { onStatus?("未找到 Codex CLI；请在菜单中选择 CLI，并先运行 codex login。"); retryAt = Date().addingTimeInterval(60); return }
        let child = Process(); child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.environment = Self.childEnvironment(ProcessInfo.processInfo.environment, executable: executable)
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        child.standardInput = stdinPipe; child.standardOutput = stdoutPipe; child.standardError = FileHandle.nullDevice
        generation += 1; let token = generation
        readQueue.sync { buffer = Data() }
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.readQueue.async { [weak self] in
                guard let self = self else { return }
                // Bound untrusted helper output instead of buffering an unlimited line.
                guard data.count <= 1_048_576, self.buffer.count <= 1_048_576 - data.count else {
                    self.buffer.removeAll(keepingCapacity: false)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.generation == token else { return }
                        self.resetConnection("额度响应过大，已重新连接")
                    }
                    return
                }
                self.buffer.append(data)
                while let newline = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer.prefix(upTo: newline); self.buffer.removeSubrange(...newline)
                    if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, self.generation == token else { return }
                            self.receive(object)
                        }
                    }
                }
            }
        }
        child.terminationHandler = { [weak self] _ in DispatchQueue.main.async {
            guard let self = self, self.generation == token else { return }
            self.disconnected("连接已断开，正在重试")
        } }
        do {
            try child.run(); process = child; input = stdinPipe.fileHandleForWriting
            initialized = false; startedAt = Date()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "marble_quota_bar", "title": "Marble Quota Bar", "version": "1.2.0"]]])
        } catch { disconnected("无法启动 Codex 额度连接") }
    }
    private func send(_ message: [String: Any]) {
        guard let method = message["method"] as? String, Self.permitsMethod(method),
              let input = input, var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(10)
        do { try input.write(contentsOf: data) } catch { resetConnection("额度连接写入失败") }
    }
    private func requestLimits() {
        requestID += 1; pending = requestID; pendingAt = Date()
        send(["id": requestID, "method": "account/rateLimits/read", "params": [:]])
    }
    private func receive(_ message: [String: Any]) {
        if let id = message["id"] as? Int, id == 1 {
            guard message["error"] == nil else { resetConnection("额度接口初始化失败"); return }
            initialized = true
            send(["method": "initialized", "params": [:]])
            requestLimits(); return
        }
        let responseID = message["id"] as? Int
        if responseID != nil && responseID == pending {
            pending = nil; pendingAt = nil
            if let error = message["error"] as? [String: Any], error["code"] as? Int == -32601 {
                onStatus?("当前 Codex CLI 不支持额度接口，请升级 Codex CLI"); return
            }
            guard message["error"] == nil, let result = message["result"] as? [String: Any] else {
                onStatus?("无法读取额度；请先运行 codex login，并确认账号支持 Codex 额度"); return
            }
            apply(result)
        } else if message["method"] as? String == "account/rateLimits/updated", let params = message["params"] as? [String: Any] {
            // Ignore updates for a different metered bucket.
            if let bucket = params["rateLimits"] as? [String: Any], let id = bucket["limitId"] as? String, id != "codex" { return }
            apply(params, partial: true)
        }
    }
    private func apply(_ result: [String: Any], partial: Bool = false) {
        guard let data = try? JSONSerialization.data(withJSONObject: result),
            let response = try? JSONDecoder().decode(QuotaResponse.self, from: data), let bucket = response.codex,
            bucket.primary?.remaining != nil || bucket.secondary?.remaining != nil else {
            onStatus?("当前登录未提供 Codex 额度数据"); return
        }
        let merged = partial ? QuotaBucket(primary: bucket.primary ?? latest?.primary, secondary: bucket.secondary ?? latest?.secondary) : bucket
        latest = merged
        // Partial quota notifications may omit credits; only replace known counts when provided.
        if !partial || result.keys.contains("rateLimitResetCredits") {
            onResetCredits?(response.rateLimitResetCredits)
        }
        failures = 0; onUpdate?(merged)
    }
    private func tick() {
        if process == nil { connect(); return }
        if !initialized, let start = startedAt, Date().timeIntervalSince(start) > 30 { resetConnection("连接超时，稍后自动重试"); return }
        if let date = pendingAt, Date().timeIntervalSince(date) > 25 { resetConnection("刷新超时，保留上次额度"); return }
        if initialized && pending == nil && Date().timeIntervalSince(lastRequest) >= 60 { requestLimits(); lastRequest = Date() }
    }
    private var lastRequest = Date()
    private func resetConnection(_ reason: String) {
        let old = process; generation += 1; process = nil; input = nil; initialized = false; pending = nil; pendingAt = nil
        if old?.isRunning == true { old?.terminate() }
        disconnected(reason)
    }
    private func disconnected(_ reason: String) {
        process = nil; input = nil; initialized = false; pending = nil; pendingAt = nil
        failures += 1; retryAt = Date().addingTimeInterval(min(120, Double(5 * (1 << min(failures, 4)))))
        if !stopping { onStatus?(reason) }
    }
    func reconnect() {
        latest = nil
        onResetCredits?(nil)
        resetConnection("正在重新连接 Codex CLI")
        retryAt = .distantPast
        connect()
    }
    func stop() {
        stopping = true; timer?.invalidate(); generation += 1
        try? input?.close(); if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil
    }
    deinit { stop() }
}

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class DragSurface: NSVisualEffectView {
    weak var owner: AppDelegate?
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = owner?.makeMenu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}
final class PassiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: BarPanel!
    private var left = PassiveLabel(labelWithString: "--%(--:--)")
    private var right = PassiveLabel(labelWithString: "--%(--/--)")
    private var dot = PassiveLabel(labelWithString: "•")
    private var contentStack: NSStackView!
    private var statusItem: NSStatusItem!
    private let client = QuotaClient()
    private var bucket: QuotaBucket?
    private var resetCredits: ResetCredits?
    private var updatedAt: Date?
    private var failure: String?
    private var staleTimer: Timer?
    private var twelveHour = !UserDefaults.standard.bool(forKey: "use24Hour")
    private var showPrimary = !UserDefaults.standard.bool(forKey: "hide5HourUsage")
    private var showSecondary = !UserDefaults.standard.bool(forKey: "hideWeeklyUsage")
    private var savingPosition = false
    private var menuTracking = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let frame = NSRect(x: 0, y: 0, width: 286, height: 36)
        panel = BarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Marble 额度条"; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isMovableByWindowBackground = true; panel.delegate = self
        let surface = DragSurface(frame: frame); surface.owner = self
        surface.material = .hudWindow; surface.blendingMode = .behindWindow; surface.state = .active
        surface.appearance = NSAppearance(named: .vibrantDark)
        surface.wantsLayer = true; surface.layer?.cornerRadius = 18; surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 0.75; surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        panel.contentView = surface
        let separator = PassiveLabel(labelWithString: "|")
        for label in [left, right, separator, dot] {
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
            label.isSelectable = false; label.isEditable = false
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        left.textColor = NSColor(calibratedRed: 0.58, green: 0.91, blue: 0.79, alpha: 1)
        right.textColor = NSColor(calibratedRed: 0.64, green: 0.77, blue: 1, alpha: 1)
        separator.textColor = NSColor.white.withAlphaComponent(0.3); dot.textColor = .systemOrange
        let stack = NSStackView(views: [dot, left, separator, right]); stack.orientation = .horizontal; stack.spacing = 8
        contentStack = stack
        stack.alignment = .centerY; stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerYAnchor.constraint(equalTo: surface.centerYAnchor), stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8)])
        restorePosition()
        if !UserDefaults.standard.bool(forKey: "desktopOverlayHidden") { panel.orderFrontRegardless() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.title = "--% | --%"; statusItem.button?.toolTip = "Marble 额度条"; statusItem.menu = makeMenu()
        client.onResetCredits = { [weak self] credits in self?.resetCredits = credits }
        client.onUpdate = { [weak self] bucket in self?.bucket = bucket; self?.updatedAt = Date(); self?.failure = nil; self?.render() }
        client.onStatus = { [weak self] message in self?.failure = message; self?.render() }
        render(); client.start()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.render() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    private func render() {
        left.stringValue = Formatter.segment(bucket?.primary, weekly: false, twelveHour: twelveHour)
        right.stringValue = Formatter.segment(bucket?.secondary, weekly: true, twelveHour: twelveHour)
        // Fit the actual text with 8 pt at each edge, keeping the bar centered in place.
        let textWidth = contentStack.arrangedSubviews.reduce(CGFloat(0)) { $0 + $1.fittingSize.width }
        let width = ceil(textWidth + contentStack.spacing * CGFloat(contentStack.arrangedSubviews.count - 1) + 16)
        if abs(panel.frame.width - width) > 0.5 {
            let frame = panel.frame
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY, width: width, height: frame.height), display: true)
        }
        let stale = failure != nil || updatedAt.map { Date().timeIntervalSince($0) > 150 } ?? true
        dot.textColor = stale ? .systemOrange : .systemGreen
        let formatter = DateFormatter(); formatter.timeZone = Formatter.zone; formatter.dateFormat = "HH:mm:ss"
        var detail = "Codex 剩余额度\n" + Formatter.detail(bucket?.primary, name: "5 小时") + "\n" + Formatter.detail(bucket?.secondary, name: "每周")
        if let updated = updatedAt { detail += "\n上次更新：\(formatter.string(from: updated))" }
        if let failure = failure { detail += "\n\(failure)；当前显示可能已过期" }
        else if stale { detail += bucket == nil ? "\n正在连接…" : "\n数据已过期，正在重试" }
        detail += "\n拖动调整位置 · 右键打开菜单"
        panel.contentView?.toolTip = detail; left.toolTip = detail; right.toolTip = detail
        let menuUsageText = [showPrimary ? left.stringValue : nil, showSecondary ? right.stringValue : nil].compactMap { $0 }.joined(separator: " | ")
        if showPrimary || showSecondary {
            let menuImage = menuBarImage(primary: bucket?.primary, secondary: bucket?.secondary, twelveHour: twelveHour, stale: stale, showPrimary: showPrimary, showSecondary: showSecondary)
            statusItem.button?.title = ""; statusItem.button?.image = menuImage
            statusItem.button?.imagePosition = .imageOnly; statusItem.length = menuImage.size.width
        } else {
            statusItem.button?.image = nil; statusItem.button?.title = "额度"
            statusItem.length = NSStatusItem.variableLength
        }
        statusItem.button?.toolTip = detail.replacingOccurrences(of: "拖动调整位置 · 右键打开菜单", with: "点击查看额度详情和操作")
        statusItem.button?.setAccessibilityLabel("Codex 剩余额度")
        statusItem.button?.setAccessibilityValue((menuUsageText.isEmpty ? "用量显示已关闭" : menuUsageText) + (stale ? "，数据待刷新" : ""))
        panel.setAccessibilityLabel("Codex 剩余额度"); panel.setAccessibilityValue(left.stringValue + " | " + right.stringValue + (stale ? "，数据待刷新" : ""))
        if !menuTracking { statusItem.menu = makeMenu() }
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Marble 额度条")
        menu.delegate = self
        let title = NSMenuItem(title: "Codex 剩余额度", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        if let bucket = bucket {
            for entry in [Formatter.detail(bucket.primary, name: "5 小时"), Formatter.detail(bucket.secondary, name: "每周")] {
                let item = NSMenuItem(title: entry, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        for text in Formatter.resetMenuTitles(resetCredits, loading: bucket == nil) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false; menu.addItem(item)
        }
        if let failure = failure { let item = NSMenuItem(title: failure, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator())
        add(menu, "立即刷新", #selector(refreshNow), "r")
        let primaryToggle = add(menu, "显示 5 小时用量", #selector(togglePrimary)); primaryToggle.state = showPrimary ? .on : .off
        let secondaryToggle = add(menu, "显示周用量", #selector(toggleSecondary)); secondaryToggle.state = showSecondary ? .on : .off
        menu.addItem(.separator())
        add(menu, panel?.isVisible == false ? "显示桌面悬浮条" : "关闭桌面悬浮条", #selector(toggleVisible))
        add(menu, "移回屏幕右上角", #selector(resetPosition))
        let format = add(menu, "使用 24 小时制", #selector(toggleTime)); format.state = twelveHour ? .off : .on
        menu.addItem(.separator())
        add(menu, "选择 Codex CLI…", #selector(chooseCLI))
        add(menu, "安装与登录说明…", #selector(showSetupHelp))
        menu.addItem(.separator()); add(menu, "退出额度条", #selector(quit), "q")
        return menu
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    @objc private func chooseCLI() {
        let picker = NSOpenPanel()
        picker.title = "选择已安装的 Codex CLI 可执行文件"
        picker.message = "可在终端运行 which codex 查看位置。请仅选择你信任的 Codex CLI。"
        picker.canChooseFiles = true; picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false; picker.showsHiddenFiles = true
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            let alert = NSAlert(); alert.messageText = "所选文件不可执行"; alert.informativeText = "请选择 Codex CLI 可执行文件。"; alert.runModal(); return
        }
        UserDefaults.standard.set(url.path, forKey: "codexExecutablePath")
        bucket = nil; resetCredits = nil; updatedAt = nil
        client.reconnect()
    }
    @objc private func showSetupHelp() {
        let alert = NSAlert(); alert.messageText = "额度条使用条件"
        alert.informativeText = "需要 macOS 13 或更新版本，以及已安装的 Codex CLI。\n\n1. 用你自己的 ChatGPT 账号运行 codex login。\n2. 终端运行 which codex 查看位置。\n3. 如果没有自动找到，点击菜单中的「选择 Codex CLI…」。\n\n支持 Apple 芯片和 Intel。额度、重置券是否提供取决于账号及 CLI 版本；仅使用 API Key 的登录不保证提供这些额度。所有重置时间显示为北京时间。"
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func refreshNow() { client.refresh() }
    @objc private func togglePrimary() { showPrimary.toggle(); UserDefaults.standard.set(!showPrimary, forKey: "hide5HourUsage"); render() }
    @objc private func toggleSecondary() { showSecondary.toggle(); UserDefaults.standard.set(!showSecondary, forKey: "hideWeeklyUsage"); render() }
    @objc private func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        UserDefaults.standard.set(!panel.isVisible, forKey: "desktopOverlayHidden")
        if !menuTracking { statusItem.menu = makeMenu() }
    }
    func menuWillOpen(_ menu: NSMenu) { menuTracking = true }
    func menuDidClose(_ menu: NSMenu) {
        menuTracking = false
        DispatchQueue.main.async { [weak self] in guard let self = self, !self.menuTracking else { return }; self.statusItem.menu = self.makeMenu() }
    }
    @objc private func toggleTime() { twelveHour.toggle(); UserDefaults.standard.set(!twelveHour, forKey: "use24Hour"); render() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screenChanged() { ensureVisible() }
    @objc private func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - panel.frame.height - 90)); savePosition()
    }
    private func restorePosition() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "barX") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "barX"), y: defaults.double(forKey: "barY"))); ensureVisible()
        } else { resetPosition() }
    }
    private func ensureVisible() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -8, dy: -8).contains(panel.frame) }) { resetPosition() }
    }
    func windowDidMove(_ notification: Notification) { savePosition() }
    private func savePosition() {
        guard panel != nil, !savingPosition else { return }; savingPosition = true
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "barX"); UserDefaults.standard.set(panel.frame.origin.y, forKey: "barY"); savingPosition = false
    }
    func applicationWillTerminate(_ notification: Notification) { staleTimer?.invalidate(); client.stop() }
}

func runSelfTests() throws {
    func decode(_ string: String) throws -> QuotaResponse { try JSONDecoder().decode(QuotaResponse.self, from: Data(string.utf8)) }
    let result = try decode("""
    {"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":14,"windowDurationMins":300,"resetsAt":1577947920},"secondary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1578556800}}}}
    """)
    precondition(result.codex?.primary?.remaining == 86)
    precondition(Formatter.segment(result.codex?.primary, weekly: false, twelveHour: true) == "86%(2:52 PM)")
    precondition(Formatter.segment(result.codex?.secondary, weekly: true, twelveHour: true) == "98%(01/09)")
    precondition(Formatter.segment(result.codex?.primary, weekly: false, twelveHour: false) == "86%(14:52)")
    let missing = try decode("{\"rateLimits\":{\"primary\":null,\"secondary\":null}}")
    precondition(missing.codex?.primary == nil)
    let clamp = try decode("{\"rateLimits\":{\"primary\":{\"usedPercent\":120},\"secondary\":{\"usedPercent\":-5}}}")
    precondition(clamp.codex?.primary?.remaining == 0 && clamp.codex?.secondary?.remaining == 100)
    precondition(Formatter.segment(nil, weekly: false, twelveHour: true).contains("--%"))
    let resets = try decode("{\"rateLimitResetCredits\":{\"availableCount\":1}}")
    precondition(resets.rateLimitResetCredits?.availableCount == 1)
    let zeroResets = try decode("{\"rateLimitResetCredits\":{\"availableCount\":0,\"credits\":null}}")
    precondition(zeroResets.rateLimitResetCredits?.availableCount == 0)
    let missingResets = try decode("{\"rateLimitResetCredits\":null}")
    precondition(missingResets.rateLimitResetCredits == nil)
    let joint = try decode("{\"rateLimitResetCredits\":{\"availableCount\":1,\"credits\":[{\"resetType\":\"codexRateLimits\",\"status\":\"available\",\"title\":\"Full reset (Weekly + 5 hr)\"}]}}")
    precondition(joint.rateLimitResetCredits?.categoryCounts == [0, 0, 1])
    precondition(Formatter.resetMenuTitles(joint.rateLimitResetCredits, loading: false) == [
        "5 小时重置次数：0 次", "每周重置次数：0 次", "完全重置次数：1 次"
    ])
    precondition(Formatter.resetMenuTitles(resets.rateLimitResetCredits, loading: false).allSatisfy { $0.contains("未提供明细") })
    precondition(zeroResets.rateLimitResetCredits?.categoryCounts == [0, 0, 0])
    let mixed = ResetCredits(availableCount: 4, credits: [
        ResetCredit(resetType: "codexRateLimits", status: "available", title: "5 hr reset"),
        ResetCredit(resetType: "codexRateLimits", status: "available", title: "Weekly reset"),
        ResetCredit(resetType: "codexRateLimits", status: "available", title: "Weekly reset"),
        ResetCredit(resetType: "codexRateLimits", status: "available", title: "Full reset (Weekly + 5 hr)"),
        ResetCredit(resetType: "codexRateLimits", status: "redeemed", title: "Full reset (Weekly + 5 hr)")
    ])
    precondition(mixed.categoryCounts == [1, 2, 1])
    precondition(ResetCredits(availableCount: 5, credits: mixed.credits).categoryCounts == nil)
    precondition(ResetCredits(availableCount: 1, credits: [ResetCredit(resetType: "unknown", status: "available", title: "Full reset (Weekly + 5 hr)")]).categoryCounts == nil)
    precondition(ResetCredits(availableCount: 1, credits: [ResetCredit(resetType: "codexRateLimits", status: "available", title: nil)]).categoryCounts == nil)
    print("PASS: exclusive reset categories, full-only 0/0/1, mixed 1/2/1, redeemed ignored, incomplete and unknown details")
    let child = QuotaClient.childEnvironment(["HOME": "/synthetic/home", "CODEX_HOME": "/synthetic/config", "HTTPS_PROXY": "http://localhost:8080", "GH_TOKEN": "test-sentinel", "OPENAI_API_KEY": "test-sentinel", "UNRELATED_SECRET": "test-sentinel", "PATH": "/synthetic/tools"])
    precondition(child["HOME"] == "/synthetic/home" && child["CODEX_HOME"] == "/synthetic/config")
    precondition(child["HTTPS_PROXY"] == "http://localhost:8080")
    precondition(child["GH_TOKEN"] == nil && child["OPENAI_API_KEY"] == nil && child["UNRELATED_SECRET"] == nil)
    precondition(child["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
    let launcher = QuotaClient.childEnvironment([:], executable: "/synthetic/node/bin/codex")
    precondition(launcher["PATH"]!.contains("/synthetic/node/bin"))
    let candidates = QuotaClient.executableCandidates(environment: ["PATH": "relative:/synthetic/bin"], home: URL(fileURLWithPath: "/synthetic/home"), preferred: nil)
    precondition(candidates.contains("/synthetic/home/.npm-global/bin/codex") && candidates.contains("/synthetic/bin/codex"))
    precondition(!candidates.contains("relative/codex"))
    precondition(QuotaClient.executableCandidates(environment: ["MARBLE_CODEX_PATH": "/synthetic/custom"], home: URL(fileURLWithPath: "/synthetic/home"), preferred: nil) == ["/synthetic/custom"])
    precondition(QuotaClient.permitsMethod("account/rateLimits/read"))
    precondition(!QuotaClient.permitsMethod("thread/start") && !QuotaClient.permitsMethod("turn/start") && !QuotaClient.permitsMethod("account/rateLimits/reset"))
    print("PASS: helper environment strips unrelated secrets; outgoing RPC method allowlist")
    print("PASS: quota bucket selection, remaining %, timezone, 12/24h, missing values, clamps")
}
// Connection checks emit capability flags only, never percentages, account IDs,
// reset timestamps, credit IDs, raw protocol responses or credentials.
func checkConnection() -> Int32 {
    let client = QuotaClient()
    var result: Int32? = nil
    client.onUpdate = { bucket in
        print("CONNECTED primary=\(bucket.primary?.remaining != nil) weekly=\(bucket.secondary?.remaining != nil)")
        result = 0
    }
    client.onStatus = { message in print("UNAVAILABLE: \(message)"); result = 1 }
    client.start()
    let deadline = Date().addingTimeInterval(35)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    client.stop()
    if result == nil { print("UNAVAILABLE: connection timeout") }
    return result ?? 1
}
signal(SIGPIPE, SIG_IGN)
if CommandLine.arguments.contains("--check-connection") { exit(checkConnection()) }
if CommandLine.arguments.contains("--self-test") { try runSelfTests(); exit(0) }
let app = NSApplication.shared
if let identifier = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { exit(0) }
let delegate = AppDelegate(); app.delegate = delegate; app.run()
