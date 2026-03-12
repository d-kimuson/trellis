import AppKit
import GhosttyKit
import QuartzCore

// MARK: - Supporting Types

/// Result of reading terminal text via ghostty_surface_read_text.
struct ScreenTextResult {
    let text: String
    /// Cell-grid offset (y * cols + x) where the currently visible viewport begins.
    /// NOT a byte offset — use `/ cols` to get the first visible visual row.
    let viewportCellOffset: Int
}

/// A single search match position within the terminal text, in visual (physical) rows/columns.
/// Physical rows account for soft-wrapped lines (no `\n` at wrap point in ghostty output).
struct FindMatch {
    let line: Int    // Visual row (relative to the text buffer it was searched in)
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
        findCurrentMatchExpectedViewportRow = -1
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
        return ScreenTextResult(text: text, viewportCellOffset: Int(rawText.offset_start))
    }

    /// Read only the currently visible viewport text.
    /// Returned match positions are viewport-relative (row 0 = top of visible area).
    private func readViewportText() -> String? {
        guard let surface else { return nil }

        let topLeft = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0, y: 0
        )
        let bottomRight = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
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

        return String(decoding: Data(bytes: ptr, count: Int(rawText.text_len)), as: UTF8.self)
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
                if !justSoftWrapped {
                    row += 1
                    col = 0
                }
                justSoftWrapped = false
            } else {
                col += 1
                justSoftWrapped = false
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
        let surfaceSize = ghostty_surface_size(surface)
        let visibleRows = max(1, Int(surfaceSize.rows))
        let cols = max(1, Int(surfaceSize.columns))

        // Re-read current viewport offset — may be stale if user scrolled manually since performFind.
        let currentViewportOffset = readScreenText().map { $0.viewportCellOffset } ?? findViewportOffset
        let viewportStartRow = currentViewportOffset / cols

        // Target: center the match vertically in the viewport.
        let targetFirstRow = max(0, match.line - visibleRows / 2)
        let linesToScroll = targetFirstRow - viewportStartRow

        // Pre-compute expected viewport row (will be refined after scroll settles).
        findCurrentMatchExpectedViewportRow = max(0, match.line - targetFirstRow)

        if linesToScroll != 0 {
            // ghostty's scroll_page_lines:N uses the scrollback-positive convention:
            // positive N = scroll UP (into scrollback / older content)
            // negative N = scroll DOWN (toward newest content)
            // linesToScroll = targetFirstRow - viewportStartRow, so we negate to match.
            let action = "scroll_page_lines:\(-linesToScroll)"
            action.withCString { cstr in
                _ = ghostty_surface_binding_action(surface, cstr, UInt(action.utf8.count))
            }
            let capturedMatch = match
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                // Refine expected row using the actual post-scroll viewport position.
                if let result = self.readScreenText() {
                    let actualStart = result.viewportCellOffset / max(1, self.findTerminalCols)
                    self.findCurrentMatchExpectedViewportRow = max(0, capturedMatch.line - actualStart)
                }
                self.drawHighlights()
            }
        } else {
            drawHighlights()
        }
    }

    /// Redraw highlights immediately. Call after any event that changes the visible viewport.
    func redrawHighlights() {
        guard session.isFindVisible, !findMatches.isEmpty else { return }
        drawHighlights()
    }

    /// Schedule a debounced highlight redraw. Used for key events where ghostty may scroll async.
    func scheduleHighlightRefresh() {
        guard session.isFindVisible, !findMatches.isEmpty else { return }
        highlightRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.drawHighlights()
        }
        highlightRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// Redraw highlights by searching the currently visible viewport text.
    /// Viewport-relative match positions require no offset calculation — row 0 = top of visible area.
    func drawHighlights() {
        guard let surface else { clearHighlights(); return }

        let query = session.findQuery
        guard !query.isEmpty, !findMatches.isEmpty else { clearHighlights(); return }

        guard let viewportText = readViewportText() else { clearHighlights(); return }

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

        // Search the viewport text — match.line is directly the viewport row (0 = top of screen).
        let viewportMatches = searchMatches(in: viewportText, query: query, cols: cols)

        // Identify which viewport match is the "current" one (shown in orange).
        // Primary key: column — the current global match has a known col.
        // When multiple viewport matches share the same col, use expected row as tiebreaker.
        let expectedRow = findCurrentMatchExpectedViewportRow
        let currentViewportMatch: FindMatch? = {
            guard session.findCurrentMatchIndex >= 1,
                  session.findCurrentMatchIndex <= findMatches.count else { return nil }
            let globalCol = findMatches[session.findCurrentMatchIndex - 1].col
            let sameCol = viewportMatches.filter { $0.col == globalCol }
            if sameCol.count == 1 { return sameCol[0] }
            if sameCol.count > 1 {
                return sameCol.min { abs($0.line - expectedRow) < abs($1.line - expectedRow) }
            }
            // Current match not visible — no orange indicator.
            return nil
        }()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        for match in viewportMatches {
            guard match.line >= 0, match.line < visibleRows else { continue }

            let x = CGFloat(match.col) * cellW
            let yFromTop = CGFloat(match.line) * cellH
            // CALayer/NSView macOS coordinate system: y=0 at bottom, increases upward.
            let y = bounds.height - yFromTop - cellH
            let matchW = max(CGFloat(match.cellLen) * cellW, cellW)

            // Compare (line, col) explicitly — avoid ambiguous tuple-shorthand closures.
            let isCurrent: Bool
            if let current = currentViewportMatch {
                isCurrent = current.line == match.line && current.col == match.col
            } else {
                isCurrent = false
            }

            let matchLayer = CALayer()
            matchLayer.frame = CGRect(x: x, y: y, width: matchW, height: cellH)
            matchLayer.cornerRadius = 2
            matchLayer.backgroundColor = isCurrent
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
