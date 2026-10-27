import SwiftUI

/// The web demo's 24px stroke icons, drawn from the same SVG markup so they look identical.
enum IconName: String, CaseIterable {
    case home, ticket, users, menu, hourglass, lock, unlock, flame, bolt, share, send, chevR, chevL, chevD, x, check, plus, minus
    case search, link, trophy, star, crown, user, userPlus, alert, info, bell, shield, sliders, logout, camera, clock, todo
    case chart, globe, phone, copy, edit, calendar, target, flask, ff, moon, trend, refresh, trash, eye, eyeOff, help, swap
    case dot, grid, radio, gift, wifiOff
}

private let iconMarkup: [IconName: String] = [
    .home: #"<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/><path d="M9.5 21v-6h5v6"/>"#,
    .ticket: #"<path d="M3 7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2.5a2.5 2.5 0 0 0 0 5V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2.5a2.5 2.5 0 0 0 0-5Z"/><path d="M14 5v2M14 11v2M14 17v2"/>"#,
    .users: #"<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8"/><path d="M18 14.2a6.5 6.5 0 0 1 3.5 5.8"/>"#,
    .menu: #"<path d="M4 6h16M4 12h16M4 18h16"/>"#,
    .hourglass: #"<path d="M6 3h12M6 21h12"/><path d="M7 3v3.5a5 5 0 0 0 2.4 4.3L12 12l2.6-1.2A5 5 0 0 0 17 6.5V3"/><path d="M7 21v-3.5a5 5 0 0 1 2.4-4.3L12 12l2.6 1.2a5 5 0 0 1 2.4 4.3V21"/>"#,
    .lock: #"<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>"#,
    .unlock: #"<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.8-1.3"/>"#,
    .flame: #"<path d="M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5 0 2 1 3 2 3 0-3-1-5.5 1-8.5Z"/>"#,
    .bolt: #"<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z"/>"#,
    .share: #"<path d="M12 3v12"/><path d="m7 8 5-5 5 5"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>"#,
    .send: #"<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7Z"/>"#,
    .chevR: #"<path d="m9 6 6 6-6 6"/>"#,
    .chevL: #"<path d="m15 6-6 6 6 6"/>"#,
    .chevD: #"<path d="m6 9 6 6 6-6"/>"#,
    .x: #"<path d="M18 6 6 18M6 6l12 12"/>"#,
    .check: #"<path d="m5 12.5 4.5 4.5L19 7"/>"#,
    .plus: #"<path d="M12 5v14M5 12h14"/>"#,
    .minus: #"<path d="M5 12h14"/>"#,
    .search: #"<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>"#,
    .link: #"<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>"#,
    .trophy: #"<path d="M8 21h8M12 17v4"/><path d="M7 4h10v5a5 5 0 0 1-10 0V4Z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>"#,
    .star: #"<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9Z"/>"#,
    .crown: #"<path d="m3 7 4.5 4L12 4l4.5 7L21 7l-2 12H5L3 7Z"/>"#,
    .user: #"<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>"#,
    .userPlus: #"<circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0M19 8v6M16 11h6"/>"#,
    .alert: #"<path d="M12 3 2 20h20L12 3Z"/><path d="M12 10v4M12 17v.5"/>"#,
    .info: #"<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>"#,
    .bell: #"<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10 21a2 2 0 0 0 4 0"/>"#,
    .shield: #"<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6l-8-3Z"/>"#,
    .sliders: #"<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>"#,
    .logout: #"<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/>"#,
    .camera: #"<path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13" r="4"/>"#,
    .clock: #"<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>"#,
    .todo: #"<path d="M11 6h10M11 12h10M11 18h10"/><path d="m3 6 1.5 1.5L7 5M3 12l1.5 1.5L7 11"/><rect x="3" y="16" width="4" height="4" rx="1"/>"#,
    .chart: #"<path d="M4 20V11M10 20V5M16 20v-6M2 20h20"/>"#,
    .globe: #"<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>"#,
    .phone: #"<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>"#,
    .copy: #"<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h8"/>"#,
    .edit: #"<path d="M4 20h4L19 9l-4-4L4 16v4Z"/>"#,
    .calendar: #"<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>"#,
    .target: #"<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>"#,
    .flask: #"<path d="M9 3h6M10 3v6L4 19a1.5 1.5 0 0 0 1.3 2h13.4A1.5 1.5 0 0 0 20 19l-6-10V3"/><path d="M7 15h10"/>"#,
    .ff: #"<path d="m4 6 8 6-8 6V6ZM12 6l8 6-8 6V6Z"/>"#,
    .moon: #"<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5Z"/>"#,
    .trend: #"<path d="m3 17 6-6 4 4 8-8M15 7h6v6"/>"#,
    .refresh: #"<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>"#,
    .trash: #"<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>"#,
    .eye: #"<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>"#,
    .eyeOff: #"<path d="M3 3l18 18M10.6 5.1A9.8 9.8 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.1 4M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>"#,
    .help: #"<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6M12 17v.5"/>"#,
    .swap: #"<path d="M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7"/>"#,
    .dot: #"<circle cx="12" cy="12" r="4" fill="currentColor"/>"#,
    .grid: #"<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>"#,
    .radio: #"<circle cx="12" cy="12" r="2"/><path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8"/>"#,
    .gift: #"<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M5 12v9h14v-9M12 8v13M12 8S10.5 3.5 8 4.5 9 8 12 8Zm0 0s1.5-4.5 4-3.5S15 8 12 8Z"/>"#,
    .wifiOff: #"<path d="M3 3l18 18"/><path d="M8.5 16.4a5 5 0 0 1 7 0M5 12.9a10 10 0 0 1 4.2-2.5M14.8 10.4A10 10 0 0 1 19 12.9M2 9.3a15 15 0 0 1 4.3-2.8M11 5.1A15 15 0 0 1 22 9.3"/><circle cx="12" cy="20" r="1" fill="currentColor"/>"#,
]

/// One parsed icon: stroked outlines plus a few filled dots, in a 24×24 box.
struct IconGeometry {
    var stroke = Path()
    var fill = Path()
}

enum IconLibrary {
    private static var cache: [IconName: IconGeometry] = [:]

    static func geometry(_ name: IconName) -> IconGeometry {
        if let hit = cache[name] { return hit }
        var geo = IconGeometry()
        for element in elements(iconMarkup[name] ?? "") {
            let path: Path
            switch element.tag {
            case "path": path = SVGPath.parse(element.attrs["d"] ?? "")
            case "circle":
                let cx = element.num("cx"), cy = element.num("cy"), r = element.num("r")
                path = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            case "rect":
                let rect = CGRect(x: element.num("x"), y: element.num("y"), width: element.num("width"), height: element.num("height"))
                let rx = element.num("rx")
                path = Path(roundedRect: rect, cornerSize: CGSize(width: rx, height: rx))
            default: continue
            }
            if element.attrs["fill"] == "currentColor" { geo.fill.addPath(path) } else { geo.stroke.addPath(path) }
        }
        cache[name] = geo
        return geo
    }

    private struct Element {
        var tag: String
        var attrs: [String: String]
        func num(_ k: String) -> CGFloat { CGFloat(Double(attrs[k] ?? "") ?? 0) }
    }

    private static func elements(_ markup: String) -> [Element] {
        var out: [Element] = []
        let scanner = markup as NSString
        let tagRegex = try! NSRegularExpression(pattern: #"<(\w+)([^>]*)/>"#)
        let attrRegex = try! NSRegularExpression(pattern: #"([\w-]+)="([^"]*)""#)
        for m in tagRegex.matches(in: markup, range: NSRange(location: 0, length: scanner.length)) {
            let tag = scanner.substring(with: m.range(at: 1))
            let body = scanner.substring(with: m.range(at: 2)) as NSString
            var attrs: [String: String] = [:]
            for a in attrRegex.matches(in: body as String, range: NSRange(location: 0, length: body.length)) {
                attrs[body.substring(with: a.range(at: 1))] = body.substring(with: a.range(at: 2))
            }
            out.append(Element(tag: tag, attrs: attrs))
        }
        return out
    }
}

/// A minimal SVG path-data parser (M L H V C S Q T A Z, absolute and relative).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens = tokenize(d)
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint? = nil
        var lastCmd: Character = " "

        func num() -> CGFloat {
            guard !tokens.isEmpty, case .number(let v) = tokens.first! else { return 0 }
            tokens.removeFirst()
            return CGFloat(v)
        }
        func flag() -> Bool { num() != 0 }

        while !tokens.isEmpty {
            if case .command(let c) = tokens.first! { cmd = c; tokens.removeFirst() }
            let rel = cmd.isLowercase
            let base = rel ? cur : .zero
            switch cmd.uppercased().first! {
            case "M":
                let p = CGPoint(x: base.x + num(), y: base.y + num())
                path.move(to: p); cur = p; start = p
                cmd = rel ? "l" : "L" // further pairs are implicit line-tos
            case "L":
                let p = CGPoint(x: base.x + num(), y: base.y + num())
                path.addLine(to: p); cur = p
            case "H":
                let x = (rel ? cur.x : 0) + num()
                cur = CGPoint(x: x, y: cur.y); path.addLine(to: cur)
            case "V":
                let y = (rel ? cur.y : 0) + num()
                cur = CGPoint(x: cur.x, y: y); path.addLine(to: cur)
            case "C":
                let c1 = CGPoint(x: base.x + num(), y: base.y + num())
                let c2 = CGPoint(x: base.x + num(), y: base.y + num())
                let p = CGPoint(x: base.x + num(), y: base.y + num())
                path.addCurve(to: p, control1: c1, control2: c2); lastCtrl = c2; cur = p
            case "S":
                let c1 = ("CS".contains(lastCmd.uppercased().first!) && lastCtrl != nil) ? CGPoint(x: 2 * cur.x - lastCtrl!.x, y: 2 * cur.y - lastCtrl!.y) : cur
                let c2 = CGPoint(x: base.x + num(), y: base.y + num())
                let p = CGPoint(x: base.x + num(), y: base.y + num())
                path.addCurve(to: p, control1: c1, control2: c2); lastCtrl = c2; cur = p
            case "Q":
                let c = CGPoint(x: base.x + num(), y: base.y + num())
                let p = CGPoint(x: base.x + num(), y: base.y + num())
                path.addQuadCurve(to: p, control: c); lastCtrl = c; cur = p
            case "A":
                let rx = num(), ry = num(), rot = num()
                let large = flag(), sweep = flag()
                let p = CGPoint(x: base.x + num(), y: base.y + num())
                addArc(&path, from: cur, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = p
            case "Z":
                path.closeSubpath(); cur = start
            default:
                tokens.removeFirst()
            }
            lastCmd = cmd
            if !"CcSsQq".contains(cmd) { lastCtrl = nil }
        }
        return path
    }

    private enum Token { case command(Character), number(Double) }

    private static func tokenize(_ d: String) -> [Token] {
        var out: [Token] = []
        var numStr = ""
        var sawDot = false, sawExp = false
        func flush() {
            if !numStr.isEmpty, let v = Double(numStr) { out.append(.number(v)) }
            numStr = ""; sawDot = false; sawExp = false
        }
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush(); out.append(.command(ch))
            } else if ch == "-" || ch == "+" {
                if let last = numStr.last, last == "e" || last == "E" { numStr.append(ch) } else { flush(); numStr.append(ch) }
            } else if ch == "." {
                if sawDot { flush() }
                numStr.append(ch); sawDot = true
            } else if ch.isNumber {
                numStr.append(ch)
            } else if ch == "e" || ch == "E" {
                numStr.append(ch); sawExp = true
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    /// SVG elliptical arc → cubic Béziers (W3C endpoint-to-center conversion).
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 || p0 == p1 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segments)
        let t = 4 / 3 * tan(delta / 4)
        var th = theta1
        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi, y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func deriv(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi, y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        for _ in 0..<segments {
            let a1 = th, a2 = th + delta
            let s = point(a1), e = point(a2)
            let d1 = deriv(a1), d2 = deriv(a2)
            path.addCurve(to: e, control1: CGPoint(x: s.x + t * d1.x, y: s.y + t * d1.y), control2: CGPoint(x: e.x - t * d2.x, y: e.y - t * d2.y))
            th = a2
        }
    }
}

/// An icon at `size` points, stroked in the current foreground color like the web's `currentColor`.
struct Icon: View {
    var name: IconName
    var size: CGFloat = 20

    init(_ name: IconName, _ size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    var body: some View {
        let geo = IconLibrary.geometry(name)
        let scale = size / 24
        ZStack {
            geo.stroke
                .applying(CGAffineTransform(scaleX: scale, y: scale))
                .stroke(style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))
            geo.fill.applying(CGAffineTransform(scaleX: scale, y: scale)).fill()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The TimeOut logo: a referee's "T" slanted 10° to match the italic wordmark.
struct BrandT: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 19, y: 23, width: 62, height: 16), cornerSize: CGSize(width: 8, height: 8))
        p.addRoundedRect(in: CGRect(x: 42, y: 44, width: 16, height: 33), cornerSize: CGSize(width: 8, height: 8))
        // translate(48 50) skewX(-10) translate(-50 -50)
        let skew = CGAffineTransform(a: 1, b: 0, c: tan(-10 * .pi / 180), d: 1, tx: 0, ty: 0)
        let t = CGAffineTransform(translationX: -50, y: -50).concatenating(skew).concatenating(CGAffineTransform(translationX: 48, y: 50))
        return p.applying(t)
    }
}

/// The T on its own, sized by height (viewBox 18.5 20 67 60).
struct BrandMark: View {
    var size: CGFloat = 20
    var body: some View {
        let w = (size * 1.12).rounded()
        BrandT()
            .fill()
            .frame(width: 100, height: 100)
            .offset(x: -18.5, y: -20)
            .frame(width: 67, height: 60, alignment: .topLeading)
            .scaleEffect(x: w / 67, y: size / 60, anchor: .topLeading)
            .frame(width: w, height: size, alignment: .topLeading)
            .accessibilityHidden(true)
    }
}

/// The same T on its green app-icon tile, for the welcome and login screens.
struct BrandIcon: View {
    var size: CGFloat = 56
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22.5, style: .continuous).fill(Color(hex: "#22D66E"))
                .frame(width: 100, height: 100)
            BrandT().fill(Color(hex: "#03140A")).frame(width: 100, height: 100)
        }
        .frame(width: 100, height: 100)
        .scaleEffect(size / 100)
        .frame(width: size, height: size)
        .shadow(color: Color(red: 34 / 255, green: 214 / 255, blue: 110 / 255).opacity(0.22), radius: 12, y: 10)
        .accessibilityLabel("TimeOut")
    }
}
