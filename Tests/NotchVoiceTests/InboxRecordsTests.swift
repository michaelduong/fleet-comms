//  InboxRecordsTests.swift
//  NotchVoice
//
//  Created by Michael Duong on 10/28/26.

import Foundation
@testable import NotchVoice
import Testing

struct InboxRecordsTests {
    @Test func decodesNoteReceipt() throws {
        let json = """
        {"schema":"fm-inbox-note.v1","outcome":"created","id":"1700000000-abc123","request_id":"abc",\
        "saved":true,"announced":false,"acknowledged":false,"path":"/x"}
        """
        let receipt = try JSONDecoder().decode(NoteReceipt.self, from: Data(json.utf8))
        #expect(receipt.id == "1700000000-abc123")
        #expect(receipt.outcome == "created")
    }

    @Test func decodesRepliesAndCursor() throws {
        let json = """
        {"schema":"fm-inbox-receipts.v1","pending":[],"handled":[],
         "replies":[{"id":"1-a","at":"2026-10-28T00:00:00Z","body":"Done.","cursor":"000000000007"}],
         "reply_cursor":"000000000007","omitted":[]}
        """
        let page = try JSONDecoder().decode(ReceiptsPage.self, from: Data(json.utf8))
        #expect(page.replies.first?.body == "Done.")
        #expect(page.replyCursor == "000000000007")
    }
}
