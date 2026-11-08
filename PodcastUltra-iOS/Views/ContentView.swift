import SwiftUI

enum ActiveTab {
    case podcasts, radio, audiobooks, settings
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var audioPlayer: AudioPlayerManager
    @ObservedObject var storage = LocalStorageManager.shared
    
    // First tab on launch is Podcasts (formerly Episodes)
    @State private var selectedTab: ActiveTab = .podcasts
    @State private var showingPlayerSheet = false
    @State private var showingSearchPanel = false
    @State private var showLaunchScreen = true
    
    var body: some View {
        ZStack {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    // Background Color matching theme (Light / Dark / OLED Black)
                    storage.mainBackgroundColor
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Glassmorphic top header (Search bar only visible in Découvrir tab)
                        if selectedTab == .audiobooks {
                            HeaderView(
                                onOpenSearch: {
                                    HapticManager.shared.trigger(.light)
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                        showingSearchPanel = true
                                    }
                                }
                            )
                        }
                        
                        // Main View Content switcher: Favoris, Découvrir, Radio, Paramètres
                        Group {
                            switch selectedTab {
                            case .podcasts:
                                EpisodesView()
                            case .radio:
                                RadioView()
                            case .audiobooks:
                                AudiobooksView()
                            case .settings:
                                SettingsView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ipadMaxWidth()
                    }
                    
                    // Sticky custom glassmorphic bottom navigation bar (Podcasts, Radio, Lecture, Apprendre, Réglages)
                    CustomBottomNavBar(selectedTab: $selectedTab, showingPlayerSheet: $showingPlayerSheet)
                    
                    // Top-down Search Panel (inverse of Player sheet)
                    if showingSearchPanel && selectedTab == .audiobooks {
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
                .toolbar(.hidden, for: .navigationBar)
                .ignoresSafeArea(.all, edges: .bottom)
                .sheet(isPresented: $showingPlayerSheet) {
                    PlayerView()
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
        .onAppear {
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
            // 1. Favoris (formerly Podcasts)
            NavTabButton(
                icon: "play.rectangle.on.rectangle",
                label: Translations.shared.t("episodes_feed", storage.currentLanguage),
                isActive: selectedTab == .podcasts,
                action: { selectedTab = .podcasts }
            )
            
            // 2. Découvrir (formerly Apprendre)
            NavTabButton(
                icon: "book.closed",
                label: Translations.shared.t("audiobooks", storage.currentLanguage),
                isActive: selectedTab == .audiobooks,
                action: { selectedTab = .audiobooks }
            )
            
            // 3. Center floating player button (Lecteur)
            Button(action: {
                HapticManager.shared.trigger(.light)
                if !audioPlayer.isPlaying {
                    audioPlayer.playLastInProgressOrDefault()
                }
                showingPlayerSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(audioPlayer.isPlaying ? storage.accentColorColor() : (storage.isLightTheme ? storage.accentColorColor().opacity(0.15) : Color.white.opacity(0.1)))
                        .frame(width: 52, height: 52)
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
            .frame(width: 56, height: 56)
            
            // 4. Radio
            NavTabButton(
                icon: "radio",
                label: Translations.shared.t("radio", storage.currentLanguage),
                isActive: selectedTab == .radio,
                action: { selectedTab = .radio }
            )
            
            // 5. Paramètres (dedicated tab at far right)
            NavTabButton(
                icon: "gearshape",
                label: Translations.shared.t("settings", storage.currentLanguage),
                isActive: selectedTab == .settings,
                action: { selectedTab = .settings }
            )
        }
        .ipadMaxWidth()
        .padding(.horizontal, 8)
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
