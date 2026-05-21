import Foundation

enum ResponseState: Equatable {
    case idle
    case input
    case loading
    case success(String, ResponseMetadata?)
    case failure(String)
}

struct ResponseMetadata: Equatable {
    let model: String
    let totalTokens: Int
}
