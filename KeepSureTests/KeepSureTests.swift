//
//  KeepSureTests.swift
//  KeepSureTests
//
//  Created by Abhishek Gang Deb on 4/8/26.
//

import Foundation
import Testing
@testable import KeepSure

struct KeepSureTests {

    @MainActor
    @Test func gmailPurchaseParserCreatesEmailDraft() async throws {
        let message = GmailMessage(
            id: "message-1",
            subject: "Order confirmed: Dyson Airwrap",
            from: "Sephora <orders@sephora.com>",
            snippet: "Your total was $599.00.",
            body: "Thank you for your order. Dyson Airwrap Complete. Order total $599.00.",
            date: .now
        )

        let draft = GmailPurchaseParser.draft(from: message)

        #expect(draft != nil)
        #expect(draft?.sourceType == "Email")
        #expect(draft?.merchantName == "Sephora")
        #expect(draft?.productName.contains("Dyson") == true)
        #expect(draft?.price == 599)
    }

}
