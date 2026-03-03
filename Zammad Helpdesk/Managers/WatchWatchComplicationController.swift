//
//  WatchComplicationController.swift
//  Zammad Helpdesk Watch App
//
//  Optional: Add complications to show unread ticket count on watch face
//

import SwiftUI
import WidgetKit

// MARK: - Complication Entry

struct TicketComplicationEntry: TimelineEntry {
    let date: Date
    let ticketCount: Int
    let relevance: TimelineEntryRelevance?
}

// MARK: - Complication Provider

struct TicketComplicationProvider: TimelineProvider {
    typealias Entry = TicketComplicationEntry
    
    func placeholder(in context: Context) -> TicketComplicationEntry {
        TicketComplicationEntry(date: Date(), ticketCount: 5, relevance: nil)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TicketComplicationEntry) -> Void) {
        let entry = TicketComplicationEntry(date: Date(), ticketCount: 5, relevance: nil)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TicketComplicationEntry>) -> Void) {
        Task {
            let count = await fetchTicketCount()
            let entry = TicketComplicationEntry(
                date: Date(),
                ticketCount: count,
                relevance: TimelineEntryRelevance(score: Float(count))
            )
            
            // Update every 15 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    private func fetchTicketCount() async -> Int {
        do {
            let tickets = try await ZammadAPIService.shared.fetchTickets(
                query: "state.name:(new OR open)"
            )
            return tickets.count
        } catch {
            print("Error fetching ticket count: \(error)")
            return 0
        }
    }
}

// MARK: - Complication View

struct TicketComplicationView: View {
    var entry: TicketComplicationEntry
    
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            VStack(spacing: 2) {
                Image(systemName: "ticket")
                    .font(.system(size: 14))
                Text("\(entry.ticketCount)")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
        }
    }
}

// MARK: - Widget Configuration

@main
struct TicketComplicationBundle: WidgetBundle {
    var body: some Widget {
        TicketComplicationWidget()
    }
}

struct TicketComplicationWidget: Widget {
    let kind: String = "TicketComplication"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: TicketComplicationProvider()
        ) { entry in
            TicketComplicationView(entry: entry)
        }
        .configurationDisplayName("Tickets")
        .description("Shows your open ticket count")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Multiple Complication Families

extension TicketComplicationView {
    @ViewBuilder
    func complicationView(for family: WidgetFamily) -> some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }
    
    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "ticket")
                    .font(.system(size: 14))
                Text("\(entry.ticketCount)")
                    .font(.system(size: 16, weight: .bold))
            }
        }
    }
    
    private var rectangularView: some View {
        HStack {
            Image(systemName: "ticket")
                .font(.system(size: 20))
            VStack(alignment: .leading) {
                Text("\(entry.ticketCount)")
                    .font(.system(size: 24, weight: .bold))
                Text("Open Tickets")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(8)
    }
    
    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "ticket")
            Text("\(entry.ticketCount)")
            Text("tickets")
        }
    }
}

/*
 SETUP INSTRUCTIONS:
 
 1. Create a new Widget Extension:
    - File → New → Target → Widget Extension
    - Name: "Zammad Helpdesk Complications"
    - Check "Include Configuration Intent" if you want customization
 
 2. Replace the generated code with this file
 
 3. Ensure these files are shared with the Widget target:
    - Models.swift
    - ZammadAPIService.swift
    - SettingsManager.swift (using App Groups)
    - Extensions.swift
 
 4. Add App Group entitlement to Widget target:
    - Same group as iOS and Watch: "group.com.worldict.helpdesk"
 
 5. Build and run Watch app
 
 6. On watch, long-press watch face → Edit → Add complication
 
 7. Select "Tickets" complication in any available slot
 
 NOTE: Complications have strict memory and CPU limits.
 Keep data fetching lightweight and cache when possible.
*/
