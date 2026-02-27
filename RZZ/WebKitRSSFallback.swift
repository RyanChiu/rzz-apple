import Foundation
import WebKit

@MainActor
enum WebKitRSSFallback {
    static func fetchData(from url: URL, timeout: TimeInterval = 30) async throws -> Data {
        let loader = XMLPageLoader(url: url, timeout: timeout)
        let xml = try await loader.load()
        guard let data = xml.data(using: .utf8), !data.isEmpty else {
            throw RSSServiceError.invalidData
        }
        return data
    }
}

@MainActor
private final class XMLPageLoader: NSObject, WKNavigationDelegate {
    private let url: URL
    private let timeout: TimeInterval
    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(url: URL, timeout: TimeInterval) {
        self.url = url
        self.timeout = timeout
        self.webView = WKWebView(frame: .zero)
        super.init()
        webView.navigationDelegate = self
    }

    func load() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            startTimeoutTask()

            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            webView.load(request)
        }
    }

    private func startTimeoutTask() {
        timeoutTask?.cancel()
        let boundedTimeout = max(1, timeout)
        let nanos = UInt64(boundedTimeout * 1_000_000_000)

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self else { return }
            await MainActor.run {
                self.timeoutIfNeeded()
            }
        }
    }

    private func timeoutIfNeeded() {
        finish(with: .failure(URLError(.timedOut)))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
        (() => {
          try {
            if (typeof XMLSerializer !== 'undefined') {
              return new XMLSerializer().serializeToString(document);
            }
            if (document.documentElement) {
              return document.documentElement.outerHTML;
            }
            return '';
          } catch (e) {
            return 'JS_ERROR:' + String(e);
          }
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }

            if let error {
                self.finish(with: .failure(error))
                return
            }

            guard let xml = result as? String, !xml.isEmpty else {
                self.finish(with: .failure(RSSServiceError.invalidData))
                return
            }

            if xml.hasPrefix("JS_ERROR:") {
                self.finish(with: .failure(RSSServiceError.parseFailed(xml)))
                return
            }

            self.finish(with: .success(xml))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil

        switch result {
        case .success(let xml):
            continuation.resume(returning: xml)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
