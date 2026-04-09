import Foundation
import CommonCrypto

/// A URLSession configured with TLS certificate pinning for the Supabase endpoint.
///
/// Pins the intermediate CA public key (Google Trust Services WE1) so the pin
/// survives leaf cert renewals. Includes the root CA (GTS Root R4) as a backup
/// in case the intermediate rotates.
///
/// Usage: Replace `URLSession.shared.data(for: req)` with
/// `PinnedURLSession.shared.data(for: req)` in any service that talks to Supabase.
enum PinnedURLSession {

    /// The pinned host — only Supabase connections are pinned.
    static let pinnedHost = "erghbsnxtsbnmfuycnyb.supabase.co"

    /// SHA-256 hashes of the Subject Public Key Info (SPKI) for trusted certs.
    /// Intermediate CA: Google Trust Services WE1
    /// Root CA: GTS Root R4 (backup)
    static let pinnedHashes: Set<String> = [
        "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=", // WE1 intermediate
        "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=", // GTS Root R4
    ]

    /// Shared session with certificate pinning enabled.
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config, delegate: PinningDelegate(), delegateQueue: nil)
    }()

    static func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

// MARK: - Pinning Delegate

private final class PinningDelegate: NSObject, URLSessionDelegate {

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == PinnedURLSession.pinnedHost,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Walk the certificate chain and check each cert's public key hash.
        guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var matched = false
        for cert in certChain {
            guard let publicKey = SecCertificateCopyKey(cert) else { continue }
            var error: Unmanaged<CFError>?
            guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
                continue
            }

            let hash = PinnedURLSession.sha256(data: publicKeyData)
            let base64Hash = hash.base64EncodedString()

            if PinnedURLSession.pinnedHashes.contains(base64Hash) {
                matched = true
                break
            }
        }

        if matched {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            print("[PinnedURLSession] Certificate pin mismatch — rejecting connection")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
