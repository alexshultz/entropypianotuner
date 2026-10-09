import SwiftUI

struct PianoKeyboard: View {
    var selected: Int
    var recorded: (Int) -> Bool
    var tuned: (Int) -> Bool
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(whiteKeys, id: \.self) { index in
                            keyFace(index, black: false)
                                .id(index)
                        }
                    }
                    HStack(spacing: 2) {
                        ForEach(whiteKeys, id: \.self) { index in
                            Color.clear
                                .frame(width: 34, height: 1)
                                .overlay(alignment: .topTrailing) {
                                    if let black = blackAfter(index) {
                                        keyFace(black, black: true)
                                            .offset(x: 12)
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
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(key, anchor: .center) }
            }
        }
        .frame(height: 168)
        .background(Color.black.opacity(0.35))
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
        let width: CGFloat = black ? 22 : 34
        let height: CGFloat = black ? 96 : 142
        return Button {
            onSelect(index)
        } label: {
            VStack {
                Spacer()
                Circle()
                    .fill(tuned(index) ? Theme.inTune : (recorded(index) ? Theme.amber : Color.clear))
                    .frame(width: 7, height: 7)
                    .padding(.bottom, black ? 8 : 10)
            }
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: black ? 4 : 5, style: .continuous)
                    .fill(fill(black: black, active: active))
            )
            .overlay(
                RoundedRectangle(cornerRadius: black ? 4 : 5, style: .continuous)
                    .stroke(active ? Theme.amber : Color.white.opacity(black ? 0 : 0.08), lineWidth: active ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .zIndex(black ? 1 : 0)
        .accessibilityLabel(PianoLayout.label(index))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func fill(black: Bool, active: Bool) -> Color {
        if black { return active ? Color(white: 0.22) : Color(white: 0.12) }
        return active ? Color(white: 0.92) : Color(white: 0.86)
    }
}
