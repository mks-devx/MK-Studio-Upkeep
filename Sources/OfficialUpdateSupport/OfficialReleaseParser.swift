// SPDX-License-Identifier: BUSL-1.1
import Foundation
import ProducerUpToDateCore

public enum OfficialReleaseParser {
    public static func version(_ data: Data, entry: OfficialSource) throws -> String {
        guard data.count <= 1_048_576, !data.contains(0), let page = String(data: data, encoding: .utf8) else { throw OfficialCheckError.ambiguous }
        let number: String
        switch entry.adapter {
        case .fabfilterCurrent, .fabfilterLegacy:
            let block: String
            if entry.adapter == .fabfilterCurrent {
                let blocks = groups("<h2\\b[^>]*>Download " + NSRegularExpression.escapedPattern(for: entry.name) + #"</h2>(.*?)(?=<h2\b|\z)"#, page)
                guard blocks.count == 1 else { throw OfficialCheckError.ambiguous }
                block = blocks[0][0]
                let numbers = groups(#"<br\s*/?>\s*([0-9]+\.[0-9]+)\s*&mdash;"#, block)
                guard numbers.count == 1 else { throw OfficialCheckError.ambiguous }
                number = numbers[0][0]
            } else {
                let blocks = groups(#"<h3\b[^>]*>Pro-Q ([0-9]+\.[0-9]+)</h3>(.*?)(?=<h3\b|\z)"#, page)
                    .filter { VersionComparator.parse($0[0])?.numbers.first == entry.major }
                guard blocks.count == 1 else { throw OfficialCheckError.ambiguous }
                number = blocks[0][0]; block = blocks[0][1]
            }
            let label = entry.adapter == .fabfilterCurrent ? "Download for macOS" : "macOS"
            let links = groups(#"<a\b[^>]*href="([^"]+)"[^>]*>\s*([^<]+)\s*</a>"#, block)
                .filter { $0[1].trimmingCharacters(in: .whitespacesAndNewlines) == label }
            let expected = "https://cdn-b.fabfilter.com/downloads/ffproq" + number.replacingOccurrences(of: ".", with: "") + ".dmg"
            guard links.count == 1, links[0][0] == expected else { throw OfficialCheckError.ambiguous }
        case .reaper:
            guard groups(#"<title>(.*?)</title>"#, page) == [["REAPER | Download"]] else { throw OfficialCheckError.ambiguous }
            let numbers = groups(#"<div\b[^>]*class=['"]hdrbottom['"][^>]*>Version ([0-9]+\.[0-9]+): [^<]+</div>"#, page)
            guard numbers.count == 1 else { throw OfficialCheckError.ambiguous }
            number = numbers[0][0]
            let expected = "files/\(entry.major).x/reaper" + number.replacingOccurrences(of: ".", with: "") + "_universal.dmg"
            let links = groups(#"<a\b[^>]*href=['"]([^'"]+)['"][^>]*title=['"]Download REAPER for macOS Universal['"][^>]*>"#, page)
            guard !links.isEmpty, links.allSatisfy({ $0[0] == expected }) else { throw OfficialCheckError.ambiguous }
        }
        guard let parsed = VersionComparator.parse(number), parsed.channel == .stable, parsed.numbers.first == entry.major else { throw OfficialCheckError.ambiguous }
        return number
    }
    private static func groups(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
            (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" }
        }
    }
}
