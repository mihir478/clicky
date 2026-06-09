//
//  DiagnoseAPIClient.swift
//  leanring-buddy
//
//  Forwards a screen/error signal to AgentGateway's AG-CTO companion via the
//  Clicky Worker /diagnose route, and returns the grounded diagnosis. Clicky's
//  job is the screen + the voice; AgentGateway's job is reaching into the
//  systems Clicky can't see (AWS/IAM, provider consoles) and learning over time.
//

import Foundation

/// One AG-CTO diagnosis. Decodes the subset of the /diagnose response the app
/// needs; extra fields (toolsReached, recall, …) are ignored by the decoder.
struct CompanionDiagnosis: Decodable {
    let source: String   // "memory" (recalled) | "llm" (fresh) | "unavailable"
    let backend: String  // "pgvector" | "in-memory"
    let rootCause: String
    let fix: String
    let spoken: String   // TTS-ready summary, spoken back to the user
    let confidence: Double
    let learned: Bool
}

@MainActor
final class DiagnoseAPIClient {
    private let proxyURL: URL
    private let session: URLSession

    init(proxyURL: String) {
        self.proxyURL = URL(string: proxyURL)!

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Sends `signal` (the error the user read aloud or described) to the AG-CTO
    /// companion and returns its diagnosis. Throws on network/non-2xx/decoding.
    func diagnose(signal: String, surface: String? = nil) async throws -> CompanionDiagnosis {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = ["signal": signal]
        if let surface {
            payload["context"] = ["surface": surface]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "DiagnoseAPI",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "diagnose request failed (HTTP \(statusCode))"]
            )
        }

        return try JSONDecoder().decode(CompanionDiagnosis.self, from: data)
    }
}
