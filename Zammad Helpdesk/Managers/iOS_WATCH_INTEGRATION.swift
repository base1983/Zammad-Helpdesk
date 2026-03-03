//
//  iOS App Watch Integration.swift
//  Code snippets to add Watch support to your iOS app
//

/*
 STEP 1: Import WatchConnectivity in Zammad_HelpdeskApp.swift
 
 Add this import at the top:
*/

import WatchConnectivity

/*
 STEP 2: Activate Watch Connectivity in AppDelegate
 
 Add this to the end of application(_:didFinishLaunchingWithOptions:)
*/

extension AppDelegate {
    func setupWatchConnectivity() {
        if WCSession.isSupported() {
            _ = WatchConnectivityManager.shared // Initialize the manager
        }
    }
}

/*
 Then call it in didFinishLaunchingWithOptions:
 
 func application(_ application: UIApplication, didFinishLaunchingWithOptions...) -> Bool {
     // ... existing code ...
     
     setupWatchConnectivity()
     
     return true
 }
*/

/*
 STEP 3: Add Watch Sync to TicketViewModel
 
 Add this method to TicketViewModel class:
*/

extension TicketViewModel {
    func syncToWatch() {
        #if os(iOS)
        WatchConnectivityManager.shared.transferTicketsToWatch(currentTickets)
        WatchConnectivityManager.shared.transferMetadataToWatch(
            states: ticketStates,
            priorities: ticketPriorities,
            users: allUsers,
            roles: roles
        )
        #endif
    }
}

/*
 STEP 4: Call syncToWatch() after data refreshes
 
 In the loadData(filter:isFullRefresh:) method, add this after successful load:
 
 self.currentTickets = tickets
 self.errorMessage = nil
 self.updateApplicationBadge()
 
 // ADD THIS:
 #if os(iOS)
 self.syncToWatch()
 #endif
*/

/*
 STEP 5: Handle Watch-initiated updates (Optional)
 
 Add these observers in TicketViewModel init:
*/

extension TicketViewModel {
    func setupWatchNotificationObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: .refreshTicketsFromWatch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.refreshAllData()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .ticketUpdatedFromWatch,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let ticketID = notification.userInfo?["ticketID"] as? Int {
                Task {
                    await self?.refreshAllData()
                }
            }
        }
        #endif
    }
}

/*
 STEP 6: Optional - Add Watch Status Indicator to Settings
 
 Add this to SettingsView.swift to show Watch connection status:
*/

struct WatchConnectionRow: View {
    @ObservedObject var connectivity = WatchConnectivityManager.shared
    
    var body: some View {
        HStack {
            Image(systemName: "applewatch")
                .foregroundColor(.accentColor)
            
            Text("Apple Watch")
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(connectivity.reachable ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(connectivity.reachable ? "Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/*
 Then add it to your SettingsView:
 
 Section("Devices") {
     WatchConnectionRow()
 }
*/

/*
 STEP 7: Update SettingsManager to use App Groups (for sharing credentials)
 
 If you want the Watch to access API credentials without iOS app running:
*/

extension SettingsManager {
    // Change from UserDefaults.standard to shared suite
    private static let sharedDefaults = UserDefaults(
        suiteName: "group.com.worldict.helpdesk"
    ) ?? .standard
    
    // Then in each method, replace UserDefaults.standard with sharedDefaults
    static func loadAPIToken() -> String? {
        return sharedDefaults.string(forKey: "api_token")
    }
    
    static func saveAPIToken(_ token: String) {
        sharedDefaults.set(token, forKey: "api_token")
    }
    
    // Do the same for loadAPIUrl() and other settings
}

/*
 IMPORTANT: If you use App Groups, you must:
 1. Enable App Groups capability in iOS target
 2. Enable App Groups capability in Watch target  
 3. Use the same group ID: "group.com.worldict.helpdesk"
*/

/*
 STEP 8: Test Everything
 
 1. Build iOS app first
 2. Build and run Watch app
 3. Both should launch
 4. Check console for WCSession activation messages
 5. Refresh tickets on iOS and verify they appear on Watch
 6. Change ticket status on Watch and verify it updates on iOS
*/

/*
 TROUBLESHOOTING:
 
 Problem: Watch app won't install
 Solution: Check bundle IDs are correct:
   - iOS: com.worldict.helpdesk
   - Watch: com.worldict.helpdesk.watchkitapp
 
 Problem: Watch can't connect to API
 Solution: 
   - Make sure SettingsManager uses App Groups
   - Verify Watch has network permissions
   - Check that ZammadAPIService is added to Watch target
 
 Problem: Data doesn't sync
 Solution:
   - Verify WCSession.isSupported() returns true
   - Check both apps are running (iOS can be background)
   - Look for connectivity errors in console
 
 Problem: Compile errors in Watch target
 Solution:
   - Make sure all required files are added to Watch target
   - Check that Models.swift is in both targets
   - Verify Extensions.swift is in both targets
*/
