package zlibraryAPI4CJ.zlibclinet

public struct ZlibBook <: Serializable<ZlibBook> {
    public var id: Int64 = 0
    public var isbn: String = ''
    public var url: String = ''
    public var title: String = ''
    public var author: String = ''
    public var cover: String = ''
    public var coverData: String = ''

    public func getDetailedInfo() {
        try {
            let client = ClientBuilder().tlsConfig(getTlsConfig()).build()

            var requestBuilder = HttpRequestBuilder()
                .method("GET")
                .url("${zlibraryUrl}${url}")
            "${zlibraryUrl}${url}" |> println

            let response = (requestBuilder |> setCommonHeader).build() |> client.send

            let res = StringReader(response.body).readToEnd()
            res |> println

            response |> println
            client.close()

        } catch (error: Exception) {
            (-1, error.toString())
        }
    }

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<Int64>("id", id))
            .add(field<String>("isbn", isbn))
            .add(field<String>("url", url))
            .add(field<String>("title", title))
            .add(field<String>("author", author))
            .add(field<String>("cover", cover))
            .add(field<String>("coverData", coverData))
    }

    public static func deserialize(dm: DataModel): ZlibBook {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = ZlibBook()
        result.id = Int64.deserialize(dms.get("id"))
        result.isbn = String.deserialize(dms.get("isbn"))
        result.url = String.deserialize(dms.get("url"))
        result.isbn = String.deserialize(dms.get("isbn"))
        result.title = String.deserialize(dms.get("title"))
        result.author = String.deserialize(dms.get("author"))
        result.cover = String.deserialize(dms.get("cover"))
        result.coverData = String.deserialize(dms.get("coverData"))
        return result
    }
}
