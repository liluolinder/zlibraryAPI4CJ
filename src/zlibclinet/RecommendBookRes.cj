package zlibraryAPI4CJ.zlibclinet

public struct RecommendBookRes <: Serializable<RecommendBookRes> {
    public var success: Int8 = 0
    public var books: ?Array<ZlibBook> = None
    public var nextPage: ?Int64 = 0

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<Int8>("success", success))
            .add(field<Option<Array<ZlibBook>>>("books", books))
            .add(field<Option<Int64>>("nextPage", nextPage))
    }

    public static func deserialize(dm: DataModel): RecommendBookRes {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = RecommendBookRes()
        result.success = Int8.deserialize(dms.get("success"))
        result.books = Option<Array<ZlibBook>>.deserialize(dms.get("books"))
        result.nextPage = Option<Int64>.deserialize(dms.get("nextPage"))
        return result
    }
}
