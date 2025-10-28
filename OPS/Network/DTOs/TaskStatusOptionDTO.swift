import Foundation

struct TaskStatusOptionDTO: Codable {
    let _id: String
    let Display: String
    let color: String
    let index: Double
    let company: String
    let Created_Date: String?
    let Modified_Date: String?

    enum CodingKeys: String, CodingKey {
        case _id
        case Display
        case color
        case index
        case company
        case Created_Date
        case Modified_Date
    }
}
