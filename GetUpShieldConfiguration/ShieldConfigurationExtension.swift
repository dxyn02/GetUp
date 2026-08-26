@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings
@preconcurrency import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let contentProvider = ShieldContentProvider(
        snapshotReader: AppGroupShieldSnapshotReader()
    )

    override func configuration(
        shielding application: Application
    ) -> ShieldConfiguration {
        configuration(for: application.token)
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(
            for: application.token,
            categoryToken: category.token
        )
    }

    override func configuration(
        shielding webDomain: WebDomain
    ) -> ShieldConfiguration {
        configuration(
            for: nil,
            webDomainToken: webDomain.token
        )
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(
            for: nil,
            categoryToken: category.token,
            webDomainToken: webDomain.token
        )
    }

    private func configuration(
        for applicationToken: ApplicationToken?,
        categoryToken: ActivityCategoryToken? = nil,
        webDomainToken: WebDomainToken? = nil
    ) -> ShieldConfiguration {
        let content = contentProvider.content(
            for: applicationToken,
            categoryToken: categoryToken,
            webDomainToken: webDomainToken
        )

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: ShieldPalette.background,
            icon: UIImage(
                named: "NaseoShieldLogo",
                in: Bundle(for: ShieldConfigurationExtension.self),
                compatibleWith: nil
            )?.withRenderingMode(.alwaysOriginal),
            title: ShieldConfiguration.Label(
                text: content.title,
                color: ShieldPalette.primaryText
            ),
            subtitle: ShieldConfiguration.Label(
                text: content.subtitle,
                color: ShieldPalette.secondaryText
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: content.primaryButtonLabel,
                color: ShieldPalette.primaryButtonText
            ),
            primaryButtonBackgroundColor: ShieldPalette.accent
        )
    }
}

private enum ShieldPalette {
    static let background = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 8 / 255, green: 9 / 255, blue: 11 / 255, alpha: 1)
        default:
            UIColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
        }
    }

    static let primaryText = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            .white
        default:
            onAccent
        }
    }

    static let secondaryText = UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 166 / 255, green: 168 / 255, blue: 173 / 255, alpha: 1)
        default:
            UIColor(red: 81 / 255, green: 83 / 255, blue: 90 / 255, alpha: 1)
        }
    }

    static let accent = UIColor(
        red: 244 / 255,
        green: 214 / 255,
        blue: 0,
        alpha: 1
    )
    static let primaryButtonText = UIColor.black
    static let onAccent = UIColor(
        red: 9 / 255,
        green: 10 / 255,
        blue: 12 / 255,
        alpha: 1
    )
}
