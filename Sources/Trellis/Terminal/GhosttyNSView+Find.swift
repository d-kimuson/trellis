import AppKit
import GhosttyKit
import QuartzCore

// MARK: - Supporting Types

/// Result of reading all terminal text (scrollback + viewport).
struct ScreenTextResult {
    let bytes: [UInt8]
    /// Byte offset in `bytes` where the currently visible viewport begins.
    let viewportOffset: Int
}

/// A single search match position within the terminal text.
struct FindMatch {
    let line: Int
    let col: Int
    let byteLen: Int
}

// MARK: - GhosttyNSView Find Extension

extension GhosttyNSView {

    // MARK: Internal API (called from setupFindSubscriptions / FindBarView)

    func performFind() {
        let query = session.findQuery

        guard !query.isEmpty, session.isFindVisible else {
            clearFind()
            return
        }

        guard let result = readScreenText() else {
            clearFind()
            return
        }

        findTextBytes = result.bytes
        findViewportOffset = result.viewportOffset

        let matches = searchMatches(in: result.bytes, query: query)
        findMatches = matches

        let prevCount = session.findMatchCount
        session.findMatchCount = matches.count

        if matches.isEmpty {
            session.findCurrentMatchIndex = 0
            clearHighlights()
        } else {
            // Keep current index in bounds, or start at the first match.
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
        findTextBytes = []
        findViewportOffset = 0
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

        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let ptr = text.text, text.text_len > 0 else { return nil }

        let bytes = [UInt8](Data(bytes: ptr, count: Int(text.text_len)))
        return ScreenTextResult(bytes: bytes, viewportOffset: Int(text.offset_start))
    }

    /// Find all occurrences of `query` (case-insensitive, ASCII-only approximation) in `bytes`.
    private func searchMatches(in bytes: [UInt8], query: String) -> [FindMatch] {
        let queryBytes = [UInt8](query.lowercased().utf8)
        guard !queryBytes.isEmpty, bytes.count >= queryBytes.count else { return [] }

        var matches: [FindMatch] = []
        var i = 0
        var currentLine = 0
        var currentCol = 0

        while i <= bytes.count - queryBytes.count {
            // Case-insensitive ASCII comparison (lower bits trick for a-z).
            let slice = bytes[i..<(i + queryBytes.count)]
            let matchesHere = zip(slice, queryBytes).allSatisfy { ($0 | 0x20) == $1 }

            if matchesHere {
                matches.append(FindMatch(line: currentLine, col: currentCol, byteLen: queryBytes.count))
                for b in slice {
                    if b == UInt8(ascii: "\n") { currentLine += 1; currentCol = 0 } else { currentCol += 1 }
                }
                i += queryBytes.count
            } else {
                if bytes[i] == UInt8(ascii: "\n") { currentLine += 1; currentCol = 0 } else { currentCol += 1 }
                i += 1
            }
        }

        return matches
    }

    private func scrollToCurrentMatch() {
        guard !findMatches.isEmpty,
              session.findCurrentMatchIndex >= 1,
              session.findCurrentMatchIndex <= findMatches.count,
              let surface else { return }

        let match = findMatches[session.findCurrentMatchIndex - 1]
        let viewportStartLine = countNewlines(in: findTextBytes, upTo: findViewportOffset)
        let surfaceSize = ghostty_surface_size(surface)
        let visibleRows = max(1, Int(surfaceSize.rows))

        // Center the match vertically in the viewport.
        let targetFirstLine = match.line - visibleRows / 2
        let linesToScroll = targetFirstLine - viewportStartLine

        if linesToScroll != 0 {
            let action = "scroll_page_lines:\(linesToScroll)"
            action.withCString { cstr in
                _ = ghostty_surface_binding_action(surface, cstr, UInt(action.utf8.count))
            }
            // Re-read viewport offset after ghostty processes the scroll command.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.refreshHighlightsAfterScroll()
            }
        } else {
            refreshHighlightsAfterScroll()
        }
    }

    private func refreshHighlightsAfterScroll() {
        guard let result = readScreenText() else {
            clearHighlights()
            return
        }
        findTextBytes = result.bytes
        findViewportOffset = result.viewportOffset
        drawHighlights()
    }

    func drawHighlights() {
        guard let surface else { clearHighlights(); return }

        let surfaceSize = ghostty_surface_size(surface)
        guard surfaceSize.cell_width_px > 0, surfaceSize.cell_height_px > 0 else {
            clearHighlights()
            return
        }

        let scale = window?.backingScaleFactor ?? 1.0
        let cellW = CGFloat(surfaceSize.cell_width_px) / scale
        let cellH = CGFloat(surfaceSize.cell_height_px) / scale
        let visibleRows = Int(surfaceSize.rows)
        let viewportStartLine = countNewlines(in: findTextBytes, upTo: findViewportOffset)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        for (index, match) in findMatches.enumerated() {
            let lineInViewport = match.line - viewportStartLine
            guard lineInViewport >= 0, lineInViewport < visibleRows else { continue }

            let x = CGFloat(match.col) * cellW
            let yFromTop = CGFloat(lineInViewport) * cellH
            // CALayer/NSView macOS coordinate system: y=0 at bottom, increases upward.
            let y = bounds.height - yFromTop - cellH
            let matchW = max(CGFloat(match.byteLen) * cellW, cellW)

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

    func countNewlines(in bytes: [UInt8], upTo limit: Int) -> Int {
        let clampedLimit = min(limit, bytes.count)
        return bytes[0..<clampedLimit].reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
    }
}
