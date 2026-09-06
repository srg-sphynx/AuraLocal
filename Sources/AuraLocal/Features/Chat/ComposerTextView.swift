//
//  Aura Local — local-first RAG chat for macOS
//  Copyright (c) 2026 srg-sphynx. All rights reserved.
//
//  Source-available, NOT open source. Personal, non-commercial evaluation only.
//  Redistribution, forks, derivative works, and commercial use are prohibited
//  without express written permission. See LICENSE at the project root.
//

import SwiftUI
import AppKit

/// Multi-line chat input backed by `NSTextView` so we get precise key handling:
/// **Return sends**, **⇧Return / ⌥Return inserts a newline**. SwiftUI's `TextEditor`
/// swallows the Return key and never fires `.onSubmit`, and `TextField(axis:.vertical)`
/// submit behavior is inconsistent across macOS releases — hence this AppKit bridge.
///
/// The view reports its content height back through `height` (clamped to
/// `minHeight…maxHeight`) so the composer can grow with the text and start
/// scrolling once it hits the cap.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    /// Drives the focus ring in the composer chrome.
    @Binding var isFocused: Bool
    /// Invoked when the user presses Return (without a modifier).
    var onSend: () -> Void

    var minHeight: CGFloat = 24
    var maxHeight: CGFloat = 120

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = Self.font()
        textView.textColor = NSColor(Theme.Palette.onSurface)
        textView.insertionPointColor = NSColor(Theme.Palette.primary)
        textView.string = text

        context.coordinator.textView = textView
        // Take focus on first appearance so the user can just start typing.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        // Only overwrite when the model diverges (e.g. cleared after send) so we
        // don't stomp the cursor position on every keystroke.
        if textView.string != text {
            textView.string = text
        }
        // Re-apply theme-driven appearance (font scale / accent can change live).
        textView.font = Self.font()
        textView.textColor = NSColor(Theme.Palette.onSurface)
        textView.insertionPointColor = NSColor(Theme.Palette.primary)

        context.coordinator.recalculateHeight()
    }

    private static func font() -> NSFont {
        NSFont.systemFont(ofSize: 13 * ThemeManager.fontScaleValue)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            recalculateHeight()
        }

        func textDidBeginEditing(_ notification: Notification) {
            setFocused(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            setFocused(false)
        }

        /// Intercept the Return key before `NSTextView` inserts a newline.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                // ⇧Return / ⌥Return → newline. Plain Return → send.
                if modifiers.contains(.shift) || modifiers.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSend()
                }
                return true
            }
            return false
        }

        func recalculateHeight() {
            guard let tv = textView,
                  let layoutManager = tv.layoutManager,
                  let container = tv.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let inset = tv.textContainerInset.height * 2
            let clamped = min(max(used + inset, parent.minHeight), parent.maxHeight)
            // Scroll once the content outgrows the cap.
            tv.enclosingScrollView?.hasVerticalScroller = (used + inset) > parent.maxHeight
            if abs(parent.height - clamped) > 0.5 {
                DispatchQueue.main.async { [height = parent.$height] in
                    height.wrappedValue = clamped
                }
            }
        }

        private func setFocused(_ value: Bool) {
            guard parent.isFocused != value else { return }
            DispatchQueue.main.async { [focused = parent.$isFocused] in
                focused.wrappedValue = value
            }
        }
    }
}
