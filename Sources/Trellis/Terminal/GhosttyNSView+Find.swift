import AppKit
import GhosttyKit
import QuartzCore

// MARK: - Supporting Types

/// Result of reading all terminal text (scrollback + viewport).
struct ScreenTextResult {
    let text: String
    /// Cell-grid offset (y * cols + x) where the currently visible viewport begins.
    /// NOT a byte offset — use `/ cols` to get the first visible visual row.
    let viewportCellOffset: Int
}

/// A single search match position within the terminal text, in visual (physical) rows/columns.
/// Physical rows account for soft-wrapped lines (no `\n` at wrap point in ghostty output).
struct FindMatch {
    let line: Int    // Visual row from top of SCREEN (including scrollback)
    let col: Int     // Column within that visual row
    let cellLen: Int // Approximate cell width of the matched text
}

// MARK: - GhosttyNSView Find Extension

extension GhosttyNSView {

    // MARK: Internal API

    func performFind() {
        let query = session.findQuery

        guard !query.isEmpty, session.isFindVisible else {
            clearFind()
            return
        }

        guard let surface, let result = readScreenText() else {
            clearFind()
            return
        }

        let cols = Int(ghostty_surface_size(surface).columns)
        findTextContent = result.text
        findViewportOffset = result.viewportCellOffset
        findTerminalCols = cols

        let matches = searchMatches(in: result.text, query: query, cols: cols)
        findMatches = matches

        let prevCount = session.findMatchCount
        session.findMatchCount = matches.count

        if matches.isEmpty {
            session.findCurrentMatchIndex = 0
            clearHighlights()
        } else {
            let idx = prevCount > 0 ? min(session.findCurrentMatchIndex, matches.count) : 1
            session.findCurrentMatchIndex = max(1, idx)
            scrollToCurrentMatch()
        }
    }

    func navigateFind(forward: Bool) {
        guard session.findMatchCount > 0 else { return }
        let count = session.findMatchCount
        if forward {
            session.findCurrentMatchIndex = (session.findCurrentMatchIndex % count) + 1
        } else {
            session.findCurrentMatchIndex = ((session.findCurrentMatchIndex - 2 + count) % count) + 1
        }
        scrollToCurrentMatch()
    }

    func clearFind() {
        findMatches = []
        findTextContent = ""
        findTextBytes = []
        findViewportOffset = 0
        findTerminalCols = 0
        session.findMatchCount = 0
        session.findCurrentMatchIndex = 0
        clearHighlights()
    }

    // MARK: Private Helpers

    /// Read all terminal text (scrollback + visible viewport) using SCREEN coordinates.
    func readScreenText() -> ScreenTextResult? {
        guard let surface else { return nil }

        let topLeft = ghostty_point_s(
            tag: GHOSTTY_POINT_SCREEN,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0, y: 0
        )
        let bottomRight = ghostty_point_s(
            tag: GHOSTTY_POINT_SCREEN,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: 0, y: 0
        )
        let selection = ghostty_selection_s(
            top_left: topLeft,
            bottom_right: bottomRight,
            rectangle: false
        )

        var rawText = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &rawText) else { return nil }
        defer { ghostty_surface_free_text(surface, &rawText) }
        guard let ptr = rawText.text, rawText.text_len > 0 else { return nil }

        let text = String(decoding: Data(bytes: ptr, count: Int(rawText.text_len)), as: UTF8.self)
        // offset_start = y * cols + x in the terminal's cell grid — NOT a byte offset.
        return ScreenTextResult(text: text, viewportCellOffset: Int(rawText.offset_start))
    }

    /// Find all matches of `query` using Swift string search (Unicode-aware, case-insensitive).
    /// Physical row/col accounts for soft-wrapped lines by wrapping at `cols`.
    private func searchMatches(in text: String, query: String, cols: Int) -> [FindMatch] {
        guard !query.isEmpty else { return [] }

        var matches: [FindMatch] = []
        var searchFrom = text.startIndex

        while let range = text.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchFrom..<text.endIndex
        ) {
            let prefix = text[text.startIndex..<range.lowerBound]
            let (row, col) = physicalPosition(of: prefix, cols: cols)
            let cellLen = query.unicodeScalars.count
            matches.append(FindMatch(line: row, col: col, cellLen: cellLen))
            // Advance past this match (by at least 1 scalar to avoid infinite loop on empty match).
            searchFrom = text.index(after: range.lowerBound)
            if range.upperBound > searchFrom { searchFrom = range.upperBound }
        }

        return matches
    }

    /// Compute visual (physical) row and column for a text prefix, accounting for soft-wrapped lines.
    /// ghostty pads short lines with trailing spaces to fill the full terminal width, then appends `\n`.
    /// Without the `justSoftWrapped` guard, the wrap-at-cols trigger and the subsequent `\n` would both
    /// increment the row counter, causing each padded row to count as two visual rows.
    private func physicalPosition(of prefix: Substring, cols: Int) -> (row: Int, col: Int) {
        var row = 0
        var col = 0
        var justSoftWrapped = false
        for scalar in prefix.unicodeScalars {
            if scalar == "\n" {
                // If we just soft-wrapped (col reached terminal width), the `\n` is the trailing
                // newline after padding — skip the row increment to avoid double-counting.
                if !justSoftWrapped {
                    row += 1
                    col = 0
                }
                justSoftWrapped = false
            } else {
                col += 1
                justSoftWrapped = false
                // When col reaches the terminal width, the line soft-wraps to the next visual row.
                if cols > 0 && col >= cols {
                    row += 1
                    col = 0
                    justSoftWrapped = true
                }
            }
        }
        return (row, col)
    }

    private func scrollToCurrentMatch() {
        guard !findMatches.isEmpty,
              session.findCurrentMatchIndex >= 1,
              session.findCurrentMatchIndex <= findMatches.count,
              let surface else { return }

        let match = findMatches[session.findCurrentMatchIndex - 1]
        let cols = max(1, findTerminalCols)
        // offset_start = y * cols + x, so dividing by cols gives the first visible visual row.
        let viewportStartRow = findViewportOffset / cols
        let surfaceSize = ghostty_surface_size(surface)
        let visibleRows = max(1, Int(surfaceSize.rows))

        // Target: center the match vertically in the viewport.
        let targetFirstRow = match.line - visibleRows / 2
        let linesToScroll = targetFirstRow - viewportStartRow

        if linesToScroll != 0 {
            let action = "scroll_page_lines:\(linesToScroll)"
            action.withCString { cstr in
                _ = ghostty_surface_binding_action(surface, cstr, UInt(action.utf8.count))
            }
            // Re-read viewport offset after ghostty processes the scroll.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.refreshHighlightsAfterScroll()
            }
        } else {
            refreshHighlightsAfterScroll()
        }
    }

    private func refreshHighlightsAfterScroll() {
        guard let result = readScreenText(), let surface else {
            clearHighlights()
            return
        }
        findViewportOffset = result.viewportCellOffset
        findTerminalCols = Int(ghostty_surface_size(surface).columns)
        drawHighlights()
    }

    /// Schedule a debounced highlight redraw to sync positions after scroll/key events.
    /// Safe to call frequently — only the last call within 60 ms fires.
    func scheduleHighlightRefresh() {
        guard session.isFindVisible, !findMatches.isEmpty else { return }
        highlightRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshHighlightsAfterScroll()
        }
        highlightRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    func drawHighlights() {
        guard let surface else { clearHighlights(); return }

        // Refresh viewport offset so highlights stay accurate after any scrolling.
        if let result = readScreenText() {
            findViewportOffset = result.viewportCellOffset
        }

        let surfaceSize = ghostty_surface_size(surface)
        guard surfaceSize.cell_width_px > 0, surfaceSize.cell_height_px > 0 else {
            clearHighlights()
            return
        }

        let scale = window?.backingScaleFactor ?? 1.0
        let cellW = CGFloat(surfaceSize.cell_width_px) / scale
        let cellH = CGFloat(surfaceSize.cell_height_px) / scale
        let visibleRows = Int(surfaceSize.rows)
        let cols = max(1, Int(surfaceSize.columns))
        // offset_start = y * cols + x → first visible visual row
        let viewportStartRow = findViewportOffset / cols

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        for (index, match) in findMatches.enumerated() {
            let lineInViewport = match.line - viewportStartRow
            guard lineInViewport >= 0, lineInViewport < visibleRows else { continue }

            let x = CGFloat(match.col) * cellW
            let yFromTop = CGFloat(lineInViewport) * cellH
            // CALayer/NSView macOS coordinate system: y=0 at bottom, increases upward.
            let y = bounds.height - yFromTop - cellH
            let matchW = max(CGFloat(match.cellLen) * cellW, cellW)

            let matchLayer = CALayer()
            matchLayer.frame = CGRect(x: x, y: y, width: matchW, height: cellH)
            matchLayer.cornerRadius = 2
            matchLayer.backgroundColor = (index == session.findCurrentMatchIndex - 1)
                ? NSColor.systemOrange.withAlphaComponent(0.55).cgColor
                : NSColor.systemYellow.withAlphaComponent(0.35).cgColor
            highlightLayer.addSublayer(matchLayer)
        }

        CATransaction.commit()
    }

    func clearHighlights() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
    }
}
