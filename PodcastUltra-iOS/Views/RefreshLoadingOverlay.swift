import SwiftUI

struct RefreshLoadingOverlay: View {
    @ObservedObject var storage = LocalStorageManager.shared
    @State private var fact: KnowledgeFact
    @State private var spinAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    init() {
        _fact = State(initialValue: KnowledgeFactsService.shared.randomFact(for: LocalStorageManager.shared.currentLanguage))
    }
    
    var body: some View {
        ZStack {
            // Arrière-plan flouté avec opacité selon le thème
            (storage.isLightTheme ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Animation de chargement
                ZStack {
                    Circle()
                        .stroke(storage.accentColorColor().opacity(0.2), lineWidth: 4)
                        .frame(width: 68, height: 68)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [storage.accentColorColor(), storage.accentColorColor().opacity(0.1)]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(spinAngle))
                    
                    Image(systemName: fact.icon)
                        .font(.system(size: 24))
                        .foregroundColor(storage.accentColorColor())
                        .scaleEffect(pulseScale)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        spinAngle = 360
                    }
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseScale = 1.15
                    }
                }
                
                // Titre et explication du chargement
                VStack(spacing: 6) {
                    Text(storage.currentLanguage == .fr ? "Actualisation de vos flux..." : "Updating your feeds...")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(storage.currentLanguage == .fr
                         ? "Synchronisation des derniers épisodes et vérification des sources audio."
                         : "Synchronizing latest episodes and verifying audio streams.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Carte du Savoir / Productivité (100 faits aléatoires)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: fact.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(storage.accentColorColor())
                        
                        Text(fact.category.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundColor(storage.accentColorColor())
                        
                        Spacer()
                        
                        Text(storage.currentLanguage == .fr ? "LE SAVIEZ-VOUS ?" : "DID YOU KNOW?")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(storage.accentColorColor().opacity(0.15))
                            .foregroundColor(storage.accentColorColor())
                            .clipShape(Capsule())
                    }
                    
                    Text(fact.title(for: storage.currentLanguage))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(fact.text(for: storage.currentLanguage))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .background(storage.subtleSurfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(storage.cardBorderColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(storage.isLightTheme ? 0.05 : 0.25), radius: 15, y: 8)
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Indication discrète
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text(storage.currentLanguage == .fr ? "100 clés de science et d'efficacité" : "100 science & productivity keys")
                        .font(.caption2)
                }
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.bottom, 24)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

