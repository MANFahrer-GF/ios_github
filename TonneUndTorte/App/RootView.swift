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
        // Antippen des schon gewählten Tabs führt zurück auf dessen Startseite, statt in einer Unterseite hängen zu bleiben
        let selection = Binding<AppTab>(get: { model.selectedTab }, set: { tab in
            if tab == model.selectedTab { model.tabResets[tab, default: 0] += 1 }
            model.selectedTab = tab
        })
        TabView(selection: selection) {
            OverviewView().id(model.tabResets[.overview, default: 0]).tabItem { Label("Übersicht", systemImage: "house.fill") }.tag(AppTab.overview)
            MonthCalendarView().id(model.tabResets[.calendar, default: 0]).tabItem { Label("Kalender", systemImage: "calendar") }.tag(AppTab.calendar)
            WasteListView().id(model.tabResets[.waste, default: 0]).tabItem { Label("Müll", systemImage: "trash.fill") }.tag(AppTab.waste)
            BirthdayListView().id(model.tabResets[.birthdays, default: 0]).tabItem { Label(L10n.t("Termine", "Events"), systemImage: "birthday.cake.fill") }.tag(AppTab.birthdays)
            MoreView().id(model.tabResets[.more, default: 0]).tabItem { Label("Mehr", systemImage: "ellipsis.circle.fill") }.tag(AppTab.more)
        }
    }
}
