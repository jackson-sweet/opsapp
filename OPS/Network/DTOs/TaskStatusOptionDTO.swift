import Foundation

struct TaskStatusOptionDTO: Codable {
    let _id: String
    let Display: String
    let Color: String
    let Index: Double
    let Company: String
    let Created_Date: String?
    let Modified_Date: String?

    enum CodingKeys: String, CodingKey {
        case _id
        case Display
        case Color
        case Index
        case Company
        case Created_Date
        case Modified_Date
    }
}
