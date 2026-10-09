import SwiftUI

struct PianoKeyboard: View {
    var selected: Int
    var recorded: (Int) -> Bool
    var tuned: (Int) -> Bool
    var onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: CGFloat(PianoLayout.keySpacing)) {
                        ForEach(whiteKeys, id: \.self) { index in
                            keyFace(index, black: false)
                                .id(index)
                        }
                    }
                    HStack(spacing: CGFloat(PianoLayout.keySpacing)) {
                        ForEach(whiteKeys, id: \.self) { index in
                            Color.clear
                                .frame(width: CGFloat(PianoLayout.whiteKeyWidth), height: 1)
                                .overlay(alignment: .topTrailing) {
                                    if let black = blackAfter(index) {
                                        keyFace(black, black: true)
                                            .offset(x: CGFloat(PianoLayout.blackKeyOffset))
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, key in
                if reduceMotion {
                    proxy.scrollTo(key, anchor: .center)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(key, anchor: .center)
                    }
                }
            }
        }
        .frame(height: CGFloat(PianoLayout.whiteKeyHeight) + 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Piano keyboard")
    }

    private var whiteKeys: [Int] {
        (0..<PianoLayout.keyCount).filter { !PianoLayout.isBlack($0) }
    }

    private func blackAfter(_ white: Int) -> Int? {
        let next = white + 1
        guard next < PianoLayout.keyCount, PianoLayout.isBlack(next) else { return nil }
        return next
    }

    private func keyFace(_ index: Int, black: Bool) -> some View {
        let active = index == selected
        let width = CGFloat(black ? PianoLayout.blackKeyWidth : PianoLayout.whiteKeyWidth)
        let height = CGFloat(black ? PianoLayout.blackKeyHeight : PianoLayout.whiteKeyHeight)
        return Button {
            onSelect(index)
        } label: {
            VStack {
                Spacer()
                marker(index, black: black)
                    .padding(.bottom, black ? 8 : 10)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: black ? 4 : 6, style: .continuous)
                    .fill(fill(black: black, active: active))
            )
            .overlay(
                RoundedRectangle(cornerRadius: black ? 4 : 6, style: .continuous)
                    .stroke(active ? Color.accentColor : Color.primary.opacity(black ? 0.35 : 0.12), lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .zIndex(black ? 1 : 0)
        .accessibilityLabel(PianoLayout.label(index))
        .accessibilityValue(tuned(index) ? "Tuned" : (recorded(index) ? "Recorded" : "Not recorded"))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private func marker(_ index: Int, black: Bool) -> some View {
        if tuned(index) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.green)
                .frame(width: black ? 10 : 12, height: black ? 10 : 12)
        } else if recorded(index) {
            Circle()
                .fill(Color.orange)
                .frame(width: 7, height: 7)
        } else {
            Color.clear.frame(width: 7, height: 7)
        }
    }

    private func fill(black: Bool, active: Bool) -> Color {
        if black { return active ? Color(white: 0.28) : Color(white: 0.12) }
        return active ? Color.white : Color(white: 0.93)
    }
}
