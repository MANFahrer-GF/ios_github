import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Query private var locations: [Location]

    var body: some View {
        if model.onboardingDone || !locations.isEmpty {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            OverviewView().tabItem { Label("Übersicht", systemImage: "house.fill") }
            MonthCalendarView().tabItem { Label("Kalender", systemImage: "calendar") }
            WasteListView().tabItem { Label("Müll", systemImage: "trash.fill") }
            BirthdayListView().tabItem { Label("Geburtstage", systemImage: "birthday.cake.fill") }
            MoreView().tabItem { Label("Mehr", systemImage: "ellipsis.circle.fill") }
        }
    }
}
