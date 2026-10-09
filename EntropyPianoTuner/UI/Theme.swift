import SwiftUI

extension PitchVerdict {
    var color: Color {
        switch self {
        case .listening: return .secondary
        case .inTune: return .green
        case .flat: return .blue
        case .sharp: return .red
        }
    }
}

/// The system has no cents meter. The readout uses a text style so it follows Dynamic Type.
struct Meter: View {
    var cents: Double?
    var level: Double
    var compact = false

    @ScaledMetric(relativeTo: .title) private var baseDial = 190.0

    var body: some View {
        let dial = compact ? baseDial * 0.58 : baseDial
        let gauge = dial * 0.8
        let bar = dial * 1.15
        let verdict = PitchVerdict.from(cents: cents)
        VStack(spacing: compact ? 8 : 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: compact ? 6 : 10)
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: compact ? 6 : 10, lineCap: .round))
                    .rotationEffect(.degrees(180))
                Needle(cents: cents ?? 0)
                    .stroke(verdict.color, style: StrokeStyle(lineWidth: compact ? 3 : 4, lineCap: .round))
                    .frame(width: gauge, height: gauge)
            }
            .frame(width: dial, height: compact ? dial * 0.72 : dial * 0.78)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cents.map { String(format: "%+.1f cents", $0) } ?? "No pitch")

            VStack(spacing: 0) {
                Text(cents.map { String(format: "%+.1f", $0) } ?? "—")
                    .font(compact ? .title3 : .title)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(verdict.color)
                Text("cents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: compact ? 4 : 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: max(6, bar * level))
                }
                .frame(width: bar)
                .accessibilityLabel("Level")
                .accessibilityValue("\(Int(level * 100)) percent")
        }
    }
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

/// The system has no tuning-curve chart. Dragging or adjusting the curve selects a key.
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
                context.stroke(axis, with: .color(.secondary.opacity(0.45)), lineWidth: 1)
                guard cents.count > 1 else { return }
                let limit = max(20, cents.map(abs).max() ?? 20)
                var line = Path()
                for (index, value) in cents.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(cents.count - 1)
                    let y = size.height * (0.5 - CGFloat(value / limit) * 0.42)
                    if index == 0 { line.move(to: CGPoint(x: x, y: y)) }
                    else { line.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                if selected >= 0, selected < cents.count {
                    let x = size.width * CGFloat(selected) / CGFloat(cents.count - 1)
                    let y = size.height * (0.5 - CGFloat(cents[selected] / limit) * 0.42)
                    let dot = Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
                    context.fill(dot, with: .color(.primary))
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                onSelect(index(at: value.location.x, width: width))
            })
            .frame(width: width, height: height)
        }
        .accessibilityElement()
        .accessibilityLabel("Tuning curve")
        .accessibilityValue(selected >= 0 && selected < cents.count ? PianoLayout.label(selected) : "")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? selected + 1 : selected - 1
            onSelect(min(max(0, next), max(0, cents.count - 1)))
        }
    }

    private func index(at x: CGFloat, width: CGFloat) -> Int {
        let count = max(cents.count - 1, 1)
        let raw = Int((x / width * CGFloat(count)).rounded())
        return min(max(0, raw), max(0, cents.count - 1))
    }
}

extension View {
    /// The keyboard is a functional layer. `safeAreaBar` supplies the system bar, including Liquid Glass, and keeps the keys off the iPhone Duo side bar.
    @ViewBuilder
    func dockedKeyboard<Keyboard: View>(@ViewBuilder keyboard: () -> Keyboard) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) {
            keyboard()
        }
    }
}
