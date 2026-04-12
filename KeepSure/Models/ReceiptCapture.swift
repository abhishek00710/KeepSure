import Foundation
import UIKit
import Vision

struct ReceiptDraft: Identifiable, Equatable {
    let id: UUID
    var productName: String
    var merchantName: String
    var categoryName: String
    var familyOwner: String
    var sourceType: String
    var notes: String
    var currencyCode: String
    var purchaseDate: Date
    var price: Double
    var returnDays: Int
    var warrantyMonths: Int
    var recognizedText: String
    var pageCount: Int

    init(
        id: UUID = UUID(),
        productName: String,
        merchantName: String,
        categoryName: String,
        familyOwner: String = "You",
        sourceType: String = "Scan",
        notes: String = "",
        currencyCode: String = "USD",
        purchaseDate: Date,
        price: Double,
        returnDays: Int,
        warrantyMonths: Int,
        recognizedText: String,
        pageCount: Int
    ) {
        self.id = id
        self.productName = productName
        self.merchantName = merchantName
        self.categoryName = categoryName
        self.familyOwner = familyOwner
        self.sourceType = sourceType
        self.notes = notes
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.price = price
        self.returnDays = returnDays
        self.warrantyMonths = warrantyMonths
        self.recognizedText = recognizedText
        self.pageCount = pageCount
    }

    static let emptyManual = ReceiptDraft(
        productName: "",
        merchantName: "",
        categoryName: "General",
        sourceType: "Manual",
        purchaseDate: .now,
        price: 0,
        returnDays: 30,
        warrantyMonths: 12,
        recognizedText: "",
        pageCount: 0
    )

    var windows: PurchaseWindows {
        PurchaseWindows.makeDeadlines(
            purchaseDate: purchaseDate,
            returnDays: returnDays,
            warrantyMonths: warrantyMonths
        )
    }
}

enum ReceiptScanError: LocalizedError {
    case emptyScan
    case textRecognitionFailed

    var errorDescription: String? {
        switch self {
        case .emptyScan:
            return "No receipt pages were captured."
        case .textRecognitionFailed:
            return "Keep Sure could not read enough text from that receipt. Try scanning in better light."
        }
    }
}

enum ReceiptOCR {
    static func recognizeText(from images: [UIImage]) async throws -> String {
        guard !images.isEmpty else {
            throw ReceiptScanError.emptyScan
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let recognized = try images.map(Self.recognizeText).joined(separator: "\n")
                    let cleaned = recognized
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")

                    guard !cleaned.isEmpty else {
                        throw ReceiptScanError.textRecognitionFailed
                    }

                    continuation.resume(returning: cleaned)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func recognizeText(in image: UIImage) throws -> String {
        guard let cgImage = image.cgImage else {
            throw ReceiptScanError.textRecognitionFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en_US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

enum ReceiptTextParser {
    private static let merchantPolicies: [String: Int] = [
        "Amazon": 30,
        "Apple": 14,
        "Best Buy": 15,
        "Costco": 90,
        "Sephora": 30,
        "Target": 30,
        "Walmart": 30
    ]

    private static let categoryDefaults: [String: Int] = [
        "Electronics": 12,
        "Home": 24,
        "Beauty": 12,
        "Travel": 36,
        "General": 12
    ]

    static func draft(from recognizedText: String, pageCount: Int) -> ReceiptDraft {
        let lines = recognizedText
            .components(separatedBy: .newlines)
            .map(Self.cleanLine)
            .filter { !$0.isEmpty }

        let merchant = inferMerchant(from: lines)
        let price = inferPrice(from: lines)
        let purchaseDate = inferPurchaseDate(from: lines) ?? .now
        let product = inferProduct(from: lines, merchant: merchant)
        let category = inferCategory(from: lines, productName: product)
        let returnDays = merchantPolicies[merchant] ?? 30
        let warrantyMonths = categoryDefaults[category] ?? 12
        let notes = "Scanned from \(pageCount) page receipt. Review the OCR text below before saving."

        return ReceiptDraft(
            productName: product,
            merchantName: merchant,
            categoryName: category,
            sourceType: "Scan",
            notes: notes,
            purchaseDate: purchaseDate,
            price: price,
            returnDays: returnDays,
            warrantyMonths: warrantyMonths,
            recognizedText: recognizedText,
            pageCount: pageCount
        )
    }

    private static func inferMerchant(from lines: [String]) -> String {
        let known = merchantPolicies.keys.sorted { $0.count > $1.count }
        for merchant in known {
            if lines.contains(where: { $0.localizedCaseInsensitiveContains(merchant) }) {
                return merchant
            }
        }

        for line in lines.prefix(8) {
            if line.rangeOfCharacter(from: .decimalDigits) == nil,
               !containsReceiptKeyword(line),
               line.count >= 3 {
                return line.capitalized
            }
        }

        return "Unknown merchant"
    }

    private static func inferProduct(from lines: [String], merchant: String) -> String {
        let blockedWords = ["total", "subtotal", "tax", "visa", "mastercard", "approved", "receipt", "thank", "change", "auth", merchant.lowercased()]

        for line in lines.dropFirst().prefix(24) {
            let lower = line.lowercased()
            guard blockedWords.allSatisfy({ !lower.contains($0) }) else { continue }
            guard line.rangeOfCharacter(from: .letters) != nil else { continue }
            if lower.contains("qty") || lower.contains("item") || line.count > 4 {
                return line.capitalized
            }
        }

        return merchant == "Unknown merchant" ? "Scanned purchase" : "\(merchant) purchase"
    }

    private static func inferCategory(from lines: [String], productName: String) -> String {
        let haystack = ([productName] + lines).joined(separator: " ").lowercased()

        if ["switch", "iphone", "airpods", "laptop", "tv", "monitor", "camera", "headphones", "speaker"].contains(where: haystack.contains) {
            return "Electronics"
        }
        if ["sofa", "lamp", "chair", "vacuum", "lights", "cookware", "mixer", "pan"].contains(where: haystack.contains) {
            return "Home"
        }
        if ["serum", "cream", "sephora", "beauty", "makeup", "dyson airwrap", "fragrance"].contains(where: haystack.contains) {
            return "Beauty"
        }
        if ["suitcase", "carry-on", "travel", "luggage", "away", "backpack"].contains(where: haystack.contains) {
            return "Travel"
        }

        return "General"
    }

    private static func inferPrice(from lines: [String]) -> Double {
        let totalKeywords = ["total", "amount paid", "grand total", "order total"]
        let currencyPattern = #"(?:USD|US\$|\$)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))"#
        let regex = try? NSRegularExpression(pattern: currencyPattern, options: [.caseInsensitive])

        func amounts(in line: String) -> [Double] {
            guard let regex else { return [] }
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            return matches.compactMap { match in
                guard match.numberOfRanges > 1 else { return nil }
                let raw = nsLine.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
                return Double(raw)
            }
        }

        for line in lines {
            if totalKeywords.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
                if let best = amounts(in: line).max() {
                    return best
                }
            }
        }

        let allAmounts = lines.flatMap(amounts(in:))
        return allAmounts.max() ?? 0
    }

    private static func inferPurchaseDate(from lines: [String]) -> Date? {
        let formats = [
            "MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy", "M-d-yyyy",
            "yyyy-MM-dd", "MMM d, yyyy", "MMMM d, yyyy",
            "dd/MM/yyyy", "d/MM/yyyy"
        ]

        let formatters = formats.map { format -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter
        }

        let pattern = #"\b(?:\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}-\d{2}-\d{2}|[A-Za-z]{3,9}\s+\d{1,2},\s+\d{4})\b"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in lines.prefix(16) {
            guard let regex else { continue }
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                let candidate = nsLine.substring(with: match.range)
                for formatter in formatters {
                    if let date = formatter.date(from: candidate) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private static func cleanLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "•", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsReceiptKeyword(_ line: String) -> Bool {
        let keywords = ["receipt", "order", "total", "subtotal", "tax", "visa", "mastercard", "thank", "change"]
        let lower = line.lowercased()
        return keywords.contains(where: lower.contains)
    }
}
