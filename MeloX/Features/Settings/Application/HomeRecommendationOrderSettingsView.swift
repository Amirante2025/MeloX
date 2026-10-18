import SwiftUI

struct HomeRecommendationOrderSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            Section {
                ForEach(settings.homeRecommendations.quickActionOrder) { action in
                    Label(action.title, systemImage: action.systemImage)
                }
                .onMove { source, destination in
                    var order = settings.homeRecommendations.quickActionOrder
                    order.move(fromOffsets: source, toOffset: destination)
                    settings.homeRecommendations.setQuickActionOrder(order)
                }
            } header: {
                Text("ui.settings.home_order.quick_actions")
            } footer: {
                Text("ui.settings.home_order.quick_actions.footer")
            }

            Section {
                ForEach(settings.homeRecommendations.sectionOrder) { slot in
                    Text(slot.fallbackTitle)
                }
                .onMove { source, destination in
                    var order = settings.homeRecommendations.sectionOrder
                    order.move(fromOffsets: source, toOffset: destination)
                    settings.homeRecommendations.setSectionOrder(order)
                }
            } header: {
                Text("ui.settings.home_order.sections")
            } footer: {
                Text("ui.settings.home_order.sections.footer")
            }

            Section {
                Button(
                    "ui.settings.home_order.reset",
                    systemImage: "arrow.counterclockwise"
                ) {
                    settings.homeRecommendations.reset()
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("ui.settings.home_order.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
