import SwiftUI

struct AppBootstrapView: View {
    @EnvironmentObject private var emailSyncManager: EmailSyncManager
    @EnvironmentObject private var appModeManager: AppModeManager
    @AppStorage("email_sync_enabled") private var emailSyncEnabled = true
    @AppStorage("gmail_launch_prompt_deferred") private var gmailLaunchPromptDeferred = false
    @AppStorage("has_seen_value_story") private var hasSeenValueStory = false

    @State private var showsLaunchExperience = true
    @State private var showsValueStory = false
    @State private var showsModeSelection = false
    @State private var showsGmailPermissionOnboarding = false

    var body: some View {
        Group {
            if showsValueStory {
                ValueStoryOnboardingView(
                    onSkip: completeValueStory,
                    onFinish: completeValueStory
                )
                .transition(.opacity)
            } else {
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
                                    await runInitialGmailConnection()
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
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showsValueStory)
        .task {
            guard showsLaunchExperience else { return }
            try? await Task.sleep(for: .milliseconds(1350))
            withAnimation(.easeInOut(duration: 0.35)) {
                showsLaunchExperience = false
            }

            try? await Task.sleep(for: .milliseconds(260))
            presentPostLaunchFlow()
        }
    }

    private func presentPostLaunchFlow() {
        guard hasSeenValueStory else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
                showsValueStory = true
            }
            return
        }

        presentSetupFlow()
    }

    private func presentSetupFlow() {
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

    private func completeValueStory() {
        hasSeenValueStory = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            showsValueStory = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            presentSetupFlow()
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

    private func runInitialGmailConnection() async {
        await emailSyncManager.connectGmail()

        guard emailSyncManager.isConnected, emailSyncManager.lastSyncAt != nil else {
            return
        }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            showsGmailPermissionOnboarding = false
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

private struct ValueStoryOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onSkip: () -> Void
    let onFinish: () -> Void

    @State private var currentPage = 0
    @State private var lifts = false

    private let pages: [ValueStoryPage] = [
        .init(
            eyebrow: "Keep Sure",
            title: "The receipt disappears long before the problem does",
            message: "Most people remember a return or warranty only after the window has already slipped by. Keep Sure is built to hold that mental load for them.",
            icon: "receipt.fill",
            accent: "Returns and warranties stay visible"
        ),
        .init(
            eyebrow: "Bring it in once",
            title: "Scan a receipt or let Gmail quietly bring purchases in",
            message: "One scan, one PDF, or one Google permission is enough for Keep Sure to start turning purchases into a calm timeline you can actually trust.",
            icon: "tray.and.arrow.down.fill",
            accent: "Import once, track automatically"
        ),
        .init(
            eyebrow: "Stay ahead",
            title: "Get the nudge before money quietly slips away",
            message: "Keep Sure watches return windows, confirmed warranty coverage, and uncertain imports so the right reminder shows up before the deadline does.",
            icon: "bell.badge.fill",
            accent: "Gentle reminders that stay useful"
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 24) {
                            HStack {
                                Button("Skip", action: onSkip)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.secondaryAccent)

                                Spacer()

                                pageDots
                            }

                            ScrollView(.vertical, showsIndicators: false) {
                                TabView(selection: $currentPage) {
                                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                                        valueStoryPage(page)
                                            .tag(index)
                                            .padding(.bottom, 4)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .never))
                                .frame(minHeight: proxy.size.height)
                            }

                            Button(action: advance) {
                                HStack(spacing: 10) {
                                    Text(currentPage == pages.count - 1 ? "Start with Keep Sure" : "Continue")
                                        .font(.headline.weight(.semibold))
                                    Image(systemName: currentPage == pages.count - 1 ? "sparkles" : "arrow.right")
                                        .font(.subheadline.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 28)
                        //.frame(maxWidth: 560)
//                        .background(
//                            RoundedRectangle(cornerRadius: 34, style: .continuous)
//                                .fill(AppTheme.panelFill)
//                                .overlay {
//                                    RoundedRectangle(cornerRadius: 34, style: .continuous)
//                                        .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
//                                }
//                                .shadow(color: Color.black.opacity(0.08), radius: 28, y: 16)
//                        )
                        //.padding(.horizontal, 20)
                        //.padding(.top, max(proxy.safeAreaInsets.top + 12, 28))
                        //.padding(.bottom, max(proxy.safeAreaInsets.bottom + 20, 28))
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                lifts = true
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? AppTheme.accent : Color.white.opacity(0.72))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.22), value: currentPage)
            }
        }
    }

    private func valueStoryPage(_ page: ValueStoryPage) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            valueStoryIllustration(for: page)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text(page.eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(AppTheme.accent)

                Text(page.title)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.message)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: page.icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(page.accent)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.captureGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.76), lineWidth: 1)
                    }
            )

            HStack(spacing: 12) {
                heroFeatureCard(icon: page.icon, title: storyFeatureTitle(for: page), subtitle: storyFeatureSubtitle(for: page))
                heroFeatureCard(icon: "clock.badge.checkmark.fill", title: "20-second start", subtitle: "Understand it fast")
                heroFeatureCard(icon: "heart.text.square.fill", title: "Calm by design", subtitle: "No admin-tool feel")
            }

        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func valueStoryIllustration(for page: ValueStoryPage) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppTheme.captureGradient)
                .frame(height: 176)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
                }

            Circle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 120, height: 120)
                .blur(radius: 8)
                .offset(x: -90, y: lifts ? -18 : -6)

            Circle()
                .fill(AppTheme.accent.opacity(0.12))
                .frame(width: 110, height: 110)
                .blur(radius: 6)
                .offset(x: 95, y: lifts ? 14 : 2)

            illustrationStack(for: page)
                .offset(y: lifts ? -6 : 6)
        }
        .shadow(color: AppTheme.accent.opacity(0.10), radius: 18, y: 12)
    }

    @ViewBuilder
    private func illustrationStack(for page: ValueStoryPage) -> some View {
        switch currentPage {
        case 0:
            ZStack {
                floatingCard(width: 170, height: 108, rotation: -8, x: -62, y: -8, icon: "arrow.uturn.backward.circle.fill", label: "Return window")
                floatingCard(width: 188, height: 116, rotation: 7, x: 62, y: 12, icon: "checkmark.shield.fill", label: "Warranty proof")
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 82)
                    .shadow(color: AppTheme.accent.opacity(0.12), radius: 16, y: 10)
            }
        case 1:
            ZStack {
                floatingCard(width: 176, height: 112, rotation: -6, x: -72, y: 8, icon: "doc.text.fill", label: "Receipt scan")
                floatingCard(width: 176, height: 112, rotation: 6, x: 72, y: -6, icon: "envelope.badge.fill", label: "Gmail import")
                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: currentPage)
            }
        default:
            ZStack {
                floatingCard(width: 162, height: 104, rotation: -7, x: -76, y: 12, icon: "clock.badge.checkmark.fill", label: "Return reminder")
                floatingCard(width: 162, height: 104, rotation: 7, x: 76, y: -10, icon: "bell.badge.fill", label: "Coverage nudge")
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("Before the date slips")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryAccent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.82), in: Capsule())
            }
        }
    }

    private func floatingCard(width: CGFloat, height: CGFloat, rotation: Double, x: CGFloat, y: CGFloat, icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("Kept ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: width, height: height, alignment: .leading)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.84), lineWidth: 1)
        }
        .rotationEffect(.degrees(rotation))
        .offset(x: x, y: y)
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 10)
    }

    private func storyFeatureTitle(for page: ValueStoryPage) -> String {
        switch currentPage {
        case 0: return "Proof kept"
        case 1: return "Pulled in"
        default: return "Watched over"
        }
    }

    private func storyFeatureSubtitle(for page: ValueStoryPage) -> String {
        switch currentPage {
        case 0: return "Receipts stay close"
        case 1: return "Gmail or scan"
        default: return "Deadlines first"
        }
    }

    private func advance() {
        if currentPage == pages.count - 1 {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                currentPage += 1
            }
        }
    }
}

private struct ValueStoryPage {
    let eyebrow: String
    let title: String
    let message: String
    let icon: String
    let accent: String
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
        }    }

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
        }    }

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
    private let bgTop = Color(red: 0.89, green: 0.85, blue: 0.79)
    private let bgBottom = Color(red: 0.75, green: 0.69, blue: 0.61)
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
                .fill(Color.white.opacity(0.45))
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

func heroFeatureCard(icon: String, title: String, subtitle: String) -> some View {
    VStack(alignment: .center, spacing: 10) {
        Image(systemName: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryAccent.opacity(0.72))
                .lineLimit(1)
        }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 84, alignment: .top)
    .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
    }
}

#Preview {
    ValueStoryOnboardingView(onSkip: {}, onFinish: {})
}
