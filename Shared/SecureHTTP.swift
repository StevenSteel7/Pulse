import Foundation
import Security
import CryptoKit

struct SecureHTTPResponse {
    let data: Data
    let status: Int
    let fingerprint: String?
}

enum ConnectionSecurityError: LocalizedError {
    case invalidRequest, certificateChanged, oversizedResponse, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Invalid secure connection request."
        case .certificateChanged: return "The device certificate changed. Re-pair the device to verify its identity."
        case .oversizedResponse: return "The device returned an unexpectedly large response."
        case .invalidResponse: return "The device returned an invalid response."
        }
    }
}

/// A separate, ephemeral session per request. Enrollment probes alone may
/// observe an unknown certificate; they send no credentials and require an
/// HMAC proof bound to that exact certificate before any approval is possible.
final class SecureHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let pin: String?
    private let discovery: Bool
    private var session: URLSession?
    private var continuation: CheckedContinuation<SecureHTTPResponse, Error>?
    private var buffer = Data()
    private var response: HTTPURLResponse?
    private var fingerprint: String?
    private var securityError: Error?
    private let maximumBytes = 1_048_576

    private init(request: URLRequest, pin: String?, discovery: Bool) {
        self.request = request
        self.pin = pin
        self.discovery = discovery
    }

    static func send(_ request: URLRequest, pin: String? = nil, discovery: Bool = false) async throws -> SecureHTTPResponse {
        if discovery {
            guard request.url?.scheme == "https", request.url?.path == "/pairing",
                  request.httpMethod == "GET", request.httpBody == nil,
                  request.value(forHTTPHeaderField: "X-API-Key") == nil,
                  request.value(forHTTPHeaderField: "Authorization") == nil else { throw ConnectionSecurityError.invalidRequest }
        }
        if pin != nil && request.url?.scheme != "https" { throw ConnectionSecurityError.invalidRequest }
        let handler = SecureHTTP(request: request, pin: pin, discovery: discovery)
        return try await handler.run()
    }

    private func run() async throws -> SecureHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForResource = max(5, request.timeoutInterval)
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.protectionSpace.host.lowercased() == request.url?.host?.lowercased(),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let data = SecCertificateCopyData(certificate) as Data
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        fingerprint = actual
        if let pin {
            guard actual == pin else {
                securityError = ConnectionSecurityError.certificateChanged
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else if discovery {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a credential or enrollment proof to another endpoint.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            securityError = ConnectionSecurityError.invalidResponse
            completionHandler(.cancel)
            return
        }
        self.response = response
        guard response.expectedContentLength <= maximumBytes else {
            securityError = ConnectionSecurityError.oversizedResponse
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard buffer.count + data.count <= maximumBytes else {
            securityError = ConnectionSecurityError.oversizedResponse
            dataTask.cancel()
            return
        }
        buffer.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.invalidateAndCancel(); self.session = nil; continuation = nil }
        if let error = securityError ?? error { continuation?.resume(throwing: error) }
        else if let response { continuation?.resume(returning: SecureHTTPResponse(data: buffer, status: response.statusCode, fingerprint: fingerprint)) }
        else { continuation?.resume(throwing: ConnectionSecurityError.invalidResponse) }
    }
}
