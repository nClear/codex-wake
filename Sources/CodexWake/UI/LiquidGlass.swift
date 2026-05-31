import SwiftUI

private enum LiquidGlassMetrics {
    static let radius: CGFloat = 10
    static let compactRadius: CGFloat = 8
}

extension View {
    @ViewBuilder
    func liquidGlassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackMaterial: Material = .regularMaterial
    ) -> some View {
        if #available(macOS 26.0, *) {
            let glass = Glass.regular.tint(tint)
            self.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            self
                .background(fallbackMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    func liquidGlassContainer(spacing: CGFloat? = nil) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func liquidGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func liquidGlassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self
                .foregroundStyle(.white)
                .tint(.accentColor)
                .buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    var liquidGlassBackground: some View {
        if #available(macOS 15.0, *) {
            background(Color(NSColor.windowBackgroundColor))
                .containerBackground(.clear, for: .window)
        } else {
            background(Color(NSColor.windowBackgroundColor))
        }
    }
}

extension RoundedRectangle {
    static var liquidGlass: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidGlassMetrics.radius, style: .continuous)
    }

    static var compactLiquidGlass: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidGlassMetrics.compactRadius, style: .continuous)
    }
}
