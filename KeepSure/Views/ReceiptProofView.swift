import PDFKit
import SwiftUI
import UIKit
import WebKit

struct ReceiptProofPresentation: Identifiable {
    let id = UUID()
    let previewData: Data?
    let documentData: Data?
    let documentType: String
    let documentName: String
    let htmlData: Data?

    init(previewData: Data?, documentData: Data?, documentType: String, documentName: String, htmlData: Data? = nil) {
        self.previewData = previewData
        self.documentData = documentData
        self.documentType = documentType
        self.documentName = documentName
        self.htmlData = htmlData
    }

    init(draft: ReceiptDraft) {
        self.init(
            previewData: draft.proofPreviewData,
            documentData: draft.proofDocumentData,
            documentType: draft.proofDocumentType,
            documentName: draft.proofDocumentName,
            htmlData: draft.proofHTMLData
        )
    }

    init(purchase: PurchaseRecord) {
        self.init(
            previewData: purchase.proofPreviewData,
            documentData: purchase.proofDocumentData,
            documentType: purchase.wrappedProofDocumentType,
            documentName: purchase.wrappedProofDocumentName,
            htmlData: purchase.proofHTMLData
        )
    }
}

struct ReceiptProofThumbnail: View {
    let previewData: Data?
    let hasProof: Bool
    let fallbackIcon: String
    let cornerRadius: CGFloat

    init(
        previewData: Data?,
        hasProof: Bool,
        fallbackIcon: String = "doc.text.viewfinder",
        cornerRadius: CGFloat = 18
    ) {
        self.previewData = previewData
        self.hasProof = hasProof
        self.fallbackIcon = fallbackIcon
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppTheme.sand.opacity(0.9))
            .overlay {
                Group {
                    if let previewData,
                       let image = UIImage(data: previewData) {
                        GeometryReader { geometry in
                            let inset: CGFloat = 6
                            let innerWidth = max(geometry.size.width - (inset * 2), 0)
                            let innerHeight = max(geometry.size.height - (inset * 2), 0)
                            let innerRadius = max(cornerRadius - 4, 0)

                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                                    .fill(.white.opacity(0.65))

                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: innerWidth, height: innerHeight, alignment: .top)
                                    .clipped()
                            }
                            .frame(width: innerWidth, height: innerHeight)
                            .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.8)
                            }
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: fallbackIcon)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppTheme.accent)

                            Text(hasProof ? "View receipt" : "No receipt image")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.76))
                        }
                        .padding(12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if hasProof {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.viewfinder.fill")
                                .font(.caption2.weight(.bold))
                            Text("Original proof")
                                .font(.caption2.weight(.bold))
                        }

                        Image(systemName: "doc.viewfinder.fill")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.22), in: Capsule())
                    .padding(10)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
            }
    }
}

struct ReceiptProofViewer: View {
    @Environment(\.dismiss) private var dismiss

    let previewData: Data?
    let documentData: Data?
    let documentType: String
    let documentName: String
    let htmlData: Data?

    @State private var selectedMode: ProofMode = .snapshot

    private enum ProofMode: String, CaseIterable, Identifiable {
        case snapshot
        case email

        var id: String { rawValue }

        var title: String {
            switch self {
            case .snapshot:
                return "Snapshot"
            case .email:
                return "Rendered email"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasRenderedEmail {
                    Picker("Proof mode", selection: $selectedMode) {
                        ForEach(availableModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }

                Group {
                    if selectedMode == .email, let htmlString {
                        RichHTMLProofView(html: htmlString)
                            .background(AppTheme.homeBackground)
                    } else {
                        snapshotView
                    }
                }
            }
            .navigationTitle(documentName.isEmpty ? "Original proof" : documentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .onAppear {
            selectedMode = hasRenderedEmail ? .email : .snapshot
        }
    }

    private var htmlString: String? {
        guard let htmlData else { return nil }
        return String(data: htmlData, encoding: .utf8)
    }

    private var hasRenderedEmail: Bool {
        htmlString?.isEmpty == false
    }

    private var availableModes: [ProofMode] {
        hasRenderedEmail ? [.email, .snapshot] : [.snapshot]
    }

    @ViewBuilder
    private var snapshotView: some View {
        if documentType == "pdf", let documentData, let document = PDFDocument(data: documentData) {
            PDFDocumentView(document: document)
                .background(AppTheme.homeBackground)
        } else if let previewData, let image = UIImage(data: previewData) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(20)
            }
            .background(AppTheme.homeBackground)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                Text("Original proof is not available yet")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("Keep Sure saved the purchase details, but this item does not have a stored receipt image or PDF to show.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.homeBackground)
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor.clear
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

private struct RichHTMLProofView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let shell = """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          background: #f5efe5;
          color: #2f2924;
          margin: 0;
          padding: 20px 16px 36px;
          line-height: 1.45;
        }
        img { max-width: 100%; height: auto; }
        table {
          width: 100%;
          border-collapse: collapse;
        }
        td, th {
          padding: 6px 4px;
          vertical-align: top;
          border-bottom: 1px solid rgba(47,41,36,0.08);
        }
        a { color: #b89254; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(shell, baseURL: nil)
    }
}
