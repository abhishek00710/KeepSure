import CoreData
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var emailSyncManager: EmailSyncManager
    @EnvironmentObject private var notificationManager: SmartNotificationManager
    @EnvironmentObject private var securityManager: AppSecurityManager
    @AppStorage("email_sync_enabled") private var emailSyncEnabled = true
    @AppStorage("gmail_launch_prompt_deferred") private var gmailLaunchPromptDeferred = false
    @AppStorage("smart_alerts_enabled") private var smartAlertsEnabled = true
    @AppStorage("family_sharing_enabled") private var familySharingEnabled = true
    @AppStorage("return_reminder_primary_days") private var returnReminderPrimaryDays = 7
    @AppStorage("return_reminder_secondary_days") private var returnReminderSecondaryDays = 3
    @AppStorage("return_reminder_final_days") private var returnReminderFinalDays = 1
    @AppStorage("warranty_reminder_primary_days") private var warrantyReminderPrimaryDays = 30
    @AppStorage("warranty_reminder_final_days") private var warrantyReminderFinalDays = 7
    @AppStorage("review_nudge_hours") private var reviewNudgeHours = 24

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
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private var householdPanel: some View {
        panel(title: "Household sharing", icon: "person.2.fill") {
            VStack(spacing: 14) {
                infoRow(title: "Status", value: "On the way")
                infoRow(
                    title: "What’s happening",
                    value: familySharingEnabled
                        ? "We’re keeping this space warm while real household syncing gets ready."
                        : "Turn this on if you want Keep Sure to keep family sharing on your radar."
                )

                Toggle(isOn: $familySharingEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep me posted when sharing is ready")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("This does not share receipts yet. It simply keeps the space ready while the real feature is being prepared.")
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
                timingCard(
                    title: "Return reminders",
                    subtitle: "Choose how early Keep Sure should start nudging you before a return window closes."
                ) {
                    timingStepper(title: "First reminder", value: $returnReminderPrimaryDays, range: 1...30, unit: "day")
                    timingStepper(title: "Second reminder", value: $returnReminderSecondaryDays, range: 1...21, unit: "day")
                    timingStepper(title: "Final reminder", value: $returnReminderFinalDays, range: 1...7, unit: "day")
                }

                timingCard(
                    title: "Warranty reminders",
                    subtitle: "Set how far ahead confirmed coverage should come back onto your radar."
                ) {
                    timingStepper(title: "Early reminder", value: $warrantyReminderPrimaryDays, range: 1...90, unit: "day")
                    timingStepper(title: "Final reminder", value: $warrantyReminderFinalDays, range: 1...30, unit: "day")
                }

                timingCard(
                    title: "Review nudges",
                    subtitle: "Control how quickly uncertain imports come back for one small clean-up pass."
                ) {
                    timingStepper(title: "Nudge after", value: $reviewNudgeHours, range: 1...72, unit: "hour")
                }
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

                Toggle(isOn: Binding(
                    get: { securityManager.isProtectionEnabled },
                    set: { newValue in
                        Task {
                            await securityManager.setProtectionEnabled(newValue)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lock Keep Sure with \(securityManager.biometryLabel)")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(securityManager.protectionStatusLine)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                    }
                }
                .tint(AppTheme.accent)

                if let errorMessage = securityManager.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.warning)
                }

                infoRow(title: "Data export", value: "Available anytime")
                infoRow(title: "Cloud backup", value: "Ready for next step")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func timingCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.74))

            content()
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

    private func timingStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                Spacer()
                Text("\(value.wrappedValue) \(value.wrappedValue == 1 ? unit : "\(unit)s")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .tint(AppTheme.accent)
        .onChange(of: value.wrappedValue) { _, _ in
            Task {
                await notificationManager.rescheduleAll(in: PersistenceController.shared.container)
            }
        }
    }

}
