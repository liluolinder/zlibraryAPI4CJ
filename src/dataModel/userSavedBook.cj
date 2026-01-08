package zlibraryAPI4CJ.dataModel

public struct GetUserSavedBookRes <: Serializable<GetUserSavedBookRes> {
    public var success: UInt8 = 0
    public var books: Array<BookInfo> = []
    public var pagination: GetUserSavedBookPagination = GetUserSavedBookPagination()

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<UInt8>("success", success))
            .add(field<Array<BookInfo>>("books", books))
            .add(field<GetUserSavedBookPagination>("pagination", pagination))
    }
    public static func deserialize(dm: DataModel): GetUserSavedBookRes {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = GetUserSavedBookRes()
        result.success = UInt8.deserialize(dms.get("success"))
        result.books = Array<BookInfo>.deserialize(dms.get("books"))
        result.pagination = GetUserSavedBookPagination.deserialize(dms.get("pagination"))
        return result
    }
}

public struct GetUserSavedBookPagination <: Serializable<GetUserSavedBookPagination> {
    public var limit: UInt64 = 0
    public var current: UInt64 = 0
    public var before: Bool = false
    public var next: Bool = false
    public var totalItems: UInt64 = 0
    public var totalPages: UInt64 = 0

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<UInt64>("limit", limit))
            .add(field<UInt64>("current", current))
            .add(field<Bool>("before", before))
            .add(field<Bool>("next", next))
            .add(field<UInt64>("total_items", totalItems))
            .add(field<UInt64>("total_pages", totalPages))
    }
    public static func deserialize(dm: DataModel): GetUserSavedBookPagination {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = GetUserSavedBookPagination()
        result.limit = UInt64.deserialize(dms.get("limit"))
        result.current = UInt64.deserialize(dms.get("current"))
        result.before = Bool.deserialize(dms.get("before"))
        result.next = Bool.deserialize(dms.get("next"))
        result.totalItems = UInt64.deserialize(dms.get("total_items"))
        result.totalPages = UInt64.deserialize(dms.get("total_pages"))
        return result
    }
}
