import SwiftUI

struct CyclePanelView: View {
    @ObservedObject var state: CyclePanelState

    private func itemTitle(_ item: CyclePanelItem) -> String {
        switch item {
        case .window(let window):
            return window.title
        case .action(let action):
            return action.title
        }
    }

    /// The badge belongs to the selected row only, and only once something has been
    /// applied to it.
    private func layout(forRowAt index: Int) -> WindowLayout? {
        index == state.selectedIndex ? state.lastLayout : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(state.applicationTitle)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.vertical, CyclePanelMetrics.headerPadding)

            Divider()
                .background(Color.white.opacity(0.2))

            if state.items.count <= CyclePanelMetrics.maxNonScrollingRows {
                VStack(spacing: CyclePanelMetrics.rowSpacing) {
                    ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                        CyclePanelRow(
                            title: itemTitle(item),
                            isSelected: index == state.selectedIndex,
                            layout: layout(forRowAt: index)
                        )
                        .id(index)
                    }
                }
                .padding(CyclePanelMetrics.listVerticalPadding)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: CyclePanelMetrics.rowSpacing) {
                            ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                                CyclePanelRow(
                                    title: itemTitle(item),
                                    isSelected: index == state.selectedIndex,
                                    layout: layout(forRowAt: index)
                                )
                                .id(index)
                            }
                        }
                        .padding(CyclePanelMetrics.listVerticalPadding)
                    }
                    .onChange(of: state.selectedIndex) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(state.selectedIndex, anchor: .center)
                        }
                    }
                }
            }

            if state.showsAlignmentHints {
                Divider()
                    .background(Color.white.opacity(0.2))

                AlignmentHintRow()
            }
        }
        .frame(width: CyclePanelMetrics.contentWidth)
        .background(Color.clear)
    }
}

struct CyclePanelRow: View {
    let title: String
    let isSelected: Bool
    var layout: WindowLayout?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)

            Text(title)
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)

            Spacer()

            if let layout {
                LayoutBadge(layout: layout)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: CyclePanelMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)

        )
    }
}
