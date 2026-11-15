import SwiftUI
import Charts

struct LotterySpendingSection: View {
    let records: [LotteryLedgerRecord]
    let month: Date
    @State private var reduction = 25.0
    private var history: [LotterySpending.Month] { LotterySpending.months(records: records, ending: month) }
    private var baseline: Int { history.last?.stakeOre ?? 0 }
    private var previous: Int { history.dropLast().last?.stakeOre ?? 0 }
    private var scenario: LotterySpending.Scenario { LotterySpending.scenario(monthlyOre: baseline, reductionPercent: Int(reduction)) }
    private func label(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.timeZone = LotteryCalendar.calendar.timeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    private func change(_ amount: Int) -> String { (amount > 0 ? "+" : "") + LotteryLedger.money(amount) }
    var body: some View {
        Section("Innsats og årsbeløp") {
            LabeledContent("Registrert innsats i valgt måned", value: LotteryLedger.money(baseline))
            LabeledContent("Endring fra måneden før", value: change(baseline - previous))
            LabeledContent("Samme månedsbeløp i 12 måneder", value: LotteryLedger.money(baseline * 12))
            LabeledContent("Registrert innsats i valgt kalenderår", value: LotteryLedger.money(LotterySpending.yearStake(records: records, selected: month)))
            Text("Bare registrert innsats med trekningsdato til og med i dag er med. Fremtidige trekninger er utelatt. Årsbeløpet er månedsbeløpet ganget med 12, ikke en prognose. En påbegynt måned kan ikke sammenlignes direkte med en hel måned.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Prøv lavere innsats") {
            Text("Reduksjon: \(Int(reduction)) %")
            Slider(value: $reduction, in: 0...100, step: 5) {
                Text("Reduser månedens nivå")
            }.accessibilityValue("\(Int(reduction)) prosent")
            LabeledContent("Lavere månedsinnsats", value: LotteryLedger.money(scenario.monthlyOre))
            LabeledContent("Tilsvarer over 12 måneder", value: LotteryLedger.money(scenario.yearlyOre))
            LabeledContent("Mindre innsats per måned", value: LotteryLedger.money(scenario.monthlySavingOre))
            LabeledContent("Mindre innsats over 12 måneder", value: LotteryLedger.money(scenario.yearlySavingOre))
            Text("Dette er en sammenligning med valgt måneds registrerte innsats. Glidebryteren endrer ikke lagrede spill eller månedsgrensen, og anslår ikke fremtidige gevinster.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Innsats siste 12 måneder") {
            Chart {
                ForEach(history) { item in
                    LineMark(x: .value("Måned", item.date, unit: .month), y: .value("Innsats i kroner", Double(item.stakeOre) / 100))
                    PointMark(x: .value("Måned", item.date, unit: .month), y: .value("Innsats i kroner", Double(item.stakeOre) / 100))
                        .accessibilityLabel(label(item.date))
                        .accessibilityValue(LotteryLedger.money(item.stakeOre))
                }
                RuleMark(y: .value("Valgt lavere månedsnivå", Double(scenario.monthlyOre) / 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartYAxisLabel("Kroner")
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { value in
                AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
            } }
            .frame(height: 190)
            .environment(\.locale, Locale(identifier: "nb_NO"))
            Text("Kurven viser registrert innsats før gevinster. Den stiplede linjen viser det lavere månedsnivået du prøver over. Manglende registreringer vises som 0 kr, og betyr ikke nødvendigvis at det ikke ble spilt.").font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Månedsbeløp og endring i kroner") {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 3) {
                        LabeledContent(label(item.date), value: LotteryLedger.money(item.stakeOre))
                        if index > 0 { Text("Endring: \(change(item.stakeOre - history[index - 1].stakeOre))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}
