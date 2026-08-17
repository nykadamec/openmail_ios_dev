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

/// A lightweight, non-scrolling WKWebView used as a fallback for HTML-only
/// messages. The document owns its typography and colours so an email cannot
/// accidentally render white text on a white web view. JavaScript remains
/// disabled because this view only needs to display already downloaded HTML.
struct EmailWebView: UIViewRepresentable {
    let html: String
    var onLoadFailure: (() -> Void)? = nil

    private static let minimumHeight: CGFloat = 120

    private var document: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            :root { color-scheme: light dark; }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              color: #1c1c1e;
              font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
              font-size: 17px;
              line-height: 1.45;
              overflow-wrap: anywhere;
              word-wrap: break-word;
            }
            body { min-height: 120px; }
            img, video, table { max-width: 100%; height: auto; }
            pre { white-space: pre-wrap; overflow-wrap: anywhere; }
            a { color: -apple-system-link; }
            @media (prefers-color-scheme: dark) {
              html, body { color: #f2f2f7; }
            }
          </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.heightAnchor.constraint(equalToConstant: Self.minimumHeight).isActive = true
        webView.loadHTMLString(document, baseURL: nil)
        context.coordinator.lastLoadedHTML = document
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != document {
            context.coordinator.lastLoadedHTML = document
            Self.setHeight(Self.minimumHeight, for: uiView)
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(of: webView)
            validateContent(of: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.measureHeight(of: webView)
                self.validateContent(of: webView)
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
            Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0,
                document.body ? document.body.offsetHeight : 0,
                document.documentElement ? document.documentElement.offsetHeight : 0
            )
            """

            webView.evaluateJavaScript(script) { result, _ in
                guard let number = result as? NSNumber else { return }
                let measuredHeight = number.doubleValue
                guard measuredHeight.isFinite, measuredHeight > 0 else { return }
                DispatchQueue.main.async {
                    EmailWebView.setHeight(CGFloat(measuredHeight), for: webView)
                }
            }
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
            webView.evaluateJavaScript(script) { result, _ in
                guard let hasContent = (result as? NSNumber)?.boolValue, !hasContent else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.onLoadFailure?()
                }
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
