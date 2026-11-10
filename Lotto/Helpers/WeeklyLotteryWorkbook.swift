import Foundation

/// Minimal OOXML workbook for on-device exports; no network or third-party runtime required.
enum WeeklyLotteryWorkbook {
    static let headers = ["Spill", "År", "Uke", "Trekningsdato"] + (1...7).map { "Hovedtall \($0)" } + ["Vikingtall", "Stjernetall 1", "Stjernetall 2", "Registrert"]
    static func data(rows: [LotteryReportRow]) -> Data {
        let ordered = WeeklyLotteryReport.normalized(rows)
        let heading = headers.enumerated().map { text($0.element, column: $0.offset, row: 1, style: 1) }.joined()
        var body = "<row r=\"1\" ht=\"28\" customHeight=\"1\">\(heading)</row>"
        for (index, item) in ordered.enumerated() {
            let row = index + 2
            var cells = text(item.game.title, column: 0, row: row)
            cells += number(Double(item.week.year), column: 1, row: row)
            cells += number(Double(item.week.number), column: 2, row: row)
            cells += number(excelDate(item.date), column: 3, row: row, style: 2)
            for (offset, value) in item.mainNumbers.sorted().enumerated() {
                cells += number(Double(value), column: offset + 4, row: row)
            }
            for (offset, value) in item.extraNumbers.sorted().enumerated() {
                cells += number(Double(value), column: item.game == .vikinglotto ? 11 : 12 + offset, row: row)
            }
            cells += text(item.isRegistered ? "Ja" : "Nei", column: 14, row: row)
            body += "<row r=\"\(row)\" ht=\"22\" customHeight=\"1\">\(cells)</row>"
        }
        let last = max(1, ordered.count + 1)
        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <dimension ref="A1:O\(last)"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <cols><col min="1" max="1" width="17" customWidth="1"/><col min="2" max="3" width="9" customWidth="1"/><col min="4" max="4" width="18" customWidth="1"/><col min="5" max="15" width="16" customWidth="1"/></cols>
        <sheetData>\(body)</sheetData><autoFilter ref="A1:O\(last)"/>
        <pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/><pageSetup orientation="landscape" paperSize="9"/>
        </worksheet>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="1"><numFmt numFmtId="164" formatCode="dd.mm.yyyy"/></numFmts>
        <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
        <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF244B6B"/><bgColor indexed="64"/></patternFill></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        </styleSheet>
        """
        return StoredZip.data([
            ("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """),
            ("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """),
            ("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Rekker" sheetId="1" r:id="rId1"/></sheets></workbook>
            """),
            ("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """),
            ("xl/styles.xml", styles), ("xl/worksheets/sheet1.xml", sheet)
        ])
    }
    static func excelDate(_ date: Date) -> Double {
        let calendar = LotteryReportWeek.calendar
        let base = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        return Double(calendar.dateComponents([.day], from: base, to: calendar.startOfDay(for: date)).day!)
    }
    private static func text(_ text: String, column: Int, row: Int, style: Int = 0) -> String {
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return "<c r=\"\(letter(column))\(row)\" t=\"inlineStr\" s=\"\(style)\"><is><t>\(escaped)</t></is></c>"
    }
    private static func number(_ value: Double, column: Int, row: Int, style: Int = 0) -> String {
        "<c r=\"\(letter(column))\(row)\" s=\"\(style)\"><v>\(value)</v></c>"
    }
    private static func letter(_ column: Int) -> String { String(UnicodeScalar(65 + column)!) }
}

/// Stored ZIP entries are sufficient for these small XML reports and are universally readable.
private enum StoredZip {
    static func data(_ files: [(String, String)]) -> Data {
        var result = Data(), directory = Data()
        for (path, text) in files {
            let name = Data(path.utf8), content = Data(text.utf8)
            let offset = UInt32(result.count), size = UInt32(content.count), checksum = crc32(content)
            result.appendLE(UInt32(0x04034b50)); result.appendLE(UInt16(20)); result.appendLE(UInt16(0)); result.appendLE(UInt16(0))
            result.appendLE(UInt16(0)); result.appendLE(UInt16(0x21)); result.appendLE(checksum)
            result.appendLE(size); result.appendLE(size); result.appendLE(UInt16(name.count)); result.appendLE(UInt16(0))
            result.append(name); result.append(content)
            directory.appendLE(UInt32(0x02014b50)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0x21))
            directory.appendLE(checksum); directory.appendLE(size); directory.appendLE(size)
            directory.appendLE(UInt16(name.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0)); directory.appendLE(UInt32(0)); directory.appendLE(offset); directory.append(name)
        }
        let start = UInt32(result.count)
        result.append(directory)
        result.appendLE(UInt32(0x06054b50)); result.appendLE(UInt16(0)); result.appendLE(UInt16(0))
        result.appendLE(UInt16(files.count)); result.appendLE(UInt16(files.count))
        result.appendLE(UInt32(directory.count)); result.appendLE(start); result.appendLE(UInt16(0))
        return result
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }
}
private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
