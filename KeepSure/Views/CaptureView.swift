import CoreData
import SwiftUI
import VisionKit

struct CaptureView: View {
    @EnvironmentObject private var emailSyncManager: EmailSyncManager
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: PurchaseRecord.recentFetchRequest, animation: .snappy)
    private var purchases: FetchedResults<PurchaseRecord>

    @State private var isPresentingScanner = false
    @State private var isProcessingScan = false
    @State private var reviewDraft: ReceiptDraft?
    @State private var latestDraftPreview: ReceiptDraft?
    @State private var scanErrorMessage: String?

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
        .sheet(item: $reviewDraft) { draft in
            ReceiptReviewView(initialDraft: draft) { savedDraft in
                latestDraftPreview = savedDraft
                reviewDraft = nil
            }
            .environment(\.managedObjectContext, viewContext)
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

            Text("Scan a receipt, let Keep Sure read the essentials, then review the return window and warranty before you save.")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.8))

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(AppTheme.captureGradient)
                    .frame(height: 290)
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                    }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppTheme.secondaryAccent.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [10, 10]))
                    .padding(22)

                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "viewfinder.circle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryAccent)

                    Text("Scan receipt")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)

                    Text("Open the camera, capture each page, and Keep Sure will prefill the review sheet for you.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.84))

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
                .padding(28)
            }
        }
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("More ways to add")

            HStack(spacing: 12) {
                actionButton(title: "Import PDF", subtitle: "Available next", systemImage: "doc.fill", action: startScan)
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
                    reviewDraft = ReceiptDraft.emptyManual
                })
                actionButton(title: "Share to family", subtitle: "Assign during review", systemImage: "person.2.fill", action: {
                    reviewDraft = ReceiptDraft.emptyManual
                })
            }
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

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
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
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.success.opacity(0.12), in: Capsule())
                        .foregroundStyle(AppTheme.success)
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
                    previewRow(title: "Price", value: preview.map { $0.price.formatted(.currency(code: $0.currencyCode)) } ?? "$0.00")
                }

                HStack(spacing: 8) {
                    previewPill(label: preview.map { "Return in \($0.returnDays) days" } ?? "Return window ready", color: AppTheme.warning)
                    previewPill(label: preview.map { "Warranty \($0.warrantyMonths) months" } ?? "Warranty estimate ready", color: AppTheme.accent)
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing captured yet")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Once something is scanned and reviewed, this becomes a calm timeline of what was added and what still needs attention.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.74))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelCard)
            } else {
                ForEach(purchases.prefix(4), id: \.objectID) { purchase in
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.12))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: purchase.wrappedSourceType == "Email" ? "envelope.fill" : "doc.text.viewfinder")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(AppTheme.accent)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(purchase.wrappedProductName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("\(purchase.wrappedMerchantName) • \(purchase.wrappedSourceType)")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
                            Text(purchase.statusLine)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.warning)
                        }

                        Spacer()

                        Text(purchase.wrappedPurchaseDate, style: .date)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.62))
                    }
                    .padding(18)
                    .background(panelCard)
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

    private func previewPill(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: Capsule())
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

    private func startScan() {
        guard VNDocumentCameraViewController.isSupported else {
            scanErrorMessage = "Document scanning is not available on this device. You can still add a purchase manually."
            return
        }
        isPresentingScanner = true
    }

    private func handleScannedPages(_ images: [UIImage]) {
        isPresentingScanner = false
        isProcessingScan = true

        Task {
            do {
                let recognizedText = try await ReceiptOCR.recognizeText(from: images)
                let draft = ReceiptTextParser.draft(from: recognizedText, pageCount: images.count)
                await MainActor.run {
                    isProcessingScan = false
                    latestDraftPreview = draft
                    reviewDraft = draft
                }
            } catch {
                await MainActor.run {
                    isProcessingScan = false
                    scanErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ReceiptReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var draft: ReceiptDraft
    @State private var showsSourceText = false
    @State private var saveErrorMessage: String?

    init(initialDraft: ReceiptDraft, onSave: @escaping (ReceiptDraft) -> Void) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
    }

    let onSave: (ReceiptDraft) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    essentialsCard
                    coverageCard
                    sourceCard
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(background)
            .navigationTitle("Review")
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
            Text(draft.sourceType == "Manual" ? "Start with the essentials" : "Confirm the extracted details")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(draft.sourceType == "Manual" ? "Add the purchase once, and Keep Sure will track the dates for you from here." : "Keep Sure guessed the merchant, purchase date, amount, and likely coverage. Adjust anything before you save.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
        }
        .padding(20)
        .background(panelCard)
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
                    ForEach(["You", "Maya", "Aarav", "Shared"], id: \.self, content: Text.init)
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
            Stepper("Warranty: \(draft.warrantyMonths) months", value: $draft.warrantyMonths, in: 0...60)
                .tint(AppTheme.accent)

            Divider()

            summaryRow(title: "Return deadline", value: draft.windows.returnDeadline?.formatted(date: .abbreviated, time: .omitted) ?? "None")
            summaryRow(title: "Warranty ends", value: draft.windows.warrantyExpiration?.formatted(date: .abbreviated, time: .omitted) ?? "None")
        }
        .padding(20)
        .background(panelCard)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("OCR source")

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

    private func textField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        let record = PurchaseRecord(context: viewContext)
        let windows = draft.windows

        record.id = UUID()
        record.productName = draft.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        record.merchantName = draft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown merchant" : draft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        record.categoryName = draft.categoryName
        record.familyOwner = draft.familyOwner
        record.sourceType = draft.sourceType
        record.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.purchaseDate = draft.purchaseDate
        record.returnDeadline = windows.returnDeadline
        record.warrantyExpiration = windows.warrantyExpiration
        record.createdAt = .now
        record.currencyCode = draft.currencyCode
        record.price = draft.price
        record.isArchived = false

        do {
            try viewContext.save()
            onSave(draft)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
