// F26 regression repro — Treeswift's empty-ancestor promotion must NOT delete a type that is still
// referenced AS A TYPE by a surviving declaration.
//
// Shape: every MEMBER of a type is flagged (each stored property gets a redundant-accessibility
// narrowing; one initializer is `unused`), but the TYPE itself is NOT flagged unused. Applying all
// the member-level changes empties the type, and `findHighestEmptyAncestor` would promote the
// deletion up to the whole type — even though a kept property / parameter / construction in another
// type still names it. The result is a deleted type with dangling references:
//
//   error: cannot find type 'VideoFmt' in scope
//   (and the owner loses its synthesized Codable/Equatable conformance)
//
// Real-world origin: Prodcore baseline R3 `23ad2547`:
//   - `struct VideoFormat` (members all flagged) deleted while `MediaFormat.video: VideoFormat?` kept.
//   - `struct PreviewSettings` (members all flagged) deleted while `ProductImportProcessor`
//     constructs `PreviewSettings(...)` and takes `settings: PreviewSettings`.
// Periphery is CORRECT here — it never flags the STRUCT as unused, only its members. The bug is in
// Treeswift's removal promotion.
//
// Expected after redundant-accessibility + unused removal (`forceRemoveAll`):
//   - members of `VideoFmt` are individually narrowed/removed as flagged, BUT
//   - `struct VideoFmt` is KEPT (it is still named by `Container.video: VideoFmt?`), so the file
//     compiles — no "cannot find type" error.
//
// Bug behavior (pre-F26): the whole `struct VideoFmt` was deleted → dangling `video: VideoFmt?`.
//
// In-repo verification: end-to-end (build_errors == 0 on R3 after F26). The fix is the
// `isReferencedAsTypeBySurvivingDeclaration` guard in
// `CodeModificationHelper.findHighestEmptyAncestor`.

// swiftformat:disable all

import Foundation

// A type whose members are all flaggable (props -> redundant-acc, memberwise init -> unused once the
// `from:` init is the only caller path), but which is still used as `Container.video`'s type.
struct VideoFmt: Codable, Equatable {
    var width: Int
    var height: Int
}

struct Container: Codable, Equatable {
    var codec: String
    var video: VideoFmt?

    init(codec: String, video: VideoFmt? = nil) {
        self.codec = codec
        self.video = video
    }
}
