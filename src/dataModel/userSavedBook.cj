package zlibraryAPI4CJ.dataModel

// public struct GetUserSavedBookRes<: Serializable<GetUserSavedBookRes>{

//     public var success: UInt8 = 0
//     public var book: BookInfo = BookInfo()

//     public func serialize(): DataModel {
//         return DataModelStruct()
//             .add(field<UInt8>("success", success))
//             .add(field<Array<ZlibRecommendBook>>("books", books))
//     }
//     public static func deserialize(dm: DataModel): RecommendBookRes {
//         var dms = match (dm) {
//             case data: DataModelStruct => data
//             case _ => throw Exception("this data is not DataModelStruct")
//         }
//         var result = RecommendBookRes()
//         result.success = UInt8.deserialize(dms.get("success"))
//         result.books = Array<ZlibRecommendBook>.deserialize(dms.get("books"))
//         return result
//     }
// }