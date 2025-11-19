import Foundation

class NotificationProxyService {
    static let shared = NotificationProxyService()
    
    // Zorg dat deze URL exact klopt. Geen slash aan het einde.
    private let baseURL = URL(string: "https://zammadproxy.world-ict.nl/api")!

    private func sendRequest(to endpoint: String, method: String, payload: [String: Any]) async throws {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Debug: Print wat we gaan versturen
        print("DEBUG: [Proxy] URL: \(url.absoluteString)")
        // print("DEBUG: [Proxy] Payload: \(payload)") // Zet aan als je de volledige inhoud wilt zien

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check de status code
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: [Proxy] HTTP Status: \(httpResponse.statusCode)")
            
            // Als het GEEN 200-299 is, print dan de foutmelding van de server
            if !(200...299).contains(httpResponse.statusCode) {
                if let serverError = String(data: data, encoding: .utf8) {
                    print("DEBUG: [Proxy] SERVER FOUTMELDING: \(serverError)")
                }
                throw URLError(.badServerResponse)
            }
        }
        
        print("DEBUG: [Proxy] Verzoek geslaagd.")
    }
    
    func updateRegistration(isSubscribing: Bool) async {
        print("DEBUG: [Proxy] Start registratie update (Inschrijven: \(isSubscribing))...")

        // 1. Haal waarden op en check of ze niet leeg zijn
        guard let deviceToken = SettingsManager.shared.loadDeviceToken(), !deviceToken.isEmpty else {
            print("DEBUG: [Proxy] FOUT - Geen Device Token gevonden in Settings.")
            return
        }
        
        guard let zammadToken = SettingsManager.shared.loadToken(), !zammadToken.isEmpty else {
            print("DEBUG: [Proxy] FOUT - Geen Zammad API Token gevonden.")
            return
        }
        
        let zammadURL = SettingsManager.shared.loadServerURL()
        if zammadURL.isEmpty {
            print("DEBUG: [Proxy] FOUT - Geen Zammad Server URL gevonden.")
            return
        }

        let endpoint = isSubscribing ? "register" : "unregister"
        
        // 2. Proxy User ID Logica
        let userID: String
        if let existingUserID = SettingsManager.shared.getProxyUserID(), !existingUserID.isEmpty {
            userID = existingUserID
        } else {
            if isSubscribing {
                // Alleen bij inschrijven genereren we een nieuwe als hij mist
                let newUserID = UUID().uuidString
                SettingsManager.shared.save(proxyUserID: newUserID)
                userID = newUserID
                print("DEBUG: [Proxy] Nieuw Proxy User ID gegenereerd: \(userID)")
            } else {
                print("DEBUG: [Proxy] FOUT - Kan niet uitschrijven zonder Proxy User ID.")
                return
            }
        }
        
        // 3. Stel payload samen
        let payload: [String: Any] = [
            "deviceToken": deviceToken,
            "proxyUserID": userID,
            "zammadURL": zammadURL,
            "zammadToken": zammadToken
        ]
        
        // 4. Verstuur
        do {
            try await sendRequest(to: endpoint, method: "POST", payload: payload)
            print("DEBUG: [Proxy] updateRegistration succesvol afgerond.")
        } catch {
            print("DEBUG: [Proxy] CRITISCHE FOUT: \(error.localizedDescription)")
        }
    }
}
