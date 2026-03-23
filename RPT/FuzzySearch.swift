import Foundation

// MARK: - FuzzySearch
//
// Lightweight fuzzy matching utility used across all search bars in the app.
// Combines three signals into a single 0-1 score:
//   1. Exact / prefix / contains bonus   (fast, zero cost)
//   2. Token overlap                     (handles word-reordering)
//   3. Levenshtein edit distance         (handles typos like "quafs" → "quads")
//
// Usage:
//   let score = FuzzySearch.score(query: "quafs", against: "Quadriceps")
//   let sorted = FuzzySearch.sort(query: "ice crean", items: foods, string: { $0.name })

enum FuzzySearch {

    // MARK: - Public API

    /// Returns a relevance score in 0…1 (higher = better match).
    /// Returns 0 when the match is too poor to show.
    static func score(query: String, against candidate: String) -> Double {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let c = candidate.lowercased().trimmingCharacters(in: .whitespaces)

        guard !q.isEmpty, !c.isEmpty else { return 0 }

        // --- Tier 1: exact / prefix / contains (cheap, high signal) ---
        if c == q                         { return 1.0 }
        if c.hasPrefix(q)                 { return 0.95 }
        if c.contains(q)                  { return 0.85 }

        // --- Tier 2: token overlap ---
        // "ice cream" query vs "ice cream sandwich" candidate
        let qTokens = q.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let cTokens = c.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var tokenScore = 0.0
        for qt in qTokens {
            // Check if any candidate token contains or is close to this query token
            let bestToken = cTokens.map { tokenSimilarity(qt, $0) }.max() ?? 0
            tokenScore += bestToken
        }
        if !qTokens.isEmpty {
            tokenScore /= Double(qTokens.count)
        }

        // --- Tier 3: full-string edit distance (catches typos) ---
        let editScore = editSimilarity(q, c)

        // Blend: token overlap weighted higher than raw edit distance
        let blended = max(tokenScore * 0.7 + editScore * 0.3, editScore)

        // Threshold — below 0.35 is noise
        return blended >= 0.35 ? blended : 0
    }

    /// Filters and sorts an array by fuzzy relevance against the query.
    /// Items that score 0 are excluded entirely.
    static func sort<T>(
        query: String,
        items: [T],
        string keyPath: (T) -> String,
        additionalStrings: ((T) -> [String])? = nil
    ) -> [T] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }

        let scored: [(item: T, score: Double)] = items.compactMap { item in
            var best = score(query: query, against: keyPath(item))
            if let extras = additionalStrings?(item) {
                for extra in extras {
                    best = max(best, score(query: query, against: extra))
                }
            }
            return best > 0 ? (item, best) : nil
        }

        return scored
            .sorted { $0.score > $1.score }
            .map { $0.item }
    }

    // MARK: - Internal helpers

    /// Similarity between two single tokens: prefix / contains / edit distance.
    private static func tokenSimilarity(_ a: String, _ b: String) -> Double {
        if b == a         { return 1.0 }
        if b.hasPrefix(a) { return 0.9 }
        if b.contains(a)  { return 0.75 }
        return editSimilarity(a, b)
    }

    /// Normalised edit-distance similarity in 0…1.
    /// Uses classic Wagner-Fischer DP; capped at length 30 per string to stay O(1) worst-case.
    private static func editSimilarity(_ a: String, _ b: String) -> Double {
        let a = String(a.prefix(30))
        let b = String(b.prefix(30))
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - Double(dist) / Double(maxLen)
    }

    /// Classic Levenshtein distance (insertions, deletions, substitutions each cost 1).
    private static func levenshtein(_ s: String, _ t: String) -> Int {
        let s = Array(s), t = Array(t)
        let m = s.count, n = t.count
        if m == 0 { return n }
        if n == 0 { return m }

        // Two-row rolling array for O(min(m,n)) space
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = Swift.min(
                    curr[j - 1] + 1,          // insertion
                    prev[j] + 1,              // deletion
                    prev[j - 1] + cost        // substitution
                )
            }
            prev = curr
        }
        return prev[n]
    }
}
