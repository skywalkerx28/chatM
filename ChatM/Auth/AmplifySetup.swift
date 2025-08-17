import Foundation
import Amplify
import AWSCognitoAuthPlugin

enum AmplifySetup {
    private static var configured = false
    static func configure() {
        guard !configured else { return }
        do {
            // Build JSONValue configuration expected by Amplify 2.x
            let pluginConfig: JSONValue = .object([
                "CognitoUserPool": .object([
                    "Default": .object([
                        "PoolId": .string(Config.userPoolId),
                        "AppClientId": .string(Config.appClientId),
                        "Region": .string(Config.region)
                    ])
                ])
            ])

            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            let authCategory = AuthCategoryConfiguration(plugins: ["awsCognitoAuthPlugin": pluginConfig])
            let configuration = AmplifyConfiguration(auth: authCategory)
            try Amplify.configure(configuration)
            configured = true
        } catch {
            assertionFailure("Amplify configure failed: \(error)")
        }
    }
}


