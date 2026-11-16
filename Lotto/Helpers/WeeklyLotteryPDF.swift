import UIKit

enum WeeklyLotteryPDF {
    static func data(rows: [LotteryReportRow], week: LotteryReportWeek) -> Data {
        let ordered = WeeklyLotteryReport.normalized(rows)
        let pages = WeeklyLotteryReport.pages(ordered)
        let systems = Array(Set(ordered.flatMap(\.systems))).sorted { $0.id < $1.id }
        let summaryPages = systems.isEmpty ? 0 : (systems.count + 4) / 5
        let pageCount = pages.count + summaryPages
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { context in
            for (pageIndex, page) in pages.enumerated() {
                context.beginPage()
                draw("Ukesrapport", x: 28, y: 28, width: 400, size: 22, bold: true)
                draw(week.title, x: 28, y: 59, width: 400, size: 13, bold: true)
                draw(week.dateRange, x: 28, y: 80, width: 400, size: 10)
                draw("\(ordered.count) valgte rekker", x: 428, y: 59, width: 139, size: 11)
                let titles = [("OK", 28.0, 20.0), ("Nr.", 48.0, 25.0), ("Spill", 73.0, 88.0), ("Dato", 161.0, 78.0),
                              ("Hovedtall", 239.0, 187.0), ("Viking-/stjernetall", 426.0, 141.0)]
                for (title, x, width) in titles { draw(title, x: x, y: 110, width: width, size: 10, bold: true) }
                for (index, row) in page.enumerated() {
                    let y = CGFloat(132 + index * 24)
                    if index.isMultiple(of: 2) {
                        UIColor(white: 0.95, alpha: 1).setFill()
                        context.cgContext.fill(CGRect(x: 26, y: y - 4, width: 543, height: 24))
                    }
                    let box = CGRect(x: 28, y: y, width: 11, height: 11)
                    context.cgContext.setStrokeColor(UIColor.gray.cgColor)
                    context.cgContext.setLineWidth(0.8)
                    context.cgContext.stroke(box)
                    if row.isRegistered {
                        context.cgContext.move(to: CGPoint(x: 30, y: y + 5))
                        context.cgContext.addLine(to: CGPoint(x: 33, y: y + 8))
                        context.cgContext.addLine(to: CGPoint(x: 37, y: y + 2))
                        context.cgContext.strokePath()
                    }
                    draw("\(pageIndex * WeeklyLotteryReport.rowsPerPage + index + 1)", x: 48, y: y, width: 25, size: 10)
                    let labels = row.systems.prefix(2).compactMap { item in systems.firstIndex(of: item).map { "S\($0 + 1)" } }.joined(separator: ", ") + (row.systems.count > 2 ? ", +\(row.systems.count - 2)" : "")
                    draw(row.game.title, x: 73, y: y, width: 88, size: 10)
                    if !labels.isEmpty { draw(labels, x: 73, y: y + 11, width: 88, size: 7) }
                    draw(WeeklyLotteryReport.dateText(row.date), x: 161, y: y, width: 78, size: 10)
                    draw(row.mainText, x: 239, y: y, width: 187, size: 10, monospaced: true)
                    draw(row.extraNumbers.isEmpty ? "-" : row.extraText, x: 426, y: y, width: 141, size: 10, monospaced: true)
                }
                draw("\(week.title) | Side \(pageIndex + 1) av \(pageCount)", x: 28, y: 793, width: 539, size: 9)
                draw(systems.isEmpty ? "OK = registrert hos Norsk Tipping" : "OK = registrert hos Norsk Tipping. S1, S2 … viser til systemoversikten bakerst.", x: 28, y: 774, width: 539, size: 9)
            }
            for page in 0..<summaryPages {
                context.beginPage()
                draw("Systemoversikt", x: 28, y: 28, width: 539, size: 22, bold: true)
                draw(week.title + " | " + week.dateRange, x: 28, y: 60, width: 539, size: 11)
                draw("Tallutvalget i hvert system. Delrekker står på de foregående sidene.", x: 28, y: 84, width: 539, size: 10)
                for offset in 0..<5 {
                    let index = page * 5 + offset
                    guard index < systems.count else { break }
                    let item = systems[index], y = CGFloat(124 + offset * 124)
                    draw("S\(index + 1) | \(LotteryReportGame(rawValue: item.gameID)?.title ?? item.gameID) | \(item.dateText)", x: 28, y: y, width: 539, size: 12, bold: true)
                    draw("Hovedtall: " + item.main.map(String.init).joined(separator: "  "), x: 28, y: y + 26, width: 539, size: 11)
                    if !item.extra.isEmpty { draw("Tilleggstall: " + item.extra.map(String.init).joined(separator: "  "), x: 28, y: y + 50, width: 539, size: 11) }
                    let game = LotteryReportGame(rawValue: item.gameID) ?? .lotto
                    let total = LotterySystem.rowCount(game: game, main: item.main.count, extra: item.extra.count)
                    let included = ordered.filter { $0.systems.contains(item) }.count
                    draw("\(included) av \(total) delrekker er med i dette eksportutvalget.", x: 28, y: y + 76, width: 539, size: 10)
                }
                draw("Overlappende delrekker telles bare én gang. Rapporten leverer ikke spill.", x: 28, y: 774, width: 539, size: 9)
                draw("\(week.title) | Side \(pages.count + page + 1) av \(pageCount)", x: 28, y: 793, width: 539, size: 9)
            }
        }
    }
    private static func draw(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat,
                             size: CGFloat, bold: Bool = false, monospaced: Bool = false) {
        let font = monospaced ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            : bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        (text as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 25),
                               withAttributes: [.font: font, .foregroundColor: UIColor.black])
    }
}
