package zlibraryAPI4CJ

import linderHttp.*
import linderHttp.commons.*
import zlibraryAPI4CJ.common.*
import zlibraryAPI4CJ.dataModel.*
import stdx.serialization.serialization.*
import stdx.encoding.json.*

public class ZlibClient {
    public func login(email!: String, password!: String): GetUserInfoOrLoginRes {
        var httpClient = LinderHttp(readTimeout: Duration.minute, writeTimeout: Duration.minute)
        let body = Form()
        body.add("email", email)
        body.add("password", password)
        let response = httpClient
            .destory()
            .setDefaultHeader()
            .setUrl("${zlibEAPI}/user/login")
            .setMehod(RequestMethod.POST)
            .setBody(body)
            .send()
        let res = GetUserInfoOrLoginRes.deserialize(response.getBodyDataModel())
        res
    }

    public func login(userID!: UInt64, userKey!: String): GetUserInfoOrLoginRes {
        let tempUserInfo: ZlibUserInfo = ZlibUserInfo()
        tempUserInfo.id = userID
        tempUserInfo.remixUserkey = userKey
        tempUserInfo.getPersonalInfo()
    }

    public func getRecommendBook(): GetBookRes {
        var httpClient = LinderHttp(readTimeout: Duration.minute, writeTimeout: Duration.minute)
        let response = httpClient.destory().setDefaultHeader().setUrl("${zlibEAPI}/book/most-popular").send()
        let res = GetBookRes.deserialize(response.getBodyDataModel())
        res
    }

    public func search(message!: String, yearFrom!: ?UInt16 = None, yearTo!: ?UInt16 = None, page!: UInt16 = 1,
        limit!: UInt16 = 20): GetBookWithInfoAndPaginationRes {
        let body = Form()
        body.add('message', message)
        body.add('page', "${page}")
        body.add('limit', "${limit}")
        if (yearFrom.isSome()) {
            body.add('yearFrom', "${yearFrom}")
        }

        if (yearTo.isSome()) {
            body.add('yearTo', "${yearTo}")
        }
        var httpClient = LinderHttp(readTimeout: Duration.minute, writeTimeout: Duration.minute)
        let response = httpClient
            .destory()
            .setDefaultHeader()
            .setMehod(RequestMethod.POST)
            .setUrl("${zlibEAPI}/book/search")
            .setBody(body)
            .send()

        let res = GetBookWithInfoAndPaginationRes.deserialize(response.getBodyDataModel())
        res
    }
}
