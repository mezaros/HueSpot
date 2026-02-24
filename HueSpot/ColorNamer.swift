import Foundation
import AppKit

struct ColorNames {
    let simplified: String
    let detailed: String
    let isccExtended: String

    init(simplified: String, detailed: String, isccExtended: String = "") {
        self.simplified = simplified
        self.detailed = detailed
        self.isccExtended = isccExtended
    }
}

/// Maps sampled colors to three labels used in the HUD:
/// - simple/minimal name
/// - nearest CSS/Wikipedia display name
/// - nearest ISCC-NBS extended name
enum ColorNamer {
    // MARK: - Core Types

    private enum BaseColor: String {
        case black = "Black"
        case white = "White"
        case gray = "Gray"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case brown = "Brown"
    }

    private struct HueBoundary {
        let a: BaseColor
        let b: BaseColor
        let angle: CGFloat
    }

    private struct ColorAliasRule {
        let name: String
        let allowedBases: Set<BaseColor>
        let hueCenter: CGFloat?
        let hueRadius: CGFloat?
        let saturationRange: ClosedRange<CGFloat>
        let brightnessRange: ClosedRange<CGFloat>
        let minimumScore: CGFloat
    }

    private static let redOrangeBoundary: CGFloat = 18.0
    private static let greenBlueBoundary: CGFloat = 170.0
    private static let bluePurpleBoundary: CGFloat = 250.0
    private static let pinkRedBoundary: CGFloat = 347.5

    private static let grayishEligibleBases: Set<BaseColor> = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .brown
    ]
    private static let chromaticBases: Set<BaseColor> = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .brown
    ]
    private static let aliasTieGap: CGFloat = 0.05

    // MARK: - Public API

    static func names(for color: NSColor, sampledHex: String? = nil) -> ColorNames {
        let srgb = color.usingColorSpace(.sRGB) ?? color

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        let sampleHex = normalizedHex(sampledHex) ?? normalizedHex(hexString(from: srgb)) ?? "000000"
        let detailed = webDisplayName(forHex: sampleHex)
        let isccMatch = nearestISCCExtendedMatch(
            to: srgb,
            sampledHex: sampleHex,
            saturation: saturation,
            brightness: brightness
        )
        let isccExtended = isccMatch.isExact ? isccMatch.name : "\(isccMatch.name) (closest)"
        let isccMainBase = isccMainBaseColor(from: isccMatch.name)
        let cssBaseHint = cssBaseHint(forHex: sampleHex)
        let minimal = minimalName(
            hueDegrees: hue * 360.0,
            saturation: saturation,
            brightness: brightness,
            isccHint: isccCompoundHint(from: isccMatch.name),
            cssBaseHint: cssBaseHint
        )
        let simplified = appendAliasIfNeeded(
            minimalName: minimal,
            minimalBase: minimalBaseColor(from: minimal),
            isccMainBase: isccMainBase,
            hueDegrees: hue * 360.0,
            saturation: saturation,
            brightness: brightness
        )
        return ColorNames(simplified: simplified, detailed: detailed, isccExtended: isccExtended)
    }

    // MARK: - Minimal Name Classification

    private static func minimalName(
        hueDegrees: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat,
        isccHint: (modifier: BaseColor, base: BaseColor)?,
        cssBaseHint: BaseColor?
    ) -> String {
        if brightness <= 0.10 {
            return BaseColor.black.rawValue
        }

        if brightness >= 0.94 && saturation <= 0.12 {
            return BaseColor.white.rawValue
        }

        if saturation <= 0.10 {
            return BaseColor.gray.rawValue
        }

        var base = chromaticBase(hueDegrees: hueDegrees, saturation: saturation, brightness: brightness)

        if let cssBaseHint,
           shouldAdoptCSSBase(
               computedBase: base,
               cssBase: cssBaseHint,
               hueDegrees: hueDegrees,
               saturation: saturation,
               brightness: brightness
           ) {
            base = cssBaseHint
        }

        // Low-saturation colors use grayish-* forms when there is still a visible hue bias.
        if saturation <= 0.24 {
            if grayishEligibleBases.contains(base) {
                if brightness >= 0.85 {
                    return BaseColor.white.rawValue
                }
                return "Grayish-\(base.rawValue.lowercased())"
            }
            return BaseColor.gray.rawValue
        }

        // Brown is treated as a basic category interior, never a hue-boundary compound.
        if base == .brown {
            return applyLightDarkPrefix(
                to: base.rawValue,
                base: base,
                saturation: saturation,
                brightness: brightness
            )
        }

        guard let boundary = nearestBoundary(
            for: base,
            hueDegrees: hueDegrees,
            saturation: saturation,
            brightness: brightness
        ) else {
            return applyLightDarkPrefix(
                to: base.rawValue,
                base: base,
                saturation: saturation,
                brightness: brightness
            )
        }

        // Boundary ambiguity / forced-choice instability gate.
        let boundaryDistance = circularDistance(hueDegrees, boundary.angle)
        let ambiguityThreshold = compoundAmbiguityThreshold(
            for: boundary,
            saturation: saturation,
            brightness: brightness,
            isccHint: isccHint
        )
        guard boundaryDistance <= ambiguityThreshold else {
            return base.rawValue
        }

        var modifier: BaseColor = (boundary.a == base) ? boundary.b : boundary.a
        var resolvedBase = base

        if let hint = isccHint,
           boundaryIncludes(boundary, color: hint.modifier),
           boundaryIncludes(boundary, color: hint.base),
           hueCompound(modifier: hint.modifier, base: hint.base) != nil {
            modifier = hint.modifier
            resolvedBase = hint.base
        }

        let name = hueCompound(modifier: modifier, base: resolvedBase) ?? resolvedBase.rawValue
        return applyLightDarkPrefix(
            to: name,
            base: resolvedBase,
            saturation: saturation,
            brightness: brightness
        )
    }

    private static func appendAliasIfNeeded(
        minimalName: String,
        minimalBase: BaseColor?,
        isccMainBase: BaseColor?,
        hueDegrees: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> String {
        guard !minimalName.isEmpty else { return minimalName }
        guard !minimalName.contains("(") else { return minimalName }
        guard let alias = nearestAlias(
            minimalBase: minimalBase,
            isccMainBase: isccMainBase,
            hueDegrees: hueDegrees,
            saturation: saturation,
            brightness: brightness
        ) else {
            return minimalName
        }
        if alias == "teal",
           let minimalBase,
           (minimalBase == .blue || minimalBase == .green),
           !minimalName.contains("-") {
            let forcedCompound = minimalBase == .blue ? "Greenish-blue" : "Bluish-green"
            return "\(forcedCompound) (\(alias))"
        }
        return "\(minimalName) (\(alias))"
    }

    // MARK: - Alias Selection

    private static func nearestAlias(
        minimalBase: BaseColor?,
        isccMainBase: BaseColor?,
        hueDegrees: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> String? {
        let effectiveBase: BaseColor?
        if let minimalBase {
            effectiveBase = minimalBase
        } else if let isccMainBase, chromaticBases.contains(isccMainBase) {
            effectiveBase = isccMainBase
        } else {
            effectiveBase = nil
        }
        let hue = normalizeHue(hueDegrees)

        var candidates: [(rule: ColorAliasRule, score: CGFloat)] = []
        candidates.reserveCapacity(colorAliasRules.count)

        for rule in colorAliasRules {
            if let effectiveBase, !rule.allowedBases.contains(effectiveBase) {
                continue
            }
            if let isccMainBase, chromaticBases.contains(isccMainBase), !rule.allowedBases.contains(isccMainBase) {
                continue
            }
            guard rule.saturationRange.contains(saturation) else { continue }
            guard rule.brightnessRange.contains(brightness) else { continue }
            guard aliasBoundaryGate(
                rule: rule,
                effectiveBase: effectiveBase,
                hueDegrees: hue,
                saturation: saturation,
                brightness: brightness
            ) else { continue }

            let saturationScore = centeredRangeScore(saturation, within: rule.saturationRange)
            let brightnessScore = centeredRangeScore(brightness, within: rule.brightnessRange)

            let score: CGFloat
            if let center = rule.hueCenter, let radius = rule.hueRadius {
                let distance = circularDistance(hue, center)
                guard distance <= radius else { continue }
                let hueScore = 1.0 - (distance / radius)
                score = 0.58 * hueScore + 0.22 * saturationScore + 0.20 * brightnessScore
            } else {
                score = 0.55 * saturationScore + 0.45 * brightnessScore
            }

            guard score >= requiredAliasScore(for: rule) else { continue }
            candidates.append((rule, score))
        }

        guard !candidates.isEmpty else { return nil }
        candidates.sort { $0.score > $1.score }
        if candidates.count > 1 && (candidates[0].score - candidates[1].score) < aliasTieGap {
            return nil
        }
        return candidates[0].rule.name
    }

    private static func requiredAliasScore(for rule: ColorAliasRule) -> CGFloat {
        var required = rule.minimumScore + 0.02
        switch rule.name {
        case "silver", "slate", "steel blue", "graphite", "gunmetal", "charcoal":
            required += 0.06
        case "turquoise", "cyan", "aqua", "lime", "chartreuse", "olive":
            required += 0.02
        default:
            break
        }
        return min(required, 0.97)
    }

    private static func aliasBoundaryGate(
        rule: ColorAliasRule,
        effectiveBase: BaseColor?,
        hueDegrees: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> Bool {
        guard rule.hueCenter != nil,
              rule.allowedBases.count > 1,
              let effectiveBase,
              chromaticBases.contains(effectiveBase) else {
            return true
        }

        guard let distance = boundaryDistanceForAlias(
            base: effectiveBase,
            allowedBases: rule.allowedBases,
            hueDegrees: hueDegrees,
            saturation: saturation,
            brightness: brightness
        ) else {
            // No relevant boundary between this base and the alias bases:
            // treat as non-clarifying and skip.
            return false
        }

        return distance <= aliasBoundaryThreshold(
            for: rule.name,
            saturation: saturation,
            brightness: brightness
        )
    }

    private static func boundaryDistanceForAlias(
        base: BaseColor,
        allowedBases: Set<BaseColor>,
        hueDegrees: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> CGFloat? {
        let boundaries = hueBoundaries(saturation: saturation, brightness: brightness)
        var best: CGFloat?
        for boundary in boundaries {
            guard boundary.a == base || boundary.b == base else { continue }
            let other = boundary.a == base ? boundary.b : boundary.a
            guard allowedBases.contains(other) else { continue }
            let distance = circularDistance(hueDegrees, boundary.angle)
            if best == nil || distance < best! {
                best = distance
            }
        }
        return best
    }

    private static func aliasBoundaryThreshold(
        for alias: String,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> CGFloat {
        var threshold: CGFloat = 17.0
        switch alias {
        case "teal":
            threshold = 22.0
        case "turquoise", "cyan", "aqua":
            threshold = 15.0
        case "lime", "chartreuse", "olive":
            threshold = 19.0
        case "magenta", "fuchsia", "indigo":
            threshold = 17.0
        default:
            break
        }
        if saturation <= 0.35 {
            threshold += 1.5
        }
        if saturation >= 0.85 {
            threshold -= 1.0
        }
        if brightness <= 0.22 {
            threshold += 1.0
        }
        return threshold
    }

    private static func centeredRangeScore(_ value: CGFloat, within range: ClosedRange<CGFloat>) -> CGFloat {
        let center = (range.lowerBound + range.upperBound) / 2.0
        let radius = max(0.0001, (range.upperBound - range.lowerBound) / 2.0)
        let normalizedDistance = abs(value - center) / radius
        return max(0.0, 1.0 - (0.70 * normalizedDistance))
    }

    private static func minimalBaseColor(from minimalName: String) -> BaseColor? {
        let normalized = minimalName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let head = normalized.split(separator: "(").first.map(String.init) ?? normalized
        let token = head
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-")
            .last
            .map(String.init) ?? head
        let candidate = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .last
            .map(String.init) ?? token
        return baseColorFromWord(candidate.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Hue Mapping

    private static func chromaticBase(hueDegrees: CGFloat, saturation: CGFloat, brightness: CGFloat) -> BaseColor {
        let hue = normalizeHue(hueDegrees)
        let orangeYellow = orangeYellowBoundary(saturation: saturation, brightness: brightness)
        let yellowGreen = yellowGreenBoundary()
        let purplePink = purplePinkBoundary(saturation: saturation, brightness: brightness)

        // Warm light reds/salmons are perceived as pink more often than red.
        if hue < 12.0 && brightness >= 0.85 && saturation <= 0.75 {
            return .pink
        }

        // Desaturated near-reds (around 360 deg) skew pink.
        if hue >= 355.0 && brightness >= 0.55 && saturation <= 0.70 {
            return .pink
        }

        // Brown occupies the dark orange/yellow region.
        let brownCandidate = saturation >= 0.25
            && brightness >= 0.10
            && brightness <= 0.62
            && hue >= 14.0
            && hue < 50.0
        let vividOrangeCandidate = saturation >= 0.90 && brightness >= 0.45
        if brownCandidate && !vividOrangeCandidate {
            return .brown
        }

        switch hue {
        case pinkRedBoundary..<360.0, 0.0..<redOrangeBoundary:
            return .red
        case redOrangeBoundary..<orangeYellow:
            return .orange
        case orangeYellow..<yellowGreen:
            return .yellow
        case yellowGreen..<greenBlueBoundary:
            return .green
        case greenBlueBoundary..<bluePurpleBoundary:
            return .blue
        case bluePurpleBoundary..<purplePink:
            return .purple
        default:
            return .pink
        }
    }

    private static func nearestBoundary(
        for base: BaseColor,
        hueDegrees: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> HueBoundary? {
        let candidates = hueBoundaries(
            saturation: saturation,
            brightness: brightness
        ).filter { $0.a == base || $0.b == base }
        guard !candidates.isEmpty else { return nil }
        let hue = normalizeHue(hueDegrees)
        return candidates.min {
            circularDistance(hue, $0.angle) < circularDistance(hue, $1.angle)
        }
    }

    private static func sharedBoundary(
        between first: BaseColor,
        and second: BaseColor,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> HueBoundary? {
        hueBoundaries(saturation: saturation, brightness: brightness).first {
            ($0.a == first && $0.b == second) || ($0.a == second && $0.b == first)
        }
    }

    private static func shouldAdoptCSSBase(
        computedBase: BaseColor,
        cssBase: BaseColor,
        hueDegrees: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> Bool {
        if computedBase == cssBase {
            return true
        }

        // If highly saturated, only accept CSS base when it's genuinely adjacent.
        if saturation >= 0.80 {
            guard let boundary = sharedBoundary(
                between: computedBase,
                and: cssBase,
                saturation: saturation,
                brightness: brightness
            ) else {
                return false
            }
            let distance = circularDistance(hueDegrees, boundary.angle)
            return distance <= 10.0
        }

        guard let boundary = sharedBoundary(
            between: computedBase,
            and: cssBase,
            saturation: saturation,
            brightness: brightness
        ) else {
            return false
        }

        let distance = circularDistance(hueDegrees, boundary.angle)
        let threshold = 12.0 + (saturation <= 0.35 ? 2.0 : 0.0) + (brightness <= 0.20 ? 1.0 : 0.0)
        return distance <= threshold
    }

    private static func hueBoundaries(saturation: CGFloat, brightness: CGFloat) -> [HueBoundary] {
        let orangeYellow = orangeYellowBoundary(saturation: saturation, brightness: brightness)
        let yellowGreen = yellowGreenBoundary()
        let purplePink = purplePinkBoundary(saturation: saturation, brightness: brightness)
        return [
            HueBoundary(a: .red, b: .orange, angle: redOrangeBoundary),
            HueBoundary(a: .orange, b: .yellow, angle: orangeYellow),
            HueBoundary(a: .yellow, b: .green, angle: yellowGreen),
            HueBoundary(a: .green, b: .blue, angle: greenBlueBoundary),
            HueBoundary(a: .blue, b: .purple, angle: bluePurpleBoundary),
            HueBoundary(a: .purple, b: .pink, angle: purplePink),
            HueBoundary(a: .pink, b: .red, angle: pinkRedBoundary)
        ]
    }

    private static func orangeYellowBoundary(saturation: CGFloat, brightness: CGFloat) -> CGFloat {
        if saturation >= 0.75 {
            return 43.0
        }
        if brightness >= 0.80 && saturation <= 0.65 {
            return 35.0
        }
        return 40.0
    }

    private static func yellowGreenBoundary() -> CGFloat {
        return 78.0
    }

    private static func purplePinkBoundary(saturation: CGFloat, brightness: CGFloat) -> CGFloat {
        if brightness < 0.45 {
            return 342.0
        }
        if brightness < 0.68 && saturation > 0.55 {
            return 332.0
        }
        if saturation < 0.35 {
            return 305.0
        }
        return 318.0
    }

    private static func compoundAmbiguityThreshold(
        for boundary: HueBoundary,
        saturation: CGFloat,
        brightness: CGFloat,
        isccHint: (modifier: BaseColor, base: BaseColor)?
    ) -> CGFloat {
        var threshold: CGFloat = 5.6

        // Widen ambiguity zones where real-world labels are commonly disputed.
        if isBoundary(boundary, between: .green, and: .blue)
            || isBoundary(boundary, between: .yellow, and: .green) {
            threshold = 8.0
        } else if isBoundary(boundary, between: .blue, and: .purple)
            || isBoundary(boundary, between: .red, and: .orange) {
            threshold = 7.4
        } else if isBoundary(boundary, between: .orange, and: .yellow)
            || isBoundary(boundary, between: .purple, and: .pink) {
            threshold = 6.5
        }

        // If ISCC already treats this hue region as a compound, trust it and widen slightly.
        if let hint = isccHint {
            let hintOnBoundary =
                boundaryIncludes(boundary, color: hint.modifier)
                && boundaryIncludes(boundary, color: hint.base)
            threshold += hintOnBoundary ? 0.9 : -0.5
        }

        if saturation <= 0.45 {
            threshold += 0.6
        }
        if saturation <= 0.32 {
            threshold += 0.4
        }
        if saturation >= 0.88 && brightness >= 0.20 && brightness <= 0.92 {
            threshold -= 1.1
        }
        if saturation >= 0.95 {
            threshold -= 0.6
        }

        return min(9.0, max(4.8, threshold))
    }

    private static func boundaryIncludes(_ boundary: HueBoundary, color: BaseColor) -> Bool {
        boundary.a == color || boundary.b == color
    }

    private static func isBoundary(_ boundary: HueBoundary, between first: BaseColor, and second: BaseColor) -> Bool {
        (boundary.a == first && boundary.b == second) || (boundary.a == second && boundary.b == first)
    }

    private static func isccCompoundHint(from isccName: String) -> (modifier: BaseColor, base: BaseColor)? {
        let normalized = isccName.lowercased()
        if normalized.contains("reddish orange") { return (.red, .orange) }
        if normalized.contains("yellowish orange") { return (.yellow, .orange) }
        if normalized.contains("orange yellow") { return (.orange, .yellow) }
        if normalized.contains("greenish yellow") { return (.green, .yellow) }
        if normalized.contains("yellowish green") || normalized.contains("yellow green") { return (.yellow, .green) }
        if normalized.contains("bluish green") { return (.blue, .green) }
        if normalized.contains("greenish blue") { return (.green, .blue) }
        if normalized.contains("purplish blue") { return (.purple, .blue) }
        if normalized.contains("bluish purple") { return (.blue, .purple) }
        if normalized.contains("pinkish purple") { return (.pink, .purple) }
        if normalized.contains("purplish pink") { return (.purple, .pink) }
        if normalized.contains("reddish pink") { return (.red, .pink) }
        return nil
    }

    private static func isccMainBaseColor(from isccName: String) -> BaseColor? {
        let normalized = isccName
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
        let tokens = normalized.split { !$0.isLetter }

        var found: BaseColor?
        for token in tokens {
            let word = String(token)
            if let adjectiveMatch = isccAdjectiveWordToBaseColor(word) {
                found = adjectiveMatch
                continue
            }
            if let nounMatch = isccNounWordToBaseColor(word) {
                found = nounMatch
            }
        }
        return found
    }

    private static func isccAdjectiveWordToBaseColor(_ word: String) -> BaseColor? {
        switch word {
        case "reddish":
            return .red
        case "orangeish", "orangish":
            return .orange
        case "yellowish":
            return .yellow
        case "greenish":
            return .green
        case "bluish":
            return .blue
        case "purplish", "violetish":
            return .purple
        case "pinkish":
            return .pink
        case "brownish":
            return .brown
        case "grayish", "greyish":
            return .gray
        case "blackish":
            return .black
        case "whitish":
            return .white
        default:
            return nil
        }
    }

    private static func isccNounWordToBaseColor(_ word: String) -> BaseColor? {
        if word == "violet" {
            return .purple
        }
        return baseColorFromWord(word)
    }

    private static func baseColorFromWord(_ word: String) -> BaseColor? {
        switch word {
        case "red":
            return .red
        case "orange":
            return .orange
        case "yellow":
            return .yellow
        case "green":
            return .green
        case "blue":
            return .blue
        case "purple":
            return .purple
        case "pink":
            return .pink
        case "brown":
            return .brown
        case "gray", "grey":
            return .gray
        case "black":
            return .black
        case "white":
            return .white
        default:
            return nil
        }
    }

    private static func hueCompound(modifier: BaseColor, base: BaseColor) -> String? {
        switch (modifier, base) {
        case (.red, .orange):
            return "Reddish-orange"
        case (.yellow, .orange):
            return "Yellowish-orange"
        case (.orange, .yellow):
            return "Orangish-yellow"
        case (.yellow, .green):
            return "Yellowish-green"
        case (.blue, .green):
            return "Bluish-green"
        case (.green, .blue):
            return "Greenish-blue"
        case (.purple, .blue):
            return "Purplish-blue"
        case (.blue, .purple):
            return "Bluish-purple"
        case (.pink, .purple):
            return "Pinkish-purple"
        case (.purple, .pink):
            return "Purplish-pink"
        case (.red, .pink):
            return "Reddish-pink"
        default:
            return nil
        }
    }

    private static func applyLightDarkPrefix(
        to name: String,
        base: BaseColor,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> String {
        guard name == base.rawValue else { return name }
        guard base != .black, base != .white, base != .gray else { return name }
        guard saturation >= 0.28 else { return name }

        if brightness >= 0.88 {
            return "Light \(name)"
        }
        if brightness <= 0.18 {
            return "Dark \(name)"
        }
        return name
    }

    // MARK: - Alias Rule Table

    private static func hueAlias(
        _ name: String,
        bases: [BaseColor],
        hue: CGFloat,
        radius: CGFloat,
        saturation: ClosedRange<CGFloat>,
        brightness: ClosedRange<CGFloat>,
        minimumScore: CGFloat = 0.84
    ) -> ColorAliasRule {
        ColorAliasRule(
            name: name,
            allowedBases: Set(bases),
            hueCenter: normalizeHue(hue),
            hueRadius: radius,
            saturationRange: saturation,
            brightnessRange: brightness,
            minimumScore: minimumScore
        )
    }

    private static func neutralAlias(
        _ name: String,
        bases: [BaseColor],
        saturation: ClosedRange<CGFloat>,
        brightness: ClosedRange<CGFloat>,
        minimumScore: CGFloat = 0.80
    ) -> ColorAliasRule {
        ColorAliasRule(
            name: name,
            allowedBases: Set(bases),
            hueCenter: nil,
            hueRadius: nil,
            saturationRange: saturation,
            brightnessRange: brightness,
            minimumScore: minimumScore
        )
    }

    private static let colorAliasRules: [ColorAliasRule] = [
        // Consolidated blue/green boundary aliases for clearer, less noisy labels.
        hueAlias("teal", bases: [.blue, .green], hue: 172, radius: 18, saturation: 0.24...1.0, brightness: 0.16...0.84, minimumScore: 0.58),
        hueAlias("teal", bases: [.blue, .green], hue: 160, radius: 15, saturation: 0.20...0.80, brightness: 0.32...0.88, minimumScore: 0.58),
        hueAlias("teal", bases: [.blue, .green], hue: 184, radius: 12, saturation: 0.50...1.0, brightness: 0.18...0.68, minimumScore: 0.55),
        hueAlias("teal", bases: [.blue, .green], hue: 180, radius: 22, saturation: 0.15...1.0, brightness: 0.12...0.95, minimumScore: 0.46),
        hueAlias("teal", bases: [.blue, .green], hue: 190, radius: 16, saturation: 0.35...1.0, brightness: 0.24...0.82, minimumScore: 0.44),
        hueAlias("turquoise", bases: [.blue, .green], hue: 176, radius: 12, saturation: 0.30...0.95, brightness: 0.68...1.0, minimumScore: 0.78),
        hueAlias("cyan", bases: [.blue, .green], hue: 182, radius: 10, saturation: 0.70...1.0, brightness: 0.82...1.0, minimumScore: 0.80),
        hueAlias("cyan", bases: [.blue, .green], hue: 186, radius: 8, saturation: 0.55...1.0, brightness: 0.68...0.88, minimumScore: 0.78),
        hueAlias("aqua", bases: [.blue, .green], hue: 178, radius: 10, saturation: 0.18...0.55, brightness: 0.88...1.0, minimumScore: 0.78),
        hueAlias("seafoam", bases: [.green, .blue], hue: 160, radius: 15, saturation: 0.12...0.50, brightness: 0.72...1.0, minimumScore: 0.84),
        hueAlias("mint", bases: [.green], hue: 150, radius: 16, saturation: 0.18...0.65, brightness: 0.72...1.0, minimumScore: 0.84),
        hueAlias("sage", bases: [.green], hue: 102, radius: 18, saturation: 0.12...0.45, brightness: 0.45...0.78, minimumScore: 0.83),
        hueAlias("emerald green", bases: [.green], hue: 145, radius: 14, saturation: 0.55...1.0, brightness: 0.35...0.85, minimumScore: 0.86),

        hueAlias("chartreuse", bases: [.yellow, .green], hue: 90, radius: 16, saturation: 0.40...1.0, brightness: 0.50...0.94, minimumScore: 0.66),
        hueAlias("lime", bases: [.yellow, .green], hue: 120, radius: 16, saturation: 0.45...1.0, brightness: 0.55...1.0, minimumScore: 0.67),
        hueAlias("lime", bases: [.yellow, .green], hue: 98, radius: 18, saturation: 0.35...1.0, brightness: 0.50...1.0, minimumScore: 0.46),
        hueAlias("lime", bases: [.yellow, .green], hue: 72, radius: 16, saturation: 0.30...1.0, brightness: 0.60...1.0, minimumScore: 0.40),
        hueAlias("lime", bases: [.yellow, .green], hue: 66, radius: 12, saturation: 0.55...1.0, brightness: 0.70...1.0, minimumScore: 0.48),
        hueAlias("lime", bases: [.yellow, .green], hue: 90, radius: 12, saturation: 0.85...1.0, brightness: 0.85...1.0, minimumScore: 0.60),
        hueAlias("olive", bases: [.green], hue: 78, radius: 18, saturation: 0.22...1.0, brightness: 0.10...0.58, minimumScore: 0.48),
        hueAlias("olive", bases: [.green], hue: 96, radius: 14, saturation: 0.30...0.90, brightness: 0.10...0.55, minimumScore: 0.52),

        hueAlias("sky blue", bases: [.blue], hue: 198, radius: 16, saturation: 0.25...0.75, brightness: 0.68...1.0, minimumScore: 0.85),
        hueAlias("royal blue", bases: [.blue], hue: 224, radius: 12, saturation: 0.55...1.0, brightness: 0.45...0.85, minimumScore: 0.86),
        hueAlias("navy blue", bases: [.blue], hue: 228, radius: 10, saturation: 0.45...1.0, brightness: 0.12...0.42, minimumScore: 0.86),
        hueAlias("periwinkle", bases: [.blue, .purple], hue: 240, radius: 14, saturation: 0.18...0.55, brightness: 0.62...1.0, minimumScore: 0.85),
        hueAlias("indigo", bases: [.blue, .purple], hue: 270, radius: 20, saturation: 0.35...1.0, brightness: 0.15...0.78, minimumScore: 0.58),
        hueAlias("lavender", bases: [.purple, .blue], hue: 270, radius: 16, saturation: 0.18...0.52, brightness: 0.72...1.0, minimumScore: 0.84),
        hueAlias("lavender", bases: [.purple, .blue, .white], hue: 240, radius: 18, saturation: 0.02...0.20, brightness: 0.92...1.0, minimumScore: 0.62),
        hueAlias("lilac", bases: [.purple, .pink], hue: 288, radius: 14, saturation: 0.25...0.62, brightness: 0.62...0.95, minimumScore: 0.84),
        hueAlias("mauve", bases: [.purple, .pink], hue: 312, radius: 14, saturation: 0.18...0.52, brightness: 0.42...0.82, minimumScore: 0.84),
        hueAlias("plum", bases: [.purple], hue: 300, radius: 14, saturation: 0.35...0.85, brightness: 0.25...0.65, minimumScore: 0.85),

        hueAlias("fuchsia", bases: [.pink, .purple], hue: 300, radius: 12, saturation: 0.75...1.0, brightness: 0.72...1.0, minimumScore: 0.55),
        hueAlias("magenta", bases: [.pink, .purple], hue: 300, radius: 8, saturation: 0.85...1.0, brightness: 0.32...0.80, minimumScore: 0.58),
        hueAlias("magenta", bases: [.pink, .purple], hue: 312, radius: 18, saturation: 0.35...0.90, brightness: 0.28...0.90, minimumScore: 0.48),

        hueAlias("rose", bases: [.pink, .red], hue: 346, radius: 12, saturation: 0.28...0.80, brightness: 0.52...0.95, minimumScore: 0.84),
        hueAlias("crimson", bases: [.red], hue: 350, radius: 18, saturation: 0.45...1.0, brightness: 0.28...0.95, minimumScore: 0.55),
        hueAlias("vermilion", bases: [.red, .orange], hue: 14, radius: 12, saturation: 0.62...1.0, brightness: 0.52...1.0, minimumScore: 0.86),
        hueAlias("coral", bases: [.red, .orange, .pink], hue: 12, radius: 14, saturation: 0.35...0.85, brightness: 0.68...1.0, minimumScore: 0.84),
        hueAlias("salmon", bases: [.pink, .orange, .red], hue: 16, radius: 15, saturation: 0.20...0.62, brightness: 0.62...0.95, minimumScore: 0.84),
        hueAlias("brick", bases: [.red, .orange, .brown], hue: 14, radius: 10, saturation: 0.35...0.80, brightness: 0.25...0.60, minimumScore: 0.85),
        hueAlias("scarlet", bases: [.red, .orange], hue: 4, radius: 10, saturation: 0.75...1.0, brightness: 0.45...0.95, minimumScore: 0.87),
        hueAlias("ruby", bases: [.red, .pink], hue: 350, radius: 9, saturation: 0.68...1.0, brightness: 0.35...0.80, minimumScore: 0.87),
        hueAlias("cherry", bases: [.red], hue: 358, radius: 10, saturation: 0.72...1.0, brightness: 0.40...0.90, minimumScore: 0.87),
        hueAlias("burgundy", bases: [.red, .purple], hue: 340, radius: 13, saturation: 0.40...0.90, brightness: 0.16...0.48, minimumScore: 0.86),
        hueAlias("maroon", bases: [.red, .brown], hue: 355, radius: 12, saturation: 0.35...0.90, brightness: 0.10...0.40, minimumScore: 0.86),

        hueAlias("amber", bases: [.orange, .yellow], hue: 42, radius: 12, saturation: 0.60...1.0, brightness: 0.50...1.0, minimumScore: 0.85),
        hueAlias("schoolbus", bases: [.yellow, .orange], hue: 44, radius: 8, saturation: 0.70...1.0, brightness: 0.85...1.0, minimumScore: 0.75),
        hueAlias("tangerine", bases: [.orange], hue: 26, radius: 10, saturation: 0.65...1.0, brightness: 0.65...1.0, minimumScore: 0.86),
        hueAlias("mustard", bases: [.yellow, .brown], hue: 52, radius: 10, saturation: 0.45...0.90, brightness: 0.38...0.75, minimumScore: 0.85),
        hueAlias("saffron", bases: [.yellow, .orange], hue: 46, radius: 11, saturation: 0.55...1.0, brightness: 0.62...1.0, minimumScore: 0.86),
        hueAlias("gold", bases: [.yellow, .orange], hue: 50, radius: 14, saturation: 0.38...1.0, brightness: 0.45...1.0, minimumScore: 0.56),
        hueAlias("rust", bases: [.orange, .red, .brown], hue: 21, radius: 12, saturation: 0.45...0.95, brightness: 0.20...0.58, minimumScore: 0.85),
        hueAlias("ochre", bases: [.yellow, .orange, .brown], hue: 38, radius: 12, saturation: 0.35...0.85, brightness: 0.36...0.82, minimumScore: 0.85),

        hueAlias("tan", bases: [.brown, .yellow], hue: 34, radius: 14, saturation: 0.20...0.50, brightness: 0.62...0.90, minimumScore: 0.84),
        hueAlias("beige", bases: [.brown, .yellow, .gray], hue: 40, radius: 14, saturation: 0.08...0.30, brightness: 0.72...0.96, minimumScore: 0.84),
        hueAlias("taupe", bases: [.brown, .gray], hue: 28, radius: 16, saturation: 0.04...0.22, brightness: 0.35...0.72, minimumScore: 0.84),
        hueAlias("chocolate", bases: [.brown], hue: 22, radius: 9, saturation: 0.45...0.95, brightness: 0.08...0.42, minimumScore: 0.86),
        hueAlias("caramel", bases: [.brown, .orange], hue: 30, radius: 10, saturation: 0.45...0.90, brightness: 0.32...0.68, minimumScore: 0.85),
        hueAlias("mocha", bases: [.brown], hue: 24, radius: 9, saturation: 0.35...0.78, brightness: 0.14...0.45, minimumScore: 0.86),
        hueAlias("walnut", bases: [.brown], hue: 26, radius: 9, saturation: 0.28...0.72, brightness: 0.12...0.42, minimumScore: 0.86),

        neutralAlias("ivory", bases: [.white, .yellow], saturation: 0.02...0.18, brightness: 0.90...1.0, minimumScore: 0.81),
        neutralAlias("linen", bases: [.white, .yellow, .gray], saturation: 0.03...0.16, brightness: 0.82...0.95, minimumScore: 0.81),
        neutralAlias("silver", bases: [.gray], saturation: 0.00...0.10, brightness: 0.60...0.92, minimumScore: 0.58),
        hueAlias("slate", bases: [.gray, .blue], hue: 210, radius: 10, saturation: 0.08...0.34, brightness: 0.28...0.72, minimumScore: 0.70),
        hueAlias("slate", bases: [.gray, .blue], hue: 222, radius: 12, saturation: 0.14...0.52, brightness: 0.20...0.60, minimumScore: 0.72),
        hueAlias("steel blue", bases: [.blue], hue: 208, radius: 12, saturation: 0.25...0.72, brightness: 0.38...0.86, minimumScore: 0.72),
        neutralAlias("graphite", bases: [.gray], saturation: 0.00...0.10, brightness: 0.18...0.40, minimumScore: 0.84),
        hueAlias("gunmetal", bases: [.gray, .blue], hue: 210, radius: 15, saturation: 0.08...0.30, brightness: 0.16...0.38, minimumScore: 0.85),
        neutralAlias("charcoal", bases: [.gray], saturation: 0.00...0.12, brightness: 0.08...0.30, minimumScore: 0.85)
    ]

    private static func normalizeHue(_ hueDegrees: CGFloat) -> CGFloat {
        let modulo = hueDegrees.truncatingRemainder(dividingBy: 360.0)
        return modulo < 0 ? modulo + 360.0 : modulo
    }

    private static func circularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let delta = abs(a - b).truncatingRemainder(dividingBy: 360.0)
        return min(delta, 360.0 - delta)
    }

    // MARK: - Web / Wikipedia Naming

    private static func formatCSSName(_ name: String) -> String {
        guard !name.isEmpty else { return name }
        var output = ""
        output.reserveCapacity(name.count + 4)
        for scalar in name.unicodeScalars {
            if CharacterSet.uppercaseLetters.contains(scalar), !output.isEmpty {
                output.append(" ")
            }
            output.unicodeScalars.append(scalar)
        }
        return output
    }

    private static func cssBaseHint(forHex sampleHex: String) -> BaseColor? {
        guard let exactCSS = cssColors.first(where: { $0.hex == sampleHex }) else {
            return nil
        }
        let tokens = cssNameTokens(exactCSS.name)
        var lastBase: BaseColor?
        for token in tokens {
            if let base = cssBaseColorToken(token) {
                lastBase = base
            }
        }
        return lastBase
    }

    private static func cssNameTokens(_ name: String) -> [String] {
        guard !name.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        current.reserveCapacity(name.count)
        for char in name {
            if char.isUppercase || !char.isLetter {
                if !current.isEmpty {
                    tokens.append(current.lowercased())
                    current.removeAll(keepingCapacity: true)
                }
                if char.isLetter {
                    current.append(char.lowercased())
                }
                continue
            }
            current.append(char)
        }
        if !current.isEmpty {
            tokens.append(current.lowercased())
        }
        return tokens
    }

    private static func cssBaseColorToken(_ token: String) -> BaseColor? {
        switch token {
        case "red":
            return .red
        case "orange":
            return .orange
        case "yellow":
            return .yellow
        case "green":
            return .green
        case "blue":
            return .blue
        case "purple", "violet":
            return .purple
        case "pink", "fuchsia", "magenta":
            return .pink
        case "brown":
            return .brown
        case "gray", "grey":
            return .gray
        case "black":
            return .black
        case "white":
            return .white
        default:
            return nil
        }
    }

    private static func webDisplayName(forHex sampleHex: String) -> String {
        if let exactCSS = cssColors.first(where: { $0.hex == sampleHex }) {
            return formatCSSName(exactCSS.name)
        }
        if let exactWiki = wikipediaColors.first(where: { $0.hex == sampleHex }) {
            return exactWiki.name
        }

        let cssMatch = nearestCSSMatch(forHex: sampleHex)
        let wikiMatch = nearestWikipediaMatch(forHex: sampleHex)

        let cssDistance = cssMatch?.distance ?? CGFloat.greatestFiniteMagnitude
        let wikiDistance = wikiMatch?.distance ?? CGFloat.greatestFiniteMagnitude

        if cssDistance <= wikiDistance, let cssMatch {
            return "\(formatCSSName(cssMatch.name)) (closest)"
        }
        if let wikiMatch {
            return "\(wikiMatch.name) (closest)"
        }
        return "Unknown"
    }

    private static func nearestCSSMatch(forHex sampleHex: String) -> (name: String, distance: CGFloat)? {
        guard let sampleRGB = rgbComponents(fromHex: sampleHex) else {
            return nil
        }

        var bestColor: CSSColor?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for entry in cssColors {
            let dr = sampleRGB.r - entry.r
            let dg = sampleRGB.g - entry.g
            let db = sampleRGB.b - entry.b
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDistance {
                bestDistance = dist
                bestColor = entry
            }
        }

        guard let bestColor else { return nil }
        return (bestColor.name, bestDistance)
    }

    private static func nearestWikipediaMatch(forHex sampleHex: String) -> (name: String, distance: CGFloat)? {
        guard let sampleRGB = rgbComponents(fromHex: sampleHex) else {
            return nil
        }

        var bestColor: PaletteColor?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for entry in wikipediaColors {
            let dr = sampleRGB.r - entry.r
            let dg = sampleRGB.g - entry.g
            let db = sampleRGB.b - entry.b
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDistance {
                bestDistance = dist
                bestColor = entry
            }
        }

        guard let bestColor else { return nil }
        return (bestColor.name, bestDistance)
    }

    private static func nearestISCCExtendedMatch(
        to color: NSColor,
        sampledHex: String,
        saturation: CGFloat,
        brightness: CGFloat
    ) -> (name: String, isExact: Bool) {
        // Keep neutrals intuitive instead of drifting to tinted "whites".
        if sampledHex == "FFFFFF" {
            return ("White", true)
        }
        if sampledHex == "000000" {
            return ("Black", true)
        }
        if let exact = isccExtendedColors.first(where: { $0.hex == sampledHex }) {
            return (exact.name, true)
        }
        if saturation <= 0.04 {
            if brightness >= 0.95 {
                return ("White", false)
            }
            if brightness <= 0.08 {
                return ("Black", false)
            }
            if brightness >= 0.72 {
                return ("Light Gray", false)
            }
            if brightness >= 0.35 {
                return ("Medium Gray", false)
            }
            return ("Dark Gray", false)
        }

        let srgb = color.usingColorSpace(.sRGB) ?? color
        let r = srgb.redComponent
        let g = srgb.greenComponent
        let b = srgb.blueComponent

        var bestName = "Unknown"
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for entry in isccExtendedColors {
            let dr = r - entry.r
            let dg = g - entry.g
            let db = b - entry.b
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDistance {
                bestDistance = dist
                bestName = entry.name
            }
        }

        return (bestName, false)
    }

    // MARK: - Data Models

    private struct CSSColor {
        let name: String
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat

        var hex: String {
            String(
                format: "%02X%02X%02X",
                min(255, max(0, Int((r * 255.0).rounded()))),
                min(255, max(0, Int((g * 255.0).rounded()))),
                min(255, max(0, Int((b * 255.0).rounded())))
            )
        }
    }

    private struct PaletteColor {
        let name: String
        let hex: String
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
    }

    private struct ISCCColor {
        let hex: String
        let name: String
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
    }

    private static func formatISCCName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }

    private static func rgbComponents(fromHex hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let normalized = normalizedHex(hex) else { return nil }
        guard
            let red = Int(normalized.prefix(2), radix: 16),
            let green = Int(normalized.dropFirst(2).prefix(2), radix: 16),
            let blue = Int(normalized.dropFirst(4).prefix(2), radix: 16)
        else {
            return nil
        }
        return (
            r: CGFloat(red) / 255.0,
            g: CGFloat(green) / 255.0,
            b: CGFloat(blue) / 255.0
        )
    }

    private static func normalizedHex(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard normalized.count == 6 else { return nil }
        guard Int(normalized, radix: 16) != nil else { return nil }
        return normalized.uppercased()
    }

    private static func hexString(from color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let red = min(255, max(0, Int((srgb.redComponent * 255.0).rounded())))
        let green = min(255, max(0, Int((srgb.greenComponent * 255.0).rounded())))
        let blue = min(255, max(0, Int((srgb.blueComponent * 255.0).rounded())))
        return String(format: "%02X%02X%02X", red, green, blue)
    }

    // MARK: - Data Sources

    private static let isccExtendedColors: [ISCCColor] = {
        isccExtendedRows.compactMap { row in
            guard let rgb = rgbComponents(fromHex: row.hex) else { return nil }
            guard let hex = normalizedHex(row.hex) else { return nil }
            return ISCCColor(
                hex: hex,
                name: formatISCCName(row.name),
                r: rgb.r,
                g: rgb.g,
                b: rgb.b
            )
        }
    }()

    private static let wikipediaColors: [PaletteColor] = {
        WikipediaColorData.rows.compactMap { row in
            guard let hex = normalizedHex(row.hex) else { return nil }
            guard let rgb = rgbComponents(fromHex: row.hex) else { return nil }
            return PaletteColor(
                name: row.name,
                hex: hex,
                r: rgb.r,
                g: rgb.g,
                b: rgb.b
            )
        }
    }()

    // ISCC-NBS centroid colors (extended names), sourced from NBS/ISCC palette tables.
    private static let isccExtendedRows: [(hex: String, name: String)] = [
        ("#fd7992", "Vivid_Pink"),
        ("#f0a121", "Strong_Orange_Yellow"),
        ("#9cc69c", "Light_Yellowish_Green"),
        ("#c5c9f0", "Very_Pale_Purplish_Blue"),
        ("#f48fa0", "Strong_Pink"),
        ("#d08511", "Deep_Orange_Yellow"),
        ("#669069", "Moderate_Yellowish_Green"),
        ("#8e92b7", "Pale_Purplish_Blue"),
        ("#e66980", "Deep_Pink"),
        ("#fcc27c", "Light_Orange_Yellow"),
        ("#2f5d3a", "Dark_Yellowish_Green"),
        ("#494d71", "Grayish_Purplish_Blue"),
        ("#f8c3ce", "Light_Pink"),
        ("#e7a75d", "Moderate_Orange_Yellow"),
        ("#10361a", "Very_Dark_Yellowish_Green"),
        ("#7931d3", "Vivid_Violet"),
        ("#e2a3ae", "Moderate_Pink"),
        ("#c38639", "Dark_Orange_Yellow"),
        ("#23eaa5", "Vivid_Green"),
        ("#987fdc", "Brilliant_Violet"),
        ("#c5808a", "Dark_Pink"),
        ("#eec6a6", "Pale_Orange_Yellow"),
        ("#49d0a3", "Brilliant_Green"),
        ("#61419c", "Strong_Violet"),
        ("#efd1dc", "Pale_Pink"),
        ("#9e671d", "Strong_Yellowish_Brown"),
        ("#158a66", "Strong_Green"),
        ("#3c1668", "Deep_Violet"),
        ("#cbadb7", "Grayish_Pink"),
        ("#673f0b", "Deep_Yellowish_Brown"),
        ("#00543d", "Deep_Green"),
        ("#c9baf8", "Very_Light_Violet"),
        ("#efdde5", "Pinkish_White"),
        ("#c49a74", "Light_Yellowish_Brown"),
        ("#a6e2ca", "Very_Light_Green"),
        ("#9b8cca", "Light_Violet"),
        ("#c7b6bd", "Pinkish_Gray"),
        ("#886648", "Moderate_Yellowish_Brown"),
        ("#6fac95", "Light_Green"),
        ("#5c4985", "Moderate_Violet"),
        ("#d51c3c", "Vivid_Red"),
        ("#50341a", "Dark_Yellowish_Brown"),
        ("#337762", "Moderate_Green"),
        ("#34254d", "Dark_Violet"),
        ("#bf344b", "Strong_Red"),
        ("#b49b8d", "Light_Grayish_Yellowish_Brown"),
        ("#164e3d", "Dark_Green"),
        ("#d0c6ef", "Very_Pale_Violet"),
        ("#87122d", "Deep_Red"),
        ("#7e695d", "Grayish_Yellowish_Brown"),
        ("#0c2e24", "Very_Dark_Green"),
        ("#9a90b5", "Pale_Violet"),
        ("#5c0625", "Very_Deep_Red"),
        ("#4d3d33", "Dark_Grayish_Yellowish_Brown"),
        ("#c7d9d6", "Very_Pale_Green"),
        ("#584e72", "Grayish_Violet"),
        ("#b14955", "Moderate_Red"),
        ("#f1bf15", "Vivid_Yellow"),
        ("#94a6a3", "Pale_Green"),
        ("#b935d5", "Vivid_Purple"),
        ("#742434", "Dark_Red"),
        ("#f7ce50", "Brilliant_Yellow"),
        ("#61716e", "Grayish_Green"),
        ("#ce8ce3", "Brilliant_Purple"),
        ("#481127", "Very_Dark_Red"),
        ("#d9ae2f", "Strong_Yellow"),
        ("#394746", "Dark_Grayish_Green"),
        ("#9352a8", "Strong_Purple"),
        ("#b4888d", "Light_Grayish_Red"),
        ("#b88f16", "Deep_Yellow"),
        ("#1f2a2a", "Blackish_Green"),
        ("#652277", "Deep_Purple"),
        ("#985d62", "Grayish_Red"),
        ("#f4d284", "Light_Yellow"),
        ("#e0e2e5", "Greenish_White"),
        ("#460a55", "Very_Deep_Purple"),
        ("#53383e", "Dark_Grayish_Red"),
        ("#d2af63", "Moderate_Yellow"),
        ("#babec1", "Light_Greenish_Gray"),
        ("#e4b9f3", "Very_Light_Purple"),
        ("#332127", "Blackish_Red"),
        ("#b08f42", "Dark_Yellow"),
        ("#848888", "Greenish_Gray"),
        ("#bc93cc", "Light_Purple"),
        ("#928186", "Reddish_Gray"),
        ("#efd7b2", "Pale_Yellow"),
        ("#545858", "Dark_Greenish_Gray"),
        ("#875e96", "Moderate_Purple"),
        ("#5d4e53", "Dark_Reddish_Gray"),
        ("#c8b18b", "Grayish_Yellow"),
        ("#212626", "Greenish_Black"),
        ("#563762", "Dark_Purple"),
        ("#30262b", "Reddish_Black"),
        ("#a99066", "Dark_Grayish_Yellow"),
        ("#13fcd5", "Vivid_Bluish_Green"),
        ("#371b41", "Very_Dark_Purple"),
        ("#fd7e5d", "Vivid_Yellowish_Pink"),
        ("#eedfda", "Yellowish_White"),
        ("#35d7ce", "Brilliant_Bluish_Green"),
        ("#e0cbeb", "Very_Pale_Purple"),
        ("#f59080", "Strong_Yellowish_Pink"),
        ("#c6b9b1", "Yellowish_Gray"),
        ("#0d8f82", "Strong_Bluish_Green"),
        ("#ad97b3", "Pale_Purple"),
        ("#ef6366", "Deep_Yellowish_Pink"),
        ("#997736", "Light_Olive_Brown"),
        ("#00443f", "Deep_Bluish_Green"),
        ("#7b667e", "Grayish_Purple"),
        ("#f8c4b6", "Light_Yellowish_Pink"),
        ("#705420", "Moderate_Olive_Brown"),
        ("#98e1e0", "Very_Light_Bluish_Green"),
        ("#513f51", "Dark_Grayish_Purple"),
        ("#e2a698", "Moderate_Yellowish_Pink"),
        ("#3f2c10", "Dark_Olive_Brown"),
        ("#5fabab", "Light_Bluish_Green"),
        ("#2f2231", "Blackish_Purple"),
        ("#c9807e", "Dark_Yellowish_Pink"),
        ("#ebdd21", "Vivid_Greenish_Yellow"),
        ("#297a7b", "Moderate_Bluish_Green"),
        ("#ebdfef", "Purplish_White"),
        ("#f1d3d1", "Pale_Yellowish_Pink"),
        ("#e9dc55", "Brilliant_Greenish_Yellow"),
        ("#154b4d", "Dark_Bluish_Green"),
        ("#c3b7c6", "Light_Purplish_Gray"),
        ("#cbacac", "Grayish_Yellowish_Pink"),
        ("#c4b827", "Strong_Greenish_Yellow"),
        ("#0a2d2e", "Very_Dark_Bluish_Green"),
        ("#8f8490", "Purplish_Gray"),
        ("#cbafa7", "Brownish_Pink"),
        ("#a29812", "Deep_Greenish_Yellow"),
        ("#0085a1", "Vivid_Greenish_Blue"),
        ("#5c525e", "Dark_Purplish_Gray"),
        ("#e83b1b", "Vivid_Reddish_Orange"),
        ("#e9dd8a", "Light_Greenish_Yellow"),
        ("#2dbce2", "Brilliant_Greenish_Blue"),
        ("#2b2630", "Purplish_Black"),
        ("#db5d3b", "Strong_Reddish_Orange"),
        ("#c0b55e", "Moderate_Greenish_Yellow"),
        ("#1385af", "Strong_Greenish_Blue"),
        ("#d429b9", "Vivid_Reddish_Purple"),
        ("#af3318", "Deep_Reddish_Orange"),
        ("#9e953c", "Dark_Greenish_Yellow"),
        ("#2e8495", "Deep_Greenish_Blue"),
        ("#a74994", "Strong_Reddish_Purple"),
        ("#cd6952", "Moderate_Reddish_Orange"),
        ("#e6dcab", "Pale_Greenish_Yellow"),
        ("#94d6ef", "Very_Light_Greenish_Blue"),
        ("#761a6a", "Deep_Reddish_Purple"),
        ("#a2402b", "Dark_Reddish_Orange"),
        ("#beb584", "Grayish_Greenish_Yellow"),
        ("#65a8c3", "Light_Greenish_Blue"),
        ("#4f094a", "Very_Deep_Reddish_Purple"),
        ("#b97565", "Grayish_Reddish_Orange"),
        ("#8b7d2e", "Light_Olive"),
        ("#2a7691", "Moderate_Greenish_Blue"),
        ("#bd80ae", "Light_Reddish_Purple"),
        ("#8b1c0e", "Strong_Reddish_Brown"),
        ("#64591a", "Moderate_Olive"),
        ("#134a60", "Dark_Greenish_Blue"),
        ("#965888", "Moderate_Reddish_Purple"),
        ("#610f12", "Deep_Reddish_Brown"),
        ("#352e0a", "Dark_Olive"),
        ("#0b2c3b", "Very_Dark_Greenish_Blue"),
        ("#5f3458", "Dark_Reddish_Purple"),
        ("#ac7a73", "Light_Reddish_Brown"),
        ("#8e856f", "Light_Grayish_Olive"),
        ("#1b5cd7", "Vivid_Blue"),
        ("#3f183c", "Very_Dark_Reddish_Purple"),
        ("#7d423b", "Moderate_Reddish_Brown"),
        ("#5d553f", "Grayish_Olive"),
        ("#419ded", "Brilliant_Blue"),
        ("#ad89a5", "Pale_Reddish_Purple"),
        ("#461d1e", "Dark_Reddish_Brown"),
        ("#35301c", "Dark_Grayish_Olive"),
        ("#276cbd", "Strong_Blue"),
        ("#86627e", "Grayish_Reddish_Purple"),
        ("#9e7f7a", "Light_Grayish_Reddish_Brown"),
        ("#8f877f", "Light_Olive_Gray"),
        ("#113074", "Deep_Blue"),
        ("#fca1e7", "Brilliant_Purplish_Pink"),
        ("#6c4d4b", "Grayish_Reddish_Brown"),
        ("#58514a", "Olive_Gray"),
        ("#99c6f9", "Very_Light_Blue"),
        ("#f483cd", "Strong_Purplish_Pink"),
        ("#43292a", "Dark_Grayish_Reddish_Brown"),
        ("#23211c", "Olive_Black"),
        ("#73a4dc", "Light_Blue"),
        ("#df6aac", "Deep_Purplish_Pink"),
        ("#f7760b", "Vivid_Orange"),
        ("#a7dc26", "Vivid_Yellow_Green"),
        ("#34689e", "Moderate_Blue"),
        ("#f5b2db", "Light_Purplish_Pink"),
        ("#fd943f", "Brilliant_Orange"),
        ("#c3df69", "Brilliant_Yellow_Green"),
        ("#173459", "Dark_Blue"),
        ("#de98bf", "Moderate_Purplish_Pink"),
        ("#ea8127", "Strong_Orange"),
        ("#82a12b", "Strong_Yellow_Green"),
        ("#c2d2ec", "Very_Pale_Blue"),
        ("#c67d9d", "Dark_Purplish_Pink"),
        ("#c26012", "Deep_Orange"),
        ("#486c0e", "Deep_Yellow_Green"),
        ("#91a2bb", "Pale_Blue"),
        ("#ebc8df", "Pale_Purplish_Pink"),
        ("#fbaf82", "Light_Orange"),
        ("#cedb9f", "Light_Yellow_Green"),
        ("#54687f", "Grayish_Blue"),
        ("#c7a3b9", "Grayish_Purplish_Pink"),
        ("#de8d5c", "Moderate_Orange"),
        ("#8b9a5f", "Moderate_Yellow_Green"),
        ("#323f4e", "Dark_Grayish_Blue"),
        ("#dd2388", "Vivid_Purplish_Red"),
        ("#b26633", "Brownish_Orange"),
        ("#d7d7c1", "Pale_Yellow_Green"),
        ("#1e2531", "Blackish_Blue"),
        ("#b83773", "Strong_Purplish_Red"),
        ("#8a4416", "Strong_Brown"),
        ("#979a85", "Grayish_Yellow_Green"),
        ("#e1e1f1", "Bluish_White"),
        ("#881055", "Deep_Purplish_Red"),
        ("#571a07", "Deep_Brown"),
        ("#2c5506", "Strong_Olive_Green"),
        ("#b7b8c6", "Light_Bluish_Gray"),
        ("#54063c", "Very_Deep_Purplish_Red"),
        ("#ad7c63", "Light_Brown"),
        ("#232f00", "Deep_Olive_Green"),
        ("#838793", "Bluish_Gray"),
        ("#ab4b74", "Moderate_Purplish_Red"),
        ("#724a38", "Moderate_Brown"),
        ("#495b22", "Moderate_Olive_Green"),
        ("#50545f", "Dark_Bluish_Gray"),
        ("#6e294c", "Dark_Purplish_Red"),
        ("#442112", "Dark_Brown"),
        ("#20340b", "Dark_Olive_Green"),
        ("#24272e", "Bluish_Black"),
        ("#431432", "Very_Dark_Purplish_Red"),
        ("#997f75", "Light_Grayish_Brown"),
        ("#545947", "Grayish_Olive_Green"),
        ("#4436d1", "Vivid_Purplish_Blue"),
        ("#b2879b", "Light_Grayish_Purplish_Red"),
        ("#674f48", "Grayish_Brown"),
        ("#2f3326", "Dark_Grayish_Olive_Green"),
        ("#8088e2", "Brilliant_Purplish_Blue"),
        ("#945c73", "Grayish_Purplish_Red"),
        ("#3e2c28", "Dark_Grayish_Brown"),
        ("#3fd740", "Vivid_Yellowish_Green"),
        ("#5359b5", "Strong_Purplish_Blue"),
        ("#e7e1e9", "White"),
        ("#928281", "Light_Brownish_Gray"),
        ("#87d989", "Brilliant_Yellowish_Green"),
        ("#2a286f", "Deep_Purplish_Blue"),
        ("#bdb7bf", "Light_Gray"),
        ("#605251", "Brownish_Gray"),
        ("#39964a", "Strong_Yellowish_Green"),
        ("#b7c0f8", "Very_Light_Purplish_Blue"),
        ("#8a8489", "Medium_Gray"),
        ("#2b211e", "Brownish_Black"),
        ("#176a1e", "Deep_Yellowish_Green"),
        ("#8991cb", "Light_Purplish_Blue"),
        ("#585458", "Dark_Gray"),
        ("#f6a600", "Vivid_Orange_Yellow"),
        ("#054208", "Very_Deep_Yellowish_Green"),
        ("#4d4e87", "Moderate_Purplish_Blue"),
        ("#2b292b", "Black"),
        ("#ffbe50", "Brilliant_Orange_Yellow"),
        ("#c5edc4", "Very_Light_Yellowish_Green"),
        ("#222248", "Dark_Purplish_Blue"),
    ]

    private static let cssColors: [CSSColor] = [
        CSSColor(name: "AliceBlue", r: 0.941, g: 0.973, b: 1.000),
        CSSColor(name: "AntiqueWhite", r: 0.980, g: 0.922, b: 0.843),
        CSSColor(name: "Aqua", r: 0.000, g: 1.000, b: 1.000),
        CSSColor(name: "Aquamarine", r: 0.498, g: 1.000, b: 0.831),
        CSSColor(name: "Azure", r: 0.941, g: 1.000, b: 1.000),
        CSSColor(name: "Beige", r: 0.961, g: 0.961, b: 0.863),
        CSSColor(name: "Bisque", r: 1.000, g: 0.894, b: 0.769),
        CSSColor(name: "Black", r: 0.000, g: 0.000, b: 0.000),
        CSSColor(name: "BlanchedAlmond", r: 1.000, g: 0.922, b: 0.804),
        CSSColor(name: "Blue", r: 0.000, g: 0.000, b: 1.000),
        CSSColor(name: "BlueViolet", r: 0.541, g: 0.169, b: 0.886),
        CSSColor(name: "Brown", r: 0.647, g: 0.165, b: 0.165),
        CSSColor(name: "BurlyWood", r: 0.871, g: 0.722, b: 0.529),
        CSSColor(name: "CadetBlue", r: 0.373, g: 0.620, b: 0.627),
        CSSColor(name: "Chartreuse", r: 0.498, g: 1.000, b: 0.000),
        CSSColor(name: "Chocolate", r: 0.824, g: 0.412, b: 0.118),
        CSSColor(name: "Coral", r: 1.000, g: 0.498, b: 0.314),
        CSSColor(name: "CornflowerBlue", r: 0.392, g: 0.584, b: 0.929),
        CSSColor(name: "Cornsilk", r: 1.000, g: 0.973, b: 0.863),
        CSSColor(name: "Crimson", r: 0.863, g: 0.078, b: 0.235),
        CSSColor(name: "Cyan", r: 0.000, g: 1.000, b: 1.000),
        CSSColor(name: "DarkBlue", r: 0.000, g: 0.000, b: 0.545),
        CSSColor(name: "DarkCyan", r: 0.000, g: 0.545, b: 0.545),
        CSSColor(name: "DarkGoldenrod", r: 0.722, g: 0.525, b: 0.043),
        CSSColor(name: "DarkGray", r: 0.663, g: 0.663, b: 0.663),
        CSSColor(name: "DarkGreen", r: 0.000, g: 0.392, b: 0.000),
        CSSColor(name: "DarkKhaki", r: 0.741, g: 0.718, b: 0.420),
        CSSColor(name: "DarkMagenta", r: 0.545, g: 0.000, b: 0.545),
        CSSColor(name: "DarkOliveGreen", r: 0.333, g: 0.420, b: 0.184),
        CSSColor(name: "DarkOrange", r: 1.000, g: 0.549, b: 0.000),
        CSSColor(name: "DarkOrchid", r: 0.600, g: 0.196, b: 0.800),
        CSSColor(name: "DarkRed", r: 0.545, g: 0.000, b: 0.000),
        CSSColor(name: "DarkSalmon", r: 0.914, g: 0.588, b: 0.478),
        CSSColor(name: "DarkSeaGreen", r: 0.561, g: 0.737, b: 0.561),
        CSSColor(name: "DarkSlateBlue", r: 0.282, g: 0.239, b: 0.545),
        CSSColor(name: "DarkSlateGray", r: 0.184, g: 0.310, b: 0.310),
        CSSColor(name: "DarkTurquoise", r: 0.000, g: 0.808, b: 0.820),
        CSSColor(name: "DarkViolet", r: 0.580, g: 0.000, b: 0.827),
        CSSColor(name: "DeepPink", r: 1.000, g: 0.078, b: 0.576),
        CSSColor(name: "DeepSkyBlue", r: 0.000, g: 0.749, b: 1.000),
        CSSColor(name: "DimGray", r: 0.412, g: 0.412, b: 0.412),
        CSSColor(name: "DodgerBlue", r: 0.118, g: 0.565, b: 1.000),
        CSSColor(name: "FireBrick", r: 0.698, g: 0.133, b: 0.133),
        CSSColor(name: "FloralWhite", r: 1.000, g: 0.980, b: 0.941),
        CSSColor(name: "ForestGreen", r: 0.133, g: 0.545, b: 0.133),
        CSSColor(name: "Fuchsia", r: 1.000, g: 0.000, b: 1.000),
        CSSColor(name: "Gainsboro", r: 0.863, g: 0.863, b: 0.863),
        CSSColor(name: "GhostWhite", r: 0.973, g: 0.973, b: 1.000),
        CSSColor(name: "Gold", r: 1.000, g: 0.843, b: 0.000),
        CSSColor(name: "Goldenrod", r: 0.855, g: 0.647, b: 0.125),
        CSSColor(name: "Gray", r: 0.502, g: 0.502, b: 0.502),
        CSSColor(name: "Green", r: 0.000, g: 0.502, b: 0.000),
        CSSColor(name: "GreenYellow", r: 0.678, g: 1.000, b: 0.184),
        CSSColor(name: "HoneyDew", r: 0.941, g: 1.000, b: 0.941),
        CSSColor(name: "HotPink", r: 1.000, g: 0.412, b: 0.706),
        CSSColor(name: "IndianRed", r: 0.804, g: 0.361, b: 0.361),
        CSSColor(name: "Indigo", r: 0.294, g: 0.000, b: 0.510),
        CSSColor(name: "Ivory", r: 1.000, g: 1.000, b: 0.941),
        CSSColor(name: "Khaki", r: 0.941, g: 0.902, b: 0.549),
        CSSColor(name: "Lavender", r: 0.902, g: 0.902, b: 0.980),
        CSSColor(name: "LavenderBlush", r: 1.000, g: 0.941, b: 0.961),
        CSSColor(name: "LawnGreen", r: 0.486, g: 0.988, b: 0.000),
        CSSColor(name: "LemonChiffon", r: 1.000, g: 0.980, b: 0.804),
        CSSColor(name: "LightBlue", r: 0.678, g: 0.847, b: 0.902),
        CSSColor(name: "LightCoral", r: 0.941, g: 0.502, b: 0.502),
        CSSColor(name: "LightCyan", r: 0.878, g: 1.000, b: 1.000),
        CSSColor(name: "LightGoldenrodYellow", r: 0.980, g: 0.980, b: 0.824),
        CSSColor(name: "LightGray", r: 0.827, g: 0.827, b: 0.827),
        CSSColor(name: "LightGreen", r: 0.565, g: 0.933, b: 0.565),
        CSSColor(name: "LightPink", r: 1.000, g: 0.714, b: 0.757),
        CSSColor(name: "LightSalmon", r: 1.000, g: 0.627, b: 0.478),
        CSSColor(name: "LightSeaGreen", r: 0.125, g: 0.698, b: 0.667),
        CSSColor(name: "LightSkyBlue", r: 0.529, g: 0.808, b: 0.980),
        CSSColor(name: "LightSlateGray", r: 0.467, g: 0.533, b: 0.600),
        CSSColor(name: "LightSteelBlue", r: 0.690, g: 0.769, b: 0.871),
        CSSColor(name: "LightYellow", r: 1.000, g: 1.000, b: 0.878),
        CSSColor(name: "Lime", r: 0.000, g: 1.000, b: 0.000),
        CSSColor(name: "LimeGreen", r: 0.196, g: 0.804, b: 0.196),
        CSSColor(name: "Linen", r: 0.980, g: 0.941, b: 0.902),
        CSSColor(name: "Magenta", r: 1.000, g: 0.000, b: 1.000),
        CSSColor(name: "Maroon", r: 0.502, g: 0.000, b: 0.000),
        CSSColor(name: "MediumAquamarine", r: 0.400, g: 0.804, b: 0.667),
        CSSColor(name: "MediumBlue", r: 0.000, g: 0.000, b: 0.804),
        CSSColor(name: "MediumOrchid", r: 0.729, g: 0.333, b: 0.827),
        CSSColor(name: "MediumPurple", r: 0.576, g: 0.439, b: 0.859),
        CSSColor(name: "MediumSeaGreen", r: 0.235, g: 0.702, b: 0.443),
        CSSColor(name: "MediumSlateBlue", r: 0.482, g: 0.408, b: 0.933),
        CSSColor(name: "MediumSpringGreen", r: 0.000, g: 0.980, b: 0.604),
        CSSColor(name: "MediumTurquoise", r: 0.282, g: 0.820, b: 0.800),
        CSSColor(name: "MediumVioletRed", r: 0.780, g: 0.082, b: 0.522),
        CSSColor(name: "MidnightBlue", r: 0.098, g: 0.098, b: 0.439),
        CSSColor(name: "MintCream", r: 0.961, g: 1.000, b: 0.980),
        CSSColor(name: "MistyRose", r: 1.000, g: 0.894, b: 0.882),
        CSSColor(name: "Moccasin", r: 1.000, g: 0.894, b: 0.710),
        CSSColor(name: "NavajoWhite", r: 1.000, g: 0.871, b: 0.678),
        CSSColor(name: "Navy", r: 0.000, g: 0.000, b: 0.502),
        CSSColor(name: "OldLace", r: 0.992, g: 0.961, b: 0.902),
        CSSColor(name: "Olive", r: 0.502, g: 0.502, b: 0.000),
        CSSColor(name: "OliveDrab", r: 0.420, g: 0.557, b: 0.137),
        CSSColor(name: "Orange", r: 1.000, g: 0.647, b: 0.000),
        CSSColor(name: "OrangeRed", r: 1.000, g: 0.271, b: 0.000),
        CSSColor(name: "Orchid", r: 0.855, g: 0.439, b: 0.839),
        CSSColor(name: "PaleGoldenrod", r: 0.933, g: 0.910, b: 0.667),
        CSSColor(name: "PaleGreen", r: 0.596, g: 0.984, b: 0.596),
        CSSColor(name: "PaleTurquoise", r: 0.686, g: 0.933, b: 0.933),
        CSSColor(name: "PaleVioletRed", r: 0.859, g: 0.439, b: 0.576),
        CSSColor(name: "PapayaWhip", r: 1.000, g: 0.937, b: 0.835),
        CSSColor(name: "PeachPuff", r: 1.000, g: 0.855, b: 0.725),
        CSSColor(name: "Peru", r: 0.804, g: 0.522, b: 0.247),
        CSSColor(name: "Pink", r: 1.000, g: 0.753, b: 0.796),
        CSSColor(name: "Plum", r: 0.867, g: 0.627, b: 0.867),
        CSSColor(name: "PowderBlue", r: 0.690, g: 0.878, b: 0.902),
        CSSColor(name: "Purple", r: 0.502, g: 0.000, b: 0.502),
        CSSColor(name: "RebeccaPurple", r: 0.400, g: 0.200, b: 0.600),
        CSSColor(name: "Red", r: 1.000, g: 0.000, b: 0.000),
        CSSColor(name: "RosyBrown", r: 0.737, g: 0.561, b: 0.561),
        CSSColor(name: "RoyalBlue", r: 0.255, g: 0.412, b: 0.882),
        CSSColor(name: "SaddleBrown", r: 0.545, g: 0.271, b: 0.075),
        CSSColor(name: "Salmon", r: 0.980, g: 0.502, b: 0.447),
        CSSColor(name: "SandyBrown", r: 0.957, g: 0.643, b: 0.376),
        CSSColor(name: "SeaGreen", r: 0.180, g: 0.545, b: 0.341),
        CSSColor(name: "SeaShell", r: 1.000, g: 0.961, b: 0.933),
        CSSColor(name: "Sienna", r: 0.627, g: 0.322, b: 0.176),
        CSSColor(name: "Silver", r: 0.753, g: 0.753, b: 0.753),
        CSSColor(name: "SkyBlue", r: 0.529, g: 0.808, b: 0.922),
        CSSColor(name: "SlateBlue", r: 0.416, g: 0.353, b: 0.804),
        CSSColor(name: "SlateGray", r: 0.439, g: 0.502, b: 0.565),
        CSSColor(name: "Snow", r: 1.000, g: 0.980, b: 0.980),
        CSSColor(name: "SpringGreen", r: 0.000, g: 1.000, b: 0.498),
        CSSColor(name: "SteelBlue", r: 0.275, g: 0.510, b: 0.706),
        CSSColor(name: "Tan", r: 0.824, g: 0.706, b: 0.549),
        CSSColor(name: "Teal", r: 0.000, g: 0.502, b: 0.502),
        CSSColor(name: "Thistle", r: 0.847, g: 0.749, b: 0.847),
        CSSColor(name: "Tomato", r: 1.000, g: 0.388, b: 0.278),
        CSSColor(name: "Turquoise", r: 0.251, g: 0.878, b: 0.816),
        CSSColor(name: "Violet", r: 0.933, g: 0.510, b: 0.933),
        CSSColor(name: "Wheat", r: 0.961, g: 0.871, b: 0.702),
        CSSColor(name: "White", r: 1.000, g: 1.000, b: 1.000),
        CSSColor(name: "WhiteSmoke", r: 0.961, g: 0.961, b: 0.961),
        CSSColor(name: "Yellow", r: 1.000, g: 1.000, b: 0.000),
        CSSColor(name: "YellowGreen", r: 0.604, g: 0.804, b: 0.196)
    ]
}
