import CryptoKit
import Foundation

struct HostedGameFeedEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let payload: String
    let signature: String
}

struct HostedGameFeed: Codable, Equatable {
    let schemaVersion: Int
    let publishedAt: String
    let release: GameRelease

    func validate() throws {
        guard schemaVersion == 1,
              ISO8601DateFormatter().date(from: publishedAt) != nil,
              let versionCode = release.versionCode,
              versionCode > 0 else {
            throw LauncherError.invalidManifest("Invalid hosted TFT feed")
        }
        try release.validate()
        for apk in release.apks {
            guard let url = apk.url,
                  url.scheme == "https",
                  url.host == MacticianIdentity.gameUpdateURL.host,
                  url.user == nil,
                  url.password == nil,
                  url.query == nil,
                  url.fragment == nil,
                  url.path.hasPrefix("/mactician/updates/game/releases/") else {
                throw LauncherError.invalidManifest("APK \(apk.name) uses an untrusted URL")
            }
        }
    }
}

enum HostedGameUpdate {
    static func isNewer(_ release: GameRelease, than state: InstallState) -> Bool {
        if let installedPackage = state.gamePackageName,
           installedPackage != release.packageName {
            return true
        }
        if let remoteVersionCode = release.versionCode,
           let installedVersionCode = state.gameVersionCode {
            return remoteVersionCode > installedVersionCode
        }
        return release.version != state.gameVersion
    }

    static func decodeAndVerify(
        _ envelopeData: Data,
        publicKeyBase64: String = MacticianIdentity.gameUpdatePublicKeyBase64
    ) throws -> HostedGameFeed {
        let envelope = try JSONDecoder().decode(HostedGameFeedEnvelope.self, from: envelopeData)
        guard envelope.schemaVersion == 1,
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              let publicKeyData = Data(base64Encoded: publicKeyBase64) else {
            throw LauncherError.invalidManifest("Invalid hosted TFT feed envelope")
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw LauncherError.integrity("The TFT feed public key is invalid")
        }
        guard publicKey.isValidSignature(signature, for: payload) else {
            throw LauncherError.integrity("The TFT feed signature is invalid")
        }
        let feed = try JSONDecoder().decode(HostedGameFeed.self, from: payload)
        try feed.validate()
        return feed
    }

    static func loadVerifiedFeed(from url: URL) throws -> HostedGameFeed {
        try decodeAndVerify(Data(contentsOf: url))
    }
}
