import Foundation
import Testing
@testable import MarkdownCore

struct SluggerTests {
    struct Vectors: Decodable {
        struct Single: Decodable { let `in`: String; let out: String }
        struct Sequence: Decodable { let `in`: [String]; let out: [String] }
        let single: [Single]
        let sequence: [Sequence]
    }

    static func vectors() throws -> Vectors {
        let url = try #require(Bundle.module.url(forResource: "slugger-vectors", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }

    @Test func singleVectors() throws {
        for vector in try Self.vectors().single {
            #expect(GitHubSlugger.slug(vector.in) == vector.out, "slug(\(vector.in))")
        }
    }

    @Test func sequenceVectors() throws {
        for vector in try Self.vectors().sequence {
            var slugger = GitHubSlugger()
            #expect(vector.in.map { slugger.uniqueSlug($0) } == vector.out)
        }
    }
}
