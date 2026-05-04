import SwiftUI
import UIKit
import WebKit

struct BrowserDestination: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}

struct InAppBrowserView: View {
    @Environment(\.dismiss) private var dismiss

    let destination: BrowserDestination
    @State private var isShowingOpenWith = false

    var body: some View {
        NavigationStack {
            WebBrowser(url: destination.url)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityIdentifier("browser.webView")
                .navigationTitle(destination.url.host() ?? L10n.string("browser.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("common.done")) {
                            dismiss()
                        }
                        .accessibilityIdentifier("browser.done")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIApplication.shared.open(destination.url)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .accessibilityLabel(L10n.string("browser.openExternal"))
                        .accessibilityIdentifier("browser.openExternal")
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isShowingOpenWith = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(L10n.string("browser.openWith"))
                        .accessibilityIdentifier("browser.openWith")
                    }
                }
        }
        .accessibilityIdentifier("browser.sheet")
        .sheet(isPresented: $isShowingOpenWith) {
            OpenWithView(url: destination.url)
        }
    }
}

private struct WebBrowser: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct OpenWithView: View {
    let url: URL

    var body: some View {
        ShareSheetView(items: [url])
    }
}
