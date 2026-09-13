import XCTest
import AppKit
@testable import AltoCore

final class PageTextTests: XCTestCase {
    /// Flattened from a whole-page selection of a Sentiers issue: site chrome,
    /// article header, body, share prompt, newsletter form and legal footer.
    static let page = """
    Sentiers
    About
    Articles
    Back issues
    Membership
    Sign in
    Subscribe
    Sep 13, 2026
    7 min read
    Lifted AF ⊗ Cyborgs, centaurs and cyberpunks
    No.416 — The importance of reading (and teaching) cyberpunk ⊗ Anticipatory literacy coaching ⊗ AI’s next ethical dilemma
    Ernst Chladni, 1787, from Entdeckungen über die Theorie des Klange. Image sourced from the Public Domain Image Archive / Max Planck Institute.
    Lifted AF
    In e-flux Journal, McKenzie Wark reviews Exocapitalism: Economies with Absolutely No Limits by Marek Poliks and Roberto Alonso Trillo. The authors start from the premise that the critical tradition gets capitalism wrong and needs a new vocabulary to describe it.
    The book’s central idea is “Lift.” Physical production comes with workers, fixed costs, and problems of scale, and companies would rather avoid all of it. A hotel company stops running hotels and becomes a brand, a financing arm, and a data business.
    † Also see Stripe which gets a cut of a huge swath of global online payments and, just last month, bought OpenRouter.
    After we stop grieving AI: cyborgs, centaurs and cyberpunks
    Mike Walsh argues that, in something akin to “a compressed cycle of grief,” most of the AI debate is stuck at bargaining. Writers, artists, universities, and companies try to fence off parts of work as human while pulling AI deeper into that same work.
    The real prize is agency: the ability to understand the machinery acting on you, refuse its defaults and negotiate from a stronger position.
    If you’d like to support the newsletter, please share it with a friend or colleague who you think might enjoy it. I appreciate the help!
    Share by email
    Futures, Fictions & Fabulations
    Anticipatory literacy coaching. “One senior executive, after mapping the pushes of the present and the weight of inherited assumptions, paused and said: ‘I’ve been running from the tide instead of learning its rhythm.’ That sentence stayed with me.”
    Asides
    Are crows really our friends?. “Like Bergstrom and my sister, many people form sustained personal connections with their local crows. Those who do often consider the attention of these charismatic corvids a privilege and a source of joy.”
    Your Futures Thinking Observatory
    jamie@example.com Subscribe
    Back issues
    Membership
    Sign up
    All original content Creative Commons licence (CC BY-SA 4.0). Sentiers acknowledges the Kanien'keha:ka, also known as the Mohawk Nation, for their hospitality on the traditional and unceded territory where our office is situated.
    """

    func testWholePageKeepsArticleAndHeadingsInOrder() {
        let cleaned = PageText.clean(Self.page)
        let blocks = cleaned.components(separatedBy: "\n\n")
        XCTAssertEqual(blocks.first, "Lifted AF ⊗ Cyborgs, centaurs and cyberpunks")
        XCTAssertEqual(blocks.last?.prefix(24), "Are crows really our fri")
        for kept in ["No.416 — The importance", "Lifted AF\n\nIn e-flux Journal", "† Also see Stripe", "After we stop grieving AI",
                     "The real prize is agency", "please share it with a friend", "Futures, Fictions & Fabulations", "Asides\n\nAre crows"] {
            XCTAssertTrue(cleaned.contains(kept), "missing: \(kept)")
        }
        for dropped in ["Sentiers\n", "About", "Back issues", "Membership", "Sign in", "Sep 13, 2026", "7 min read", "Image sourced",
                        "Share by email", "Your Futures Thinking Observatory", "jamie@example.com", "Sign up", "Creative Commons"] {
            XCTAssertFalse(cleaned.contains(dropped), "still present: \(dropped)")
        }
        XCTAssertEqual(blocks.count, 14)
    }
    func testProseSelectionPassesThroughUnchanged() {
        let prose = """
        Physical production comes with workers, fixed costs, and problems of scale, and companies would rather avoid all of it.

        Profit comes from sitting between parties and taking a cut of each exchange, and software lets companies do this at any scale.
        """
        XCTAssertEqual(PageText.clean(prose), prose)
        XCTAssertEqual(PageText.clean("Hello <b>world</b>! 😀"), "Hello world!")
    }
    func testShortSelectionsAndMenusFallBackToTheOriginalText() {
        let menu = "About\nArticles\nBack issues\nMembership\nSign in\nSubscribe"
        XCTAssertEqual(PageText.clean(menu), menu)
        XCTAssertEqual(PageText.clean("Read this. Then that."), "Read this. Then that.")
        XCTAssertEqual(PageText.clean(""), "")
    }
    func testListsAndFootnotesInsideArticlesSurvive() {
        let article = """
        Why this matters
        The authors start from the premise that the critical tradition gets capitalism wrong and needs a new vocabulary to describe it.
        - Concepts wear out over time
        - Language must make the economy look strange again
        - Wealth still depends on the people who produce it
        Wark keeps Marx’s view that change comes out of conflict between classes, and the book blurs several coexisting systems when it calls a garment factory feudal.
        """
        let cleaned = PageText.clean(article)
        XCTAssertTrue(cleaned.hasPrefix("Why this matters\n\n"))
        XCTAssertTrue(cleaned.contains("- Concepts wear out over time\n\n- Language must"))
        XCTAssertTrue(cleaned.hasSuffix("garment factory feudal."))
    }
    func testRichTextDropsLinkListsAndImages() throws {
        let prose = "Physical production comes with workers, fixed costs, and problems of scale, and companies would rather avoid all of it. Profit comes from sitting between parties and taking a cut of each exchange, and software lets companies do this at any scale.\n"
        let rich = NSMutableAttributedString(string: "Latest stories\n")
        for title in ["How lift works in practice today", "Exocapitalism reviewed by McKenzie Wark", "Reading cyberpunk with teenagers"] {
            rich.append(NSAttributedString(string: title + "\n", attributes: [.link: URL(string: "https://example.com")!]))
        }
        rich.append(NSAttributedString(attachment: NSTextAttachment()))
        rich.append(NSAttributedString(string: "\n" + prose))
        rich.append(NSAttributedString(string: "Also in this issue, the economy of tokens upon tokens and where the social infrastructure went.\n"))
        let blocks = PageText.blocks(from: rich)
        XCTAssertEqual(blocks.filter { $0.linkDensity >= 0.6 }.count, 3)
        XCTAssertFalse(blocks.contains { $0.text.contains("\u{FFFC}") })
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let data = try XCTUnwrap(rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]))
        pasteboard.setData(data, forType: .rtf)
        pasteboard.setString(rich.string, forType: .string)
        let cleaned = PageText.clean(from: pasteboard)
        XCTAssertTrue(cleaned.hasPrefix("Physical production"))
        XCTAssertTrue(cleaned.hasSuffix("infrastructure went."))
        XCTAssertFalse(cleaned.contains("McKenzie"))
        XCTAssertFalse(cleaned.contains("Latest stories"))
    }
}
