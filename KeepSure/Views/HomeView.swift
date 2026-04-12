import CoreData
import SwiftUI

struct HomeView: View {
    @FetchRequest(fetchRequest: PurchaseRecord.recentFetchRequest, animation: .snappy)
    private var purchases: FetchedResults<PurchaseRecord>

    private var activePurchases: [PurchaseRecord] {
        purchases.filter { !$0.isArchived }
    }

    private var returnsSoon: [PurchaseRecord] {
        activePurchases
            .filter { $0.returnDeadline != nil }
            .sorted { ($0.returnDeadline ?? .distantFuture) < ($1.returnDeadline ?? .distantFuture) }
    }

    private var warrantiesSoon: [PurchaseRecord] {
        activePurchases
            .filter { $0.warrantyExpiration != nil }
            .sorted { ($0.warrantyExpiration ?? .distantFuture) < ($1.warrantyExpiration ?? .distantFuture) }
    }

    private var recentPurchases: [PurchaseRecord] {
        activePurchases.sorted { $0.wrappedCreatedAt > $1.wrappedCreatedAt }
    }

    private var dueThisWeekCount: Int {
        activePurchases.filter {
            guard let deadline = $0.nextDeadline?.date else { return false }
            let days = Calendar.current.dateComponents([.day], from: .now, to: deadline).day ?? 999
            return days >= 0 && days <= 7
        }.count
    }

    private var familyHighlights: String {
        let owners = Dictionary(grouping: activePurchases, by: \.wrappedFamilyOwner)
        let topOwner = owners.max { $0.value.count < $1.value.count }
        guard let topOwner else { return "Everyone is up to date this week" }
        return "\(topOwner.value.count) items added by \(topOwner.key)"
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
                warrantySection
                    .softEntrance(delay: 0.18)
                recentSection
                    .softEntrance(delay: 0.22)
                familySection
                    .softEntrance(delay: 0.26)
                suggestionCard
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
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greetingLine)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            if dueThisWeekCount > 0 {
                Text("\(dueThisWeekCount) things need attention this week")
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

            Text("You’re protected on \(activePurchases.count) items")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text("A softer place to keep returns, warranties, and proof of purchase organized before money slips away.")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                heroBadge("Returns first")
                heroBadge("Warranty ready")
                heroBadge("Family shared")
            }
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
            metricCard(title: "Act soon", value: "\(dueThisWeekCount)", subtitle: "urgent deadlines")
            metricCard(title: "Protected", value: "\(recentPurchases.count)", subtitle: "receipts on hand")
        }
    }

    private var actSoonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Act soon")

            ForEach(returnsSoon.prefix(3), id: \.objectID) { purchase in
                timelineCard(
                    title: purchase.wrappedProductName,
                    subtitle: purchase.wrappedMerchantName,
                    detail: deadlineLine(prefix: "Return closes", date: purchase.returnDeadline),
                    urgency: purchase.urgency,
                    icon: icon(for: purchase.wrappedCategoryName)
                )
            }
        }
    }

    private var warrantySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Upcoming warranties")

            ForEach(warrantiesSoon.prefix(3), id: \.objectID) { purchase in
                timelineCard(
                    title: purchase.wrappedProductName,
                    subtitle: purchase.wrappedFamilyOwner,
                    detail: deadlineLine(prefix: "Warranty active until", date: purchase.warrantyExpiration, relative: false),
                    urgency: PurchaseUrgency(deadline: purchase.warrantyExpiration),
                    icon: "checkmark.shield.fill"
                )
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Recently added")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(recentPurchases.prefix(5), id: \.objectID) { purchase in
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.9), AppTheme.sand],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 114)
                                .overlay(alignment: .topLeading) {
                                    Text("Receipt verified")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AppTheme.accent.opacity(0.10), in: Capsule())
                                        .foregroundStyle(AppTheme.accent)
                                        .padding(12)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    HStack(spacing: 8) {
                                        Image(systemName: icon(for: purchase.wrappedCategoryName))
                                            .font(.caption.weight(.bold))
                                        Text(purchase.wrappedCategoryName.uppercased())
                                            .font(.caption2.weight(.bold))
                                            .tracking(1.0)
                                    }
                                    .foregroundStyle(AppTheme.secondaryAccent)
                                    .padding(14)
                                }

                            Text(purchase.wrappedProductName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)

                            Text(purchase.wrappedMerchantName)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                        }
                        .padding(16)
                        .frame(width: 224, alignment: .leading)
                        .background(panelCard)
                    }
                }
            }
        }
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Family snapshot")
            Text(familyHighlights)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Shared households see one calm timeline instead of scattered receipts and forgotten return dates.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.78))
        }
        .padding(20)
        .background(panelCard)
    }

    private var suggestionCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Smart suggestion")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("2 receipts need review. Confirm the extracted product names and return windows so your alerts stay accurate.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.8))
            }

            Spacer()
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

    private var greetingLine: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning, Abhishek"
        case 12..<17: return "Good afternoon, Abhishek"
        default: return "Good evening, Abhishek"
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
        )
    }

    private func timelineCard(title: String, subtitle: String, detail: String, urgency: PurchaseUrgency, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color(for: urgency).opacity(0.12))
                    .frame(width: 54, height: 54)
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color(for: urgency))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(for: urgency))
            }

            Spacer()

            Text(urgency.label)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(color(for: urgency).opacity(0.10), in: Capsule())
                .foregroundStyle(color(for: urgency))
        }
        .padding(16)
        .background(panelCard)
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
