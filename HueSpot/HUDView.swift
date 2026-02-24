// Copyright © 2026 Mark Zaros. All Rights Reserved. License: GNU Public License 2.0 only.
import SwiftUI
import AppKit

struct HUDView: View {
    let color: NSColor
    let names: ColorNames
    let hex: String
    let copyFeedback: String
    let showISCCNABColorName: Bool
    let showWebColorName: Bool
    let showHex: Bool

    var body: some View {
        HStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(color))
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(names.simplified.isEmpty ? "Sampling" : names.simplified)
                    .font(.system(size: 24, weight: .semibold))
                if showISCCNABColorName && !names.isccExtended.isEmpty {
                    Text("ISCC: \(names.isccExtended)")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                if showWebColorName && !names.detailed.isEmpty {
                    Text("Web: \(names.detailed)")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                if showHex && !hex.isEmpty {
                    Text(hex)
                        .font(.system(size: 20, weight: .regular, design: .monospaced))
                }
                if !copyFeedback.isEmpty {
                    Text(copyFeedback)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
        )
        .fixedSize()
    }
}
