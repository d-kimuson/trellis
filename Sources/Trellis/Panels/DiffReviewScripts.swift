// swiftlint:disable file_length
/// CSS and JavaScript for diff review comment functionality.
/// Extracted from SyntaxHighlightWebView to keep type body length manageable.
enum DiffReviewScripts {
    static let css: String = """
        .review-comment-row td { padding: 0 !important; }
        .review-comment-row td.review-cell {
            padding: 8px 12px !important;
            border-top: 1px solid var(--d2h-border-color, #d0d7de);
            border-bottom: 1px solid var(--d2h-border-color, #d0d7de);
        }
        .review-input-wrap {
            display: flex; align-items: flex-start; gap: 8px;
            background: var(--d2h-bg-color, #fff);
            border-radius: 6px; border: 1px solid var(--d2h-border-color, #d0d7de);
            padding: 8px;
        }
        .review-input-wrap textarea {
            flex: 1; border: none; outline: none; resize: vertical;
            font-family: 'SF Mono', 'Menlo', monospace;
            font-size: inherit; background: transparent;
            color: var(--d2h-color, inherit); min-height: 2.4em;
        }
        .review-input-wrap button {
            padding: 4px 10px; border-radius: 4px; border: none; cursor: pointer;
            font-size: 12px; white-space: nowrap;
        }
        .review-btn-save {
            background: #2ea043; color: #fff;
        }
        .review-btn-cancel {
            background: transparent; color: var(--d2h-dim-color, #636c76);
            border: 1px solid var(--d2h-border-color, #d0d7de) !important;
        }
        .review-saved {
            display: flex; align-items: flex-start; gap: 8px;
            background: var(--d2h-info-bg-color, #ddf4ff);
            border-radius: 6px; border: 1px solid var(--d2h-info-border-color, #54aeff66);
            padding: 8px; cursor: pointer;
        }
        .review-saved-text {
            flex: 1; white-space: pre-wrap; word-break: break-word;
            font-family: 'SF Mono', 'Menlo', monospace; font-size: inherit;
            color: var(--d2h-color, inherit);
        }
        .review-saved-actions { display: flex; gap: 4px; }
        .review-saved button {
            padding: 2px 6px; border-radius: 3px; border: none; cursor: pointer;
            font-size: 11px; background: transparent;
            color: var(--d2h-dim-color, #636c76);
        }
        .review-saved button:hover { background: var(--d2h-border-color, #d0d7de); }
        .d2h-code-linenumber {
            cursor: pointer;
            user-select: none;
            -webkit-user-select: none;
            pointer-events: auto !important;
            position: relative;
        }
        .d2h-code-linenumber:hover {
            background: var(--d2h-ins-highlight-bg-color, #abf2bc) !important;
        }
        .d2h-code-linenumber .review-add-btn {
            display: none;
            position: absolute; top: 50%; left: 2px;
            transform: translateY(-50%);
            width: 18px; height: 18px;
            border-radius: 4px; border: none;
            background: #2ea043; color: #fff;
            font-size: 14px; line-height: 18px;
            text-align: center; cursor: pointer;
            z-index: 2; padding: 0;
        }
        .d2h-code-linenumber:hover .review-add-btn {
            display: block;
        }
        """

    // swiftlint:disable:next function_body_length
    static let js: String = """
        var __reviews = {};
        function __notifyBridge() {
            var has = Object.keys(__reviews).some(function(k){ return __reviews[k].text; });
            try { webkit.messageHandlers.reviewUpdate.postMessage(has); } catch(e) {}
        }
        function __getReviewComments() {
            var arr = [];
            Object.keys(__reviews).forEach(function(k) {
                var r = __reviews[k];
                if (r.text) arr.push({line: parseInt(k), text: r.text});
            });
            return JSON.stringify(arr);
        }
        function __addCommentUI(lineNum, tr) {
            if (document.querySelector('.review-comment-row[data-line="'+lineNum+'"]')) return;
            var row = document.createElement('tr');
            row.className = 'review-comment-row';
            row.setAttribute('data-line', lineNum);
            var existing = __reviews[lineNum];
            if (existing && existing.text) {
                row.innerHTML = __savedHTML(lineNum, existing.text, tr.cells.length);
            } else {
                row.innerHTML = __inputHTML(lineNum, '', tr.cells.length);
            }
            tr.parentNode.insertBefore(row, tr.nextSibling);
        }
        function __inputHTML(lineNum, val, colspan) {
            return '<td class="review-cell" colspan="'+colspan+'">'
                + '<div class="review-input-wrap">'
                + '<textarea data-line="'+lineNum+'" placeholder="Comment...">'
                + __escHtml(val) + '</textarea>'
                + '<div style="display:flex;flex-direction:column;gap:4px;">'
                + '<button class="review-btn-save" onclick="__saveComment('+lineNum+')">Save</button>'
                + '<button class="review-btn-cancel" onclick="__cancelComment('+lineNum+')">Cancel</button>'
                + '</div></div></td>';
        }
        function __savedHTML(lineNum, text, colspan) {
            return '<td class="review-cell" colspan="'+colspan+'">'
                + '<div class="review-saved" onclick="__editComment('+lineNum+')">'
                + '<span class="review-saved-text">' + __escHtml(text) + '</span>'
                + '<div class="review-saved-actions">'
                + '<button onclick="event.stopPropagation();__editComment('+lineNum+')">Edit</button>'
                + '<button onclick="event.stopPropagation();__deleteComment('+lineNum+')">Delete</button>'
                + '</div></div></td>';
        }
        function __escHtml(t) {
            var d = document.createElement('div'); d.textContent = t; return d.innerHTML;
        }
        function __saveComment(lineNum) {
            var ta = document.querySelector('.review-comment-row[data-line="'+lineNum+'"] textarea');
            if (!ta) return;
            var text = ta.value.trim();
            if (!text) { __cancelComment(lineNum); return; }
            __reviews[lineNum] = {text: text};
            var row = document.querySelector('.review-comment-row[data-line="'+lineNum+'"]');
            if (row) {
                var colspan = row.querySelector('td').getAttribute('colspan');
                row.innerHTML = __savedHTML(lineNum, text, colspan);
            }
            __notifyBridge();
        }
        function __cancelComment(lineNum) {
            var row = document.querySelector('.review-comment-row[data-line="'+lineNum+'"]');
            if (row) row.remove();
            if (__reviews[lineNum] && !__reviews[lineNum].text) delete __reviews[lineNum];
        }
        function __editComment(lineNum) {
            var row = document.querySelector('.review-comment-row[data-line="'+lineNum+'"]');
            if (!row) return;
            var existing = __reviews[lineNum];
            var colspan = row.querySelector('td').getAttribute('colspan');
            row.innerHTML = __inputHTML(lineNum, existing ? existing.text : '', colspan);
            var ta = row.querySelector('textarea');
            if (ta) { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }
        }
        function __deleteComment(lineNum) {
            delete __reviews[lineNum];
            var row = document.querySelector('.review-comment-row[data-line="'+lineNum+'"]');
            if (row) row.remove();
            __notifyBridge();
        }
        function __getLineNum(cell) {
            var el2 = cell.querySelector('.line-num2');
            var el1 = cell.querySelector('.line-num1');
            var n2 = el2 ? parseInt(el2.textContent.trim()) : NaN;
            if (!isNaN(n2) && n2 > 0) return n2;
            var n1 = el1 ? parseInt(el1.textContent.trim()) : NaN;
            if (!isNaN(n1) && n1 > 0) return n1;
            return NaN;
        }
        function __injectAddButtons() {
            document.querySelectorAll('td.d2h-code-linenumber').forEach(function(cell) {
                if (cell.querySelector('.review-add-btn')) return;
                var num = __getLineNum(cell);
                if (isNaN(num)) return;
                var btn = document.createElement('button');
                btn.className = 'review-add-btn';
                btn.textContent = '+';
                btn.setAttribute('data-line', num);
                cell.insertBefore(btn, cell.firstChild);
            });
        }
        __injectAddButtons();
        // Use event delegation so the listener works even if the DOM is mutated after setup.
        document.addEventListener('click', function(e) {
            var cell = e.target.closest('td.d2h-code-linenumber');
            if (!cell) return;
            var num = __getLineNum(cell);
            if (isNaN(num)) return;
            var tr = cell.closest('tr');
            if (!tr) return;
            __addCommentUI(num, tr);
            setTimeout(function() {
                var ta = document.querySelector(
                    '.review-comment-row[data-line="'+num+'"] textarea');
                if (ta) ta.focus();
            }, 50);
        });
        """
}
// swiftlint:enable file_length
