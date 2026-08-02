import SwiftUI

/// Токены и общие кирпичики окна настроек.
///
/// Сигнатуры заморожены: разделы вызывают их и не переопределяют.
/// Реализация здесь намеренно простая — оформление доводит слайс «Оформление»,
/// он же единственный, кто правит этот файл.
enum Palette {
    // Шаг сетки 4pt.
    static let space2xs: CGFloat = 4
    static let spaceXs: CGFloat = 8
    static let spaceSm: CGFloat = 12
    static let spaceMd: CGFloat = 16
    static let spaceLg: CGFloat = 20
    static let spaceXl: CGFloat = 24
    static let space2xl: CGFloat = 32

    static let radiusCard: CGFloat = 12
    static let radiusTile: CGFloat = 10
    static let radiusField: CGFloat = 6
    static let radiusRow: CGFloat = 8

    /// Максимальная ширина колонки с карточками.
    static let contentWidth: CGFloat = 640

    static var surfaceCard: Color { Color.primary.opacity(0.05) }
    static var surfaceTile: Color { Color.primary.opacity(0.06) }
    static var surfaceRowHover: Color { Color.primary.opacity(0.05) }
    static var rimCard: Color { Color.primary.opacity(0.09) }
    static var hairline: Color { Color(nsColor: .separatorColor) }
}

/// Каркас панели раздела: одна колонка карточек, прокрутка и поля от краёв окна.
struct SectionScaffold<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Palette.spaceXl) {
                content
            }
            .frame(maxWidth: Palette.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Palette.spaceLg)
            .padding(.vertical, Palette.spaceLg)
        }
        .scrollContentBackground(.hidden)
    }
}

/// Карточка-секция: заголовок внутри, первой строкой.
struct GlassCard<Content: View>: View {
    private let title: String
    private let accessory: AnyView?
    private let content: Content

    init(_ title: String, accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Palette.spaceSm) {
            HStack(spacing: Palette.spaceXs) {
                Text(title).font(.headline)
                Spacer(minLength: Palette.spaceXs)
                accessory
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Palette.spaceMd)
        .background(
            RoundedRectangle(cornerRadius: Palette.radiusCard, style: .continuous)
                .fill(Palette.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Palette.radiusCard, style: .continuous)
                .strokeBorder(Palette.rimCard, lineWidth: 1)
        )
    }
}

/// Строка настройки: подпись слева, контрол справа, описание под подписью.
struct SettingRow<Control: View>: View {
    private let title: String
    private let subtitle: String?
    private let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Palette.spaceSm) {
            VStack(alignment: .leading, spacing: Palette.space2xs) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Palette.spaceSm)
            control
        }
    }
}

/// Переключатель — всегда switch, никогда не чекбокс.
struct SwitchToggle: View {
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// Подсказка под контролом. Допустима, только если объясняет невидимое последствие.
struct Hint: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Плитка статистики: крупное моноширинное число и подпись под ним.
struct StatTile: View {
    private let value: String
    private let caption: String

    init(value: String, caption: String) {
        self.value = value
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Palette.space2xs) {
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Palette.spaceSm)
        .background(
            RoundedRectangle(cornerRadius: Palette.radiusTile, style: .continuous)
                .fill(Palette.surfaceTile)
        )
    }
}
