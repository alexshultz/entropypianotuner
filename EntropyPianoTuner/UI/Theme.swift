import SwiftUI

enum Theme {
    static let ink = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let muted = Color(red: 0.72, green: 0.68, blue: 0.60)
    static let amber = Color(red: 0.93, green: 0.62, blue: 0.28)
    static let inTune = Color(red: 0.42, green: 0.78, blue: 0.48)
    static let flat = Color(red: 0.45, green: 0.62, blue: 0.95)
    static let sharp = Color(red: 0.93, green: 0.45, blue: 0.32)
    static let card = Color.white.opacity(0.06)
    static let background = Color(red: 0.08, green: 0.07, blue: 0.06)
}

struct Meter: View {
    var cents: Double?
    var level: Double
    var compact = false

    var body: some View {
        let gauge = compact ? 88.0 : 150.0
        let dial = compact ? 110.0 : 190.0
        let readout = compact ? 22.0 : 42.0
        let bar = compact ? 120.0 : 220.0
        VStack(spacing: compact ? 8 : 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: compact ? 6 : 10)
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: compact ? 6 : 10, lineCap: .round))
                    .rotationEffect(.degrees(180))
                Needle(cents: cents ?? 0)
                    .stroke(color, style: StrokeStyle(lineWidth: compact ? 3 : 4, lineCap: .round))
                    .frame(width: gauge, height: gauge)
                VStack(spacing: 2) {
                    Text(cents.map { String(format: "%+.1f", $0) } ?? "—")
                        .font(.system(size: readout, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    Text("cents")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                .offset(y: compact ? 16 : 28)
            }
            .frame(width: dial, height: compact ? 96 : 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cents.map { String(format: "%+.1f cents", $0) } ?? "No pitch")
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: compact ? 4 : 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.amber)
                        .frame(width: max(6, bar * level))
                }
                .frame(width: bar)
                .accessibilityLabel("Level")
                .accessibilityValue("\(Int(level * 100)) percent")
        }
    }

    private var color: Color {
        guard let cents else { return Theme.muted }
        if abs(cents) < 1 { return Theme.inTune }
        return cents < 0 ? Theme.flat : Theme.sharp
    }

    private var ink: Color { color }
}

private struct Needle: Shape {
    var cents: Double
    func path(in rect: CGRect) -> Path {
        let clamped = min(50, max(-50, cents))
        let angle = (-90 + clamped / 50 * 70) * .pi / 180
        let reach = min(rect.width, rect.height) * 0.41
        let center = CGPoint(x: rect.midX, y: rect.midY + reach * 0.16)
        let end = CGPoint(x: center.x + CGFloat(cos(angle)) * reach, y: center.y + CGFloat(sin(angle)) * reach)
        var path = Path()
        path.move(to: center)
        path.addLine(to: end)
        return path
    }
}

struct TuningCurve: View {
    var cents: [Double]
    var selected: Int
    var onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            Canvas { context, size in
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: size.height / 2))
                axis.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(axis, with: .color(.white.opacity(0.15)), lineWidth: 1)
                guard cents.count > 1 else { return }
                let limit = max(20, cents.map(abs).max() ?? 20)
                var line = Path()
                for (index, value) in cents.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(cents.count - 1)
                    let y = size.height * (0.5 - CGFloat(value / limit) * 0.42)
                    if index == 0 { line.move(to: CGPoint(x: x, y: y)) }
                    else { line.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(line, with: .color(Theme.amber), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                if selected >= 0, selected < cents.count {
                    let x = size.width * CGFloat(selected) / CGFloat(cents.count - 1)
                    let y = size.height * (0.5 - CGFloat(cents[selected] / limit) * 0.42)
                    let dot = Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
                    context.fill(dot, with: .color(Theme.ink))
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let index = Int((value.location.x / width * CGFloat(max(cents.count - 1, 1))).rounded())
                onSelect(min(max(0, index), max(0, cents.count - 1)))
            })
            .frame(width: width, height: height)
        }
    }
}

extension View {
    /// Pins the keyboard to the bottom edge. On iOS 26 and later the bar
    /// reserves its own space and moves aside when the system bar does,
    /// including the vertical bar on iPhone Duo.
    @ViewBuilder
    func dockedKeyboard<Keyboard: View>(@ViewBuilder keyboard: () -> Keyboard) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, watchOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0) {
                keyboard()
            }
        } else {
            VStack(spacing: 0) {
                self
                keyboard()
            }
        }
    }
}
