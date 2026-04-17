import CoreData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct CaptureView: View {
    @EnvironmentObject private var emailSyncManager: EmailSyncManager
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: PurchaseRecord.recentFetchRequest, animation: .snappy)
    private var purchases: FetchedResults<PurchaseRecord>

    @State private var isPresentingScanner = false
    @State private var isImportingPDF = false
    @State private var isProcessingScan = false
    @State private var reviewSession: ReviewSession?
    @State private var latestDraftPreview: ReceiptDraft?
    @State private var scanErrorMessage: String?
    @State private var proofPresentation: ReceiptProofPresentation?

    private var hasPurchases: Bool {
        !purchases.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                captureHero
                    .softEntrance(delay: 0.02)
                actionGrid
                    .softEntrance(delay: 0.07)
                reviewPreview
                    .softEntrance(delay: 0.12)
                importTimeline
                    .softEntrance(delay: 0.17)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(screenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isPresentingScanner) {
            ReceiptScannerView(
                onFinish: handleScannedPages,
                onCancel: { isPresentingScanner = false },
                onError: { error in
                    isPresentingScanner = false
                    scanErrorMessage = error.localizedDescription
                }
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isImportingPDF,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handlePDFImport(result)
        }
        .sheet(item: $reviewSession) { session in
            ReceiptReviewView(initialDraft: session.draft, purchaseToEdit: session.purchaseToEdit) { savedDraft in
                latestDraftPreview = savedDraft
                reviewSession = nil
            }
            .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $proofPresentation) { proof in
            ReceiptProofViewer(
                previewData: proof.previewData,
                documentData: proof.documentData,
                documentType: proof.documentType,
                documentName: proof.documentName,
                htmlData: proof.htmlData
            )
        }
        .overlay {
            if isProcessingScan {
                scanProcessingOverlay
            }
        }
        .onDisappear {
            if !isPresentingScanner {
                isProcessingScan = false
            }
        }
        .alert("Scan issue", isPresented: Binding(
            get: { scanErrorMessage != nil },
            set: { if !$0 { scanErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanErrorMessage ?? "")
        }
    }

    private var screenBackground: some View {
        ZStack {
            AppTheme.homeBackground
                .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: 160, y: -250)

            Circle()
                .fill(AppTheme.accent.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 28)
                .offset(x: -140, y: -80)
        }
    }

    private var captureHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep Sure")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(AppTheme.accent)

            Text("Capture protection before the receipt disappears")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text(
                hasPurchases
                    ? "Scan a receipt, let Keep Sure read the essentials, then review the return window and warranty before you save."
                    : "Your first receipt can become something you never have to remember alone. Scan it once, and Keep Sure will shape it into a calm timeline."
            )
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.8))

            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(AppTheme.captureGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                    }
                    .padding(4)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                AppTheme.secondaryAccent.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1, dash: [8, 8])
                            )
                    }
                    .padding(18)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Image(systemName: "viewfinder.circle.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryAccent)

                        Spacer(minLength: 0)
                    }

                    if !hasPurchases {
                        delightfulBadge(text: "Your first one is the hardest. We can hold the rest.")
                    }

                    Text("Scan receipt")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)

                    Text("Open the camera, capture each page, and Keep Sure will prefill the review sheet for you.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: startScan) {
                        Text("Start scanning")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 34)
                .padding(.vertical, 34)
            }
        }
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("More ways to add")

            HStack(spacing: 12) {
                actionButton(title: "Import PDF", subtitle: "Bring in a saved receipt PDF", systemImage: "doc.fill", action: startPDFImport)
                actionButton(
                    title: emailSyncManager.isConnected ? "Sync Gmail" : "Connect Gmail",
                    subtitle: emailSyncManager.isConnected
                        ? "Import recent purchase emails"
                        : (emailSyncManager.hasUsableConfiguration ? "One-time permission, then automatic imports" : "Gmail sync is unavailable in this build"),
                    systemImage: "envelope.badge.fill",
                    action: {
                        if emailSyncManager.hasUsableConfiguration {
                            Task {
                                await emailSyncManager.connectOrSync()
                            }
                        } else {
                            scanErrorMessage = "Gmail syncing is not available in this build yet."
                        }
                    }
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            if emailSyncManager.isSyncing || emailSyncManager.isAuthorizing {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppTheme.accent)
                    Text(emailSyncManager.connectionStatusLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryAccent)
                    Spacer()
                }
                .padding(.horizontal, 4)
            } else if let statusMessage = emailSyncManager.statusMessage, emailSyncManager.isConnected {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.success)
                    Text(statusMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryAccent)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                actionButton(title: "Add manually", subtitle: "Open a blank review sheet", systemImage: "square.and.pencil", action: {
                    reviewSession = .create(from: .emptyManual)
                })
                actionButton(title: "Share to family", subtitle: "Assign during review", systemImage: "person.2.fill", action: {
                    reviewSession = .create(from: .emptyManual)
                })
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 182, maxHeight: 182, alignment: .topLeading)
            .background(panelCard)
        }
        .buttonStyle(.plain)
    }

    private var reviewPreview: some View {
        let preview = latestDraftPreview

        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Extraction review")

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(preview?.merchantName ?? "Receipt review")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(preview == nil ? "Ready when you are" : "Parsed")
                        .multilineTextAlignment(.center)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.success.opacity(0.12), in: Capsule())
                        .foregroundStyle(AppTheme.success)
                }

                if let preview {
                    proofPreviewBlock(for: preview)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(preview?.productName.isEmpty == false ? preview?.productName ?? "" : "Scan a receipt to prefill this review")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(preview?.recognizedText.isEmpty == false ? "Keep Sure found text, guessed the merchant and price, and let you confirm the final details before saving." : "Your next scan will show the merchant, purchase date, price, return window, and warranty guesses here.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.76))
                }

                VStack(spacing: 12) {
                    previewRow(title: "Merchant", value: preview?.merchantName ?? "Waiting for scan")
                    previewRow(title: "Purchase date", value: preview.map { $0.purchaseDate.formatted(date: .abbreviated, time: .omitted) } ?? "Not parsed yet")
                    previewRow(title: "Price", value: preview.map { $0.price.formatted(.currency(code: $0.currencyCode)) } ?? "Will appear after scan")
                }

                HStack(spacing: 10) {
                    heroFeatureCard(
                        icon: "arrow.uturn.backward.circle.fill",
                        title: "Returns",
                        subtitle: preview.map { "\($0.returnDays) days" } ?? "Ready"
                    ).background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(AppTheme.dashboardGradient)
                            .overlay {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                            }
                    )
                    heroFeatureCard(
                        icon: "checkmark.shield.fill",
                        title: "Warranty",
                        subtitle: preview.map { warrantyPreviewValue(for: $0) } ?? "Needs confirmation"
                    ).background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(AppTheme.dashboardGradient)
                            .overlay {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                            }
                    )
                }
            }
            .padding(20)
            .background(panelCard)
        }
    }

    private var importTimeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Recent capture timeline")

            if purchases.isEmpty {
                emptyTimelineCard(
                    title: "Your capture timeline is waiting for its first receipt",
                    message: "Once something is scanned and reviewed, this becomes a calm record of what was saved and what Keep Sure is watching for you."
                )
            } else {
                ForEach(purchases.prefix(4), id: \.objectID) { purchase in
                    Button {
                        reviewSession = .edit(purchase)
                    } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            ReceiptProofThumbnail(
                                previewData: purchase.proofPreviewData,
                                hasProof: purchase.hasReceiptProof,
                                fallbackIcon: purchase.wrappedSourceType == "Email" ? "envelope.fill" : "doc.text.viewfinder",
                                cornerRadius: 16
                            )
                            .frame(width: 58, height: 58)

                            Text(purchase.wrappedProductName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            
                        }
                        Text("\(purchase.wrappedMerchantName) • \(purchase.wrappedSourceType)")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
                        
                        HStack(alignment: .top, spacing: 14) {
                            Text(purchase.statusLine)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.warning)
                            Spacer()
                            Text(purchase.wrappedPurchaseDate, style: .date)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.62))
                        }
                    }
                    .padding(18)
                    .background(panelCard)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scanProcessingOverlay: some View {
        ZStack {
            Color.white.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.accent)
                Text("Reading your receipt")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("Keep Sure is extracting the merchant, date, price, and likely coverage windows.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(panelCard)
        }
    }

    private var panelCard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(AppTheme.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
            }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
    }

    private func previewStatusCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .center, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)

                Text(value)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func previewRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func delightfulBadge(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
            Text(text)
                .font(.caption.weight(.bold))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.72), in: Capsule())
        .foregroundStyle(AppTheme.accent)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func emptyTimelineCard(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "face.smiling.inverse")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.74))
            }

            Spacer()
        }
        .padding(20)
        .background(panelCard)
    }

    private func warrantyPreviewValue(for draft: ReceiptDraft) -> String {
        switch draft.warrantyStatus {
        case .none:
            return "No warranty"
        case .estimated:
            return draft.warrantyMonths > 0 ? "\(draft.warrantyMonths) mo to confirm" : "Needs confirmation"
        case .confirmed:
            return draft.warrantyMonths > 0 ? "\(draft.warrantyMonths) months confirmed" : "Confirmed"
        }
    }

    private func startScan() {
        guard VNDocumentCameraViewController.isSupported else {
            scanErrorMessage = "Document scanning is not available on this device. You can still add a purchase manually."
            return
        }
        isPresentingScanner = true
    }

    private func startPDFImport() {
        isImportingPDF = true
    }

    private func proofPreviewBlock(for draft: ReceiptDraft) -> some View {
        Button {
            proofPresentation = ReceiptProofPresentation(draft: draft)
        } label: {
            HStack(spacing: 14) {
                ReceiptProofThumbnail(
                    previewData: draft.proofPreviewData,
                    hasProof: draft.hasProofAttachment,
                    cornerRadius: 20
                )
                .frame(width: 112, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Original proof")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    Text(draft.proofDocumentName.isEmpty ? "Stored with this review" : draft.proofDocumentName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
                        .lineLimit(2)

                    Text("Open the actual receipt so the parsed fields never feel disconnected from the real proof.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("View receipt")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent.opacity(0.10), in: Capsule())
                        .foregroundStyle(AppTheme.accent)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func handleScannedPages(_ images: [UIImage]) {
        isPresentingScanner = false
        isProcessingScan = true

        Task {
            do {
                let recognizedText = try await ReceiptOCR.recognizeText(from: images)
                let proof = ReceiptProofBuilder.packageScannedImages(images)
                var draft = ReceiptTextParser.draft(from: recognizedText, pageCount: images.count)
                draft.proofPreviewData = proof.previewData
                draft.proofDocumentData = proof.documentData
                draft.proofDocumentType = proof.documentType
                draft.proofDocumentName = proof.documentName
                await MainActor.run {
                    isProcessingScan = false
                    latestDraftPreview = draft
                    reviewSession = .create(from: draft)
                }
            } catch {
                await MainActor.run {
                    isProcessingScan = false
                    scanErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isProcessingScan = true

            Task {
                do {
                    let imported = try await ReceiptPDFOCR.recognizeText(from: url)
                    var draft = ReceiptTextParser.draft(from: imported.text, pageCount: imported.pageCount)
                    draft.proofPreviewData = imported.previewData
                    draft.proofDocumentData = imported.documentData
                    draft.proofDocumentType = "pdf"
                    draft.proofDocumentName = imported.documentName
                    await MainActor.run {
                        isProcessingScan = false
                        latestDraftPreview = draft
                        reviewSession = .create(from: draft)
                    }
                } catch {
                    await MainActor.run {
                        isProcessingScan = false
                        scanErrorMessage = error.localizedDescription
                    }
                }
            }

        case .failure(let error):
            scanErrorMessage = error.localizedDescription
        }
    }
}

struct ReceiptReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notificationManager: SmartNotificationManager

    @State private var draft: ReceiptDraft
    @State private var showsSourceText = false
    @State private var showsLearningDetails = false
    @State private var saveErrorMessage: String?
    @State private var proofPresentation: ReceiptProofPresentation?
    private let purchaseToEdit: PurchaseRecord?
    private let initialDraft: ReceiptDraft

    init(initialDraft: ReceiptDraft, purchaseToEdit: PurchaseRecord? = nil, onSave: @escaping (ReceiptDraft) -> Void) {
        _draft = State(initialValue: initialDraft)
        self.purchaseToEdit = purchaseToEdit
        self.initialDraft = initialDraft
        self.onSave = onSave
    }

    let onSave: (ReceiptDraft) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    reviewAssistCard
                    essentialsCard
                    coverageCard
                    proofCard
                    sourceCard
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(background)
            .navigationTitle(purchaseToEdit == nil ? "Review" : "Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.secondaryAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .foregroundStyle(canSave ? AppTheme.accent : AppTheme.secondaryAccent.opacity(0.45))
                        .disabled(!canSave)
                }
            }
            .alert("Save issue", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .sheet(item: $proofPresentation) { proof in
                ReceiptProofViewer(
                    previewData: proof.previewData,
                    documentData: proof.documentData,
                    documentType: proof.documentType,
                    documentName: proof.documentName,
                    htmlData: proof.htmlData
                )
            }
        }
    }

    private var canSave: Bool {
        !draft.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var background: some View {
        ZStack {
            AppTheme.homeBackground
                .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(width: 240, height: 240)
                .blur(radius: 22)
                .offset(x: 150, y: -230)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(headerMessage)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
        }
        .padding(20)
        .background(panelCard)
    }

    private var headerTitle: String {
        if purchaseToEdit != nil {
            return "Review what Keep Sure found"
        }

        return draft.sourceType == "Manual" ? "Start with the essentials" : "Confirm the extracted details"
    }

    private var headerMessage: String {
        if purchaseToEdit != nil {
            return "Tighten any details that still feel uncertain so your reminders and warranty timeline stay trustworthy."
        }

        return draft.sourceType == "Manual"
            ? "Add the purchase once, and Keep Sure will track the dates for you from here."
            : "Keep Sure guessed the merchant, purchase date, amount, and likely coverage. Adjust anything before you save."
    }

    private var reviewAssistCard: some View {
        Group {
            if shouldShowReviewAssist {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quick review")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("Fix the uncertain parts first, then the rest of the form usually falls into place.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
                        }
                    }

                    if !draft.learnedAdjustmentSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.accent)

                                Text(draft.learnedAdjustmentSummary)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            DisclosureGroup(isExpanded: $showsLearningDetails) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Keep Sure reused a correction from one of your earlier reviews so this import starts closer to right.")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))

                                    Button("Reset learned suggestion") {
                                        resetLearnedSuggestion()
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 6)
                            } label: {
                                Text("Why this changed")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if needsMerchantHelp {
                        reviewSuggestionBlock(
                            title: "Merchant looks uncertain",
                            subtitle: "Choose one of the likely matches or keep editing manually.",
                            suggestions: merchantSuggestions
                        ) { suggestion in
                            draft.merchantName = suggestion
                        }
                    }

                    if needsProductHelp {
                        reviewSuggestionBlock(
                            title: "Product name needs a quick pass",
                            subtitle: "Keep Sure pulled a few likely product lines from the import.",
                            suggestions: productSuggestions
                        ) { suggestion in
                            draft.productName = suggestion
                        }
                    }

                    if needsWarrantyHelp {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Warranty still needs confirmation")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)

                            Text("One tap is enough if you already know the right answer.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.75))

                            HStack(spacing: 10) {
                                quickReviewButton("No warranty") {
                                    draft.warrantyStatus = .none
                                    draft.warrantyMonths = 0
                                }

                                quickReviewButton("Keep likely") {
                                    if draft.warrantyStatus == .none {
                                        draft.warrantyStatus = .estimated
                                        draft.warrantyMonths = max(draft.warrantyMonths, 12)
                                    } else {
                                        draft.warrantyStatus = .estimated
                                    }
                                }

                                quickReviewButton("Confirm") {
                                    draft.warrantyStatus = .confirmed
                                    draft.warrantyMonths = max(draft.warrantyMonths, 12)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(panelCard)
            }
        }
    }

    private var essentialsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Essentials")

            Group {
                textField("Product name", text: $draft.productName)
                textField("Merchant", text: $draft.merchantName)

                Picker("Category", selection: $draft.categoryName) {
                    ForEach(["General", "Electronics", "Home", "Travel", "Beauty"], id: \.self, content: Text.init)
                }
                .tint(AppTheme.accent)

                Picker("Household owner", selection: $draft.familyOwner) {
                    ForEach(ReceiptDraft.householdOwnerOptions, id: \.self, content: Text.init)
                }
                .tint(AppTheme.accent)

                HStack {
                    Text("Price")
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
                    Spacer()
                    TextField("0.00", value: $draft.price, format: .number.precision(.fractionLength(2)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppTheme.ink)
                }

                DatePicker("Purchase date", selection: $draft.purchaseDate, displayedComponents: .date)
                    .tint(AppTheme.accent)
            }
        }
        .padding(20)
        .background(panelCard)
    }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Coverage")

            Stepper("Return window: \(draft.returnDays) days", value: $draft.returnDays, in: 0...180)
                .tint(AppTheme.accent)
            Picker("Warranty type", selection: $draft.warrantyStatus) {
                ForEach(WarrantyStatus.allCases, id: \.self) { status in
                    Text(status.title).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .tint(AppTheme.accent)

            Stepper("Warranty: \(draft.warrantyMonths) months", value: $draft.warrantyMonths, in: 0...60)
                .tint(AppTheme.accent)
                .disabled(draft.warrantyStatus == .none)
                .opacity(draft.warrantyStatus == .none ? 0.45 : 1)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: warrantyGuidanceIcon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(warrantyGuidanceText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Divider()

            summaryRow(title: "Return deadline", value: draft.windows.returnDeadline?.formatted(date: .abbreviated, time: .omitted) ?? "None")
            summaryRow(title: "Warranty status", value: draft.warrantyStatus.title)
            summaryRow(title: "Warranty ends", value: draft.windows.warrantyExpiration?.formatted(date: .abbreviated, time: .omitted) ?? "None")

            explanationCard(
                title: "Why this return window is tracked",
                text: draft.returnExplanationText,
                icon: "arrow.uturn.backward.circle.fill"
            )

            explanationCard(
                title: "Why this warranty is tracked",
                text: draft.warrantyExplanationText,
                icon: warrantyGuidanceIcon
            )
        }
        .padding(20)
        .background(panelCard)
    }

    private var proofCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Original proof")

            if draft.hasProofAttachment {
                Button {
                    proofPresentation = ReceiptProofPresentation(draft: draft)
                } label: {
                    HStack(spacing: 14) {
                        ReceiptProofThumbnail(
                            previewData: draft.proofPreviewData,
                            hasProof: true,
                            cornerRadius: 20
                        )
                        .frame(width: 120, height: 144)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.proofDocumentName.isEmpty ? "Saved receipt" : draft.proofDocumentName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(2)

                            Text("Open the exact receipt or PDF alongside the parsed details whenever you want a confidence check.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)

                            Text("View original proof")
                                .font(.footnote.weight(.bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.accent.opacity(0.10), in: Capsule())
                                .foregroundStyle(AppTheme.accent)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: draft.sourceType == "Email" ? "envelope.open.fill" : "doc.text.magnifyingglass")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(draft.sourceType == "Email"
                        ? "This purchase came from Gmail parsing, so Keep Sure has the extracted order details but not a stored receipt image yet."
                        : "Keep Sure saved the parsed details for this purchase, but there is no stored receipt image or PDF attached yet.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(20)
        .background(panelCard)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Imported text")

            if draft.recognizedText.isEmpty {
                TextField("Optional notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            } else {
                DisclosureGroup(isExpanded: $showsSourceText) {
                    Text(draft.recognizedText)
                        .font(.footnote.monospaced())
                        .foregroundStyle(AppTheme.secondaryAccent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } label: {
                    Text("Show scanned text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }

                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(20)
        .background(panelCard)
    }

    private var panelCard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(AppTheme.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
            }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func explanationCard(title: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 38, height: 38)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.accent)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func textField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func reviewSuggestionBlock(
        title: String,
        subtitle: String,
        suggestions: [String],
        apply: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.75))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        quickReviewButton(suggestion) {
                            apply(suggestion)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func quickReviewButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppTheme.accent.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var shouldShowReviewAssist: Bool {
        needsMerchantHelp || needsProductHelp || needsWarrantyHelp
    }

    private var needsMerchantHelp: Bool {
        draft.sourceType != "Manual"
            && (trimmedMerchantName.isEmpty || trimmedMerchantName == "Unknown merchant")
            && !merchantSuggestions.isEmpty
    }

    private var needsProductHelp: Bool {
        draft.sourceType != "Manual"
            && (trimmedProductName.isEmpty || trimmedProductName == "Untitled purchase" || trimmedProductName == "Scanned purchase")
            && !productSuggestions.isEmpty
    }

    private var needsWarrantyHelp: Bool {
        draft.sourceType != "Manual" && draft.warrantyStatus == .estimated
    }

    private var merchantSuggestions: [String] {
        ReceiptTextParser.merchantSuggestions(from: draft.recognizedText)
            .filter { $0.caseInsensitiveCompare(trimmedMerchantName) != .orderedSame }
    }

    private var productSuggestions: [String] {
        ReceiptTextParser.productSuggestions(from: draft.recognizedText, merchant: draft.merchantName)
            .filter { $0.caseInsensitiveCompare(trimmedProductName) != .orderedSame }
    }

    private var trimmedMerchantName: String {
        draft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedProductName: String {
        draft.productName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var warrantyGuidanceIcon: String {
        switch draft.warrantyStatus {
        case .none:
            return "shield"
        case .estimated:
            return "sparkles"
        case .confirmed:
            return "checkmark.shield.fill"
        }
    }

    private var warrantyGuidanceText: String {
        if draft.warrantyStatus == .estimated, !draft.warrantyConfidenceNote.isEmpty {
            return draft.warrantyConfidenceNote
        }

        return draft.warrantyStatus.reviewGuidance
    }

    private func resetLearnedSuggestion() {
        ImportLearningStore.shared.forgetLearnedAdjustments(appliedTo: draft)

        guard let baseline = draft.importBaseline else {
            draft.learnedAdjustmentSummary = ""
            showsLearningDetails = false
            return
        }

        draft.merchantName = baseline.merchantName
        draft.productName = baseline.productName
        draft.categoryName = baseline.categoryName
        draft.warrantyStatus = baseline.warrantyStatus
        draft.warrantyMonths = baseline.warrantyMonths
        draft.warrantyConfidenceNote = baseline.warrantyConfidenceNote
        draft.learnedAdjustmentSummary = ""
        showsLearningDetails = false
    }

    private func save() {
        let record = purchaseToEdit ?? PurchaseRecord(context: viewContext)
        let windows = draft.windows

        if record.id == nil {
            record.id = UUID()
        }
        record.productName = draft.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        record.merchantName = draft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown merchant" : draft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        record.categoryName = draft.categoryName
        record.familyOwner = draft.familyOwner
        record.sourceType = draft.sourceType
        record.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.purchaseDate = draft.purchaseDate
        record.returnDeadline = windows.returnDeadline
        record.warrantyExpiration = windows.warrantyExpiration
        record.warrantyStatusRaw = draft.warrantyStatus.rawValue
        record.returnExplanation = draft.returnExplanationText
        record.warrantyExplanation = draft.warrantyExplanationText
        if record.createdAt == nil {
            record.createdAt = .now
        }
        record.currencyCode = draft.currencyCode
        record.price = draft.price
        record.isArchived = false
        record.returnCompleted = false
        record.proofPreviewData = draft.proofPreviewData
        record.proofDocumentData = draft.proofDocumentData
        record.proofDocumentType = draft.proofDocumentType.isEmpty ? nil : draft.proofDocumentType
        record.proofDocumentName = draft.proofDocumentName.isEmpty ? nil : draft.proofDocumentName
        record.proofHTMLData = draft.proofHTMLData

        do {
            try viewContext.save()
            ImportLearningStore.shared.recordCorrection(from: initialDraft, to: draft)
            Task {
                await notificationManager.rescheduleAll(in: PersistenceController.shared.container)
            }
            onSave(draft)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
