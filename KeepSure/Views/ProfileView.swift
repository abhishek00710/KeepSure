import CoreData
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var emailSyncManager: EmailSyncManager
    @EnvironmentObject private var appModeManager: AppModeManager
    @EnvironmentObject private var notificationManager: SmartNotificationManager
    @AppStorage("email_sync_enabled") private var emailSyncEnabled = true
    @AppStorage("gmail_launch_prompt_deferred") private var gmailLaunchPromptDeferred = false
    @AppStorage("smart_alerts_enabled") private var smartAlertsEnabled = true
    @AppStorage("family_sharing_enabled") private var familySharingEnabled = true
    @State private var pendingModeSwitch: AppMode?

    @FetchRequest(fetchRequest: PurchaseRecord.recentFetchRequest, animation: .snappy)
    private var purchases: FetchedResults<PurchaseRecord>

    private var hasPurchases: Bool {
        !purchases.isEmpty
    }

    private var totalValue: Double {
        purchases.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHero
                    .softEntrance(delay: 0.02)
                householdPanel
                    .softEntrance(delay: 0.07)
                connectionPanel
                    .softEntrance(delay: 0.12)
                preferencesPanel
                    .softEntrance(delay: 0.17)
                privacyPanel
                    .softEntrance(delay: 0.22)
                modePanel
                    .softEntrance(delay: 0.27)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(screenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Gmail sync issue", isPresented: Binding(
            get: { emailSyncManager.errorMessage != nil },
            set: { if !$0 { emailSyncManager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(emailSyncManager.errorMessage ?? "")
        }
        .confirmationDialog(
            pendingModeSwitch == .demo ? "Switch to Demo mode?" : "Switch to Live mode?",
            isPresented: Binding(
                get: { pendingModeSwitch != nil },
                set: { if !$0 { pendingModeSwitch = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingModeSwitch {
                Button(pendingModeSwitch == .live ? "Switch to Live mode" : "Switch to Demo mode") {
                    Task {
                        await applyModeSwitch(pendingModeSwitch)
                        self.pendingModeSwitch = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    self.pendingModeSwitch = nil
                }
            }
        } message: {
            Text(pendingModeSwitch?.resetSummary ?? "")
        }
    }

    private var screenBackground: some View {
        ZStack {
            AppTheme.homeBackground
                .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.56))
                .frame(width: 250, height: 250)
                .blur(radius: 24)
                .offset(x: 170, y: -240)

            Circle()
                .fill(AppTheme.accent.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 26)
                .offset(x: -130, y: -100)
        }
    }

    private var profileHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep Sure")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(AppTheme.accent)

            Text("Your protection profile")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text(
                hasPurchases
                    ? "Everything that makes Keep Sure feel protective lives here: your household, your connections, your alerts, and the rules behind them."
                    : "This is where your protection rhythm begins: household sharing, Gmail connection, thoughtful alerts, and a calmer system around every purchase."
            )
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.82))

            HStack(spacing: 12) {
                if hasPurchases {
                    profileMetric(title: "Tracked", value: "\(purchases.count)", subtitle: purchases.count == 1 ? "item" : "items")
                    profileMetric(title: "Protected", value: totalValue.formatted(.currency(code: "USD")), subtitle: "purchase value")
                } else {
                    profileMessageMetric(title: "Protection", value: "Ready", subtitle: "Your first saved item will make this space feel alive.")
                    profileMessageMetric(title: "Next step", value: "Connect", subtitle: "Gmail or one scanned receipt is enough to begin.")
                }
            }
        }
    }

    private var householdPanel: some View {
        panel(title: "Household sharing", icon: "person.2.fill") {
            VStack(spacing: 14) {
                infoRow(title: "Sharing", value: familySharingEnabled ? "Family sharing is on" : "Family sharing is off")
                infoRow(title: "Family snapshot", value: familySharingEnabled ? (hasPurchases ? "Shared purchases are easy to keep in one place" : "Your shared timeline will begin with your first saved purchase") : "Sharing is resting for now")

                Toggle(isOn: $familySharingEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable family sharing")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Keep one household timeline instead of scattered receipts.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
                    }
                }
                .tint(AppTheme.accent)
            }
        }
    }

    private var connectionPanel: some View {
        panel(title: "Connections", icon: "link.circle.fill") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $emailSyncEnabled) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Email parsing")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Connect Gmail and let Keep Sure turn order emails into tracked purchases.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
                    }
                }
                .tint(AppTheme.accent)

                if emailSyncEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        if appModeManager.selectedMode != .live {
                            Text("Gmail syncing is available in Live mode only. Switch modes below when you want real purchases instead of sample data.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                        } else {
                            infoRow(
                                title: "Permission flow",
                                value: emailSyncManager.isConnected ? "Granted through Google" : "Requested on first launch"
                            )
                            infoRow(title: "Inbox status", value: emailSyncManager.connectionStatusLine)

                            if let connectedEmail = emailSyncManager.connectedEmail {
                                infoRow(title: "Connected account", value: connectedEmail)
                            }

                            if let lastSyncAt = emailSyncManager.lastSyncAt {
                                infoRow(
                                    title: "Last sync",
                                    value: lastSyncAt.formatted(date: .abbreviated, time: .shortened)
                                )
                            }

                            if emailSyncManager.requiresBundledClientIDSetup {
                                Text("Gmail syncing is not available in this build yet.")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                            } else {
                                Text("Keep Sure asks Google for permission once, returns you to the app automatically, and then keeps your purchase tracking up to date.")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                            }

                            if let statusMessage = emailSyncManager.statusMessage {
                                Text(statusMessage)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(AppTheme.accent)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    gmailLaunchPromptDeferred = false
                                    Task {
                                        await emailSyncManager.connectOrSync()
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if emailSyncManager.isAuthorizing || emailSyncManager.isSyncing {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .tint(.white)
                                        }
                                        Text(emailSyncManager.isConnected ? "Sync Gmail now" : "Connect Gmail")
                                            .font(.headline.weight(.semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.accent, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(emailSyncManager.requiresBundledClientIDSetup || emailSyncManager.isAuthorizing || emailSyncManager.isSyncing)

                                if emailSyncManager.isConnected {
                                    Button("Disconnect") {
                                        gmailLaunchPromptDeferred = false
                                        emailSyncManager.disconnect()
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.secondaryAccent)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.captureGradient)
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                            }
                    )
                }

                Toggle(isOn: $smartAlertsEnabled) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Smart notifications")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Return reminders first, warranty nudges second, and fewer noisy alerts.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.7))
                    }
                }
                .tint(AppTheme.accent)
                .onChange(of: smartAlertsEnabled) { _, isEnabled in
                    Task {
                        await notificationManager.applyPreference(enabled: isEnabled, container: PersistenceController.shared.container)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    infoRow(title: "Reminder status", value: notificationManager.permissionStatusLine)
                    infoRow(title: "Reminder mix", value: notificationManager.cadenceLine)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.elevatedPanelFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
                        }
                )
            }
        }
    }

    private var preferencesPanel: some View {
        panel(title: "Preferences", icon: "slider.horizontal.3") {
            VStack(spacing: 14) {
                infoRow(title: "Retailer return policies", value: "Coming soon")
                infoRow(title: "Return reminders", value: "7, 3, and 1 day before the window closes")
                infoRow(title: "Warranty reminders", value: "30 and 7 days before confirmed coverage ends")
                infoRow(title: "Review nudges", value: "Next day for uncertain imports only")
                infoRow(title: "Claim assistant", value: "Planned")
                infoRow(title: "Receipt export", value: "PDF and CSV")
            }
        }
    }

    private var privacyPanel: some View {
        panel(title: "Privacy and control", icon: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your receipts should feel secure, searchable, and easy to move if you ever need them elsewhere.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.74))

                infoRow(title: "Face ID lock", value: "Recommended")
                infoRow(title: "Data export", value: "Available anytime")
                infoRow(title: "Cloud backup", value: "Ready for next step")
            }
        }
    }

    private var modePanel: some View {
        panel(title: "App mode", icon: "square.2.layers.3d.fill") {
            VStack(alignment: .leading, spacing: 14) {
                infoRow(title: "Current mode", value: appModeManager.selectedMode?.title ?? "Not selected")

                Text("Demo mode keeps sample purchases in place. Live mode clears local purchases and makes Gmail sync the first step.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.74))

                HStack(spacing: 12) {
                    modeButton(for: .demo)
                    modeButton(for: .live)
                }
            }
        }
    }

    private func profileMetric(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(AppTheme.accent.opacity(0.9))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
        )
    }

    private func profileMessageMetric(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(AppTheme.accent.opacity(0.9))

            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .minimumScaleFactor(0.75)
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.elevatedPanelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                }
        )
    }

    private func panel<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
            }

            content()
        }
        .padding(20)
        .background(panelCard)
    }

    private var panelCard: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(AppTheme.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
            }
    }
    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.62))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func modeButton(for mode: AppMode) -> some View {
        let isSelected = appModeManager.selectedMode == mode

        return Button {
            pendingModeSwitch = mode
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(mode.shortTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : AppTheme.ink)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }

                Text(mode.summary)
                    .font(.footnote)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.88) : AppTheme.secondaryAccent.opacity(0.76))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? AppTheme.accent : AppTheme.elevatedPanelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(isSelected ? AppTheme.accent : Color.white.opacity(0.75), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
        .disabled(appModeManager.isApplying || (mode == .live && emailSyncManager.isAuthorizing))
    }

    private func applyModeSwitch(_ mode: AppMode) async {
        if mode == .live {
            emailSyncEnabled = true
            gmailLaunchPromptDeferred = false
        }

        await appModeManager.select(mode)

        guard appModeManager.selectedMode == mode else { return }

        if mode == .live {
            if emailSyncManager.isConnected {
                await emailSyncManager.syncInbox()
            } else if emailSyncManager.hasUsableConfiguration {
                await emailSyncManager.connectGmail()
            }
        }

        await notificationManager.rescheduleAll(in: PersistenceController.shared.container)
    }
}
