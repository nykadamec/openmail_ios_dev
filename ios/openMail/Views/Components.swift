import SwiftUI
import WebKit

// MARK: - Avatar

/// A circular avatar showing the first letter of a sender's name.
/// Pick a deterministic colour from a small palette so a given sender
/// always renders with the same colour across the app.
struct AvatarView: View {
    let name: String

    private static let palette: [Color] = [
        .blue, .indigo, .purple, .pink, .red, .orange, .teal, .cyan, .green, .mint,
    ]

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var colour: Color {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        Circle()
            .fill(colour.gradient)
            .frame(width: 44, height: 44)
            .overlay(
                Text(initial)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - WebView

/// A lightweight WKWebView used to render HTML-only
/// messages. The document owns its typography and colours so an email cannot
/// accidentally render white text on a white web view. JavaScript remains
/// disabled because this view only needs to display already downloaded HTML.
struct EmailWebView: UIViewRepresentable {
    let html: String
    var onLoadFailure: (() -> Void)? = nil

    // A real initial frame is important here. SwiftUI's outer ScrollView can
    // otherwise offer UIViewRepresentable only a small fraction of its height
    // before WebKit has reported the document's size.
    private static let minimumHeight: CGFloat = 120
    private static let fallbackHeight: CGFloat = 600
    private static let maximumMeasuredHeight: CGFloat = 20_000

    private var document: String {
        Self.normalizedDocument(from: html)
    }

    private static let responsiveHead = """
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style data-openmail="responsive">
        :root { color-scheme: light dark; }
        html, body {
          margin: 0;
          padding: 0;
          max-width: 100%;
          background: transparent;
          color: #1c1c1e;
          font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
          font-size: 17px;
          line-height: 1.45;
          overflow-wrap: anywhere;
          word-wrap: break-word;
        }
        body { min-height: 120px; overflow-x: hidden; }
        img, video { max-width: 100%; height: auto; }
        table { max-width: 100%; }
        td, th { overflow-wrap: anywhere; word-wrap: break-word; }
        pre { white-space: pre-wrap; overflow-wrap: anywhere; }
        a { color: -apple-system-link; }
        @media (prefers-color-scheme: dark) {
          html, body { color: #f2f2f7; }
        }
      </style>
    """

    /// Email bodies are not necessarily fragments. In particular, newsletters
    /// commonly include their own doctype, head, and style elements. Wrapping
    /// such a body in another body creates an invalid document and changes how
    /// WebKit applies the newsletter's CSS, so only fragments are wrapped here.
    private static func normalizedDocument(from html: String) -> String {
        let lowercased = html.lowercased()
        let isCompleteDocument = lowercased.contains("<!doctype") ||
            lowercased.range(of: "<html(?:\\s|>)", options: .regularExpression) != nil

        guard isCompleteDocument else {
            return """
            <!doctype html>
            <html>
            <head>
            \(responsiveHead)
            </head>
            <body>\(html)</body>
            </html>
            """
        }

        var document = html
        // Put the compatibility rules before the email's own styles. This
        // keeps the original selectors and inline styles authoritative.
        if let headStart = document.range(of: "<head", options: .caseInsensitive),
           let openingTagEnd = document.range(of: ">", range: headStart.upperBound..<document.endIndex) {
            document.insert(contentsOf: responsiveHead, at: openingTagEnd.upperBound)
        } else if let bodyStart = document.range(of: "<body", options: .caseInsensitive) {
            document.insert(contentsOf: "<head>\(responsiveHead)</head>", at: bodyStart.lowerBound)
        } else {
            document = "<!doctype html><html><head>\(responsiveHead)</head><body>\(document)</body></html>"
        }

        return document
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Auto-height is preferred, but scrolling is the safe fallback for
        // documents whose height cannot be measured (or which are unusually
        // large). This also prevents an HTML body from being clipped.
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.heightAnchor.constraint(equalToConstant: Self.fallbackHeight).isActive = true
        context.coordinator.lastAppliedHeight = Self.fallbackHeight
        webView.loadHTMLString(document, baseURL: nil)
        context.coordinator.lastLoadedHTML = document
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onLoadFailure = onLoadFailure
        if context.coordinator.lastLoadedHTML != document {
            context.coordinator.lastLoadedHTML = document
            context.coordinator.applyHeight(Self.fallbackHeight, to: uiView)
            uiView.loadHTMLString(document, baseURL: nil)
        }
    }

    private static func setHeight(_ height: CGFloat, for webView: WKWebView) {
        for constraint in webView.constraints where constraint.firstAttribute == .height {
            constraint.isActive = false
        }
        webView.heightAnchor.constraint(equalToConstant: max(height, minimumHeight)).isActive = true
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String?
        var onLoadFailure: (() -> Void)?
        var lastAppliedHeight: CGFloat?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(of: webView)
            validateContent(of: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.measureHeight(of: webView)
                self.validateContent(of: webView)
            }
            // Images and late-running layout work can change the DOM after
            // didFinish. A second pass catches those changes without using a
            // continuous layout observer (which would loop in SwiftUI's
            // enclosing ScrollView).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.measureHeight(of: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.onLoadFailure?()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.onLoadFailure?()
            }
        }

        private func measureHeight(of webView: WKWebView) {
            let script = """
            (() => {
                const body = document.body;
                const root = document.documentElement;
                return Math.max(
                    body ? body.scrollHeight : 0,
                    root ? root.scrollHeight : 0,
                    body ? body.offsetHeight : 0,
                    root ? root.offsetHeight : 0,
                    body ? body.getBoundingClientRect().height : 0,
                    root ? root.getBoundingClientRect().height : 0
                );
            })()
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard error == nil, let number = result as? NSNumber else {
                    self?.notifyLoadFailure()
                    return
                }
                let measuredHeight = number.doubleValue
                guard measuredHeight.isFinite, measuredHeight > 0 else {
                    self?.notifyLoadFailure()
                    return
                }
                DispatchQueue.main.async {
                    let domHeight = min(CGFloat(measuredHeight), EmailWebView.maximumMeasuredHeight)
                    // DOM height is authoritative when JavaScript returns a
                    // valid value. WebKit's contentSize is useful as a native
                    // safety net for the small/partially laid-out documents.
                    let nativeHeight = webView.scrollView.contentSize.height
                    let height = domHeight >= EmailWebView.minimumHeight
                        ? domHeight
                        : max(domHeight, min(nativeHeight, EmailWebView.maximumMeasuredHeight))
                    self?.applyHeight(height, to: webView)
                }
            }
        }

        /// Change the constraint only when the result is materially different.
        /// This makes the representable settle instead of feeding every SwiftUI
        /// layout pass back into WebKit.
        fileprivate func applyHeight(_ height: CGFloat, to webView: WKWebView) {
            let safeHeight = min(max(height, EmailWebView.minimumHeight), EmailWebView.maximumMeasuredHeight)
            if let lastAppliedHeight, abs(lastAppliedHeight - safeHeight) < 1 {
                return
            }
            lastAppliedHeight = safeHeight
            EmailWebView.setHeight(safeHeight, for: webView)
        }

        private func validateContent(of webView: WKWebView) {
            // A successful navigation can still leave an empty document
            // (for example malformed or stripped HTML). Let the SwiftUI
            // caller show its plain-text/empty-body fallback in that case.
            let script = """
            Boolean(document.body && (
                document.body.innerText.trim().length > 0 ||
                document.body.querySelector('img, video, table, svg') !== null
            ))
            """
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard error == nil else {
                    self?.notifyLoadFailure()
                    return
                }
                guard let hasContent = (result as? NSNumber)?.boolValue else {
                    self?.notifyLoadFailure()
                    return
                }
                if !hasContent {
                    self?.notifyLoadFailure()
                }
            }
        }

        private func notifyLoadFailure() {
            DispatchQueue.main.async { [weak self] in
                self?.onLoadFailure?()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onLoadFailure = onLoadFailure
        return coordinator
    }
}

// MARK: - Activity view controller bridge

/// A tiny bridge used to present `UIActivityViewController` for sharing an
/// attachment file. Kept separate from `EmailWebView` on purpose.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Date helpers

extension String {
    /// Parses the uncommon date formats returned by the backend:
    /// SQLite `yyyy-MM-dd HH:mm:ss` plus a few ISO 8601 variants.
    func openmailDate() -> Date? {
        let locale = Locale(identifier: "en_US_POSIX")
        let sql = DateFormatter()
        sql.locale = locale
        sql.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = sql.date(from: self) { return date }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: self) { return date }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self)
    }
}

/// A short, locale-aware timestamp for list rows: time-of-day for today,
/// weekday within the last week, and an abbreviated date otherwise.
func smartTimeLabel(from raw: String?) -> String {
    guard let raw, let date = raw.openmailDate() else { return "" }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return date.formatted(date: .omitted, time: .shortened)
    }
    if let weekAgo = calendar.date(byAdding: .day, value: -6, to: Date()),
       date >= weekAgo {
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
    return date.formatted(date: .abbreviated, time: .omitted)
}

/// A full, locale-aware timestamp for the email detail screen.
func longTimeLabel(from raw: String?) -> String {
    guard let raw, let date = raw.openmailDate() else { return "" }
    return date.formatted(date: .complete, time: .shortened)
}
