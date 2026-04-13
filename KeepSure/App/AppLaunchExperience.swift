import SwiftUI

struct AppBootstrapView: View {
    @EnvironmentObject private var emailSyncManager: EmailSyncManager
    @EnvironmentObject private var appModeManager: AppModeManager
    @AppStorage("email_sync_enabled") private var emailSyncEnabled = true
    @AppStorage("gmail_launch_prompt_deferred") private var gmailLaunchPromptDeferred = false

    @State private var showsLaunchExperience = true
    @State private var showsModeSelection = false
    @State private var showsGmailPermissionOnboarding = false

    var body: some View {
        ZStack {
            RootView()

            if showsModeSelection {
                ModeSelectionView(
                    isApplying: appModeManager.isApplying,
                    errorMessage: appModeManager.errorMessage,
                    onSelectDemo: {
                        Task {
                            await selectMode(.demo)
                        }
                    },
                    onSelectLive: {
                        Task {
                            await selectMode(.live)
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

            if showsGmailPermissionOnboarding {
                GmailPermissionOnboardingView(
                    isBusy: emailSyncManager.isAuthorizing || emailSyncManager.isSyncing,
                    errorMessage: emailSyncManager.errorMessage,
                    onContinue: {
                        Task {
                            await emailSyncManager.connectGmail()
                        }
                    },
                    onMaybeLater: {
                        gmailLaunchPromptDeferred = true
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
                            showsGmailPermissionOnboarding = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            if showsLaunchExperience {
                LaunchExperienceView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                    .zIndex(4)
            }
        }
        .task {
            guard showsLaunchExperience else { return }
            try? await Task.sleep(for: .milliseconds(1350))
            withAnimation(.easeInOut(duration: 0.35)) {
                showsLaunchExperience = false
            }

            try? await Task.sleep(for: .milliseconds(260))
            presentPostLaunchFlow()
        }
        .onChange(of: emailSyncManager.isConnected) { _, isConnected in
            guard isConnected else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
                showsGmailPermissionOnboarding = false
            }
        }
    }

    private func presentPostLaunchFlow() {
        if appModeManager.requiresSelection {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
                showsModeSelection = true
            }
            return
        }

        guard shouldOfferGmailPrompt else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            showsGmailPermissionOnboarding = true
        }
    }

    private func selectMode(_ mode: AppMode) async {
        if mode == .live {
            emailSyncEnabled = true
            gmailLaunchPromptDeferred = false
        }

        await appModeManager.select(mode)

        guard appModeManager.selectedMode == mode else { return }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            showsModeSelection = false
            if mode == .demo {
                showsGmailPermissionOnboarding = false
            }
        }

        guard mode == .live else { return }

        if emailSyncManager.isConnected {
            await emailSyncManager.syncInbox()
        } else if shouldOfferGmailPrompt {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
                showsGmailPermissionOnboarding = true
            }
        }
    }

    private var shouldOfferGmailPrompt: Bool {
        appModeManager.selectedMode == .live
            && !showsModeSelection
            && !appModeManager.isApplying
            && emailSyncEnabled
            && !gmailLaunchPromptDeferred
            && !emailSyncManager.isConnected
            && emailSyncManager.hasUsableConfiguration
    }
}

private struct ModeSelectionView: View {
    let isApplying: Bool
    let errorMessage: String?
    let onSelectDemo: () -> Void
    let onSelectLive: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 36)

                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()

                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .shadow(color: AppTheme.accent.opacity(0.16), radius: 24, y: 12)

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose how you want to start")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)

                        Text("Demo mode fills the app with sample purchases. Live mode starts clean and uses Gmail as the first source of truth.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.86))
                    }

                    VStack(spacing: 14) {
                        modeCard(
                            title: AppMode.demo.title,
                            summary: AppMode.demo.summary,
                            detail: AppMode.demo.resetSummary,
                            systemImage: "sparkles.rectangle.stack.fill",
                            actionTitle: "Start in Demo",
                            isApplying: isApplying,
                            action: onSelectDemo
                        )

                        modeCard(
                            title: AppMode.live.title,
                            summary: AppMode.live.summary,
                            detail: AppMode.live.resetSummary,
                            systemImage: "tray.full.fill",
                            actionTitle: "Start in Live",
                            isApplying: isApplying,
                            action: onSelectLive
                        )
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppTheme.ivory)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(AppTheme.warning.opacity(0.18), lineWidth: 1)
                                    }
                            )
                    }
                }
                .padding(28)
                .frame(maxWidth: 560)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(AppTheme.panelFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 28, y: 16)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }

    private func modeCard(
        title: String,
        summary: String,
        detail: String,
        systemImage: String,
        actionTitle: String,
        isApplying: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.8))

                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryAccent.opacity(0.68))
                }
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    if isApplying {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(actionTitle)
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.58))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                }
        )
    }
}

private struct GmailPermissionOnboardingView: View {
    let isBusy: Bool
    let errorMessage: String?
    let onContinue: () -> Void
    let onMaybeLater: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()

                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 92, height: 92)
                            .shadow(color: AppTheme.accent.opacity(0.16), radius: 24, y: 12)

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Bring in your Gmail purchases")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)

                        Text("Tap continue, approve Google access, and Keep Sure will come right back here to organize your purchase emails into tracked returns and warranties.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryAccent.opacity(0.86))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow(icon: "checkmark.shield.fill", text: "One secure Google permission")
                        permissionRow(icon: "envelope.badge.fill", text: "Purchase emails imported automatically")
                        permissionRow(icon: "bell.badge.fill", text: "Return and warranty reminders handled for you")
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppTheme.ivory)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(AppTheme.warning.opacity(0.18), lineWidth: 1)
                                    }
                            )
                    }

                    VStack(spacing: 12) {
                        Button(action: onContinue) {
                            HStack(spacing: 10) {
                                if isBusy {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "envelope.badge.fill")
                                        .font(.headline.weight(.bold))
                                }

                                Text(isBusy ? "Connecting Gmail..." : "Continue with Gmail")
                                    .font(.headline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)

                        Button("Maybe later", action: onMaybeLater)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryAccent)
                            .disabled(isBusy)
                    }
                }
                .padding(28)
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(AppTheme.panelFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 28, y: 16)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }

    private func permissionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.ink)

            Spacer()
        }
    }
}

private struct LaunchExperienceView: View {
    private let bgTop = Color(red: 0.93, green: 0.91, blue: 0.87)
    private let bgBottom = Color(red: 0.84, green: 0.80, blue: 0.74)
    private let text = Color(red: 0.21, green: 0.19, blue: 0.18)
    private let accent = Color(red: 0.70, green: 0.58, blue: 0.39)
    private let subtext = Color(red: 0.42, green: 0.36, blue: 0.30)

    @State private var lifts = false
    @State private var reveals = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(width: 260, height: 180)
                .blur(radius: 18)
                .offset(x: -70, y: -180)

            VStack(spacing: 22) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 166, height: 166)
                    .scaleEffect(lifts ? 1 : 0.94)

                VStack(spacing: 8) {
                    Text("Keep Sure")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(text)

                    Text("Protect what you buy.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(subtext)
                }
                .opacity(reveals ? 1 : 0)
                .offset(y: reveals ? 0 : 8)
            }
        }
        .task {
            withAnimation(.spring(response: 0.82, dampingFraction: 0.9)) {
                lifts = true
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.08)) {
                reveals = true
            }
        }
    }
}
