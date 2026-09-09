// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Maintainer evidence for a version-free official destination.
public enum OfficialLinkReview {
    public static func isValid(date: String) -> Bool {
        guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let parsed = formatter.date(from: date) else { return false }
        return formatter.string(from: parsed) == date
    }

    public static func isComplete(referenceURL: URL, reviewedOn: String) -> Bool {
        referenceURL.scheme?.lowercased() == "https"
            && referenceURL.host?.isEmpty == false
            && referenceURL.user == nil
            && referenceURL.password == nil
            && isValid(date: reviewedOn)
    }
}
