import Foundation

/// Ein veroeffentlichtes Release, das als Update in Frage kommt.
struct UpdateRelease: Equatable {
    let version: AppVersion
    let tagName: String
    let releaseNotes: String
    let archiveURL: URL
    let signatureURL: URL
    let archiveSize: Int
}
