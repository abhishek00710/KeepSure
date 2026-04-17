import CoreData
import SwiftUI

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var emailSyncManager: EmailSyncManager
    @EnvironmentObject private var notificationManager: SmartNotificationManager
    @FetchRequest(fetchRequest: PurchaseRecord.recentFetchRequest, animation: .snappy)
    private var purchases: FetchedResults<PurchaseRecord>
    @State private var reviewSession: ReviewSession?
    @State private var showsProtectedSummary = false
    @State private var protectedSearchText = ""
    @State private var undoReturnPurchase: PurchaseRecord?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var proofPresentation: ReceiptProofPresentation?
    @State private var explanationPresentation: ProtectionExplanationPresentation?

    private var activePurchases: [PurchaseRecord] {
        purchases.filter { !$0.isArchived }
    }

    private var actSoonPurchases: [PurchaseRecord] {
        activePurchases
            .filter { purchase in
                guard !purchase.isReturnHandled else { return false }
                guard let returnDeadline = purchase.returnDeadline else { return false }
                let urgency = PurchaseUrgency(deadline: returnDeadline)
                switch urgency {
                case .critical, .soon, .expired:
                    return true
                case .calm:
                    return false
                }
            }
            .sorted { ($0.returnDeadline ?? .distantFuture) < ($1.returnDeadline ?? .distantFuture) }
    }

    private var confirmedWarrantyPurchases: [PurchaseRecord] {
        activePurchases
            .filter { purchase in
                purchase.confirmedWarrantyExpiration != nil
            }
            .sorted { lhs, rhs in
                let today = Calendar.current.startOfDay(for: .now)
                let lhsDate = lhs.confirmedWarrantyExpiration ?? .distantFuture
                let rhsDate = rhs.confirmedWarrantyExpiration ?? .distantFuture
                let lhsIsUpcoming = lhsDate >= today
                let rhsIsUpcoming = rhsDate >= today

                if lhsIsUpcoming != rhsIsUpcoming {
                    return lhsIsUpcoming
                }

                if lhsIsUpcoming {
                    return lhsDate < rhsDate
                }

                return lhsDate > rhsDate
            }
    }

    private var warrantiesSoon: [PurchaseRecord] {
        confirmedWarrantyPurchases.filter {
            guard let warrantyExpiration = $0.confirmedWarrantyExpiration else { return false }
            return warrantyExpiration >= Calendar.current.startOfDay(for: .now)
        }
    }

    private var handledReturnPurchases: [PurchaseRecord] {
        activePurchases
            .filter { $0.isReturnHandled && $0.returnDeadline != nil }
            .sorted { ($0.returnDeadline ?? .distantPast) > ($1.returnDeadline ?? .distantPast) }
    }

    private var estimatedWarrantyPurchases: [PurchaseRecord] {
        activePurchases
            .filter { $0.estimatedWarrantyExpiration != nil }
            .sorted { ($0.estimatedWarrantyExpiration ?? .distantFuture) < ($1.estimatedWarrantyExpiration ?? .distantFuture) }
    }

    private var estimatedWarrantyCount: Int {
        estimatedWarrantyPurchases.count
    }

    private var reviewCandidates: [PurchaseRecord] {
        activePurchases
            .filter(\.needsReview)
            .sorted { $0.wrappedCreatedAt > $1.wrappedCreatedAt }
    }

    private var prioritizedReviewPurchase: PurchaseRecord? {
        reviewCandidates.sorted { lhs, rhs in
            reviewPriority(for: lhs) > reviewPriority(for: rhs)
        }.first
    }

    private var protectedSheetPrimaryPurchase: PurchaseRecord? {
        prioritizedReviewPurchase ?? recentPurchases.first
    }

    private var recentPurchases: [PurchaseRecord] {
        activePurchases.sorted { $0.wrappedCreatedAt > $1.wrappedCreatedAt }
    }

    private var confirmedWarrantyCount: Int {
        activePurchases.filter(\.hasVisibleWarranty).count
    }

    private var filteredProtectedPurchases: [PurchaseRecord] {
        let query = protectedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recentPurchases }

        return recentPurchases.filter { purchase in
            purchase.wrappedProductName.localizedCaseInsensitiveContains(query)
                || purchase.wrappedMerchantName.localizedCaseInsensitiveContains(query)
                || purchase.wrappedCategoryName.localizedCaseInsensitiveContains(query)
                || purchase.wrappedSourceType.localizedCaseInsensitiveContains(query)
                || purchase.wrappedNotes.localizedCaseInsensitiveContains(query)
        }
    }

    private var protectedPurchaseGroups: [(title: String, purchases: [PurchaseRecord])] {
        let needsReview = filteredProtectedPurchases.filter(\.needsReview)
        let warrantyReady = filteredProtectedPurchases.filter { !$0.needsReview && $0.hasVisibleWarranty }
        let receiptsOnly = filteredProtectedPurchases.filter { !$0.needsReview && !$0.hasVisibleWarranty }

        return [
            ("Needs review", needsReview),
            ("Warranty confirmed", warrantyReady),
            ("Saved receipts", receiptsOnly)
        ]
        .filter { !$0.1.isEmpty }
    }

    private var actSoonCount: Int {
        actSoonPurchases.count
    }

    private var hasProtectedItems: Bool {
        !activePurchases.isEmpty
    }

    private var familyHighlights: String {
        hasProtectedItems
            ? "Your protected purchases are gathering in one calm place."
            : "Start with one purchase and your shared timeline can grow from there."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                greetingHeader
                    .softEntrance(delay: 0.02)
                protectedHero
                    .softEntrance(delay: 0.06)
                statusStrip
                    .softEntrance(delay: 0.10)
                actSoonSection
                    .softEntrance(delay: 0.14)
                handledReturnsSection
                    .softEntrance(delay: 0.16)
                warrantySection
                    .softEntrance(delay: 0.18)
                needsReviewSection
                    .softEntrance(delay: 0.22)
                recentSection
                    .softEntrance(delay: 0.26)
                familySection
                    .softEntrance(delay: 0.30)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(
            ZStack {
                AppTheme.homeBackground
                    .ignoresSafeArea()

                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 260, height: 260)
                    .blur(radius: 20)
                    .offset(x: 150, y: -260)

                Circle()
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .blur(radius: 24)
                    .offset(x: -150, y: -100)
            }
        )
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $reviewSession) { session in
            ReceiptReviewView(initialDraft: session.draft, purchaseToEdit: session.purchaseToEdit) { _ in
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
        .sheet(item: $explanationPresentation) { explanation in
            explanationSheet(for: explanation)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsProtectedSummary) {
            protectedSummarySheet
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            if let undoReturnPurchase {
                undoToast(for: undoReturnPurchase)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            consumePendingNotificationRouteIfNeeded()
        }
        .onChange(of: notificationManager.pendingDeepLink?.id) { _, newValue in
            guard newValue != nil else { return }
            consumePendingNotificationRouteIfNeeded()
        }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingLine)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            if actSoonCount > 0 {
                Text("\(actSoonCount) purchases need attention soon")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.8))
            } else if !hasProtectedItems {
                Text("Your protection timeline is ready whenever your first purchase arrives.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.8))
            }
        }
        .padding(.top, 8)
    }

    private var protectedHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep Sure")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(AppTheme.accent)

            if !hasProtectedItems {
                emptyDelightBadge(text: "A gentle start")
            }

            Text(hasProtectedItems ? "You’re protected on \(activePurchases.count) items" : "Your protection space is ready")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text(
                hasProtectedItems
                    ? "A softer place to keep returns, warranties, and proof of purchase organized before money slips away."
                    : "Scan your first receipt or connect Gmail and Keep Sure will gently turn it into deadlines, warranties, and reminders you will not have to carry alone."
            )
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            heroFeatureRow
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppTheme.dashboardGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                }
        )
    }

    private var statusStrip: some View {
        HStack(spacing: 14) {
            if hasProtectedItems {
                if actSoonCount > 0 {
                    metricCard(title: "Act soon", value: "\(actSoonCount)", subtitle: actSoonCount == 1 ? "purchase needs attention" : "purchases need attention")
                } else {
                    messageMetricCard(title: "Act soon", headline: "All calm", subtitle: "Nothing needs your attention right now. Keep Sure is quietly watching the dates for you.")
                }
                Button {
                    showsProtectedSummary = true
                } label: {
                    metricCard(title: "Protected", value: "\(recentPurchases.count)", subtitle: recentPurchases.count == 1 ? "receipt on hand" : "receipts on hand")
                }
                .buttonStyle(.plain)
            } else {
                messageMetricCard(title: "Ready to begin", headline: "A calm start", subtitle: "Add your first purchase and we will begin watching the dates that matter.")
                messageMetricCard(title: "Next step", headline: "One receipt", subtitle: "Scan a receipt or connect Gmail to bring your timeline to life.")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actSoonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Act soon")

            if actSoonPurchases.isEmpty {
                emptySectionCard(
                    title: "Nothing needs attention yet",
                    message: "As soon as a return window matters, Keep Sure will place it here first."
                )
            } else {
                ForEach(actSoonPurchases.prefix(3), id: \.objectID) { purchase in
                    SwipeToDoneCard(
                        accentColor: AppTheme.accent,
                        actionLabel: "Done",
                        actionIcon: "checkmark.circle.fill",
                        onDone: {
                            markReturnHandled(for: purchase)
                        }
                    ) {
                        timelineCard(
                            title: purchase.wrappedProductName,
                            subtitle: purchase.wrappedMerchantName,
                            detail: deadlineLine(prefix: "Return closes", date: purchase.returnDeadline),
                            explanation: purchase.wrappedReturnExplanation,
                            onExplainTap: {
                                explanationPresentation = .returnWindow(purchase)
                            },
                            urgency: purchase.urgency,
                            icon: icon(for: purchase.wrappedCategoryName)
                        )
                    }
                }
            }
        }
    }

    private var warrantySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Warranty coverage")

            if confirmedWarrantyPurchases.isEmpty {
                emptySectionCard(
                    title: "Confirmed warranties will live here",
                    message: "Keep Sure only shows warranty coverage once it is confirmed, so this space stays meaningful instead of noisy."
                )
            } else {
                ForEach(confirmedWarrantyPurchases.prefix(3), id: \.objectID) { purchase in
                    timelineCard(
                        title: purchase.wrappedProductName,
                        subtitle: purchase.wrappedFamilyOwner,
                        detail: deadlineLine(
                            prefix: warrantyDetailPrefix(for: purchase),
                            date: purchase.confirmedWarrantyExpiration,
                            relative: false
                        ),
                        explanation: purchase.wrappedWarrantyExplanation,
                        onExplainTap: {
                            explanationPresentation = .warrantyCoverage(purchase)
                        },
                        urgency: PurchaseUrgency(deadline: purchase.confirmedWarrantyExpiration),
                        icon: "checkmark.shield.fill"
                    )
                }
            }

            if estimatedWarrantyCount > 0 {
                estimatedWarrantyHintCard(count: estimatedWarrantyCount)
            }
        }
    }

    private var handledReturnsSection: some View {
        Group {
            if !handledReturnPurchases.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        sectionTitle("Handled returns")

                        Spacer()

                        Text(handledReturnPurchases.count == 1 ? "1 cleared" : "\(handledReturnPurchases.count) cleared")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                    }

                    Text("A gentle history of returns you already took care of, so they stay visible without crowding what still needs action.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.76))

                    ForEach(handledReturnPurchases.prefix(3), id: \.objectID) { purchase in
                        handledReturnCard(for: purchase)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Recently added")

            if recentPurchases.isEmpty {
                emptySectionCard(
                    title: "Your first saved purchase will appear here",
                    message: "Scan a receipt, sync Gmail, or add one manually and Keep Sure will start building your story."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recentPurchases.prefix(5), id: \.objectID) { purchase in
                            VStack(alignment: .center, spacing: 12) {
                                ZStack(alignment: .topLeading) {
                                    ReceiptProofThumbnail(
                                        previewData: purchase.proofPreviewData,
                                        hasProof: purchase.hasReceiptProof,
                                        fallbackIcon: icon(for: purchase.wrappedCategoryName),
                                        cornerRadius: 22
                                    )
                                    .frame(height: 108)

                                    Text(purchase.hasReceiptProof ? "Receipt on hand" : "Receipt saved")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.88), in: Capsule())
                                        .foregroundStyle(AppTheme.accent)
                                        .padding(12)
                                }

                                Text(purchase.wrappedProductName)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(purchase.wrappedMerchantName)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if purchase.hasReceiptProof {
                                    Button {
                                        proofPresentation = ReceiptProofPresentation(purchase: purchase)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "doc.viewfinder.fill")
                                                .font(.caption.weight(.bold))
                                            Text("VIEW RECEIPT")
                                                .font(.caption2.weight(.bold))
                                                .tracking(1.0)
                                        }
                                        .foregroundStyle(AppTheme.secondaryAccent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.62), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: icon(for: purchase.wrappedCategoryName))
                                            .font(.caption.weight(.bold))
                                        Text(purchase.wrappedCategoryName.uppercased())
                                            .font(.caption2.weight(.bold))
                                            .tracking(1.0)
                                    }
                                    .foregroundStyle(AppTheme.secondaryAccent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.62), in: Capsule())
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .frame(width: 224, height: 270, alignment: .topLeading)
                            .background(panelCard)
                            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .onTapGesture {
                                reviewSession = .edit(purchase)
                            }
                        }
                    }
                }
            }
        }
    }

    private var needsReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Needs review")

            if reviewCandidates.isEmpty {
                emptySectionCard(
                    title: "Everything feels settled",
                    message: "When Keep Sure finds estimated warranties or uncertain purchase details, it will gather them here for a calm second look."
                )
            } else {
                ForEach(reviewCandidates.prefix(3), id: \.objectID) { purchase in
                    reviewCard(for: purchase)
                }
            }
        }
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                sectionTitle("Family snapshot")
            }
            Text(familyHighlights)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Shared households see one calm timeline instead of scattered receipts and forgotten return dates.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
        }.frame(maxWidth: .infinity, alignment: .init(horizontal: .leading, vertical: .center))
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

    private var greetingLine: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let baseGreeting: String

        switch hour {
        case 5..<12:
            baseGreeting = "Good morning"
        case 12..<17:
            baseGreeting = "Good afternoon"
        default:
            baseGreeting = "Good evening"
        }

        guard
            let firstName = emailSyncManager.connectedFirstName,
            !firstName.isEmpty
        else {
            return baseGreeting
        }

        return "\(baseGreeting), \(firstName)"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
    }

    private func heroBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.72), in: Capsule())
            .foregroundStyle(AppTheme.secondaryAccent)
    }

    private var heroFeatureRow: some View {
        HStack(spacing: 10) {
            heroFeatureCard(
                icon: hasProtectedItems ? "arrow.uturn.backward.circle.fill" : "doc.text.fill",
                title: hasProtectedItems ? "Returns" : "Receipts",
                subtitle: hasProtectedItems ? "First" : "Ready"
            )
            heroFeatureCard(
                icon: hasProtectedItems ? "checkmark.shield.fill" : "envelope.fill",
                title: hasProtectedItems ? "Warranty" : "Gmail",
                subtitle: hasProtectedItems ? "Ready" : "Ready"
            )
            heroFeatureCard(
                icon: "person.2.fill",
                title: "Family",
                subtitle: hasProtectedItems ? "Shared" : "Optional"
            )
        }
    }

    private func emptyDelightBadge(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "face.smiling.fill")
                .font(.caption.weight(.bold))
            Text(text)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.82), in: Capsule())
        .foregroundStyle(AppTheme.accent)
    }

    private func metricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(AppTheme.accent.opacity(0.9))
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
        )
    }

    private func messageMetricCard(title: String, headline: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(AppTheme.accent.opacity(0.9))
            Text(headline)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
        )
    }

    private func emptySectionCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
            
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(panelCard)
    }

    private func estimatedWarrantyHintCard(count: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(count == 1 ? "1 warranty estimate is waiting for confirmation" : "\(count) warranty estimates are waiting for confirmation")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                Text("Keep Sure found likely coverage, but it will only appear here after you confirm it in review.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
            }

            Spacer()
        }
        .padding(18)
        .background(panelCard)
    }

    private func reviewCard(for purchase: PurchaseRecord) -> some View {
        Button {
            reviewSession = .edit(purchase)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: purchase.needsWarrantyConfirmation ? "checkmark.shield.fill" : "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(purchase.wrappedProductName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    Text("\(purchase.wrappedMerchantName) • \(purchase.wrappedSourceType)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))

                    Text(purchase.primaryReviewReason)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                Spacer()

                Text("Review")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(18)
            .background(panelCard)
        }
        .buttonStyle(.plain)
    }

    private func handledReturnCard(for purchase: PurchaseRecord) -> some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(purchase.wrappedProductName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
            }
            
            Text("\(purchase.wrappedMerchantName) • Return was due \(purchase.returnDeadline?.formatted(date: .abbreviated, time: .omitted) ?? "recently")")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.74))
                .multilineTextAlignment(.leading)
            Button("Bring back") {
                undoReturnHandled(for: purchase)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.accent.opacity(0.10), in: Capsule())
            .buttonStyle(.plain)
            
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(panelCard)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            reviewSession = .edit(purchase)
        }
    }

    private var protectedSummarySheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                Text("Protected purchases")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)

                Text("Keep Sure is holding your saved receipts, confirmed warranties, and review items in one calmer place.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))

                HStack(spacing: 12) {
                    summaryPill(title: "Receipts", value: "\(recentPurchases.count)")
                    summaryPill(title: "Confirmed", value: "\(confirmedWarrantyCount)")
                    summaryPill(title: "Review", value: "\(reviewCandidates.count)")
                }

                if let nextPurchase = protectedSheetPrimaryPurchase {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(protectedSheetPrimaryTitle(for: nextPurchase))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)

                        Text(protectedSheetPrimaryMessage(for: nextPurchase))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(AppTheme.elevatedPanelFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                            }
                    )

                    Button {
                        showsProtectedSummary = false
                        reviewSession = .edit(nextPurchase)
                    } label: {
                        Text(protectedSheetPrimaryButtonTitle(for: nextPurchase))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("All receipts")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)

                        Spacer()

                        Text(filteredProtectedPurchases.count == 1 ? "1 saved item" : "\(filteredProtectedPurchases.count) saved items")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                    }

                    protectedSearchField

                    if protectedPurchaseGroups.isEmpty {
                        emptySectionCard(
                            title: "Nothing matched that search",
                            message: "Try a merchant name, product name, or category and Keep Sure will narrow the list for you."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(protectedPurchaseGroups, id: \.title) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(group.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.secondaryAccent)

                                        Spacer()

                                        Text(group.purchases.count == 1 ? "1 item" : "\(group.purchases.count) items")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.6))
                                    }

                                    LazyVStack(spacing: 10) {
                                        ForEach(group.purchases, id: \.objectID) { purchase in
                                            protectedReceiptRow(for: purchase)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Button("Close") {
                    showsProtectedSummary = false
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.homeBackground.ignoresSafeArea())
    }

    private var protectedSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.6))

            TextField("Search receipts, merchants, or categories", text: $protectedSearchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(AppTheme.ink)

            if !protectedSearchText.isEmpty {
                Button {
                    protectedSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                }
        )
    }

    private func protectedReceiptRow(for purchase: PurchaseRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ReceiptProofThumbnail(
                previewData: purchase.proofPreviewData,
                hasProof: purchase.hasReceiptProof,
                fallbackIcon: icon(for: purchase.wrappedCategoryName),
                cornerRadius: 14
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(purchase.wrappedProductName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if purchase.needsReview {
                        Text("Review")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(AppTheme.accent.opacity(0.10), in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                Text(purchase.wrappedMerchantName)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.76))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(purchase.wrappedPurchaseDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))

                    Text("•")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.4))

                    Text(purchase.price.formatted(.currency(code: purchase.wrappedCurrencyCode)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))

                    if purchase.hasVisibleWarranty {
                        Text("•")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.4))

                        Text("Warranty")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.green.opacity(0.8))
                    }
                }

                if purchase.hasReceiptProof {
                    Button {
                        proofPresentation = ReceiptProofPresentation(purchase: purchase)
                    } label: {
                        Text("View original receipt")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppTheme.accent.opacity(0.10), in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                if purchase.needsReview {
                    Text(purchase.primaryReviewReason)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            showsProtectedSummary = false
            reviewSession = .edit(purchase)
        }
    }

    private func warrantyDetailPrefix(for purchase: PurchaseRecord) -> String {
        guard let expiration = purchase.confirmedWarrantyExpiration else {
            return "Warranty"
        }

        if expiration >= Calendar.current.startOfDay(for: .now) {
            return "Warranty active until"
        }

        return "Warranty ended"
    }

    private func markReturnHandled(for purchase: PurchaseRecord) {
        undoDismissTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            purchase.returnCompleted = true
        }

        do {
            try viewContext.save()
            Task {
                await notificationManager.rescheduleAll(in: PersistenceController.shared.container)
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                undoReturnPurchase = purchase
            }
            scheduleUndoDismiss()
        } catch {
            viewContext.rollback()
        }
    }

    private func undoReturnHandled(for purchase: PurchaseRecord) {
        undoDismissTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            purchase.returnCompleted = false
        }

        do {
            try viewContext.save()
            Task {
                await notificationManager.rescheduleAll(in: PersistenceController.shared.container)
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                undoReturnPurchase = nil
            }
        } catch {
            viewContext.rollback()
        }
    }

    private func scheduleUndoDismiss() {
        undoDismissTask?.cancel()
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                undoReturnPurchase = nil
            }
        }
    }

    private func consumePendingNotificationRouteIfNeeded() {
        guard let route = notificationManager.consumePendingDeepLink(),
              let purchase = purchaseForNotificationRoute(route) else { return }

        switch route.destination {
        case .returnWindow:
            explanationPresentation = .reminderReturnWindow(purchase)
        case .warrantyCoverage:
            explanationPresentation = .reminderWarrantyCoverage(purchase)
        case .review:
            reviewSession = .edit(purchase)
        }
    }

    private func purchaseForNotificationRoute(_ route: NotificationDeepLink) -> PurchaseRecord? {
        guard let url = URL(string: route.purchaseURI),
              let coordinator = viewContext.persistentStoreCoordinator,
              let objectID = coordinator.managedObjectID(forURIRepresentation: url),
              let purchase = try? viewContext.existingObject(with: objectID) as? PurchaseRecord
        else {
            return nil
        }

        return purchase
    }

    private func undoToast(for purchase: PurchaseRecord) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Return marked done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                Text("\(purchase.wrappedProductName) was cleared from Act soon.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.76))
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button("Undo") {
                undoReturnHandled(for: purchase)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.accent.opacity(0.10), in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.panelFill)
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 10)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                }
        )
    }

    private func reviewPriority(for purchase: PurchaseRecord) -> Int {
        var score = 0

        if purchase.needsWarrantyConfirmation {
            score += 30
        }
        if purchase.hasUncertainMerchant {
            score += 20
        }
        if purchase.hasUncertainProduct {
            score += 20
        }
        if purchase.wrappedNotes.localizedCaseInsensitiveContains("review") {
            score += 10
        }

        return score
    }

    private func protectedSheetPrimaryTitle(for purchase: PurchaseRecord) -> String {
        if purchase.needsReview {
            return "Next best review"
        }

        return "Latest protected purchase"
    }

    private func protectedSheetPrimaryMessage(for purchase: PurchaseRecord) -> String {
        if purchase.needsReview {
            return "\(purchase.wrappedProductName) is the best next stop because \(purchase.primaryReviewReason.lowercased())."
        }

        return "\(purchase.wrappedProductName) was saved most recently and is a good place to double-check your protection details."
    }

    private func protectedSheetPrimaryButtonTitle(for purchase: PurchaseRecord) -> String {
        purchase.needsReview ? "Review this purchase" : "Open latest purchase"
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
        )
    }

    private func timelineCard(
        title: String,
        subtitle: String,
        detail: String,
        explanation: String? = nil,
        onExplainTap: (() -> Void)? = nil,
        urgency: PurchaseUrgency,
        icon: String
    ) -> some View {
        VStack (alignment: .leading){

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(color(for: urgency).opacity(0.12))
                            .frame(width: 54, height: 54)
                        Image(systemName: icon)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(color(for: urgency))
                    }
                    
                    let titleText = Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    let subtitleText = Text("(\(subtitle))")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))

                    Text("\(titleText) \(subtitleText)")
                }.frame(maxWidth: .infinity, alignment: .init(horizontal: .leading, vertical: .center))
                
                
                HStack(alignment: .center, spacing: 10) {
                    
                    Text(detail)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color(for: urgency))
                    Spacer()
                    Text(urgency.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(color(for: urgency).opacity(0.10), in: Capsule())
                        .foregroundStyle(color(for: urgency))
                }.frame(maxWidth: .infinity, alignment: .init(horizontal: .leading, vertical: .center))

                if let explanation, !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(explanation)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.74))
                            .lineLimit(2)

                        if let onExplainTap {
                            Button(action: onExplainTap) {
                                HStack(spacing: 6) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.caption.weight(.bold))
                                    Text("Why this?")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(AppTheme.accent.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }.frame(maxWidth: .infinity, alignment: .init(horizontal: .leading, vertical: .center))
        }
        .padding(16)
        .background(panelCard)
    }

    @ViewBuilder
    private func explanationSheet(for explanation: ProtectionExplanationPresentation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(explanation.eyebrow.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(AppTheme.accent)

                        Text(explanation.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.ink)

                        Text(explanation.subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
                    }

                    if explanation.isFromReminder {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bell.badge.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 42, height: 42)
                                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(explanation.reminderHeadline)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)

                                Text(explanation.reminderMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .background(panelCard)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: explanation.icon)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(explanation.fullExplanation)
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(panelCard)

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("What Keep Sure is using")

                        summaryPill(title: "Purchase date", value: explanation.purchase.wrappedPurchaseDate.formatted(date: .abbreviated, time: .omitted))

                        if let deadlineValue = explanation.deadlineValue {
                            summaryPill(title: explanation.deadlineTitle, value: deadlineValue)
                        }

                        if let sourceValue = explanation.sourceValue {
                            summaryPill(title: explanation.sourceTitle, value: sourceValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle(explanation.isFromReminder ? "Take action now" : "Next steps")

                        VStack(spacing: 12) {
                            if explanation.showsMarkDoneAction {
                                Button {
                                    markReturnHandled(for: explanation.purchase)
                                    explanationPresentation = nil
                                } label: {
                                    Text("Mark return done")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 12) {
                                Button {
                                    reviewSession = .edit(explanation.purchase)
                                    explanationPresentation = nil
                                } label: {
                                    Text(explanation.reviewButtonTitle)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(explanation.showsMarkDoneAction ? AppTheme.accent : .white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            explanation.showsMarkDoneAction
                                            ? AppTheme.accent.opacity(0.10)
                                            : AppTheme.accent,
                                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)

                                if explanation.purchase.hasReceiptProof {
                                    Button {
                                        proofPresentation = ReceiptProofPresentation(purchase: explanation.purchase)
                                        explanationPresentation = nil
                                    } label: {
                                        Text(explanation.proofButtonTitle)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.homeBackground)
            .navigationTitle("Why Keep Sure thinks this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        explanationPresentation = nil
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    private func deadlineLine(prefix: String, date: Date?, relative: Bool = true) -> String {
        guard let date else { return "Receipt verified" }
        if relative {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "\(prefix) \(formatter.localizedString(for: date, relativeTo: .now))"
        } else {
            return "\(prefix) \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private func color(for urgency: PurchaseUrgency) -> Color {
        switch urgency {
        case .critical: AppTheme.accent
        case .soon: AppTheme.warning
        case .calm: AppTheme.success
        case .expired: AppTheme.secondaryAccent
        }
    }

    private func icon(for category: String) -> String {
        switch category.lowercased() {
        case "electronics": "desktopcomputer"
        case "home": "lamp.floor.fill"
        case "beauty": "sparkles"
        case "travel": "suitcase.rolling.fill"
        default: "shippingbox.fill"
        }
    }
}

private struct ProtectionExplanationPresentation: Identifiable {
    enum Kind {
        case returnWindow
        case warrantyCoverage
    }

    enum Source {
        case card
        case reminder
    }

    let id = UUID()
    let purchase: PurchaseRecord
    let kind: Kind
    let source: Source

    static func returnWindow(_ purchase: PurchaseRecord) -> ProtectionExplanationPresentation {
        .init(purchase: purchase, kind: .returnWindow, source: .card)
    }

    static func warrantyCoverage(_ purchase: PurchaseRecord) -> ProtectionExplanationPresentation {
        .init(purchase: purchase, kind: .warrantyCoverage, source: .card)
    }

    static func reminderReturnWindow(_ purchase: PurchaseRecord) -> ProtectionExplanationPresentation {
        .init(purchase: purchase, kind: .returnWindow, source: .reminder)
    }

    static func reminderWarrantyCoverage(_ purchase: PurchaseRecord) -> ProtectionExplanationPresentation {
        .init(purchase: purchase, kind: .warrantyCoverage, source: .reminder)
    }

    var eyebrow: String {
        switch kind {
        case .returnWindow: "Return window"
        case .warrantyCoverage: "Warranty coverage"
        }
    }

    var title: String {
        switch kind {
        case .returnWindow:
            return purchase.wrappedProductName
        case .warrantyCoverage:
            return purchase.wrappedProductName
        }
    }

    var subtitle: String {
        switch kind {
        case .returnWindow:
            return "\(purchase.wrappedMerchantName) • \(purchase.wrappedSourceType)"
        case .warrantyCoverage:
            return "\(purchase.wrappedMerchantName) • \(purchase.wrappedFamilyOwner)"
        }
    }

    var isFromReminder: Bool {
        source == .reminder
    }

    var reminderHeadline: String {
        switch kind {
        case .returnWindow:
            return "Your return window is getting close"
        case .warrantyCoverage:
            return "Your warranty is worth checking now"
        }
    }

    var reminderMessage: String {
        switch kind {
        case .returnWindow:
            return "If you already started the return, you can clear it here. Otherwise, open the purchase and keep the proof close by."
        case .warrantyCoverage:
            return "This is a good moment to review the coverage details and keep your original proof nearby in case you need to act."
        }
    }

    var icon: String {
        switch kind {
        case .returnWindow:
            return "arrow.uturn.backward.circle.fill"
        case .warrantyCoverage:
            return purchase.needsWarrantyConfirmation ? "sparkles" : "checkmark.shield.fill"
        }
    }

    var fullExplanation: String {
        switch kind {
        case .returnWindow:
            return purchase.wrappedReturnExplanation
        case .warrantyCoverage:
            return purchase.wrappedWarrantyExplanation
        }
    }

    var deadlineTitle: String {
        switch kind {
        case .returnWindow: "Return deadline"
        case .warrantyCoverage: "Coverage ends"
        }
    }

    var deadlineValue: String? {
        switch kind {
        case .returnWindow:
            return purchase.returnDeadline?.formatted(date: .abbreviated, time: .omitted)
        case .warrantyCoverage:
            return purchase.warrantyExpiration?.formatted(date: .abbreviated, time: .omitted)
        }
    }

    var sourceTitle: String {
        switch kind {
        case .returnWindow: "Tracked from"
        case .warrantyCoverage: "Coverage status"
        }
    }

    var sourceValue: String? {
        switch kind {
        case .returnWindow:
            return purchase.wrappedSourceType
        case .warrantyCoverage:
            return purchase.warrantyStatus.title
        }
    }

    var showsMarkDoneAction: Bool {
        kind == .returnWindow && !purchase.isReturnHandled
    }

    var reviewButtonTitle: String {
        switch kind {
        case .returnWindow:
            return "Review return"
        case .warrantyCoverage:
            return "Review coverage"
        }
    }

    var proofButtonTitle: String {
        switch kind {
        case .returnWindow:
            return "View proof"
        case .warrantyCoverage:
            return "Open proof"
        }
    }
}

private struct SwipeToDoneCard<Content: View>: View {
    let accentColor: Color
    let actionLabel: String
    let actionIcon: String
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0

    private let revealWidth: CGFloat = 112

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(accentColor.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.22), lineWidth: 1)
                }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    offsetX = 0
                }
                onDone()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: actionIcon)
                        .font(.headline.weight(.bold))
                    Text(actionLabel)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(accentColor)
                .frame(width: revealWidth, height: 108)
            }
            .buttonStyle(.plain)

            content()
                .offset(x: offsetX)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard value.translation.width < 0 else { return }
                            offsetX = max(-revealWidth, value.translation.width)
                        }
                        .onEnded { value in
                            let shouldReveal = value.translation.width < -52 || value.predictedEndTranslation.width < -90
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offsetX = shouldReveal ? -revealWidth : 0
                            }
                        }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if offsetX != 0 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offsetX = 0
                            }
                        }
                    }
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Swipe left to mark this return as done.")
    }
}
