import SwiftUI

struct LaunchScreenView: View {
    @ObservedObject var storage = LocalStorageManager.shared
    var onFinished: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            storage.mainBackgroundColor
                .ignoresSafeArea()
            
            // Lightweight centered App Logo + Title matching the native iOS LaunchImage (140pt)
            VStack(spacing: 16) {
                ZStack {
                    if let uiImage = UIImage(named: "LaunchImage") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 140, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .shadow(color: storage.accentColorColor().opacity(0.35), radius: 14, x: 0, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [storage.accentColorColor(), storage.accentColorColor().opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .shadow(color: storage.accentColorColor().opacity(0.35), radius: 14, x: 0, y: 6)
                            .overlay(
                                Image(systemName: "waveform.and.mic")
                                    .font(.system(size: 54, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                
                Text("Podcast Ultra")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(storage.primaryTextColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFinished?()
        }
    }
}

