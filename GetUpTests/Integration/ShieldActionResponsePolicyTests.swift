@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@Suite("Shield action response policy")
struct ShieldActionResponsePolicyTests {
    @Test("The primary action closes the restricted app without granting access")
    func primaryActionClosesRestrictedApp() {
        let response = ShieldActionResponsePolicy().response(
            for: .primaryButtonPressed
        )

        #expect(response == .close)
    }

    @Test("An unexpected secondary action still cannot bypass the restriction")
    func unexpectedSecondaryActionAlsoClosesRestrictedApp() {
        let response = ShieldActionResponsePolicy().response(
            for: .secondaryButtonPressed
        )

        #expect(response == .close)
    }
}
