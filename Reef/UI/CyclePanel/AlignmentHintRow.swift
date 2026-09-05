//
//  AlignmentHintRow.swift
//  Reef
//
//  The alignment key hints shown at the foot of the cycle panel, and the small live
//  diagram that shows what the selected window was just snapped to.
//

import SwiftUI

/// A one-line reminder of the alignment keys, shown while the panel lists real windows.
struct AlignmentHintRow: View {
    var body: some View {
        HStack(spacing: 12) {
            hint("HJKL", "halves")
            hint("⌥", "quarters")
            hint("M", "max")
            hint("C", "centre")
            hint("R", "undo")
        }
        .font(.caption2)
        .foregroundColor(.white.opacity(0.55))
        .frame(maxWidth: .infinity)
        .frame(height: CyclePanelMetrics.hintRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alignment keys: H J K L for halves, Option for quarters, "
                            + "M to maximise, C to centre, R to undo")
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(keys)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.8))
            Text(label)
        }
    }
}

/// A 16×11 thumbnail of the screen with the applied layout filled in.
///
/// Drawn by calling the very same `WindowLayout.frame(in:current:)` the aligner uses, so
/// it doubles as a live check that the geometry is doing what it claims.
struct LayoutBadge: View {
    let layout: WindowLayout

    private static let boxSize = CGSize(width: 16, height: 11)

    var body: some View {
        let bounds = CGRect(origin: .zero, size: LayoutBadge.boxSize)
        // Only `.center` reads `current`; give it a half-size window so the badge shows
        // a centred rectangle rather than a full one.
        let sample = CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height / 2)
        let rect = layout.frame(in: bounds, current: sample)

        // Accessibility space and SwiftUI's local space share a top-left origin with y
        // increasing downward, so the layout rect can be drawn without conversion.
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.75))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            RoundedRectangle(cornerRadius: 1.5)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: bounds.width, height: bounds.height)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .accessibilityLabel(layout.shortDescription)
    }
}
