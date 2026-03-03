# Apple Watch App - Quick Start Checklist

Use this checklist to quickly set up your Apple Watch companion app.

## ✅ Phase 1: Xcode Setup (15 minutes)

### Create Watch Target
- [ ] File → New → Target → Watch App
- [ ] Name: "Zammad Helpdesk Watch App"
- [ ] Bundle ID: `com.worldict.helpdesk.watchkitapp`
- [ ] Minimum deployment: watchOS 10.0+

### Add Watch Files
- [ ] Copy all files from `/Watch/` folder to Watch target in Xcode
- [ ] Files: WatchTicketListView.swift, WatchTicketDetailView.swift, WatchTicketViewModel.swift, Zammad_HelpdeskApp_Watch.swift

### Share iOS Files with Watch Target
Select each file → File Inspector → Check "Zammad Helpdesk Watch App" target:

**Models & Data:**
- [ ] Models.swift
- [ ] Extensions.swift

**Services:**
- [ ] ZammadAPIService.swift
- [ ] SettingsManager.swift

**Localization:**
- [ ] All Localizable.strings files

**iOS Only (don't share with Watch):**
- [ ] WatchConnectivityManager.swift (iOS target only)

---

## ✅ Phase 2: iOS Integration (10 minutes)

### Update AppDelegate
Open `Zammad_HelpdeskApp.swift`:

```swift
// Add at top
import WatchConnectivity

// In application(_:didFinishLaunchingWithOptions:)
// Add before return true:
if WCSession.isSupported() {
    _ = WatchConnectivityManager.shared
}
```

### Update TicketViewModel
Open `TicketViewModel.swift`:

Find the `loadData(filter:isFullRefresh:)` method, after this line:
```swift
self.updateApplicationBadge()
```

Add:
```swift
#if os(iOS)
WatchConnectivityManager.shared.transferTicketsToWatch(self.currentTickets)
WatchConnectivityManager.shared.transferMetadataToWatch(
    states: self.ticketStates,
    priorities: self.ticketPriorities,
    users: self.allUsers,
    roles: self.roles
)
#endif
```

---

## ✅ Phase 3: App Groups (Optional but Recommended) (5 minutes)

### Enable App Groups for iOS
- [ ] Select iOS target → Signing & Capabilities
- [ ] Click "+ Capability"
- [ ] Add "App Groups"
- [ ] Click "+" and add: `group.com.worldict.helpdesk`

### Enable App Groups for Watch
- [ ] Select Watch target → Signing & Capabilities
- [ ] Add "App Groups" capability
- [ ] Check the same group: `group.com.worldict.helpdesk`

### Update SettingsManager
Open `SettingsManager.swift`, replace `UserDefaults.standard` with:

```swift
private static let sharedDefaults = UserDefaults(
    suiteName: "group.com.worldict.helpdesk"
) ?? .standard
```

Then replace all `UserDefaults.standard` calls with `sharedDefaults`

---

## ✅ Phase 4: Build & Test (5 minutes)

### First Build - iOS
- [ ] Select "Zammad Helpdesk" scheme
- [ ] Choose iPhone simulator
- [ ] ⌘R to build and run
- [ ] App should launch normally

### Second Build - Watch
- [ ] Select "Zammad Helpdesk Watch App" scheme
- [ ] Choose "Apple Watch Series 9" (or later) simulator
- [ ] ⌘R to build and run
- [ ] Both iOS and Watch simulators should launch

### Test Core Features
- [ ] Watch app shows ticket list
- [ ] Can filter tickets (Menu → Filter)
- [ ] Can open ticket details
- [ ] Can change ticket status
- [ ] Can change ticket priority
- [ ] Can reassign ticket owner
- [ ] Changes sync back to iOS app

---

## ✅ Phase 5: Polish (Optional)

### Add Complications (Advanced)
- [ ] Create Widget Extension target
- [ ] Use `WatchComplicationController.swift` code
- [ ] Share necessary files with widget target
- [ ] Test complications on watch face

### Add Settings Indicator
In `SettingsView.swift`, add this view:

```swift
Section("Devices") {
    HStack {
        Image(systemName: "applewatch")
        Text("Apple Watch")
        Spacer()
        Circle()
            .fill(WatchConnectivityManager.shared.reachable ? Color.green : Color.gray)
            .frame(width: 8, height: 8)
        Text(WatchConnectivityManager.shared.reachable ? "Connected" : "Not Connected")
            .font(.caption)
    }
}
```

---

## 🎯 Success Criteria

Your Watch app is ready when:

✅ Watch app launches without crashes  
✅ Ticket list displays tickets  
✅ Filtering works correctly  
✅ Ticket details open and display data  
✅ Status changes save to API  
✅ Priority changes save to API  
✅ Owner reassignment works  
✅ Error states display properly  
✅ Empty states display properly  

---

## 🐛 Common Issues & Fixes

### Issue: "No such module 'WatchConnectivity'"
**Fix:** Make sure you imported it: `import WatchConnectivity`

### Issue: Watch app crashes on launch
**Fix:** Check that all shared files are added to Watch target

### Issue: "Cannot find type 'Ticket' in scope"
**Fix:** Add Models.swift to Watch target (File Inspector)

### Issue: API calls fail on Watch
**Fix:** 
1. Ensure SettingsManager is shared with Watch target
2. Use App Groups to share UserDefaults
3. Check that ZammadAPIService is in Watch target

### Issue: Ticket list is empty
**Fix:**
1. Check API credentials in SettingsManager
2. Verify network requests aren't blocked
3. Check console for API error messages

### Issue: Changes don't sync between iOS and Watch
**Fix:**
1. Verify WCSession.isSupported() returns true
2. Check WatchConnectivityManager is initialized in both apps
3. Both apps need to be running (iOS can be in background)

---

## 📱 Testing on Real Devices

### Before Testing on Physical Watch:
1. Pair Apple Watch with iPhone
2. Install iOS app on iPhone first
3. Watch app will install automatically (or via Watch app on iPhone)
4. Launch iOS app and log in
5. Open Watch app
6. Data should sync automatically

### Debugging on Device:
1. Connect iPhone to Mac
2. Open Xcode → Window → Devices and Simulators
3. Select your iPhone
4. View console logs for both iOS and Watch apps
5. Look for WCSession and API error messages

---

## 📚 Additional Resources

- **Full Setup Guide:** See `WATCH_APP_SETUP.md`
- **iOS Integration:** See `iOS_WATCH_INTEGRATION.swift`
- **Complications:** See `Watch/WatchComplicationController.swift`

- **Apple Documentation:**
  - [WatchKit](https://developer.apple.com/documentation/watchkit)
  - [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity)
  - [watchOS Design Guidelines](https://developer.apple.com/design/human-interface-guidelines/watchos)

---

## 🎉 Next Steps

Once your Watch app is working:

1. **Test thoroughly** on all watch sizes (40mm, 44mm, 49mm)
2. **Optimize performance** (reduce network calls, cache data)
3. **Add haptic feedback** for actions
4. **Improve error handling** with better messages
5. **Add complications** for quick glances
6. **Submit to App Store** with Watch app screenshots

---

**Estimated Total Setup Time: 35-45 minutes**

Good luck with your Apple Watch app! 🚀⌚️
