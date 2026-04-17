import Foundation
import PDFKit
import UIKit
import Vision

struct ReceiptDraft: Identifiable, Equatable {
    static let householdOwnerOptions = ["You", "Family", "Shared"]

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
    var warrantyStatus: WarrantyStatus
    var warrantyConfidenceNote: String
    var learnedAdjustmentSummary: String
    var importBaseline: ReceiptImportBaseline?
    var recognizedText: String
    var pageCount: Int
    var proofPreviewData: Data?
    var proofDocumentData: Data?
    var proofDocumentType: String
    var proofDocumentName: String
    var proofHTMLData: Data?

    var returnExplanationText: String {
        ProtectionExplanationBuilder.returnExplanation(
            merchant: merchantName,
            sourceType: sourceType,
            returnDays: returnDays
        )
    }

    var warrantyExplanationText: String {
        ProtectionExplanationBuilder.warrantyExplanation(
            status: warrantyStatus,
            months: warrantyStatus == .none ? 0 : warrantyMonths,
            evidenceNote: warrantyConfidenceNote
        )
    }

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
        warrantyStatus: WarrantyStatus,
        warrantyConfidenceNote: String = "",
        learnedAdjustmentSummary: String = "",
        importBaseline: ReceiptImportBaseline? = nil,
        recognizedText: String,
        pageCount: Int,
        proofPreviewData: Data? = nil,
        proofDocumentData: Data? = nil,
        proofDocumentType: String = "",
        proofDocumentName: String = "",
        proofHTMLData: Data? = nil
    ) {
        self.id = id
        self.productName = productName
        self.merchantName = merchantName
        self.categoryName = categoryName
        self.familyOwner = Self.normalizedFamilyOwner(familyOwner)
        self.sourceType = sourceType
        self.notes = notes
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.price = price
        self.returnDays = returnDays
        self.warrantyMonths = warrantyMonths
        self.warrantyStatus = warrantyStatus
        self.warrantyConfidenceNote = warrantyConfidenceNote
        self.learnedAdjustmentSummary = learnedAdjustmentSummary
        self.importBaseline = importBaseline
        self.recognizedText = recognizedText
        self.pageCount = pageCount
        self.proofPreviewData = proofPreviewData
        self.proofDocumentData = proofDocumentData
        self.proofDocumentType = proofDocumentType
        self.proofDocumentName = proofDocumentName
        self.proofHTMLData = proofHTMLData
    }

    static let emptyManual = ReceiptDraft(
        productName: "",
        merchantName: "",
        categoryName: "General",
        sourceType: "Manual",
        purchaseDate: .now,
        price: 0,
        returnDays: 30,
        warrantyMonths: 0,
        warrantyStatus: .none,
        warrantyConfidenceNote: "",
        learnedAdjustmentSummary: "",
        importBaseline: nil,
        recognizedText: "",
        pageCount: 0,
        proofPreviewData: nil,
        proofDocumentData: nil,
        proofDocumentType: "",
        proofDocumentName: "",
        proofHTMLData: nil
    )

    var windows: PurchaseWindows {
        PurchaseWindows.makeDeadlines(
            purchaseDate: purchaseDate,
            returnDays: returnDays,
            warrantyMonths: warrantyStatus == .none ? 0 : warrantyMonths
        )
    }

    var hasProofAttachment: Bool {
        proofPreviewData != nil || proofDocumentData != nil
    }

    var hasRichHTMLProof: Bool {
        proofHTMLData != nil
    }

    init(from purchase: PurchaseRecord) {
        let purchaseDate = purchase.purchaseDate ?? .now
        let returnDays = Self.daysBetween(start: purchaseDate, end: purchase.returnDeadline)
        let warrantyMonths = Self.monthsBetween(start: purchaseDate, end: purchase.warrantyExpiration)

        self.init(
            id: purchase.id ?? UUID(),
            productName: purchase.wrappedProductName,
            merchantName: purchase.wrappedMerchantName,
            categoryName: purchase.wrappedCategoryName,
            familyOwner: purchase.wrappedFamilyOwner,
            sourceType: purchase.wrappedSourceType,
            notes: purchase.wrappedNotes,
            currencyCode: purchase.wrappedCurrencyCode,
            purchaseDate: purchaseDate,
            price: purchase.price,
            returnDays: max(returnDays, 0),
            warrantyMonths: max(warrantyMonths, 0),
            warrantyStatus: purchase.warrantyStatus,
            warrantyConfidenceNote: purchase.wrappedWarrantyExplanation,
            learnedAdjustmentSummary: "",
            importBaseline: nil,
            recognizedText: "",
            pageCount: 0,
            proofPreviewData: purchase.proofPreviewData,
            proofDocumentData: purchase.proofDocumentData,
            proofDocumentType: purchase.wrappedProofDocumentType,
            proofDocumentName: purchase.wrappedProofDocumentName,
            proofHTMLData: purchase.proofHTMLData
        )
    }

    private static func daysBetween(start: Date, end: Date?) -> Int {
        guard let end else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func monthsBetween(start: Date, end: Date?) -> Int {
        guard let end else { return 0 }
        return Calendar.current.dateComponents([.month], from: start, to: end).month ?? 0
    }

    static func normalizedFamilyOwner(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch trimmed.lowercased() {
        case "", "me", "you":
            return "You"
        case "family":
            return "Family"
        case "shared":
            return "Shared"
        default:
            return "You"
        }
    }
}

struct ReviewSession: Identifiable {
    let id = UUID()
    let draft: ReceiptDraft
    let purchaseToEdit: PurchaseRecord?

    static func create(from draft: ReceiptDraft) -> ReviewSession {
        ReviewSession(draft: draft, purchaseToEdit: nil)
    }

    static func edit(_ purchase: PurchaseRecord) -> ReviewSession {
        ReviewSession(draft: ReceiptDraft(from: purchase), purchaseToEdit: purchase)
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

    nonisolated private static func recognizeText(in image: UIImage) throws -> String {
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

enum ReceiptProofBuilder {
    static func packageScannedImages(_ images: [UIImage]) -> (previewData: Data?, documentData: Data?, documentType: String, documentName: String) {
        let previewData = images.first.flatMap(makePreviewData(from:))
        let documentData = makePDFData(from: images)
        return (
            previewData,
            documentData,
            documentData == nil ? "image" : "pdf",
            documentData == nil ? "Scanned receipt.jpg" : "Scanned receipt.pdf"
        )
    }

    nonisolated static func makePreviewData(from image: UIImage) -> Data? {
        image.preparingThumbnail(of: CGSize(width: 720, height: 720))?
            .jpegData(compressionQuality: 0.82) ?? image.jpegData(compressionQuality: 0.82)
    }

    private static func makePDFData(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }

        let document = PDFDocument()
        for (index, image) in images.enumerated() {
            guard let page = PDFPage(image: image) else { continue }
            document.insert(page, at: index)
        }

        return document.pageCount > 0 ? document.dataRepresentation() : nil
    }
}

enum ReceiptPDFOCR {
    static func recognizeText(from url: URL) async throws -> (text: String, pageCount: Int, previewData: Data?, documentData: Data?, documentName: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessGranted {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    guard let document = PDFDocument(url: url) else {
                        throw ReceiptScanError.textRecognitionFailed
                    }

                    let pageCount = document.pageCount
                    guard pageCount > 0 else {
                        throw ReceiptScanError.emptyScan
                    }

                    let documentData = try Data(contentsOf: url)

                    var images: [UIImage] = []
                    for index in 0..<pageCount {
                        guard let page = document.page(at: index) else { continue }
                        if let image = render(page: page) {
                            images.append(image)
                        }
                    }

                    guard !images.isEmpty else {
                        throw ReceiptScanError.textRecognitionFailed
                    }

                    let previewData = images.first.flatMap(ReceiptProofBuilder.makePreviewData(from:))

                    Task {
                        do {
                            let recognizedText = try await ReceiptOCR.recognizeText(from: images)
                            continuation.resume(returning: (
                                recognizedText,
                                pageCount,
                                previewData,
                                documentData,
                                url.lastPathComponent
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func render(page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        let targetWidth: CGFloat = 1800
        let scale = targetWidth / max(bounds.width, 1)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
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

    private static let contextualCategoryDefaults: [String: Int] = [
        "Electronics": 12,
        "Home": 12,
        "Beauty": 12,
        "Travel": 12
    ]

    private static let productWarrantyDefaults: [(keywords: [String], months: Int)] = [
        (["iphone", "ipad", "macbook", "airpods", "apple watch"], 12),
        (["laptop", "monitor", "camera", "headphones", "speaker", "tv", "vacuum", "mixer"], 12)
    ]

    private static let merchantWarrantyProfiles: [String: MerchantWarrantyProfile] = [
        "Apple": MerchantWarrantyProfile(
            strongPhrases: ["applecare+", "applecare plus", "apple limited warranty"],
            weakPhrases: ["applecare", "coverage details", "serial number", "model number"],
            productKeywords: ["iphone", "ipad", "macbook", "airpods", "apple watch", "studio display"],
            defaultMonths: 12
        ),
        "Best Buy": MerchantWarrantyProfile(
            strongPhrases: ["geek squad protection", "protection plan purchased", "protection plan included"],
            weakPhrases: ["geek squad", "protection plan", "service plan"],
            productKeywords: ["laptop", "monitor", "camera", "tv", "headphones", "speaker", "vacuum"],
            defaultMonths: 12
        ),
        "Costco": MerchantWarrantyProfile(
            strongPhrases: ["costco concierge", "concierge services", "second year warranty", "2nd year warranty"],
            weakPhrases: ["concierge services", "technical support", "model number", "serial number"],
            productKeywords: ["tv", "laptop", "monitor", "camera", "vacuum", "mixer", "refrigerator", "dishwasher"],
            defaultMonths: 24
        )
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
        let warrantyInference = inferWarrantyDetails(
            from: recognizedText,
            category: category,
            merchant: merchant,
            productName: product
        )
        let notes = "Scanned from \(pageCount) page receipt. Review the OCR text below before saving."

        var draft = ReceiptDraft(
            productName: product,
            merchantName: merchant,
            categoryName: category,
            sourceType: "Scan",
            notes: notes,
            purchaseDate: purchaseDate,
            price: price,
            returnDays: returnDays,
            warrantyMonths: warrantyInference.months,
            warrantyStatus: warrantyInference.status,
            warrantyConfidenceNote: warrantyInference.note,
            importBaseline: ReceiptImportBaseline(
                merchantName: merchant,
                productName: product,
                categoryName: category,
                warrantyStatus: warrantyInference.status,
                warrantyMonths: warrantyInference.months,
                warrantyConfidenceNote: warrantyInference.note
            ),
            recognizedText: recognizedText,
            pageCount: pageCount
        )

        ImportLearningStore.shared.apply(to: &draft)

        let refinedWarrantyInference = inferWarrantyDetails(
            from: recognizedText,
            category: draft.categoryName,
            merchant: draft.merchantName,
            productName: draft.productName
        )
        if draft.warrantyStatus != .confirmed {
            draft.warrantyStatus = refinedWarrantyInference.status
            draft.warrantyMonths = refinedWarrantyInference.months
            draft.warrantyConfidenceNote = refinedWarrantyInference.note
        }

        return draft
    }

    static func merchantSuggestions(from recognizedText: String) -> [String] {
        let lines = recognizedText
            .components(separatedBy: .newlines)
            .map(Self.cleanLine)
            .filter { !$0.isEmpty }

        let known = merchantPolicies.keys.filter { merchant in
            lines.contains { $0.localizedCaseInsensitiveContains(merchant) }
        }

        var suggestions: [String] = known
        for line in lines.prefix(8) {
            guard line.rangeOfCharacter(from: .decimalDigits) == nil else { continue }
            guard !containsReceiptKeyword(line) else { continue }
            guard line.count >= 3 else { continue }
            suggestions.append(line.capitalized)
        }

        return uniqueSuggestions(from: suggestions)
    }

    static func productSuggestions(from recognizedText: String, merchant: String) -> [String] {
        let lines = recognizedText
            .components(separatedBy: .newlines)
            .map(Self.cleanLine)
            .filter { !$0.isEmpty }

        let blockedWords = ["total", "subtotal", "tax", "visa", "mastercard", "approved", "receipt", "thank", "change", "auth", merchant.lowercased()]
        var suggestions: [String] = []

        for line in lines.dropFirst().prefix(24) {
            let lower = line.lowercased()
            guard blockedWords.allSatisfy({ !lower.contains($0) }) else { continue }
            guard line.rangeOfCharacter(from: .letters) != nil else { continue }
            guard line.count > 4 else { continue }
            suggestions.append(line.capitalized)
        }

        return uniqueSuggestions(from: suggestions)
    }

    static func inferWarrantyDetails(
        from recognizedText: String,
        category: String,
        merchant: String,
        productName: String
    ) -> WarrantyInference {
        let haystack = recognizedText.lowercased()
        let explicitMonths = inferWarrantyMonths(from: haystack)
        let hasStrongCoverageLanguage = containsStrongCoverageLanguage(in: haystack)
        let hasWeakCoverageContext = containsWeakCoverageContext(in: haystack)
        let isAvailabilityOnly = containsAvailabilityOnlyWarrantyLanguage(in: haystack)
        let merchantProfile = merchantWarrantyProfiles[merchant]
        let hasMerchantStrongCoverageLanguage = merchantProfile?.strongPhrases.contains(where: haystack.contains) == true
        let hasMerchantWeakCoverageLanguage = merchantProfile?.weakPhrases.contains(where: haystack.contains) == true
        let heuristicMonths = heuristicWarrantyMonths(
            category: category,
            merchant: merchant,
            productName: productName,
            recognizedText: haystack
        )

        if let explicitMonths, explicitMonths > 0 {
            return WarrantyInference(
                status: .confirmed,
                months: explicitMonths,
                note: "Keep Sure found direct warranty language with a specific duration, so this coverage is treated as dependable."
            )
        }

        if !isAvailabilityOnly, hasMerchantStrongCoverageLanguage {
            let months = heuristicMonths ?? merchantProfile?.defaultMonths ?? contextualCategoryDefaults[category] ?? 12
            return WarrantyInference(
                status: .estimated,
                months: months,
                note: "\(merchant) surfaced coverage language that usually means real warranty support, but Keep Sure still wants you to confirm the exact term before relying on it."
            )
        }

        if hasStrongCoverageLanguage {
            let months = heuristicMonths ?? contextualCategoryDefaults[category] ?? 12
            return WarrantyInference(
                status: .estimated,
                months: months,
                note: "Keep Sure found coverage language, but the duration still looks inferred rather than explicit. Confirm it before relying on reminders."
            )
        }

        if !isAvailabilityOnly, hasMerchantWeakCoverageLanguage, let heuristicMonths {
            return WarrantyInference(
                status: .estimated,
                months: heuristicMonths,
                note: "\(merchant) gives Keep Sure a few merchant-specific warranty clues here, but the coverage still looks like a likely match rather than confirmed proof."
            )
        }

        if !isAvailabilityOnly, hasWeakCoverageContext, let heuristicMonths {
            return WarrantyInference(
                status: .estimated,
                months: heuristicMonths,
                note: "Keep Sure found a few coverage hints around this purchase, but not enough to call the warranty confirmed yet."
            )
        }

        return WarrantyInference(
            status: .none,
            months: 0,
            note: "Keep Sure did not find dependable warranty evidence on this receipt yet. Add coverage only once the receipt or product details confirm it."
        )
    }

    private static func inferWarrantyMonths(from haystack: String) -> Int? {
        let patterns: [String] = [
            #"(?i)\b(\d{1,2})\s*(?:year|yr|years|yrs)\s*(?:limited\s+)?(?:manufacturer\s+)?(?:warranty|coverage|protection plan|care plan)\b"#,
            #"(?i)\b(\d{1,2})\s*(?:month|months|mo)\s*(?:limited\s+)?(?:manufacturer\s+)?(?:warranty|coverage|protection plan|care plan)\b"#,
            #"(?i)\b(?:warranty|coverage|protection plan|care plan)\s*(?:for|of)?\s*(\d{1,2})\s*(?:year|yr|years|yrs)\b"#,
            #"(?i)\b(?:warranty|coverage|protection plan|care plan)\s*(?:for|of)?\s*(\d{1,2})\s*(?:month|months|mo)\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsHaystack = haystack as NSString
            let range = NSRange(location: 0, length: nsHaystack.length)
            guard let match = regex.firstMatch(in: haystack, range: range), match.numberOfRanges > 1 else { continue }

            let rawValue = nsHaystack.substring(with: match.range(at: 1))
            guard let number = Int(rawValue) else { continue }

            if pattern.localizedCaseInsensitiveContains("year|yr") {
                return number * 12
            }

            return number
        }

        let writtenNumbers: [String: Int] = [
            "one": 12,
            "two": 24,
            "three": 36,
            "four": 48,
            "five": 60
        ]

        for (word, months) in writtenNumbers {
            let patterns = [
                "\(word) year limited warranty",
                "\(word) year warranty",
                "\(word)-year limited warranty",
                "\(word)-year warranty"
            ]

            if patterns.contains(where: haystack.contains) {
                return months
            }
        }

        return nil
    }

    private static func containsStrongCoverageLanguage(in haystack: String) -> Bool {
        let phrases = [
            "limited warranty",
            "manufacturer warranty",
            "manufacturers warranty",
            "covered by warranty",
            "warranty coverage",
            "warranty expires",
            "warranty valid until",
            "warranty through",
            "applecare+",
            "applecare plus",
            "protection plan included",
            "protection plan purchased",
            "service plan included"
        ]

        return phrases.contains(where: haystack.contains)
    }

    private static func containsWeakCoverageContext(in haystack: String) -> Bool {
        let phrases = [
            "service plan",
            "care plan",
            "serial number",
            "model number",
            "register your product",
            "register product",
            "warranty claim",
            "coverage details",
            "manufacturer support"
        ]

        return phrases.contains(where: haystack.contains)
    }

    private static func containsAvailabilityOnlyWarrantyLanguage(in haystack: String) -> Bool {
        let phrases = [
            "protection plan available",
            "extended warranty available",
            "add applecare",
            "purchase applecare",
            "buy applecare",
            "purchase a protection plan",
            "learn more about warranty",
            "for warranty information",
            "warranty information",
            "terms and conditions apply"
        ]

        return phrases.contains(where: haystack.contains)
    }

    private static func heuristicWarrantyMonths(
        category: String,
        merchant: String,
        productName: String,
        recognizedText: String
    ) -> Int? {
        let productLower = productName.lowercased()
        let merchantProfile = merchantWarrantyProfiles[merchant]

        if merchant == "Apple",
           category == "Electronics",
           ["iphone", "ipad", "macbook", "airpods", "apple watch"].contains(where: productLower.contains) {
            return 12
        }

        if let merchantProfile,
           merchantProfile.productKeywords.contains(where: productLower.contains) {
            return merchantProfile.defaultMonths
        }

        if recognizedText.contains("serial number") || recognizedText.contains("model number") {
            return merchantProfile?.defaultMonths ?? contextualCategoryDefaults[category]
        }

        for candidate in productWarrantyDefaults {
            if candidate.keywords.contains(where: productLower.contains) {
                return candidate.months
            }
        }

        return nil
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

    nonisolated private static func cleanLine(_ line: String) -> String {
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

    private static func uniqueSuggestions(from values: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(trimmed)
        }

        return Array(results.prefix(3))
    }
}

struct WarrantyInference: Equatable {
    let status: WarrantyStatus
    let months: Int
    let note: String
}

struct ReceiptImportBaseline: Equatable {
    let merchantName: String
    let productName: String
    let categoryName: String
    let warrantyStatus: WarrantyStatus
    let warrantyMonths: Int
    let warrantyConfidenceNote: String
}

private struct MerchantWarrantyProfile {
    let strongPhrases: [String]
    let weakPhrases: [String]
    let productKeywords: [String]
    let defaultMonths: Int
}
