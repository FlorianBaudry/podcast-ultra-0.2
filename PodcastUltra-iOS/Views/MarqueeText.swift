import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var color: Color = .white
    
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isVisible: Bool = false
    
    var body: some View {
        let isTooLong = textWidth > containerWidth && containerWidth > 0
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 40) {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
                
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .opacity(isTooLong ? 1 : 0)
            }
            .offset(x: offset)
        }
        .disabled(true)
        .background(
            Text(text)
                .font(font)
                .lineLimit(1)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: WidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .opacity(0)
                .fixedSize(horizontal: true, vertical: true),
            alignment: .leading
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ContainerWidthPreferenceKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self) { value in
            if abs(textWidth - value) > 0.5 {
                textWidth = value
                if isVisible { restartAnimation() }
            }
        }
        .onPreferenceChange(ContainerWidthPreferenceKey.self) { value in
            if abs(containerWidth - value) > 0.5 {
                containerWidth = value
                if isVisible { restartAnimation() }
            }
        }
        .onChange(of: text) { _, _ in
            if isVisible { restartAnimation() }
        }
        .onAppear {
            isVisible = true
            restartAnimation()
        }
        .onDisappear {
            isVisible = false
            offset = 0 // Stop animating and reset offset when off-screen
        }
    }
    
    private func restartAnimation() {
        offset = 0
        
        guard isVisible else { return }
        guard textWidth > containerWidth && containerWidth > 0 else { return }
        
        DispatchQueue.main.async {
            guard self.isVisible, self.textWidth > self.containerWidth else { return }
            
            let speed: Double = 30 // points per second
            let duration = Double(self.textWidth + 40) / speed
            
            withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: false)) {
                self.offset = -(self.textWidth + 40)
            }
        }
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
