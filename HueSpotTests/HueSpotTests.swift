// Copyright © 2026 Mark Zaros. All Rights Reserved. License: GNU Public License 2.0 only.
import Testing
import AppKit
@testable import HueSpot

struct HueSpotTests {
    @Test
    func exactCSSNamesDoNotUseClosestSuffix() throws {
        let aliceBlue = try names(forHex: "F0F8FF")
        #expect(aliceBlue.detailed == "Alice Blue")

        let antiqueWhite = try names(forHex: "FAEBD7")
        #expect(antiqueWhite.detailed == "Antique White")
    }

    @Test
    func pureWhiteMapsToWhiteInISCCLine() throws {
        let names = try names(forHex: "FFFFFF")
        #expect(names.isccExtended == "White")
    }

    @Test
    func midnightBlueDoesNotClassifyAsGreen() throws {
        let names = try names(forHex: "071832")
        #expect(baseColorToken(fromSimpleName: names.simplified) == "blue")
    }

    @Test(arguments: [
        "990F02", "900603", "541E1B", "900D09", "A91A0D", "A91B0D", "9B1003", "9B1104"
    ])
    func deepRedSwatchesStayInRedFamily(_ hex: String) throws {
        let names = try names(forHex: hex)
        #expect(baseColorToken(fromSimpleName: names.simplified) == "red")
    }

    @Test(arguments: ["008080", "00555A", "006D5B", "004747", "66B2B2", "009999"])
    func tealHexesUseTealParenthetical(_ hex: String) throws {
        let names = try names(forHex: hex)
        #expect(names.simplified.lowercased().contains("(teal)"))
    }
}

private extension HueSpotTests {
    func names(forHex hex: String) throws -> ColorNames {
        let color = try colorFromHex(hex)
        return ColorNamer.names(for: color, sampledHex: "#\(hex)")
    }

    func colorFromHex(_ hex: String) throws -> NSColor {
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            throw TestError.invalidHex(hex)
        }
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }

    func baseColorToken(fromSimpleName name: String) -> String {
        let withoutParenthetical = name
            .split(separator: "(")
            .first
            .map(String.init) ?? name
        let stripped = withoutParenthetical
            .replacingOccurrences(of: "Dark ", with: "")
            .replacingOccurrences(of: "Light ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let compoundBase = stripped.split(separator: "-").last {
            return String(compoundBase).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stripped
    }

    enum TestError: Error {
        case invalidHex(String)
    }
}
