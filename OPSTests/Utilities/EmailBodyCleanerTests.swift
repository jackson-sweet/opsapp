//
//  EmailBodyCleanerTests.swift
//  OPSTests
//
//  Bug 183f7ec9 — the lead activity feed showed whole quoted reply chains, so
//  every email in a thread read as the same wall of text. `EmailBodyCleaner`
//  reduces one message to the text its sender actually typed. These tests pin
//  the conservative contract: strip only on a confident anchor, and never blank
//  out a message.
//
//  Heuristics ported from the ops-web reference
//  (`src/lib/api/services/conversation-state/message-cleaner.ts` +
//  `src/lib/utils/email-parsing.ts` QUOTE_MARKERS) — read-only reference.
//

import XCTest
@testable import OPS

final class EmailBodyCleanerTests: XCTestCase {

    // MARK: - Quote markers

    func testStripsGmailWroteBlock() {
        let raw = """
        Yes, Friday works. See you at 9.

        On Mon, Jan 15, 2026 at 3:45 PM John Smith <john@example.com> wrote:
        > Can you make it Friday morning?
        > Let me know.
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Yes, Friday works. See you at 9.")
    }

    func testStripsLineWrappedGmailWroteBlock() {
        let raw = """
        Sounds good.

        On Mon, Jan 15, 2026 at 3:45 PM John Smith <john@example.com>
        wrote:
        > original text here
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Sounds good.")
    }

    func testStripsOutlookOriginalMessageBlock() {
        let raw = """
        Approved. Go ahead and order the material.

        -----Original Message-----
        From: Helen Calloway
        Sent: Monday, January 15, 2026 9:02 AM
        To: Jackson
        Subject: Re: Roof tear-off
        """

        XCTAssertEqual(
            EmailBodyCleaner.clean(raw),
            "Approved. Go ahead and order the material."
        )
    }

    func testStripsOutlookHeaderTripletBlock() {
        let raw = """
        Confirmed for Thursday.

        From: Helen Calloway <helen@calloway.example>
        Sent: Monday, January 15, 2026 9:02 AM
        To: Jackson Sweet
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Confirmed for Thursday.")
    }

    func testStripsAppleMailWroteBlock() {
        let raw = """
        Perfect, thanks for the update.

        On Jan 15, 2026, at 3:45 PM, John Smith wrote:
        > earlier message
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Perfect, thanks for the update.")
    }

    func testStripsForwardedMessageBlock() {
        let raw = """
        Passing this along.

        ---------- Forwarded message ----------
        From: someone@example.com
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Passing this along.")
    }

    func testStripsBeginForwardedMessageBlock() {
        let raw = """
        See below.

        Begin forwarded message:

        From: someone@example.com
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "See below.")
    }

    func testStripsRunOfQuotedLinePrefixes() {
        let raw = """
        Numbers look right to me.

        > line one of the quote
        > line two of the quote
        > line three of the quote
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Numbers look right to me.")
    }

    func testKeepsShortRunOfQuotedLines() {
        // Two quoted lines is below the 3-line run threshold — a sender quoting
        // one short passage inline is content, not a reply chain.
        let raw = """
        Numbers look right to me.

        > line one
        > line two
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), raw)
    }

    func testStripsOutlookWebDividerBlock() {
        let raw = """
        Works for us.

        ________________________________
        From: Helen Calloway
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Works for us.")
    }

    func testStripsAtTheEarliestMarkerWhenSeveralAppear() {
        let raw = """
        Short answer: yes.

        On Mon, Jan 15, 2026 at 3:45 PM John Smith <john@example.com> wrote:
        > text

        -----Original Message-----
        From: someone
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Short answer: yes.")
    }

    // MARK: - Signature / footer stripping

    func testStripsRFC3676SignatureDelimiter() {
        let raw = """
        Booked for Tuesday.

        --
        Helen Calloway
        Calloway Homes
        555-0142
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Booked for Tuesday.")
    }

    func testStripsDeviceFooter() {
        let raw = """
        On my way.

        Sent from my iPhone
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "On my way.")
    }

    func testStripsSignoffFollowedByContactTail() {
        let raw = """
        The quote is attached.

        Thanks,
        Helen Calloway
        helen@calloway.example
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "The quote is attached.")
    }

    func testStripsSignoffFollowedByLoneNameLine() {
        let raw = """
        Confirmed.

        Regards,
        Helen
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Confirmed.")
    }

    func testKeepsConversationalThanksMidMessage() {
        // "Thanks for getting back to me" is prose, not a sign-off line, and the
        // tail is a long paragraph — never cut here.
        let raw = """
        Thanks for getting back to me so quickly on the estimate.

        We reviewed it internally and the scope looks right, though we would like to talk through the tear-off schedule before signing anything.
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), raw)
    }

    func testKeepsSignoffWhenTailIsLongProse() {
        let raw = """
        Here is where we landed.

        Thanks,
        We reviewed the estimate internally and the scope looks right, though we would like to talk through the tear-off schedule before we sign anything at all.
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), raw)
    }

    func testStripsTrailingLabelledFooterLines() {
        let raw = """
        Materials are on site.

        Phone: 555-0142
        Address: 1240 Maple Ave
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Materials are on site.")
    }

    func testKeepsLabelledLinesThatAreNotTrailing() {
        let raw = """
        Phone: 555-0142
        is the number that keeps calling about the tear-off — can you check it?
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), raw)
    }

    // MARK: - Conservatism guarantees

    func testReturnsOriginalWhenStrippingWouldLeaveNothing() {
        // The entire message is a quote — showing the quote beats showing blank.
        let raw = """
        On Mon, Jan 15, 2026 at 3:45 PM John Smith <john@example.com> wrote:
        > Can you make it Friday morning?
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), raw)
    }

    func testReturnsOriginalWhenSignatureIsTheWholeMessage() {
        let raw = """
        --
        Helen Calloway
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), raw)
    }

    func testLeavesCleanBodyUntouched() {
        let raw = "Can you get me a price on the tear-off by Thursday?"
        XCTAssertEqual(EmailBodyCleaner.clean(raw), raw)
    }

    func testNormalizesCRLFLineEndings() {
        let raw = "Yes, Friday works.\r\n\r\n--\r\nHelen Calloway\r\n555-0142"
        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Yes, Friday works.")
    }

    func testEmptyAndWhitespaceBodiesSurviveUnchanged() {
        XCTAssertEqual(EmailBodyCleaner.clean(""), "")
        XCTAssertEqual(EmailBodyCleaner.clean("   \n  "), "   \n  ")
    }

    func testStripsQuoteThenSignatureTogether() {
        let raw = """
        Friday at 9 works.

        Thanks,
        Helen
        555-0142

        On Mon, Jan 15, 2026 at 3:45 PM Jackson <jackson@ops.example> wrote:
        > Does Friday work?
        """

        XCTAssertEqual(EmailBodyCleaner.clean(raw), "Friday at 9 works.")
    }

    // MARK: - Collapsed preview

    func testPreviewCollapsesWhitespaceAndCapsLength() {
        let raw = """
        Friday at 9 works for us, and we will have the dumpster dropped the
        night before so the crew can start first thing in the morning without
        waiting around for anything at all to be delivered to the site.
        """

        let preview = EmailBodyCleaner.preview(raw, limit: 80)

        XCTAssertFalse(preview.contains("\n"))
        XCTAssertLessThanOrEqual(preview.count, 80)
        XCTAssertTrue(preview.hasPrefix("Friday at 9 works for us"))
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testPreviewLeavesShortBodyWhole() {
        XCTAssertEqual(EmailBodyCleaner.preview("On my way.", limit: 80), "On my way.")
    }

    func testPreviewStripsQuotesBeforeTruncating() {
        let raw = """
        Yes.

        On Mon, Jan 15, 2026 at 3:45 PM John Smith <john@example.com> wrote:
        > a very long quoted message that would otherwise dominate the preview
        """

        XCTAssertEqual(EmailBodyCleaner.preview(raw, limit: 80), "Yes.")
    }
}
