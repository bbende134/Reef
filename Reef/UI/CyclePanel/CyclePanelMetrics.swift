//
//  CyclePanelMetrics.swift
//  Reef
//
//  One source of truth for the cycle panel's layout numbers.
//
//  CyclePanelController sizes the NSPanel arithmetically while CyclePanelView lays the
//  content out with SwiftUI, so the two have to agree. They previously agreed only by a
//  comment ("Keep these aligned with CyclePanelView") and had already drifted.
//

import CoreGraphics

enum CyclePanelMetrics {
    static let contentWidth: CGFloat = 400
    static let maxFrameHeightCap: CGFloat = 520

    /// Nominal header height used for panel sizing.
    ///
    /// Note this is slightly larger than the header actually measures (a `.headline`
    /// line plus `headerPadding` top and bottom). The value is preserved as-is so panel
    /// sizing is unchanged by the extraction; reconciling it is a cosmetic fix on its own.
    static let headerHeight: CGFloat = 44
    static let headerPadding: CGFloat = 12

    static let dividerHeight: CGFloat = 1

    static let rowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 4
    static let listVerticalPadding: CGFloat = 8

    /// Above this many windows the list scrolls instead of growing.
    static let maxNonScrollingRows: Int = 5

    /// The alignment hint footer.
    static let hintRowHeight: CGFloat = 26

    /// Height of the list area for a given number of rows.
    static func listHeight(rowCount: Int) -> CGFloat {
        let rows = CGFloat(rowCount) * rowHeight
        let spacing = CGFloat(max(0, rowCount - 1)) * rowSpacing
        return rows + spacing + (listVerticalPadding * 2)
    }

    /// Total content height for a given number of rows.
    static func contentHeight(rowCount: Int, includesHintRow: Bool) -> CGFloat {
        headerHeight
            + dividerHeight
            + listHeight(rowCount: rowCount)
            + (includesHintRow ? dividerHeight + hintRowHeight : 0)
    }
}
