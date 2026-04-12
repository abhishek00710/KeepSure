import SwiftUI
import UIKit

struct RootView: View {
    private enum Tab: Hashable {
        case home
        case capture
        case profile
    }

    @State private var selectedTab: Tab = .home

//    init() {
//        let appearance = UITabBarAppearance()
//        appearance.configureWithOpaqueBackground()
//        appearance.backgroundEffect = nil
//        appearance.backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1)
//        appearance.shadowColor = UIColor(red: 0.86, green: 0.82, blue: 0.76, alpha: 0.55)
//
//        let normalColor = UIColor(red: 0.42, green: 0.36, blue: 0.30, alpha: 0.75)
//        let selectedColor = UIColor(red: 0.70, green: 0.58, blue: 0.39, alpha: 1)
//
//        [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance].forEach { itemAppearance in
//            itemAppearance.normal.iconColor = normalColor
//            itemAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
//            itemAppearance.selected.iconColor = selectedColor
//            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
//        }
//
//        UITabBar.appearance().standardAppearance = appearance
//        UITabBar.appearance().scrollEdgeAppearance = appearance
//        UITabBar.appearance().isTranslucent = false
//    }

    var body: some View {
        ZStack {
            AppTheme.homeBackground
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView()
                }
                .tabItem {
                    Label {
                        Text("Home")
                    } icon: {
                        Image(systemName: "house.fill")
                            .symbolEffect(.bounce.down.byLayer, value: selectedTab == .home)
                    }
                }
                .tag(Tab.home)

                NavigationStack {
                    CaptureView()
                }
                .tabItem {
                    Label {
                        Text("Capture")
                    } icon: {
                        Image(systemName: "viewfinder.circle.fill")
                            .symbolEffect(.bounce.down.byLayer, value: selectedTab == .capture)
                    }
                }
                .tag(Tab.capture)

                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label {
                        Text("Profile")
                    } icon: {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolEffect(.bounce.down.byLayer, value: selectedTab == .profile)
                    }
                }
                .tag(Tab.profile)
            }
        }
        .tint(AppTheme.accent)
        .animation(.easeInOut(duration: 0.22), value: selectedTab)
    }
}
