import SwiftUI
import WebKit
import OSLog

@main
struct MaRechargeApp: App {
    var body: some Scene {
        WindowGroup { ChargingView() }
    }
}

struct ChargingView: View {
    @StateObject private var browser = ChargingBrowser()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if browser.isLoading {
                    ProgressView(value: browser.progress)
                        .tint(.green)
                }
                ZStack {
                    ChargingWebView(browser: browser)
                    if let message = browser.errorMessage {
                        ContentUnavailableView {
                            Label("Connexion interrompue", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Réessayer") { browser.retry() }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                    }
                }
            }
            .navigationTitle("ZePlug")
            .navigationBarTitleDisplayMode(.inline)

        }
        .tint(Color(red: 0.04, green: 0.25, blue: 0.34))
    }
}

@MainActor
final class ChargingBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let homeURL = URL(string: "https://customer.zeplug.com/")!
    let webView: WKWebView
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var errorMessage: String?
    private var observations: [NSKeyValueObservation] = []
    private static let savedPathKey = "lastChargingPagePath"
    private let launchLogger = Logger(subsystem: "com.yvancognasse.marecharge", category: "Loading")
    private var navigationStartedAt: TimeInterval?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateState() }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateState() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.rememberChargingPage() }
            }
        ]
        let path = UserDefaults.standard.string(forKey: Self.savedPathKey)
        let url = Self.chargingPageURL(for: path) ?? Self.homeURL
        webView.load(URLRequest(url: url))
    }

    private func updateState() {
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    func goHome() {
        errorMessage = nil
        webView.load(URLRequest(url: Self.homeURL))
    }

    // Only restore the known charging route; never store login tokens or query strings.
    private static func chargingPageURL(for path: String?) -> URL? {
        guard let path,
              path.range(of: "^/contracts/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/?$",
                         options: .regularExpression) != nil else { return nil }
        return URL(string: path, relativeTo: homeURL)?.absoluteURL
    }

    private func rememberChargingPage() {
        guard let url = webView.url,
              url.scheme == "https", url.host == Self.homeURL.host,
              Self.chargingPageURL(for: url.path) != nil else { return }
        UserDefaults.standard.set(url.path, forKey: Self.savedPathKey)
    }

    func retry() {
        errorMessage = nil
        if webView.url == nil { goHome() } else { webView.reload() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        navigationStartedAt = ProcessInfo.processInfo.systemUptime
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let startedAt = navigationStartedAt {
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            launchLogger.info("Web content committed after \(elapsed, privacy: .public) seconds")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        rememberChargingPage()
        if webView.url?.host == Self.homeURL.host, webView.url?.path == "/login" {
            UserDefaults.standard.removeObject(forKey: Self.savedPathKey)
        }
        if let startedAt = navigationStartedAt {
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            launchLogger.info("Web navigation finished after \(elapsed, privacy: .public) seconds")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    private func showError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = "Impossible de charger votre espace client. Vérifiez votre connexion Internet, puis réessayez."
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        switch url.scheme?.lowercased() {
        case "https", "about":
            decisionHandler(.allow)
        case "mailto", "tel":
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        default:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           navigationAction.request.url?.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

struct ChargingWebView: UIViewRepresentable {
    let browser: ChargingBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
