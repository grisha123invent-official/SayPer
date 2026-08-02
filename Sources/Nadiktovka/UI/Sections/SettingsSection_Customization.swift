import AppKit
import SwiftUI

/// Раздел «Кастомизация»: как приложение выглядит.
///
/// Отдельным разделом, а не строкой в «Системе»: внешний вид — то, что
/// человек крутит под себя в первый же день, и прятать его среди ключа
/// и разрешений значит спрятать совсем.
struct SettingsSectionCustomization: View {
    @State private var accent = Settings.shared.accentTheme
    @State private var appearance = Settings.shared.appearanceMode

    var body: some View {
        SectionScaffold {
            colors
            theme
            SoundsCard()
        }
    }

    private var colors: some View {
        GlassCard("Цвет") {
            SettingRow(
                "Акцент",
                subtitle: "Переключатели, активная вкладка, свечение фона и индикатор записи"
            ) {
                HStack(spacing: Palette.spaceXs) {
                    ForEach(AccentTheme.allCases) { item in
                        AccentSwatch(theme: item, isSelected: accent == item) {
                            accent = item
                            Settings.shared.accentTheme = item
                        }
                    }
                }
            }

            // Иконку приложения выбором не поменять — она лежит в подписанном
            // бандле, и запись туда ломает подпись, к которой привязаны
            // разрешения. Честно говорим об этом, а не прячем ограничение.
            Hint("Иконка приложения не меняется: она часть подписи, без которой слетают разрешения")
        }
    }

    private var theme: some View {
        GlassCard("Тема") {
            SettingRow("Оформление", subtitle: appearance.summary) {
                SegmentedControl(selection: $appearance, options: AppearanceMode.allCases,
                                 compact: true) { $0.title }
                    .frame(width: 240)
            }
            .onChange(of: appearance) { _, newValue in
                Settings.shared.appearanceMode = newValue
                newValue.apply()
            }
        }
    }

    private struct AccentSwatch: View {
        let theme: AccentTheme
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 22, height: 22)
                    // Выбранный обведён кольцом с зазором, а не галочкой:
                    // галочка на цветном кружке читается хуже кольца.
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                            .padding(-4)
                    )
                    .contentShape(Circle().inset(by: -4))
            }
            .buttonStyle(.plain)
            .help(Text(theme.title))
            .accessibilityLabel(theme.title)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }
}

/// Карточка «Звуки»: громкость и что именно звучит.
///
/// Поштучно, а не одним выключателем: сигнал старта нужен почти всем — без
/// него не понять, что запись пошла, — а «текст вставлен» многих раздражает,
/// потому что результат и так виден в поле.
private struct SoundsCard: View {
    @State private var enabled = Settings.shared.playSounds
    @State private var volume = Settings.shared.soundVolume
    @State private var events: [SoundEvent: Bool] = Dictionary(
        uniqueKeysWithValues: SoundEvent.allCases.map { ($0, Settings.shared.isSoundEnabled($0)) }
    )

    var body: some View {
        GlassCard("Звуки") {
            SwitchToggle("Звуковые сигналы", isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    Settings.shared.playSounds = newValue
                }

            SettingRow("Громкость") {
                HStack(spacing: Palette.spaceXs) {
                    Slider(value: $volume, in: 0...1)
                        .controlSize(.small)
                        .frame(width: 180)
                        .tint(Palette.accent)
                    Text("\(Int(volume * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            // Послушать громкость можно кнопкой у любого сигнала ниже:
            // крутить ручку вслепую — гадание.
            .onChange(of: volume) { _, newValue in
                Settings.shared.soundVolume = newValue
            }

            CardDivider()

            ForEach(SoundEvent.allCases) { event in
                SettingRow(event.title, subtitle: event.subtitle) {
                    HStack(spacing: Palette.spaceXs) {
                        Button {
                            Sounds.preview(event)
                        } label: {
                            Image(systemName: "play.circle")
                                .font(.system(size: 15))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Послушать")

                        Toggle("", isOn: binding(for: event))
                            .toggleStyle(GlassSwitchStyle())
                            .labelsHidden()
                    }
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.45)
        }
    }

    private func binding(for event: SoundEvent) -> Binding<Bool> {
        Binding(
            get: { events[event] ?? true },
            set: { newValue in
                events[event] = newValue
                Settings.shared.setSound(newValue, for: event)
            }
        )
    }
}

/// Тема оформления приложения.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var summary: String {
        switch self {
        case .system: return "Следует за настройками macOS"
        case .light: return "Всегда светлая, независимо от системы"
        case .dark: return "Всегда тёмная, независимо от системы"
        }
    }

    /// `nil` возвращает приложение под контроль системы.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension Settings {
    /// Тема оформления: ключ `ui.appearance`.
    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: text("ui.appearance", default: "system")) ?? .system }
        set { set(newValue.rawValue, forKey: "ui.appearance") }
    }
}
