import SwiftUI
import XCTest

@testable import Kohai

final class TokenTests: XCTestCase {

    private let palettes: [(name: String, palette: KohaiPalette)] = [
        ("dark", .dark),
        ("dark-increase-contrast", .darkIncreasedContrast),
    ]

    /// White default-button text on the neutral button fill.
    func testButtonFillKeepsButtonTextReadable() {
        let white = KohaiColor(0xFFFFFF)
        for (name, p) in palettes {
            let ratio = white.contrast(against: p.surface.buttonFill)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) button text = \(ratio)")
        }
    }

    /// Account / space colors are the stripe tones, so they inherit the forbidden-hue rule.
    func testEveryLabelToneIsAStripeTone() {
        for tone in LabelTone.allCases {
            XCTAssertTrue(KohaiPalette.dark.projectStripes.contains(KohaiPalette.dark.label(tone)), "\(tone)")
        }
        XCTAssertEqual(Set(LabelTone.allCases.map { KohaiPalette.dark.label($0).hex }).count, LabelTone.allCases.count)
    }

    // MARK: Contrast

    /// Every text token >= 4.5:1 on the nominal AND the worst-case lifted material stand-in.
    func testTextTokensMeetAA() {
        for (name, p) in palettes {
            let backdrops = [("nominal", p.preview.materialNominal), ("lifted", p.preview.materialLifted)]
            let texts = [
                ("primary", p.text.primary), ("secondary", p.text.secondary), ("tertiary", p.text.tertiary),
            ]
            for (backdropName, backdrop) in backdrops {
                for (textName, text) in texts {
                    let ratio = text.contrast(against: backdrop)
                    XCTAssertGreaterThanOrEqual(
                        ratio, 4.5, "\(name) \(textName) on \(backdropName) = \(ratio)")
                }
            }
        }
    }

    /// Kanji / count drawn on a seal fill is text: >= 4.5:1.
    func testSealGlyphContrast() {
        for (name, p) in palettes {
            XCTAssertGreaterThanOrEqual(p.text.onSeal.contrast(against: p.seal.needsInput), 4.5, name)
            XCTAssertGreaterThanOrEqual(p.text.onSeal.contrast(against: p.seal.done), 4.5, name)
        }
    }

    /// Seal fills are non-text graphics: >= 3:1 against the material.
    func testSealFillContrastAgainstMaterial() {
        for (name, p) in palettes {
            for backdrop in [p.preview.materialNominal, p.preview.materialLifted] {
                XCTAssertGreaterThanOrEqual(p.seal.needsInput.contrast(against: backdrop), 3.0, name)
                XCTAssertGreaterThanOrEqual(p.seal.done.contrast(against: backdrop), 3.0, name)
            }
        }
    }

    // MARK: Palette rules

    private func allColors(_ p: KohaiPalette) -> [KohaiColor] {
        [p.text.primary, p.text.secondary, p.text.tertiary, p.text.onSeal,
         p.seal.needsInput, p.seal.done, p.mascot.line, p.icon.templateInk,
         p.preview.materialNominal, p.preview.materialLifted, p.preview.stage,
         p.preview.barDark, p.preview.barLight, p.preview.barMid,
         p.preview.iconOnDarkBar, p.preview.iconOnLightBar]
            + p.projectStripes
    }

    /// Forbidden hue band: no chromatic color with hue 240...320.
    func testNoColorInForbiddenHueBand() {
        for (name, p) in palettes {
            for color in allColors(p) {
                let hsv = color.hsv
                if hsv.saturation > 0.10 && hsv.value > 0.15 {
                    XCTAssertFalse(
                        (240.0...320.0).contains(hsv.hue),
                        "\(name): #\(String(color.hex, radix: 16)) hue \(hsv.hue) is in the forbidden hue band")
                }
            }
        }
    }

    func testEightProjectStripes() {
        XCTAssertEqual(KohaiPalette.dark.projectStripes.count, 8)
        XCTAssertEqual(Set(KohaiPalette.dark.projectStripes.map { $0.hex }).count, 8)
    }

    /// Vermilion is the only saturated red-orange: no other color may sit in its hue band.
    func testNothingElseIsVermilion() {
        for (name, p) in palettes {
            let vermilionHue = p.seal.needsInput.hsv.hue
            let others = allColors(p).filter { $0 != p.seal.needsInput }
            for color in others {
                let hsv = color.hsv
                var distance = abs(hsv.hue - vermilionHue)
                distance = min(distance, 360 - distance)
                if distance < 20 {
                    XCTAssertLessThanOrEqual(
                        hsv.saturation, 0.30,
                        "\(name): #\(String(color.hex, radix: 16)) is too close to vermilion")
                }
            }
        }
    }

    func testStripeIsDeterministic() {
        let p = KohaiPalette.dark
        XCTAssertEqual(p.stripe(forProject: "yheat"), p.stripe(forProject: "yheat"))
    }

    // MARK: Copy

    func testCopyKeysUniqueAndBothTonesPresent() {
        let keys = Copy.all.map { $0.key }
        XCTAssertEqual(Set(keys).count, keys.count)
        for entry in Copy.all {
            XCTAssertFalse(entry.polite.isEmpty, entry.key)
            XCTAssertFalse(entry.serious.isEmpty, entry.key)
        }
    }

    func testCopyPlaceholdersMatchBetweenTones() {
        let pattern = try! NSRegularExpression(pattern: "\\{[a-zA-Z]+\\}")
        func placeholders(_ s: String) -> Set<String> {
            let range = NSRange(s.startIndex..., in: s)
            return Set(pattern.matches(in: s, range: range).compactMap {
                Range($0.range, in: s).map { String(s[$0]) }
            })
        }
        for entry in Copy.all {
            XCTAssertEqual(placeholders(entry.polite), placeholders(entry.serious), entry.key)
        }
    }

    /// The hint rows are one line: keep them short.
    func testHintsAreShort() {
        for entry in [Copy.firstRunHint, Copy.overflowHint] {
            XCTAssertLessThanOrEqual(entry.polite.count, 48, entry.key)
            XCTAssertLessThanOrEqual(entry.serious.count, 48, entry.key)
        }
    }

    // MARK: Ordering and formatting

    func testNeedsInputIsPinnedToTop() {
        let groups = SessionGrouping.groups(PreviewData.mixed)
        // Groups with needs_input come first.
        let flags = groups.map { $0.needsInputCount > 0 }
        XCTAssertEqual(flags, flags.sorted { $0 && !$1 })
        // Inside every group needs_input rows come first.
        for group in groups {
            let ranks = group.sessions.map { $0.status.sortRank }
            XCTAssertEqual(ranks, ranks.sorted())
        }
        XCTAssertEqual(groups.first?.sessions.first?.status, .needsInput)
    }

    func testTimeFormatting() {
        XCTAssertEqual(TimeInStatus.short(0), "0:00")
        XCTAssertEqual(TimeInStatus.short(192), "3:12")
        XCTAssertEqual(TimeInStatus.short(3_725), "1h 02m")
        XCTAssertEqual(TimeInStatus.short(93_600), "1d 2h")
        XCTAssertEqual(TimeInStatus.short(-5), "0:00")
    }
}
