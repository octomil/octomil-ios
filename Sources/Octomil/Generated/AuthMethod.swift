// Auto-generated from octomil-contracts. Do not edit.

public enum AuthMethod: String, Codable, Sendable {
    case password = "password"
    case passkey = "passkey"
    case oauthGoogle = "oauth_google"
    case oauthApple = "oauth_apple"
    case oauthGithub = "oauth_github"
    case ssoSaml = "sso_saml"
    case devLogin = "dev_login"
}
