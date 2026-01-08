package zlibraryAPI4CJ.dataModel

public struct GetBookRes <: Serializable<GetBookRes> {
    public var success: UInt8 = 0
    public var books: Array<BookInfoBrief> = []

    public func serialize(): DataModel {
        return DataModelStruct().add(field<UInt8>("success", success)).add(field<Array<BookInfoBrief>>("books", books))
    }
    public static func deserialize(dm: DataModel): GetBookRes {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = GetBookRes()
        result.success = UInt8.deserialize(dms.get("success"))
        result.books = Array<BookInfoBrief>.deserialize(dms.get("books"))
        return result
    }
}

public class BookInfoBrief <: Serializable<BookInfoBrief> {
    public var id: UInt64 = 0
    public var title: String = ''
    public var author: String = ''
    public var cover: String = ''
    public var hash: String = ''

    public func getBookInfo(cookie!: ?String = None): GetBookInfoRes {
        let response = httpClient
            .destory()
            .setDefaultHeader()
            .setIntercept(Intercept(requestL: {
                http => if (cookie.isSome()) {
                    http.httpHeader.set(key: "cookie", value: cookie.getOrThrow())
                }
            }))
            .setUrl("${zlibEAPI}/book/${id}/${hash}")
            .send()

        try {
            let res = GetBookInfoRes.deserialize(response.getBodyDataModel())
            res
        } catch (err: Exception) {
            throw Exception('获取错误，错误信息${err.message}')
        }
    }

    public func getSimilarBook(): GetBookRes {
        let response = httpClient
            .destory()
            .setUrl("${zlibEAPI}/book/${id}/${hash}/similar")
            .setMehod(RequestMethod.GET)
            .send()

        try {
            let res = GetBookRes.deserialize(response.getBodyDataModel())
            res
        } catch (err: Exception) {
            throw Exception('获取错误，错误信息${err.message}')
        }
    }

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<UInt64>("id", id))
            .add(field<String>("title", title))
            .add(field<String>("author", author))
            .add(field<String>("cover", cover))
            .add(field<String>("hash", hash))
    }
    public static func deserialize(dm: DataModel): BookInfoBrief {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = BookInfoBrief()
        result.id = UInt64.deserialize(dms.get("id"))
        result.title = String.deserialize(dms.get("title"))
        result.author = String.deserialize(dms.get("author"))
        result.cover = String.deserialize(dms.get("cover"))
        result.hash = String.deserialize(dms.get("hash"))

        return result
    }
}
