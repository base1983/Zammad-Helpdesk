import Foundation

class NotificationProxyService {
    static let shared = NotificationProxyService()
    
    private let proxyBaseURL = URL(string: "https://zammadproxy.world-ict.nl/api/")!

    private init() {}

    func getWebhookURL() -> String {
        let userID = SettingsManager.shared.getProxyUserID()
        return proxyBaseURL.appendingPathComponent("webhook/\(userID)").absoluteString
    }

    func updateRegistration(isSubscribing: Bool) async {
        guard let deviceToken = SettingsManager.shared.loadDeviceToken() else {
            print("Device token not available, cannot update registration.")
            return
        }
        
        let endpoint = isSubscribing ? "register" : "unregister"
        let url = proxyBaseURL.appendingPathComponent(endpoint)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = RegistrationPayload(
            deviceToken: deviceToken,
            proxyUserID: SettingsManager.shared.getProxyUserID(),
            zammadURL: SettingsManager.shared.loadServerURL(),
            zammadToken: SettingsManager.shared.loadToken() ?? ""
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Successfully updated registration (subscribed: \(isSubscribing)) with proxy server.")
            } else {
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("Failed to update registration. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0), Body: \(responseBody)")
            }
        } catch {
            print("Error updating registration with proxy server: \(error)")
        }
    }
    
    private struct RegistrationPayload: Codable {
        let deviceToken: String
        let proxyUserID: String
        let zammadURL: String
        let zammadToken: String
    }
}

