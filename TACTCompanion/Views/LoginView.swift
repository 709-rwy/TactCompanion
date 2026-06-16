import SwiftUI
import WebKit

struct LoginView: View {
    @ObservedObject var viewModel: AuthenticationViewModel

    var body: some View {
        NavigationStack {
            TactLoginWebView { cookies in
                Task {
                    await viewModel.completeWebLogin(cookies: cookies)
                }
            }
            .overlay {
                if viewModel.isChecking {
                    ProgressView("ログイン状態を確認中")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("TACTにログイン")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct TactLoginWebView: UIViewRepresentable {
    let onCookiesUpdated: ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesUpdated: onCookiesUpdated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.navigationDelegate = context.coordinator
        webView.load(
            URLRequest(
                url: URL(string: "https://tact.ac.thers.ac.jp/portal")!
            )
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCookiesUpdated: ([HTTPCookie]) -> Void
        private var hasSubmittedAuthenticatedPage = false

        init(onCookiesUpdated: @escaping ([HTTPCookie]) -> Void) {
            self.onCookiesUpdated = onCookiesUpdated
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation?
        ) {
            guard
                let url = webView.url,
                url.host == "tact.ac.thers.ac.jp",
                url.path == "/portal" || url.path.hasPrefix("/portal/"),
                !url.path.contains("sakai-login-tool"),
                !url.path.contains("shibboleth.sso"),
                !hasSubmittedAuthenticatedPage
            else {
                return
            }

            webView.evaluateJavaScript(
                "document.querySelector('a[href*=\"/portal/logout\"]') !== null"
            ) { [weak self, weak webView] result, _ in
                guard
                    let self,
                    let webView,
                    result as? Bool == true,
                    !hasSubmittedAuthenticatedPage
                else {
                    return
                }
                hasSubmittedAuthenticatedPage = true

                webView.configuration.websiteDataStore.httpCookieStore
                    .getAllCookies { [onCookiesUpdated] cookies in
                    let tactCookies = cookies.filter {
                        $0.domain.contains("tact.ac.thers.ac.jp")
                    }
                    guard !tactCookies.isEmpty else { return }
                    onCookiesUpdated(tactCookies)
                }
            }
        }
    }
}
