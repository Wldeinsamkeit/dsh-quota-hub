import AppKit
import SwiftUI
import Combine

func qlog(_ text: String) {
    let line = "\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)) \(text)\n"
    let path = "/tmp/quotabar-debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Models

struct Metric: Codable, Identifiable {
    var kind: String?
    var label: String?
    var used: Double?
    var limit: Double?
    var value: String?
    var unit: String?
    var resetsAt: Double?
    var remainingPercent: Double?
    var unlimited: Bool?
    var id: String { (label ?? "?") + "|" + (kind ?? "") }
}

struct Provider: Codable, Identifiable {
    var id: String
    var label: String?
    var ok: Bool?
    var error: String?
    var metrics: [Metric]?
}

struct QuotaState: Codable {
    var updatedAt: Double?
    var providers: [Provider]?
    var errors: [String]?
}

// MARK: - Store

final class QuotaStore: ObservableObject {
    @Published var state: QuotaState?
    @Published var refreshing = false
    @Published var lastError: String?

    private let fm = FileManager.default

    var supportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QuotaBar", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    var stateURL: URL { supportDir.appendingPathComponent("state.json") }
    var configURL: URL { supportDir.appendingPathComponent("config.json") }
    var collectorURL: URL { supportDir.appendingPathComponent("collect.mjs") }

    func loadState() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoded = try? JSONDecoder().decode(QuotaState.self, from: data)
        if let decoded = decoded { self.state = decoded }
    }

    static func nodePath() -> String? {
        let candidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        for c in candidates where FileManager.default.fileExists(atPath: c) { return c }
        return nil
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        let collector = collectorURL
        let nodePath = Self.nodePath()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var runError: String?
            if let node = nodePath, FileManager.default.fileExists(atPath: collector.path) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: node)
                p.arguments = [collector.path]
                let pipe = Pipe()
                p.standardError = pipe
                p.standardOutput = FileHandle.nullDevice
                do {
                    try p.run()
                    p.waitUntilExit()
                    if p.terminationStatus != 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        runError = String(data: data, encoding: .utf8)
                    }
                } catch {
                    runError = error.localizedDescription
                }
            } else {
                runError = "collector 或 node 不可用"
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadState()
                self.lastError = runError
                self.refreshing = false
            }
        }
    }
}

// MARK: - UI 状态（仅用于"重新打开时收起"信号）

final class PanelModel: ObservableObject {
    @Published var reopenCounter = 0

    func requestCollapse() { reopenCounter += 1 }
}

// MARK: - 面板窗口（贴在状态栏图标下方）

final class QuotaPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .windowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - 展示逻辑

private let barBlue = Color(red: 0.05, green: 0.45, blue: 0.95)
private let barGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
private let barYellow = Color(red: 0.95, green: 0.75, blue: 0.05)
private let barRed = Color.red

/// 剩余分档固定色：90+ 绿 / 70-90 黄 / 30-70 蓝 / <30 红
private func levelColor(remainingPct: Double) -> Color {
    if remainingPct >= 90 { return barGreen }
    if remainingPct >= 70 { return barYellow }
    if remainingPct >= 30 { return barBlue }
    return barRed
}

private func barColor(_ ratio: Double) -> Color {
    levelColor(remainingPct: (1 - ratio) * 100)
}

/// 彩虹分段色（每个 AI 一道弧）
private let rainbowColors: [Color] = [
    Color(red: 1.00, green: 0.27, blue: 0.23),   // 红   #FF453A
    Color(red: 0.04, green: 0.52, blue: 1.00),   // 蓝   #0A84FF
    Color(red: 1.00, green: 0.62, blue: 0.04),   // 橙   #FF9F0A
    Color(red: 0.75, green: 0.35, blue: 0.95),   // 紫   #BF5AF2
    Color(red: 0.19, green: 0.82, blue: 0.35),   // 绿   #30D158
    Color(red: 0.37, green: 0.36, blue: 0.90),   // 靛   #5E5CE6
]

private func usageRatio(_ m: Metric) -> Double? {
    if m.unlimited == true { return nil }
    if let pct = m.remainingPercent { return min(1, max(0, (100 - pct) / 100)) }
    guard let used = m.used, let limit = m.limit, limit > 0 else { return nil }
    return min(1, max(0, used / limit))
}

private func clockShort(_ ms: Double?) -> String {
    guard let ms = ms, ms > 0 else { return "" }
    let date = Date(timeIntervalSince1970: ms / 1000)
    if date < Date() { return "已重置" }
    let f = DateFormatter()
    f.dateFormat = "MM/dd HH:mm"
    return f.string(from: date)
}

private func providerIcon(_ id: String) -> String {
    switch id {
    case "minimax": return "waveform"
    case "codex": return "terminal"
    case "gemini": return "sparkles"
    default: return "gauge"
    }
}

private func providerName(_ p: Provider) -> String {
    let label = p.label ?? p.id
    if let range = label.range(of: " ·") { return String(label[..<range.lowerBound]) }
    return label
}

private func shortCode(_ provider: Provider) -> String {
    switch provider.id {
    case "zai-coding": return "Z"
    case "minimax": return "MM"
    case "codex": return "CX"
    case "deepseek": return "DS"
    case "gemini": return "G"
    default:
        let label = (provider.label ?? provider.id) as NSString
        return label.substring(to: min(2, label.length)).uppercased()
    }
}

private func primaryMetric(_ p: Provider) -> Metric? {
    let ms = p.metrics ?? []
    return ms.first(where: { $0.kind == "window5h" })
        ?? ms.first(where: { $0.kind == "balance" })
        ?? ms.first(where: { $0.kind == "daily" })
        ?? ms.first(where: { $0.remainingPercent != nil })
        ?? ms.first
}

private func remainingFraction(_ m: Metric?) -> Double {
    guard let m = m else { return 0 }
    if m.unlimited == true { return 1 }
    if let pct = m.remainingPercent { return max(0, min(1, pct / 100)) }
    guard let used = m.used, let limit = m.limit, limit > 0 else {
        return (m.kind == "balance") ? 1 : 0   // 余额型视为满格
    }
    return max(0, min(1, 1 - used / limit))
}

private func bigValue(_ p: Provider, _ m: Metric?) -> (text: String, color: Color) {
    guard let m = m else { return ("—", .secondary) }
    if m.kind == "balance" {
        return (m.value ?? "—", .primary)
    }
    if m.unlimited == true { return ("∞", barGreen) }
    let ratio = usageRatio(m) ?? 0
    return ("剩余 \(Int(round((1 - ratio) * 100)))%", barColor(ratio))
}

private func detailLines(_ p: Provider) -> [String] {
    var lines: [String] = []
    for m in p.metrics ?? [] {
        let label = m.label ?? (m.kind ?? "额度")
        if m.unlimited == true {
            lines.append("\(label)：∞ 无限制")
            continue
        }
        if let v = m.value, !v.isEmpty {
            lines.append("\(label)：\(v)")
            continue
        }
        var text = ""
        if let pct = m.remainingPercent {
            text = "剩余 \(Int(pct))%"
        } else if let used = m.used, let limit = m.limit, limit > 0 {
            let unit = (m.unit ?? "").isEmpty ? "" : " " + m.unit!
            text = "\(Int(used))/\(Int(limit))\(unit)"
        } else if let used = m.used {
            text = "\(Int(used))"
        }
        if let reset = m.resetsAt, reset > 0 {
            text += " · 重置 " + clockShort(reset)
        }
        if !text.isEmpty { lines.append("\(label)：\(text)") }
    }
    if lines.isEmpty, let err = p.error, !err.isEmpty {
        lines.append(err)
    }
    return lines
}

// MARK: - 半圆形彩虹仪表盘

struct ArcBandShape: Shape {
    var radius: CGFloat
    var startFraction: CGFloat
    var endFraction: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(radius, AnimatablePair(startFraction, endFraction)) }
        set {
            radius = newValue.first
            startFraction = newValue.second.first
            endFraction = newValue.second.second
        }
    }

    /// 确定性折线采样：严格沿上半圆（180°→360°）
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let a0 = (180.0 + 180.0 * Double(startFraction)) * .pi / 180
        let a1 = (180.0 + 180.0 * Double(endFraction)) * .pi / 180
        let n = 64
        for i in 0...n {
            let t = Double(i) / Double(n)
            let a = a0 + (a1 - a0) * t
            let pt = CGPoint(x: center.x + CGFloat(cos(a)) * radius,
                             y: center.y + CGFloat(sin(a)) * radius)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }
}

struct RainbowGauge: View {
    let segments: [(ratio: Double, color: Color)]
    @Binding var showWeekly: Bool
    var replay: Int = 0
    let hoverDetail: (Int) -> String
    @State private var progress: CGFloat = 0
    @State private var hover: (index: Int, point: CGPoint)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let maxR = w / 2 - 14
            let band = maxR / CGFloat(max(1, segments.count)) * 0.88
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, seg in
                    let r = maxR - CGFloat(index) * band
                    // 轨道用本段彩虹色的淡色：0% 也能看出是哪家
                    ArcBandShape(radius: r, startFraction: 0, endFraction: 1)
                        .stroke(seg.color.opacity(0.16), lineWidth: band)
                    ArcBandShape(radius: r, startFraction: 0, endFraction: CGFloat(seg.ratio) * progress)
                        .stroke(seg.color, lineWidth: band)
                }
            }
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.7), value: showWeekly)
            .overlay(MouseTrackView(
                onTap: {
                    withAnimation(.easeInOut(duration: 0.7)) { showWeekly.toggle() }
                },
                onUpdate: { pt in
                    hover = pt.flatMap { bandAt($0, size: geo.size, maxR: maxR, band: band) }
                }
            ))
            .overlay(alignment: .topLeading) {
                if let h = hover {
                    let text = hoverDetail(h.index)
                    if !text.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(text.split(separator: "\n").enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(size: i == 0 ? 11.5 : 10.5, weight: i == 0 ? .semibold : .regular))
                                    .foregroundStyle(i == 0 ? Color.primary : Color.secondary)
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .fixedSize(horizontal: true, vertical: true)
                        .position(x: min(max(h.point.x, 78), w - 78), y: max(h.point.y - 44, 40))
                        .transition(.opacity)
                        .zIndex(10)
                    }
                }
            }
        }
        .onAppear { replayFill() }
        .onChange(of: replay) { _ in replayFill() }
    }

    private func replayFill() {
        progress = 0
        withAnimation(.easeOut(duration: 0.9).delay(0.1)) { progress = 1 }
    }

    private func bandAt(_ pt: CGPoint, size: CGSize, maxR: CGFloat, band: CGFloat) -> (index: Int, point: CGPoint)? {
        let c = CGPoint(x: size.width / 2, y: size.height)
        let dx = pt.x - c.x
        let dy = c.y - pt.y   // 向上为正
        if dy < -4 { return nil }
        let r = sqrt(dx * dx + dy * dy)
        guard r <= maxR + band / 2, r >= maxR - CGFloat(segments.count) * band - band / 2 else { return nil }
        let idx = Int((maxR - r) / band)
        guard idx >= 0, idx < segments.count else { return nil }
        let ringR = maxR - CGFloat(idx) * band
        guard abs(r - ringR) <= band / 2 + 2 else { return nil }
        return (idx, pt)
    }
}

/// 鼠标悬浮追踪（NSView 底部原点坐标转换为 SwiftUI 顶部原点）
struct MouseTrackView: NSViewRepresentable {
    var onTap: () -> Void = {}
    let onUpdate: (NSPoint?) -> Void

    func makeNSView(context: Context) -> TrackView {
        let v = TrackView()
        v.onUpdate = onUpdate
        v.onTap = onTap
        return v
    }
    func updateNSView(_ v: TrackView, context: Context) {
        v.onUpdate = onUpdate
        v.onTap = onTap
    }

    final class TrackView: NSView {
        var onUpdate: ((NSPoint?) -> Void)?
        var onTap: (() -> Void)?
        override func mouseUp(with event: NSEvent) {
            if event.clickCount >= 1 { onTap?() }
            super.mouseUp(with: event)
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                           owner: self))
        }
        override func mouseMoved(with event: NSEvent) { onUpdate?(report(event)) }
        override func mouseEntered(with event: NSEvent) { onUpdate?(report(event)) }
        override func mouseExited(with event: NSEvent) { onUpdate?(nil) }
        private func report(_ event: NSEvent) -> NSPoint {
            let p = convert(event.locationInWindow, from: nil)
            return NSPoint(x: p.x, y: bounds.height - p.y)
        }
    }
}

// MARK: - 卡片（详情区）

struct ProviderSection: View {
    let provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 42, height: 42)
                    .overlay { providerBadge(provider.id) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(providerName(provider))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ForEach(Self.orderedMetrics(provider)) { m in
                MetricRow(metric: m)
            }
        }
        .padding(.vertical, 12)
    }

    static func orderedMetrics(_ provider: Provider) -> [Metric] {
        func rank(_ k: String?) -> Int {
            switch k {
            case "window5h": return 0
            case "weekly": return 1
            case "balance": return 2
            case "daily": return 3
            default: return 4
            }
        }
        return (provider.metrics ?? []).sorted { rank($0.kind) < rank($1.kind) }
    }

    @ViewBuilder
    private func providerBadge(_ id: String) -> some View {
        switch id {
        case "whale", "deepseek":
            if let url = Bundle.main.url(forResource: "whale-color", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().scaledToFit().padding(6)
            } else {
                Image(systemName: "creditcard").font(.system(size: 19))
            }
        case "zlogo", "zai-coding":
            Text("Z")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
        default:
            Image(systemName: providerIcon(id))
                .font(.system(size: 19))
                .foregroundStyle(.primary)
        }
    }
}

/// 每个额度指标单独一行：标签 + 数值 + 进度条 + 重置时间
struct MetricRow: View {
    let metric: Metric

    var body: some View {
        let val = metricValueText(metric)
        let rem = remainingViewFraction(metric)
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if !reset.isEmpty {
                    Text(reset)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                Text(val.text)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(val.color)
            }
            if let rem = rem {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(levelColor(remainingPct: rem * 100))
                            .frame(width: max(6, geo.size.width * rem))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.top, 6)
    }

    private var reset: String {
        guard let ms = metric.resetsAt, ms > 0 else { return "" }
        return "重置 " + clockShort(ms)
    }
}

private func remainingViewFraction(_ m: Metric) -> Double? {
    if m.unlimited == true { return 1 }
    if let pct = m.remainingPercent { return max(0, min(1, pct / 100)) }
    guard let used = m.used, let limit = m.limit, limit > 0 else {
        return (m.value != nil) ? nil : nil   // 余额/数值行不画条
    }
    return max(0, min(1, 1 - used / limit))
}

private func metricValueText(_ m: Metric) -> (text: String, color: Color) {
    if m.unlimited == true { return ("∞ 无限制", barGreen) }
    if let v = m.value, !v.isEmpty { return (v, .primary) }
    let remaining: Double
    if let pct = m.remainingPercent {
        remaining = pct
    } else if let used = m.used, let limit = m.limit, limit > 0 {
        remaining = (1 - used / limit) * 100
    } else {
        remaining = 0
    }
    var text = "—"
    if let pct = m.remainingPercent {
        text = "剩余 \(Int(pct))%"
    } else if let used = m.used, let limit = m.limit, limit > 0 {
        let unit = (m.unit ?? "").isEmpty ? "" : " " + m.unit!
        text = "\(Int(used))/\(Int(limit))\(unit)"
    } else if let used = m.used {
        text = "\(Int(used))\((m.unit ?? "").isEmpty ? "" : " " + m.unit!)"
    }
    return (text, levelColor(remainingPct: remaining))
}

// MARK: - 面板

// MARK: - 面板

struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var ui: PanelModel
    @State private var expanded = false
    @State private var showWeekly = false
    let onHeightChange: (Bool) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack(spacing: 12) {
                if let url = Bundle.main.url(forResource: "rainbow-color", withExtension: "png"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().frame(width: 24, height: 24)
                }
                Text("AI 额度中心")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { store.refresh() } label: {
                    Image(systemName: store.refreshing ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(store.refreshing)
                .help("立即刷新")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("打开配置目录")
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // 半圆彩虹：默认 5 小时额度，点击拱形切换周额度；出现/切换带加满动画；悬浮看详情
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(showWeekly ? "每周额度" : "5 小时额度")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("点击拱形切换")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 18)

                RainbowGauge(segments: modeSegments, showWeekly: $showWeekly, replay: ui.reopenCounter,
                             hoverDetail: hoverDetail)
                    .frame(width: 280, height: 150)
                HStack(spacing: 10) {
                    ForEach(Array(modeSegments.enumerated()), id: \.offset) { index, seg in
                        let ps = store.state?.providers ?? []
                        if index < ps.count {
                            HStack(spacing: 3) {
                                Circle().fill(seg.color).frame(width: 7, height: 7)
                                Text(shortCode(ps[index]) + " " + String(Int(round(seg.ratio * 100))) + "%")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 4)

            // 展开按钮
            VStack(spacing: 0) {
                Divider()
                Button {
                    qlog("expand button tapped -> \(!expanded)")
                    expanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? "收起详情" : "查看详情")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // 详情区（展开时）：固定高度，窗口高度同步变化
            if expanded {
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        if let ps = store.state?.providers, !ps.isEmpty {
                            ForEach(Array(ps.enumerated()), id: \.element.id) { index, p in
                                if index > 0 {
                                    Divider().padding(.horizontal, 18)
                                }
                                ProviderSection(provider: p)
                                    .padding(.horizontal, 18)
                            }
                        } else if store.refreshing {
                            Text("正在刷新数据…")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                .padding(.vertical, 40)
                        } else {
                            Text("暂无数据，点 ↻ 刷新")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                .padding(.vertical, 40)
                        }
                        if let err = store.lastError {
                            Text(err)
                                .font(.system(size: 10)).foregroundStyle(.red)
                                .padding(.horizontal, 18)
                        }
                    }
                }
                .frame(height: 484)
            }

            // 底部说明
            HStack {
                Text(updatedText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("每 5 分钟自动刷新 · Esc 关闭")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .frame(width: 340, alignment: .top)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .onExitCommand { onClose() }
        .onChange(of: expanded) { newValue in
            onHeightChange(newValue)
        }
        .onChange(of: ui.reopenCounter) { _ in
            expanded = false
        }
    }

    private var modeSegments: [(ratio: Double, color: Color)] {
        let ps = store.state?.providers ?? []
        return ps.enumerated().map { index, p in
            let ms = p.metrics ?? []
            let m = showWeekly
                ? (ms.first(where: { $0.kind == "weekly" }) ?? primaryMetric(p))
                : (ms.first(where: { $0.kind == "window5h" }) ?? primaryMetric(p))
            return (remainingFraction(m), rainbowColors[index % rainbowColors.count])
        }
    }

    private func hoverDetail(_ index: Int) -> String {
        let ps = store.state?.providers ?? []
        guard index < ps.count else { return "" }
        let p = ps[index]
        var lines = [providerName(p)]
        for m in p.metrics ?? [] {
            let label = m.label ?? ""
            if m.unlimited == true { lines.append(label + ": ∞ 无限制"); continue }
            var t = ""
            if let pct = m.remainingPercent {
                t = "剩余 \(Int(pct))%"
            } else if let u = m.used, let l = m.limit, l > 0 {
                let unit = (m.unit ?? "").isEmpty ? "" : " " + m.unit!
                t = "\(Int(u))/\(Int(l))\(unit)"
            } else if let v = m.value, !v.isEmpty {
                t = v
            }
            if let r = m.resetsAt, r > 0 { t += " · " + clockShort(r) }
            if !t.isEmpty { lines.append(label + ": " + t) }
        }
        if lines.count == 1, let err = p.error, !err.isEmpty { lines.append(err) }
        return lines.joined(separator: "\n")
    }

    private var updatedText: String {
        guard let t = store.state?.updatedAt else { return "尚未采集" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date(timeIntervalSince1970: t / 1000))
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let detailHeight: CGFloat = 484
    static let panelWidth: CGFloat = 340
    private var collapsedIdeal: CGFloat = 282   // 稍后由 fittingSize 实测修正

    private let store = QuotaStore()
    private let ui = PanelModel()
    private var panel: QuotaPanelWindow?
    private var statusItem: NSStatusItem?
    private var reloadTimer: Timer?
    private var collectTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例守卫
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tianzhao.quotabar")
            .filter { $0.processIdentifier != myPID }
        for app in others { app.terminate() }

        store.loadState()
        store.refresh()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            var hasIcon = false
            if let url = Bundle.main.url(forResource: "rainbow-bar", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = false
                button.image = img
                hasIcon = true
            }
            if !hasIcon { button.title = "🌈" }
            button.action = #selector(togglePanel(_:))
            button.target = self
            button.toolTip = "AI 额度中心"
        }
        statusItem = item

        setupPanel()

        reloadTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.store.loadState()
        }
        collectTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
    }

    private func setupPanel() {
        let panel = QuotaPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: collapsedIdeal),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        for btn in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(btn)?.isHidden = true
        }

        let host = NSHostingController(
            rootView: QuotaPanel(
                store: store,
                ui: ui,
                onHeightChange: { [weak self] expanded in
                    self?.applyHeight(expanded: expanded, animate: true)
                },
                onClose: { [weak panel] in panel?.orderOut(nil) }
            )
        )
        if #available(macOS 13.0, *) {
            host.sizingOptions = []
        }
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: Self.panelWidth, height: collapsedIdeal))
        self.panel = panel

        // 实测折叠态内容高度，窗口高度贴合内容（消除底部空白）
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let host = self.panel?.contentViewController as? NSHostingController<QuotaPanel> else { return }
            var ideal: CGFloat = 282   // 兜底值
            if #available(macOS 13.0, *) {
                let fit = host.sizeThatFits(in: CGSize(width: Self.panelWidth, height: 10000))
                qlog("sizeThatFits collapsed = \(fit)")
                if fit.height > 100 { ideal = ceil(fit.height) }
            }
            self.collapsedIdeal = min(420, max(240, ideal))
            qlog("collapsedIdeal final = \(self.collapsedIdeal)")
            if !self.uiExpandedActive {
                self.applyHeight(expanded: false, animate: false)
            }
        }
    }

    private var uiExpandedActive: Bool = false
    private func height(forExpanded expanded: Bool) -> CGFloat {
        expanded ? Self.detailHeight + collapsedIdeal + 16 : collapsedIdeal
    }

    private func applyHeight(expanded: Bool, animate: Bool) {
        uiExpandedActive = expanded
        guard let panel = panel else { return }
        let newH = height(forExpanded: expanded)
        var f = panel.frame
        guard abs(f.size.height - newH) > 0.5 else {
            qlog("applyHeight(\(expanded)) no-op (already \(newH))")
            return
        }
        let top = f.maxY
        f.size.height = newH
        f.origin.y = top - newH
        qlog("applyHeight(\(expanded)) \(Int(f.size.height)) -> \(Int(newH))")
        panel.setFrame(f, display: true, animate: animate)
    }

    private func positionPanelUnderStatusIcon() {
        guard let panel = panel, let button = statusItem?.button, let frame = button.window?.frame else { return }
        let size = panel.frame.size
        let x = max(4, frame.maxX - size.width)
        let y = frame.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func togglePanel(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            if let ev = event { showMenu(ev) }
            return
        }
        store.refresh()
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            ui.requestCollapse()      // 每次打开先只显示彩虹（onChange 里收起并回调高度）
            positionPanelUnderStatusIcon()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func showMenu(_ event: NSEvent) {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "刷新全部额度", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        menu.addItem(withTitle: "打开配置目录", action: #selector(openConfig(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 QuotaBar", action: #selector(quitApp(_:)), keyEquivalent: "q")
        for it in menu.items { it.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func refreshNow(_ sender: Any?) { store.refresh() }

    @objc private func openConfig(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([store.configURL])
    }

    @objc private func quitApp(_ sender: Any?) { NSApp.terminate(nil) }
}

// MARK: - Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
