import SwiftUI

struct ConversationIslandSettingsView:View {
    @Bindable private var activity=ConversationLiveActivity.shared
    var body:some View {
        List {
            Section {
                Toggle("灵动岛陪伴",isOn:$activity.enabled).accessibilityIdentifier("islandEnabledToggle")
                Toggle("显示这句对话",isOn:$activity.showsPreview).disabled(!activity.enabled)
                    .accessibilityIdentifier("islandPreviewToggle")
            } footer: {
                Text("角色思考、轻声说话时，在灵动岛和锁屏陪你一小会儿。默认只显示状态，开启后才显示简短台词。")
            }.listRowBackground(Theme.surface)
            Section {
                Label(activity.systemEnabled ? "系统已允许实时活动" : "系统未允许实时活动",systemImage:activity.systemEnabled ? "checkmark.circle" : "info.circle")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            } footer: {
                Text("可在 iOS 设置中的星夜页面管理实时活动。切出 App 会暂停声音；仍在生成的回复会尽力完成，点灵动岛回到会话。")
            }.listRowBackground(Theme.surface)
        }.scrollContentBackground(.hidden).background(Theme.background)
            .foregroundStyle(Theme.ink).tint(Theme.accent)
            .navigationTitle("灵动岛陪伴").navigationBarTitleDisplayMode(.inline)
    }
}
