import AppKit
import SwiftUI

/// Столбцы расходов по дням.
///
/// **Почему не Swift Charts.** Линковка голым `swiftc` проверена и проходит,
/// дело не в ней: у `BarMark` на macOS 13 нет способа скруглить только верх —
/// `.cornerRadius` округляет все четыре угла, а `UnevenRoundedRectangle`
/// появился в macOS 14, при цели 13.0. Утверждённый мокап требует ровно
/// «скругление сверху, низ на базовой линии», плюс фиксированную ширину
/// столбца и прямой ярлык на единственном экстремуме. Всё это — тридцать строк
/// `Path`, и они дают ту геометрию, которая согласована, а не близкую к ней.
///
/// Форма из `dna.md`: одна серия — одна кривая величина, поэтому один тон,
/// без легенды, без второй оси. Значение подписано прямо у столбца-максимума,
/// остальные читаются по трём делениям слева.
struct UsageChart: View {
    struct Point: Identifiable, Equatable {
        let day: Date
        /// Доллары за этот день.
        let value: Double

        var id: Date { day }
    }

    let points: [Point]

    @State private var hovered: Int?

    // Геометрия из мокапа: поля вокруг области построения и её высота.
    private let padLeading: CGFloat = 40
    private let padTrailing: CGFloat = 6
    private let padTop: CGFloat = 24
    private let plotHeight: CGFloat = 100
    private let labelStrip: CGFloat = 28

    /// Полная высота: 24 сверху под ярлык + 100 область + 28 под подписи дат.
    private var totalHeight: CGFloat { padTop + plotHeight + labelStrip }

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(
                width: geometry.size.width,
                padLeading: padLeading,
                padTrailing: padTrailing,
                padTop: padTop,
                plotHeight: plotHeight,
                points: points
            )

            ZStack(alignment: .topLeading) {
                grid(layout)
                bars(layout)
                peakLabel(layout)
                dateLabels(layout)
                tooltip(layout)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovered = layout.index(atX: location.x)
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Слои

    /// Три деления по Y плюс базовая линия. Сплошной волосок, без пунктира:
    /// пунктир на сетке спорит с волосками-разделителями внутри карточки.
    private func grid(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.ticks, id: \.self) { tick in
                let y = layout.y(for: tick)

                Path { path in
                    path.move(to: CGPoint(x: padLeading, y: y))
                    path.addLine(to: CGPoint(x: layout.width - padTrailing, y: y))
                }
                .stroke(Self.gridColor, lineWidth: 1)

                Text(tick == 0 ? "0" : Pricing.money(tick))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: padLeading - 8, alignment: .trailing)
                    .offset(y: y - 7)
            }
        }
    }

    private func bars(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let height = layout.height(for: point.value)
                if height > 0 {
                    TopRoundedBar(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: layout.barWidth, height: height)
                        .brightness(hovered == index ? 0.06 : 0)
                        .offset(
                            x: layout.centerX(index) - layout.barWidth / 2,
                            y: layout.baseline - height
                        )
                }
            }
        }
    }

    /// Прямой ярлык — только на максимуме. Подписывать каждый столбец значит
    /// заменить график таблицей; подписывать ноль столбцов — заставить
    /// человека считать по сетке.
    @ViewBuilder
    private func peakLabel(_ layout: Layout) -> some View {
        if let peak = layout.peakIndex, points[peak].value > 0 {
            let height = layout.height(for: points[peak].value)

            Text(Pricing.money(points[peak].value))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
                .fixedSize()
                .frame(width: layout.barWidth * 6, alignment: .center)
                .offset(
                    x: layout.centerX(peak) - layout.barWidth * 3,
                    y: layout.baseline - height - 16
                )
        }
    }

    private func dateLabels(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.dateTickIndices, id: \.self) { index in
                Text(Self.shortDay(points[index].day))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: 60, alignment: .center)
                    .offset(x: layout.centerX(index) - 30, y: layout.baseline + 8)
            }
        }
    }

    /// Значение под курсором — точной цифрой. Столбец сам по себе отвечает
    /// на «много или мало», а на «сколько именно» отвечает подсказка.
    @ViewBuilder
    private func tooltip(_ layout: Layout) -> some View {
        if let index = hovered, points.indices.contains(index) {
            let point = points[index]
            let top = max(layout.baseline - layout.height(for: point.value), padTop)

            HStack(spacing: 4) {
                Text(Self.fullDay(point.day))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(Pricing.money(point.value))
            }
            .font(.subheadline)
            .monospacedDigit()
            .padding(.horizontal, Palette.spaceXs)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Palette.radiusField, style: .continuous)
                    .fill(Palette.surfaceField)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Palette.radiusField, style: .continuous)
                    .strokeBorder(Palette.rimCard, lineWidth: 1)
            )
            .fixedSize()
            .allowsHitTesting(false)
            .frame(width: 220, alignment: .center)
            .offset(x: layout.centerX(index) - 110, y: top - 30)
        }
    }

    // MARK: - Раскладка

    /// Всё, что зависит от ширины: шаг, ширина столбца, масштаб по Y, деления.
    private struct Layout {
        let width: CGFloat
        let padLeading: CGFloat
        let padTrailing: CGFloat
        let padTop: CGFloat
        let plotHeight: CGFloat
        let points: [Point]

        var baseline: CGFloat { padTop + plotHeight }
        private var plotWidth: CGFloat { max(width - padLeading - padTrailing, 1) }
        var band: CGFloat { plotWidth / CGFloat(max(points.count, 1)) }

        /// Столбец — доля шага, но не толще 22: на семи днях столбцы шириной
        /// в треть карточки читаются как заливка, а не как величина.
        var barWidth: CGFloat { min(max(band * 0.55, 3), 22) }

        func centerX(_ index: Int) -> CGFloat {
            padLeading + band * CGFloat(index) + band / 2
        }

        func index(atX x: CGFloat) -> Int? {
            guard !points.isEmpty, x >= padLeading, x <= width - padTrailing else { return nil }
            let index = Int((x - padLeading) / band)
            return points.indices.contains(index) ? index : nil
        }

        var peakIndex: Int? {
            points.indices.max { points[$0].value < points[$1].value }
        }

        private var dataMax: Double {
            points.map(\.value).max() ?? 0
        }

        /// Верх шкалы и три деления. Ноль всегда есть — без него столбцы
        /// врут о пропорции.
        var axis: (max: Double, ticks: [Double]) {
            guard dataMax > 0 else { return (1, [0]) }
            let step = Self.niceStep(dataMax / 2)
            let top = max(dataMax, step * 2)
            var ticks: [Double] = [0]
            if step <= top { ticks.append(step) }
            if step * 2 <= top { ticks.append(step * 2) }
            return (top, ticks)
        }

        var ticks: [Double] { axis.ticks }

        func y(for value: Double) -> CGFloat {
            baseline - height(for: value)
        }

        func height(for value: Double) -> CGFloat {
            guard value > 0 else { return 0 }
            return CGFloat(min(value / axis.max, 1)) * plotHeight
        }

        /// Подписи дат. До десяти столбцов подписывается каждый — иначе пять
        /// равномерных отметок на семи днях садятся на соседние столбцы
        /// и читаются как пропуск. Дальше — пять: первая, последняя и три между.
        var dateTickIndices: [Int] {
            guard points.count > 1 else { return points.isEmpty ? [] : [0] }
            guard points.count > 10 else { return Array(points.indices) }
            let wanted = 5
            let last = points.count - 1
            let stride = Double(last) / Double(wanted - 1)
            return (0..<wanted).map { Int((Double($0) * stride).rounded()) }
        }

        /// Круглый шаг сетки: 1, 2 или 5 в своём десятичном порядке, но не мельче цента.
        ///
        /// Оба ограничения обязательны. Половинные шаги (2,5) дали бы деление
        /// `$0.025`, а подпись у него — `$0.02`: линия и её цифра разошлись бы.
        /// Шаг мельче цента подписывается как `$0.00` — деление без значения.
        private static func niceStep(_ value: Double) -> Double {
            guard value > 0.01 else { return 0.01 }
            let exponent = pow(10, (log10(value)).rounded(.down))
            let candidates = [1.0, 2.0, 5.0].map { $0 * exponent }
            return max(candidates.last { $0 <= value } ?? exponent, 0.01)
        }
    }

    // MARK: - Оформление

    /// Сетка светлее любого текста: её задача — дать линейку, а не читаться.
    /// Токена под это в палитре нет, а `DesignSystem.swift` правит только
    /// слайс оформления, поэтому цвет живёт здесь.
    private static let gridColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.10)
            : NSColor(white: 0, alpha: 0.09)
    })

    /// «4 июл» — без точки: точка в подписи оси читается как конец предложения.
    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static func shortDay(_ date: Date) -> String {
        shortFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private static func fullDay(_ date: Date) -> String {
        shortDay(date)
    }

    private var accessibilitySummary: String {
        let total = points.reduce(0) { $0 + $1.value }
        guard let peak = points.max(by: { $0.value < $1.value }), peak.value > 0 else {
            return "Расходы по дням: за \(points.count) дней записей нет"
        }
        return "Расходы по дням за \(points.count) дней, всего \(Pricing.money(total)), "
            + "максимум \(Pricing.money(peak.value)) \(Self.shortDay(peak.day))"
    }
}

/// Столбец со скруглённым верхом и прямым низом: он стоит на базовой линии,
/// а не висит над ней, поэтому нижние углы обязаны остаться острыми.
struct TopRoundedBar: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.height, rect.width / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
