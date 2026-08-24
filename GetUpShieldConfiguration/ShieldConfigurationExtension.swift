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
        configuration(for: application.token)
    }

    override func configuration(
        shielding webDomain: WebDomain
    ) -> ShieldConfiguration {
        configuration(for: nil)
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(for: nil)
    }

    private func configuration(
        for applicationToken: ApplicationToken?
    ) -> ShieldConfiguration {
        let content = contentProvider.content(for: applicationToken)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(
                red: 8 / 255,
                green: 10 / 255,
                blue: 13 / 255,
                alpha: 1
            ),
            icon: UIImage(systemName: "figure.stand"),
            title: ShieldConfiguration.Label(
                text: content.title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: content.subtitle,
                color: UIColor(
                    red: 166 / 255,
                    green: 168 / 255,
                    blue: 173 / 255,
                    alpha: 1
                )
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: content.primaryButtonLabel,
                color: .white
            ),
            primaryButtonBackgroundColor: .systemBlue
        )
    }
}
