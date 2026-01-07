package zlibraryAPI4CJ.dataModel

public struct RecommendBookRes <: Serializable<RecommendBookRes> {
    public var success: UInt8 = 0
    public var books: Array<ZlibRecommendBook> = []



    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<UInt8>("success", success))
            .add(field<Array<ZlibRecommendBook>>("books", books))
    }
    public static func deserialize(dm: DataModel): RecommendBookRes {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = RecommendBookRes()
        result.success = UInt8.deserialize(dms.get("success"))
        result.books = Array<ZlibRecommendBook>.deserialize(dms.get("books"))
        return result
    }
}

public struct ZlibRecommendBook <: Serializable<ZlibRecommendBook> {
    public var id: UInt64 = 0
    public var title: String = ''
    public var author: String = ''
    public var cover: String = ''
    public var hash: String = ''

    public func getBookInfo(): BookInfoRes {
        let response = httpClient.destory().setDefaultHeader().setUrl("${zlibEAPI}/book/${id}/${hash}").send()
        //response.getBodyJsonString() |> println
        try {
            let res = BookInfoRes.deserialize(response.getBodyDataModel())
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
    public static func deserialize(dm: DataModel): ZlibRecommendBook {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = ZlibRecommendBook()
        result.id = UInt64.deserialize(dms.get("id"))
        result.title = String.deserialize(dms.get("title"))
        result.author = String.deserialize(dms.get("author"))
        result.cover = String.deserialize(dms.get("cover"))
        result.hash = String.deserialize(dms.get("hash"))

        return result
    }
}
