import SwiftUI
import SwiftData
import TonneCore

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
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            OverviewView().tabItem { Label("Übersicht", systemImage: "house.fill") }.tag(AppTab.overview)
            MonthCalendarView().tabItem { Label("Kalender", systemImage: "calendar") }.tag(AppTab.calendar)
            WasteListView().tabItem { Label("Müll", systemImage: "trash.fill") }.tag(AppTab.waste)
            BirthdayListView().tabItem { Label(L10n.t("Termine", "Events"), systemImage: "birthday.cake.fill") }.tag(AppTab.birthdays)
            MoreView().tabItem { Label("Mehr", systemImage: "ellipsis.circle.fill") }.tag(AppTab.more)
        }
    }
}
