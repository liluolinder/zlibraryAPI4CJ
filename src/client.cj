package zlibraryAPI4CJ

import linderHttp.*
import zlibraryAPI4CJ.common.*
import zlibraryAPI4CJ.dataModel.*
import stdx.serialization.serialization.*
import stdx.encoding.json.*

public class ZlibClient {
    public func getRecommendBook(): RecommendBookRes {
        httpClient.destory()
        httpClient.setDefaultHeader()
        httpClient.setUrl("${zlibEAPI}/book/most-popular")

        let response = httpClient.send()
        try {
            let res = RecommendBookRes.deserialize(response.getBodyDataModel())
            res
        } catch (err: Exception) {
           
            throw Exception('获取错误，错误信息${err.message}')
        }
    }
}
