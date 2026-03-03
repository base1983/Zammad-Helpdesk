# Apple Watch Companion App Setup Guide

This guide will help you set up the Apple Watch companion app for Zammad Helpdesk.

## Architecture Overview

The Watch app uses:
- **Shared Models** - Ticket, User, TicketState, TicketPriority models
- **Shared API Service** - ZammadAPIService for network requests
- **Watch Connectivity** - For syncing data between iOS and watchOS
- **Dedicated Watch Views** - Optimized for small screen

## Step 1: Create Watch App Target in Xcode

1. **Add Watch App Target**
   - File → New → Target
   - Choose "Watch App"
   - Product Name: "Zammad Helpdesk Watch App"
   - Select "watchOS" as platform
   - Choose minimum deployment target (watchOS 10.0 or later)

2. **Configure Bundle Identifiers**
   - iOS App: `com.worldict.helpdesk`
   - Watch App: `com.worldict.helpdesk.watchkitapp`

## Step 2: Share Files Between iOS and Watch Targets

In Xcode, select these files and enable both targets in File Inspector:

### Models to Share:
- ✅ `Models.swift` (Ticket, User, TicketState, TicketPriority, etc.)
- ✅ `Extensions.swift` (String.localized(), Date.timeAgoDisplay())

### Services to Share:
- ✅ `ZammadAPIService.swift`
- ✅ `APIError.swift` (if you have one)
- ✅ `SettingsManager.swift` (for API credentials)

### Localizations to Share:
- ✅ All `.strings` files in your localization folders

### Watch-Specific Files (Watch Target Only):
- ✅ `Watch/WatchTicketListView.swift`
- ✅ `Watch/WatchTicketDetailView.swift`
- ✅ `Watch/WatchTicketViewModel.swift`
- ✅ `Watch/Zammad_HelpdeskApp_Watch.swift`

### iOS-Specific (Add to iOS Target):
- ✅ `WatchConnectivityManager.swift`

## Step 3: Update iOS App to Support Watch Connectivity

Add to your `Zammad_HelpdeskApp.swift` or `AppDelegate`:

```swift
import WatchConnectivity

// In your App struct or AppDelegate init/didFinishLaunching:
if WCSession.isSupported() {
    WCSession.default.delegate = WatchConnectivityManager.shared
    WCSession.default.activate()
}
```

Update `TicketViewModel` to sync with Watch:

```swift
func refreshAllData() async {
    await loadData(filter: activeFilter, isFullRefresh: true)
    
    // Sync to watch when data is refreshed
    WatchConnectivityManager.shared.transferTicketsToWatch(currentTickets)
    WatchConnectivityManager.shared.transferMetadataToWatch(
        states: ticketStates,
        priorities: ticketPriorities,
        users: allUsers,
        roles: roles
    )
}
```

## Step 4: Configure Capabilities

### iOS App Target:
1. Select iOS app target → Signing & Capabilities
2. Click "+ Capability"
3. Add "Background Modes"
4. Enable "Background fetch" and "Remote notifications"

### Watch App Target:
1. Select Watch app target → Signing & Capabilities
2. Capabilities should automatically inherit from iOS app
3. Ensure App Groups are matching if you use them

## Step 5: Update Info.plist Files

### Watch App Info.plist:
```xml
<key>WKCompanionAppBundleIdentifier</key>
<string>com.worldict.helpdesk</string>
<key>WKWatchOnly</key>
<false/>
```

## Step 6: Add Required Entitlements

If using App Groups for shared data:

1. iOS Target → Signing & Capabilities → + Capability → App Groups
2. Add group: `group.com.worldict.helpdesk`
3. Repeat for Watch Target

Update `SettingsManager` to use shared container:
```swift
private static let sharedDefaults = UserDefaults(suiteName: "group.com.worldict.helpdesk")!
```

## Step 7: Build and Run

1. **Select Watch Simulator/Device**
   - Choose "Zammad Helpdesk Watch App" scheme
   - Select Apple Watch Series 9 (or your watch) simulator

2. **Build and Run**
   - ⌘R to run on Watch simulator
   - The iOS app will automatically launch in companion

3. **Test Features**:
   - ✅ View list of tickets
   - ✅ Filter by My Tickets, Unassigned, All Open
   - ✅ Open ticket details
   - ✅ Change ticket status
   - ✅ Change ticket priority
   - ✅ Reassign ticket owner

## Features Implemented

### ✅ Ticket List View
- View all tickets with filtering
- Pull to refresh
- See ticket number, title, status, and last update time
- Status color indicators

### ✅ Ticket Detail View
- Full ticket information
- Customer name
- Current status with color indicator
- Priority level
- Assigned owner
- Creation date

### ✅ Quick Actions
- **Change Status** - Sheet with all available statuses
- **Change Priority** - Sheet with priority options
- **Reassign Owner** - Sheet with list of agent users
- Changes save immediately via API

### ✅ Smart Features
- Automatic pending time handling (sets 1 hour by default)
- Color-coded status indicators
- Localized strings support
- Error handling with retry options
- Empty state views

## Watch App Design Considerations

The Watch app is optimized for:
- **Glanceable Information** - Quick status checks
- **Quick Actions** - Fast status/priority/owner changes
- **Simplified UI** - No article viewing (too much text for watch)
- **Battery Efficiency** - Uses background transfers when possible

## Data Synchronization

The app uses two methods for syncing:

1. **Real-time Updates** (when watch is reachable):
   ```swift
   WatchConnectivityManager.shared.sendTicketsToWatch(tickets)
   ```

2. **Background Transfers** (when watch is not reachable):
   ```swift
   WatchConnectivityManager.shared.transferTicketsToWatch(tickets)
   ```

## Limitations & Future Enhancements

### Current Limitations:
- ❌ No article viewing (screen too small)
- ❌ No ticket creation (complex for watch)
- ❌ No reply to tickets
- ❌ No time accounting entry

### Possible Future Features:
- 📱 Complications showing unread ticket count
- 📱 Quick reply with voice dictation
- 📱 Mark as read/unread from watch
- 📱 Push notifications on watch
- 📱 Handoff support (continue on iPhone)

## Troubleshooting

### Watch App Not Installing:
1. Ensure both iOS and Watch apps have correct bundle IDs
2. Check that WKCompanionAppBundleIdentifier matches iOS app
3. Clean build folder (Shift+⌘K) and rebuild

### Data Not Syncing:
1. Check Watch Connectivity activation in both apps
2. Verify both apps are running (iOS in background is OK)
3. Check console logs for connectivity errors

### API Errors on Watch:
1. Ensure SettingsManager is shared between targets
2. Verify API token is accessible on watch
3. Check network permissions in Watch app

## Testing Checklist

- [ ] Watch app launches successfully
- [ ] Ticket list loads and displays
- [ ] Filtering works (My Tickets, Unassigned, All Open)
- [ ] Ticket details view opens
- [ ] Status picker displays and saves changes
- [ ] Priority picker displays and saves changes
- [ ] Owner picker displays and saves changes
- [ ] Error states display correctly
- [ ] Empty states display correctly
- [ ] Loading states display correctly
- [ ] Colors match iOS app design
- [ ] Localization works correctly

## App Store Submission Notes

When submitting to App Store:
1. Include Watch app in iOS app submission
2. Provide Watch app screenshots (required)
3. Describe Watch app features in App Store description
4. Test on physical Apple Watch before submission
5. Ensure Watch app follows Apple Watch Human Interface Guidelines

## Support & Maintenance

The Watch app shares most code with iOS app, so:
- Model changes automatically propagate
- API updates work on both platforms
- Bug fixes often apply to both apps
- Keep watchOS deployment target up to date

---

**Need Help?** Check Apple's documentation:
- [WatchKit Programming Guide](https://developer.apple.com/documentation/watchkit)
- [Watch Connectivity Framework](https://developer.apple.com/documentation/watchconnectivity)
- [Human Interface Guidelines for watchOS](https://developer.apple.com/design/human-interface-guidelines/watchos)
