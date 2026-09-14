import Foundation

struct Sekai: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let gameURL: URL
    let creatorID: String
    let creatorName: String
    let likeCount: Int

    enum CodingKeys: String, CodingKey {
        case id = "game_id", title, gameURL = "game_url"
        case creatorID = "creator_id", creatorName = "creator_name", likeCount = "like_count"
    }
}
