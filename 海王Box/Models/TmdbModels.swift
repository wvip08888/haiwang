import Foundation

let TMDB_SOURCE_KEY = "tmdb"

struct TmdbSearchHit: Codable, Identifiable {
    var id: Int = 0
    var mediaType: String = ""
    var title: String = ""
    var originalTitle: String = ""
    var year: Int = 0
    var posterPath: String = ""
    var originalLanguage: String? = nil
}

struct TmdbCastMember: Codable, Identifiable {
    var id: Int = 0
    var name: String = ""
    var character: String = ""
    var profilePath: String = ""
}

struct TmdbDetail: Codable {
    var overview: String = ""
    var rating: Double = 0
    var genres: [String] = []
    var cast: [TmdbCastMember] = []
    var seasons: [TmdbSeason] = []
}

struct TmdbSeason: Codable, Identifiable {
    var seasonNumber: Int = 0
    var episodeCount: Int = 0
    var id: Int { seasonNumber }
}

struct TmdbEpisode: Codable, Identifiable {
    var name: String = ""
    var stillPath: String = ""
    var id: String { name }
}

struct TmdbEpisodeRef: Codable, Hashable {
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0
}

/// TMDB 配置
struct TmdbConfig: Codable {
    var enabled: Bool = false
    var apiKey: String = ""
    var apiBase: String = "https://api.themoviedb.org/3"
    var imageBase: String = "https://image.tmdb.org/t/p/w500"
    var posterStyle: String = "fixed"  // fixed / random / roll
}
