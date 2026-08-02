import SwiftUI

/// Корень окна настроек: полоса разделов сверху, панель раздела под ней.
///
/// Навигация — горизонтальные вкладки, а не боковой список: разделов пять,
/// иерархии нет, а окно должно оставаться узким (`design/ia.md`).
/// Здесь только рабочий каркас; стеклянную капсулу в титлбаре делает
/// слайс «Оформление».
struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            section
        }
        .onAppear { model.refreshPermissions() }
    }

    private var tabs: some View {
        HStack(spacing: Palette.space2xs) {
            ForEach(SettingsSection.allCases) { item in
                Button {
                    model.section = item
                } label: {
                    HStack(spacing: Palette.space2xs + 2) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15))
                            .symbolRenderingMode(.hierarchical)
                        Text(item.title)
                            .font(.system(size: 11, weight: model.section == item ? .medium : .regular))
                    }
                    .foregroundStyle(model.section == item ? Color.primary : Color.secondary)
                    .frame(minWidth: 84)
                    .padding(.horizontal, Palette.spaceSm)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(model.section == item ? Palette.surfaceTile : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(item.shortcut), modifiers: .command)
                .help(item.title)
            }
        }
        .padding(.horizontal, Palette.spaceLg)
        .frame(height: 44)
    }

    @ViewBuilder
    private var section: some View {
        switch model.section {
        case .general:
            SettingsSectionGeneral(model: model)
        case .dictation:
            SettingsSectionDictation(model: model)
        case .history:
            SettingsSectionHistory()
        case .usage:
            SettingsSectionUsage()
        case .system:
            SettingsSectionSystem(model: model)
        }
    }
}

/// Заглушка раздела, который ещё не сделан.
struct SectionPlaceholder: View {
    private let symbol: String

    init(symbol: String) {
        self.symbol = symbol
    }

    var body: some View {
        VStack(spacing: Palette.spaceSm) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Раздел в работе")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
