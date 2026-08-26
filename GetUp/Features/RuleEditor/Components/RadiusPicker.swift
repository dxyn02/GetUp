import SwiftUI

struct RadiusPicker: View {
    @Binding private var selection: RadiusOption

    init(selection: Binding<RadiusOption>) {
        self._selection = selection
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("반경")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(RuleEditorColor.textSecondary)

                Spacer()

                Text(Self.displayName(for: selection))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(RuleEditorColor.accent)
                    .accessibilityHidden(true)
            }

            Slider(value: selectionIndex, in: 0...Double(Self.options.count - 1), step: 1)
                .tint(RuleEditorColor.accent)
                .accessibilityLabel("반경")
                .accessibilityValue(Self.displayName(for: selection))
                .accessibilityHint("위아래로 쓸어 네 단계 중 하나를 선택합니다.")
                .accessibilityIdentifier("locationPicker.radius")
        }
    }

    private var selectionIndex: Binding<Double> {
        Binding(
            get: {
                Double(Self.options.firstIndex(of: selection) ?? 0)
            },
            set: { newValue in
                let index = min(
                    max(Int(newValue.rounded()), 0),
                    Self.options.count - 1
                )
                selection = Self.options[index]
            }
        )
    }

    private static let options = RadiusOption.allCases

    static func displayName(for radius: RadiusOption) -> String {
        switch radius {
        case .meters100: "100m"
        case .meters250: "250m"
        case .meters500: "500m"
        case .meters1000: "1km"
        }
    }
}
