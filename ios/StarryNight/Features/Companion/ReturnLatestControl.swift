import SwiftUI

/// An overlay: its animation and placement never change the message/composer layout.
struct ReturnLatestControl:View {
    var action:()->Void
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        Button(action:action) {
            Image(systemName:"chevron.down.2")
                .font(.system(size:13,weight:.medium))
                .foregroundStyle(Theme.ink.opacity(reduceMotion ? 0.40 : drift ? 0.46 : 0.34))
                .shadow(color:.black.opacity(0.18),radius:2,y:1)
                .offset(y:reduceMotion ? 0 : drift ? 0.75 : -0.75)
                .frame(width:44,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("回到最近")
            .accessibilityIdentifier("returnLatestButton")
            .animation(reduceMotion ? nil : .easeInOut(duration:1.8).repeatForever(autoreverses:true),value:drift)
            .onAppear { drift = !reduceMotion }
            .onChange(of:reduceMotion) { drift = !reduceMotion }
    }
}
