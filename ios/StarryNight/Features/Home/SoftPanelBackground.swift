import SwiftUI

private struct SoftPanelHasSurfaceKey:EnvironmentKey { static let defaultValue=false }
extension EnvironmentValues {
    var softPanelHasSurface:Bool {
        get { self[SoftPanelHasSurfaceKey.self] }
        set { self[SoftPanelHasSurfaceKey.self]=newValue }
    }
}
private struct SoftPanelPageSurface:ViewModifier {
    var opaque:Bool
    @Environment(\.softPanelHasSurface) private var inherited
    func body(content:Content) -> some View {
        content.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .environment(\.softPanelHasSurface,true)
            .background {
                if !inherited {
                    if opaque { Theme.background.ignoresSafeArea() }
                    else { SoftPanelBackground().ignoresSafeArea() }
                }
            }
    }
}
extension View {
    func softPanelPageSurface(opaque:Bool=false) -> some View { modifier(SoftPanelPageSurface(opaque:opaque)) }
}

/// Preview gradient; the presentation controller adds a solid base when a panel fills the screen.
struct SoftPanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency || ThemeSettings.shared.solid {
            Theme.background
        } else {
            LinearGradient(stops:[
                .init(color:Theme.background.opacity(0.18),location:0),
                .init(color:Theme.background.opacity(0.34),location:0.16),
                .init(color:Theme.background.opacity(0.66),location:0.40),
                .init(color:Theme.background.opacity(0.86),location:0.72),
                .init(color:Theme.background.opacity(0.94),location:1)
            ],startPoint:.top,endPoint:.bottom)
        }
    }
}

extension View {
    func softSheetSurface() -> some View {
        toolbarBackground(.hidden,for:.navigationBar)
    }
}

extension View {
    @ViewBuilder func softNavigationBackground() -> some View {
        if #available(iOS 18.0, *) {
            containerBackground(.clear,for:.navigation).toolbarBackground(.hidden,for:.navigationBar)
        } else {
            toolbarBackground(.hidden,for:.navigationBar)
        }
    }
}
