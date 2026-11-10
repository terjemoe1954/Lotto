import SwiftUI
import SwiftData
import Charts

struct InternationalStatisticsView: View {
    let game: InternationalGame
    @Query(sort: \InternationalLotteryEntry.date) private var entries: [InternationalLotteryEntry]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGap = false
    @State private var extraPool = false
    @State private var period = LotteryStatisticsPeriod.all
    @State private var sortOrder = LotteryStatisticsSort.mostFrequent

    var body: some View {
        let report = InternationalLotteryStatistics.report(
            records: entries.map(\.archiveRecord), game: game, extraPool: extraPool,
            period: period, excludeHighestGap: excludeHighestGap
        )
        let rows = report.sorted(by: sortOrder)
        NavigationStack {
            List {
                Section {
                    Picker("Tallgruppe", selection: $extraPool) {
                        Text("Hovedtall").tag(false)
                        Text(game.extraTitle).tag(true)
                    }.pickerStyle(.segmented)
                    Picker("Periode", selection: $period) {
                        ForEach(LotteryStatisticsPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Trekninger i perioden", value: "\(report.drawCount)")
                    if let first = report.firstDate, let last = report.lastDate {
                        Text("\(LotteryCalendar.text(first)) – \(LotteryCalendar.text(last))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if report.missingDrawCount > 0 {
                        Label("\(report.missingDrawCount) planlagte trekninger mangler mellom første og siste dato. Intervaller i trekninger teller bare lagrede resultater.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if report.drawCount > 0 {
                    frequencyChart(report)
                    Section {
                        Picker("Sorter etter", selection: $sortOrder) {
                            ForEach(LotteryStatisticsSort.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Utelat lengste intervall fra snittet", isOn: $excludeHighestGap)
                        if excludeHighestGap {
                            Text("Det lengste intervallet i dager tas ut av begge gjennomsnitt når minst to intervaller finnes. Antall og lengste intervall endres ikke. Innstillingen deles med Lotto.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        ForEach(rows) { row in
                            statisticsRow(row)
                        }
                    } header: {
                        Text(extraPool ? game.extraTitle : "Hovedtall")
                    } footer: {
                        Text("Andel betyr prosent av trekningene i valgt periode. Snitt og lengste intervall beregnes mellom forekomster i perioden. Dager siden sist måles fram til i dag. Trykk på et tall for flere detaljer. Historiske mønstre endrer ikke vinnersjansen i neste trekning.")
                    }
                } else {
                    Section {
                        ContentUnavailableView("Ingen trekninger i perioden", systemImage: "chart.bar",
                                               description: Text("Velg en annen periode eller hent nye trekninger fra spillets hovedside."))
                    }
                }
            }
            .navigationTitle("\(game.title) statistikk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ferdig") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText(report: report, rows: rows)) {
                        Label("Del statistikk", systemImage: "square.and.arrow.up")
                    }.disabled(report.drawCount == 0)
                }
            }
        }
    }

    private func frequencyChart(_ report: LotteryStatisticsReport) -> some View {
        let top = Array(report.sorted(by: .mostFrequent).filter { $0.count > 0 }.prefix(10))
        return Section {
            Chart(top) { row in
                BarMark(x: .value("Forekomster", row.count), y: .value("Tall", String(row.number)))
                    .foregroundStyle(Color.accentColor.gradient)
                    .annotation(position: .trailing) { Text("\(row.count)").font(.caption).monospacedDigit() }
                    .accessibilityLabel("Tall \(row.number)")
                    .accessibilityValue("\(row.count) forekomster")
            }
            .chartYScale(domain: top.map { String($0.number) })
            .chartXAxisLabel("Antall trekninger med tallet")
            .frame(height: CGFloat(top.count * 27 + 35))
            .padding(.trailing, 20)
            .padding(.vertical, 4)
        } header: {
            Text(top.count < 10 ? "Forekomster" : "De 10 vanligste tallene")
        } footer: {
            Text("\(extraPool ? game.extraTitle : "Hovedtall") telles separat. Tall med likt antall vises i tallrekkefølge.")
        }
    }

    private func statisticsRow(_ row: LotteryNumberStatistics) -> some View {
        DisclosureGroup {
            LabeledContent("Sist trukket", value: row.lastDate.map { LotteryCalendar.text($0) } ?? "Ikke sett i perioden")
            LabeledContent("Dager siden sist", value: row.daysSinceLast.map(String.init) ?? "–")
            LabeledContent("Lagrede trekninger siden sist", value: row.drawsSinceLast.map(String.init) ?? "–")
            LabeledContent("Snitt mellom forekomster", value: unit(row.averageDays, suffix: "dager"))
            LabeledContent("Snitt i trekninger", value: unit(row.averageDraws, suffix: "trekninger"))
            LabeledContent("Lengste intervall", value: row.longestGapDays.map { "\($0) dager" } ?? "–")
            LabeledContent("Lengste intervall i trekninger", value: row.longestGapDraws.map(String.init) ?? "–")
            if row.count < 2 {
                Text("Minst to forekomster i perioden kreves for å beregne intervaller.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(row.number)")
                    .font(.headline).monospacedDigit()
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(row.count) forekomster · \(row.share.formatted(.percent.precision(.fractionLength(1))))")
                        .font(.subheadline.bold()).foregroundStyle(.primary)
                    if let last = row.lastDate, let since = row.drawsSinceLast {
                        Text("Sist \(LotteryCalendar.text(last)) · \(since) trekninger siden")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Ikke sett i valgt periode").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Snitt: \(unit(row.averageDays, suffix: "dager")) / \(unit(row.averageDraws, suffix: "trekninger"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 3)
        }
    }

    private func unit(_ value: Double?, suffix: String) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(1)))) \(suffix)" } ?? "–"
    }

    private func shareText(report: LotteryStatisticsReport, rows: [LotteryNumberStatistics]) -> String {
        var lines = ["\(game.title) – \(extraPool ? game.extraTitle : "Hovedtall")", period.title,
                     "\(report.drawCount) trekninger",
                     "Periode: \(report.firstDate.map { LotteryCalendar.text($0) } ?? "–") – \(report.lastDate.map { LotteryCalendar.text($0) } ?? "–")",
                     "Dager siden sist beregnet per \(LotteryCalendar.text(.now))."]
        if excludeHighestGap { lines.append("Lengste intervall er utelatt fra gjennomsnittene når minst to intervaller finnes.") }
        if report.missingDrawCount > 0 { lines.append("\(report.missingDrawCount) planlagte trekninger mangler i perioden.") }
        for row in rows {
            lines.append("Tall \(row.number): \(row.count) ganger (\(row.share.formatted(.percent.precision(.fractionLength(1))))). Sist: \(row.lastDate.map { LotteryCalendar.text($0) } ?? "ikke sett"). Dager siden: \(row.daysSinceLast.map(String.init) ?? "–"). Trekninger siden: \(row.drawsSinceLast.map(String.init) ?? "–"). Snitt: \(unit(row.averageDays, suffix: "dager")) / \(unit(row.averageDraws, suffix: "trekninger")). Lengste intervall: \(row.longestGapDays.map { "\($0) dager" } ?? "–") / \(row.longestGapDraws.map { "\($0) trekninger" } ?? "–").")
        }
        lines.append("Historiske mønstre endrer ikke vinnersjansen i neste trekning.")
        return lines.joined(separator: "\n")
    }
}
