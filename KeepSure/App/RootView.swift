import SwiftUI
import UIKit

struct RootView: View {
    private enum Tab: Hashable {
        case home
        case capture
        case profile
    }

    @State private var selectedTab: Tab = .home
    @EnvironmentObject private var notificationManager: SmartNotificationManager
    @EnvironmentObject private var securityManager: AppSecurityManager

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
        .onChange(of: notificationManager.pendingDeepLink?.id) { _, newValue in
            guard newValue != nil else { return }
            selectedTab = .home
        }
        .overlay {
            if securityManager.isLocked {
                SecurityLockOverlay(
                    subtitle: securityManager.protectionStatusLine,
                    unlockAction: {
                        Task {
                            await securityManager.unlock()
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .alert("App lock", isPresented: Binding(
            get: { securityManager.errorMessage != nil },
            set: { if !$0 { securityManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(securityManager.errorMessage ?? "")
        }
    }
}

private struct SecurityLockOverlay: View {
    let subtitle: String
    let unlockAction: () -> Void

    var body: some View {
        ZStack {
            AppTheme.homeBackground
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: AppTheme.accent.opacity(0.16), radius: 24, y: 12)

                VStack(spacing: 10) {
                    Text("Keep Sure is locked")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text(subtitle)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))
                }

                Button(action: unlockAction) {
                    HStack(spacing: 10) {
                        Image(systemName: "faceid")
                            .font(.headline.weight(.bold))
                        Text("Unlock")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(AppTheme.panelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 28, y: 16)
            )
            .padding(24)
        }
    }
}
