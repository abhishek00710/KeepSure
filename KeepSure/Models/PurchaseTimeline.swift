import Foundation

enum WarrantyStatus: String, CaseIterable {
    case none
    case estimated
    case confirmed

    var title: String {
        switch self {
        case .none:
            return "No warranty"
        case .estimated:
            return "Likely"
        case .confirmed:
            return "Confirmed"
        }
    }

    var reviewGuidance: String {
        switch self {
        case .none:
            return "Keep Sure did not find dependable warranty evidence yet. Add coverage only once the receipt, product page, or warranty card confirms it."
        case .estimated:
            return "Keep Sure found some warranty clues, but the coverage still needs confirmation before reminders should be trusted."
        case .confirmed:
            return "Keep Sure has enough direct warranty evidence to track this coverage confidently."
        }
    }
}

struct PurchaseWindows: Equatable {
    let returnDeadline: Date?
    let warrantyExpiration: Date?

    static func makeDeadlines(
        purchaseDate: Date,
        returnDays: Int,
        warrantyMonths: Int,
        calendar: Calendar = .current
    ) -> PurchaseWindows {
        let returnDeadline = returnDays > 0
            ? calendar.date(byAdding: .day, value: returnDays, to: purchaseDate)
            : nil
        let warrantyExpiration = warrantyMonths > 0
            ? calendar.date(byAdding: .month, value: warrantyMonths, to: purchaseDate)
            : nil

        return PurchaseWindows(
            returnDeadline: returnDeadline,
            warrantyExpiration: warrantyExpiration
        )
    }
}

enum ProtectionExplanationBuilder {
    static func returnExplanation(
        merchant: String,
        sourceType: String,
        returnDays: Int
    ) -> String {
        guard returnDays > 0 else {
            return "Keep Sure is not tracking a return window for this purchase right now."
        }

        let merchantName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantReference = merchantName.isEmpty || merchantName == "Unknown merchant"
            ? "this purchase"
            : merchantName

        switch sourceType {
        case "Manual":
            return "Keep Sure is tracking the \(returnDays)-day return window you entered manually and counting it from the purchase date."
        case "Email":
            return "Keep Sure is tracking a \(returnDays)-day return window for \(merchantReference) based on the connected retailer profile and counting it from the purchase date in the order email."
        case "Scan":
            return "Keep Sure is tracking a \(returnDays)-day return window for \(merchantReference) using the scanned receipt date and the retailer policy it recognized."
        default:
            return "Keep Sure is tracking a \(returnDays)-day return window for \(merchantReference) from the purchase date. Review it if the store policy says something different."
        }
    }

    static func warrantyExplanation(
        status: WarrantyStatus,
        months: Int,
        evidenceNote: String
    ) -> String {
        let trimmedNote = evidenceNote.trimmingCharacters(in: .whitespacesAndNewlines)

        switch status {
        case .none:
            if !trimmedNote.isEmpty {
                return trimmedNote
            }
            return "Keep Sure has not found dependable warranty proof yet, so no warranty reminders are being scheduled."
        case .estimated:
            if !trimmedNote.isEmpty {
                if months > 0 {
                    return "\(trimmedNote) Keep Sure is holding a \(months)-month estimate from the purchase date until you confirm it."
                }
                return "\(trimmedNote) Keep Sure is keeping this as an estimate until you confirm it."
            }

            if months > 0 {
                return "Keep Sure found partial warranty clues and is holding a \(months)-month estimate from the purchase date until you confirm it."
            }
            return "Keep Sure found partial warranty clues, but the coverage still needs confirmation before reminders should be trusted."
        case .confirmed:
            if !trimmedNote.isEmpty {
                if months > 0 {
                    return "\(trimmedNote) Keep Sure is tracking \(months) months of confirmed coverage from the purchase date."
                }
                return trimmedNote
            }

            if months > 0 {
                return "Keep Sure has enough direct warranty proof to track \(months) months of confirmed coverage from the purchase date."
            }
            return "Keep Sure has enough direct warranty proof to track this confirmed coverage confidently."
        }
    }
}

enum PurchaseUrgency {
    case critical
    case soon
    case calm
    case expired

    init(referenceDate: Date = .now, deadline: Date?) {
        guard let deadline else {
            self = .calm
            return
        }

        let daysRemaining = Calendar.current.dateComponents([.day], from: referenceDate, to: deadline).day ?? 0

        switch daysRemaining {
        case ..<0:
            self = .expired
        case 0...3:
            self = .critical
        case 4...14:
            self = .soon
        default:
            self = .calm
        }
    }

    var label: String {
        switch self {
        case .critical:
            "Act now"
        case .soon:
            "Coming up"
        case .calm:
            "On track"
        case .expired:
            "Expired"
        }
    }
}
