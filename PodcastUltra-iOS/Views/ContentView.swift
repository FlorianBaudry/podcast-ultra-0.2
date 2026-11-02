import SwiftUI

enum ActiveTab {
    case episodes, discover, audiobooks, radio
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    // First tab on launch is now Episodes
    @State private var selectedTab: ActiveTab = .episodes
    @State private var showingPlayerSheet = false
    @State private var showingSearchPanel = false
    @State private var showingWatchCompanion = false
    @State private var showLaunchScreen = true
    
    var body: some View {
        ZStack {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    // Background Color matching theme (Light / Dark / OLED Black)
                    storage.mainBackgroundColor
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Glassmorphic top header
                        HeaderView(
                            onOpenSearch: {
                                HapticManager.shared.trigger(.light)
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                    showingSearchPanel = true
                                }
                            },
                            onOpenWatch: {
                                HapticManager.shared.trigger(.light)
                                showingWatchCompanion = true
                            }
                        )
                        
                        // Main View Content switcher
                        Group {
                            switch selectedTab {
                            case .episodes:
                                EpisodesView()
                            case .discover:
                                DiscoverView()
                            case .audiobooks:
                                AudiobooksView()
                            case .radio:
                                RadioView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ipadMaxWidth()
                    }
                    
                    // Sticky custom glassmorphic bottom navigation bar
                    CustomBottomNavBar(selectedTab: $selectedTab, showingPlayerSheet: $showingPlayerSheet)
                    
                    // Top-down Search Panel (inverse of Player sheet)
                    if showingSearchPanel {
                        SearchView(onClose: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                showingSearchPanel = false
                            }
                        })
                        .environmentObject(audioPlayer)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(50)
                    }
                }
                .navigationBarHidden(true)
                .ignoresSafeArea(.all, edges: .bottom)
                .sheet(isPresented: $showingPlayerSheet) {
                    PlayerView()
                        .environmentObject(audioPlayer)
                }
                .sheet(isPresented: $showingWatchCompanion) {
                    WatchCompanionView()
                        .environmentObject(audioPlayer)
                }
            }
            
            // Launch Screen with Logo, "Beta", and Weather
            if showLaunchScreen {
                LaunchScreenView(onFinished: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showLaunchScreen = false
                    }
                })
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .preferredColorScheme(storage.isLightTheme ? .light : .dark)
        .tint(storage.accentColorColor())
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                storage.triggerAppOpenEpisodesRefresh()
            }
        }
        .onAppear {
            storage.triggerAppOpenEpisodesRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if showLaunchScreen {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showLaunchScreen = false
                    }
                }
            }
        }
    }
}

struct HeaderView: View {
    @ObservedObject var storage = LocalStorageManager.shared
    var onOpenSearch: () -> Void
    var onOpenWatch: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Search Input button (opens top-down Search Panel & auto-focuses input)
            Button(action: onOpenSearch) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(Translations.shared.t("search_placeholder", storage.currentLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(storage.subtleSurfaceColor)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(storage.cardBorderColor, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // iWatch Companion Button
            Button(action: onOpenWatch) {
                Image(systemName: "applewatch")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(storage.accentColorColor())
                    .frame(width: 40, height: 40)
                    .background(storage.subtleSurfaceColor)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(storage.cardBorderColor, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Settings Button
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(storage.isLightTheme ? .primary : .secondary)
                    .frame(width: 40, height: 40)
                    .background(storage.subtleSurfaceColor)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(storage.cardBorderColor, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .ipadMaxWidth()
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            (storage.isLightTheme ? Color.white.opacity(0.85) : Color.black.opacity(0.2))
                .background(.ultraThinMaterial)
        )
    }
}

struct CustomBottomNavBar: View {
    @Binding var selectedTab: ActiveTab
    @Binding var showingPlayerSheet: Bool
    
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        HStack(alignment: .center) {
            // Tab 1: Episodes (Switched to 1st position as requested)
            NavTabButton(
                icon: "play.rectangle.on.rectangle",
                label: Translations.shared.t("episodes_feed", storage.currentLanguage),
                isActive: selectedTab == .episodes,
                action: { selectedTab = .episodes }
            )
            
            // Tab 2: Podcasts (Switched to 2nd position as requested)
            NavTabButton(
                icon: "safari",
                label: Translations.shared.t("discover", storage.currentLanguage),
                isActive: selectedTab == .discover,
                action: { selectedTab = .discover }
            )
            
            // Center floating player button
            Button(action: {
                HapticManager.shared.trigger(.light)
                showingPlayerSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(audioPlayer.isPlaying ? storage.accentColorColor() : (storage.isLightTheme ? storage.accentColorColor().opacity(0.15) : Color.white.opacity(0.1)))
                        .frame(width: 54, height: 54)
                        .shadow(color: audioPlayer.isPlaying ? storage.accentColorColor().opacity(0.4) : Color.clear, radius: 10, y: 5)
                        .overlay(
                            Circle()
                                .stroke(storage.cardBorderColor, lineWidth: 1)
                        )
                    
                    if audioPlayer.isPlaying {
                        PlayingEqualizerBars()
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundColor(storage.isLightTheme ? storage.accentColorColor() : .white)
                            .offset(x: 2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 60, height: 60)
            
            // Tab 3: Audiobooks
            NavTabButton(
                icon: "book.closed",
                label: Translations.shared.t("audiobooks", storage.currentLanguage),
                isActive: selectedTab == .audiobooks,
                action: { selectedTab = .audiobooks }
            )
            
            // Tab 4: Radio
            NavTabButton(
                icon: "radio",
                label: Translations.shared.t("radio", storage.currentLanguage),
                isActive: selectedTab == .radio,
                action: { selectedTab = .radio }
            )
        }
        .ipadMaxWidth()
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, safeAreaBottomInset() > 0 ? safeAreaBottomInset() : 16)
        .background(
            (storage.isLightTheme ? Color.white.opacity(0.92) : Color.black.opacity(0.35))
                .background(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(storage.isLightTheme ? 0.08 : 0.3), radius: 15, y: -5)
        )
        .overlay(
            Rectangle()
                .fill(storage.cardBorderColor)
                .frame(height: 0.5),
            alignment: .top
        )
        .ignoresSafeArea(.all, edges: .bottom)
    }
    
    private func safeAreaBottomInset() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.bottom
        }
        return 0
    }
}

/// Self-contained equalizer bar view that animates once on appear without stacking animations on state ticks.
struct PlayingEqualizerBars: View {
    var color: Color = .white
    @State private var animate = false
    
    var body: some View {
        HStack(spacing: 3) {
            Capsule()
                .fill(color)
                .frame(width: 3, height: animate ? 15 : 6)
                .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: animate)
            Capsule()
                .fill(color)
                .frame(width: 3, height: animate ? 7 : 16)
                .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: animate)
            Capsule()
                .fill(color)
                .frame(width: 3, height: animate ? 14 : 5)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animate)
        }
        .onAppear {
            animate = true
        }
    }
}

struct NavTabButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void
    @ObservedObject var storage = LocalStorageManager.shared
    
    var body: some View {
        Button(action: {
            HapticManager.shared.trigger(.light)
            action()
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? storage.accentColorColor() : .secondary)
                    .frame(height: 24)
                
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isActive ? storage.accentColorColor() : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IpadMaxWidthModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            content
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func ipadMaxWidth() -> some View {
        modifier(IpadMaxWidthModifier())
    }
}
