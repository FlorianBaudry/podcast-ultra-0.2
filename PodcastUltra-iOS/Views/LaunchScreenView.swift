import SwiftUI

struct LaunchScreenView: View {
    @ObservedObject var storage = LocalStorageManager.shared
    @ObservedObject var weatherService = WeatherService.shared
    var onFinished: (() -> Void)? = nil
    
    @State private var appearAnimation = false
    
    var body: some View {
        ZStack {
            storage.mainBackgroundColor
                .ignoresSafeArea()
            
            // Subtle ambient radial glow
            Circle()
                .fill(storage.accentColorColor().opacity(storage.isLightTheme ? 0.12 : 0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(y: -80)
            
            VStack(spacing: 20) {
                Spacer(minLength: 16)
                
                // 1. App Logo + Title + "Beta" Badge
                VStack(spacing: 14) {
                    ZStack {
                        if let uiImage = UIImage(named: "LaunchImage") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 108, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .shadow(color: storage.accentColorColor().opacity(0.35), radius: 16, x: 0, y: 8)
                        } else {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [storage.accentColorColor(), storage.accentColorColor().opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 108, height: 108)
                                .shadow(color: storage.accentColorColor().opacity(0.35), radius: 16, x: 0, y: 8)
                                .overlay(
                                    Image(systemName: "waveform.and.mic")
                                        .font(.system(size: 46, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .scaleEffect(appearAnimation ? 1.0 : 0.9)
                    
                    VStack(spacing: 8) {
                        Text("Podcast Ultra")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(storage.primaryTextColor)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        
                        // Explicit "Beta" badge clearly visible in full
                        Text("Beta")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(storage.accentColorColor())
                                    .shadow(color: storage.accentColorColor().opacity(0.4), radius: 6, y: 3)
                            )
                    }
                }
                
                // 2. Full Weather Card (always completely visible)
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(storage.accentColorColor())
                        Text(storage.currentLanguage == .fr ? "MÉTÉO LOCALE" : "LOCAL WEATHER")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(storage.accentColorColor())
                            .tracking(1.2)
                    }
                    
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(storage.accentColorColor().opacity(0.14))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: weatherService.weatherIcon)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(storage.accentColorColor())
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(weatherService.cityName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(storage.primaryTextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Text(weatherService.weatherDescription)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Text("\(Int(round(weatherService.temperature ?? 19.0)))°C")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(storage.primaryTextColor)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                }
                .padding(18)
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(storage.cardBackgroundColor)
                        .shadow(color: Color.black.opacity(storage.isLightTheme ? 0.08 : 0.25), radius: 12, x: 0, y: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(storage.cardBorderColor, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                
                // Loading indicator
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(storage.accentColorColor())
                    Text(storage.currentLanguage == .fr ? "Chargement..." : "Loading...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
                
                Spacer(minLength: 16)
            }
            .padding(.vertical, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFinished?()
        }
        .onAppear {
            weatherService.requestLocation()
            withAnimation(.easeOut(duration: 0.45)) {
                appearAnimation = true
            }
        }
    }
}

