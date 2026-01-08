package zlibraryAPI4CJ

import linderHttp.*
import linderHttp.commons.*
import zlibraryAPI4CJ.common.*
import zlibraryAPI4CJ.dataModel.*
import stdx.serialization.serialization.*
import stdx.encoding.json.*

public class ZlibClient {
    public func loginIn(email!: String, password!: String): GetUserInfoOrLoginRes {
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
        try {
            let res = GetUserInfoOrLoginRes.deserialize(response.getBodyDataModel())
            res
        } catch (err: Exception) {
            throw Exception('获取错误，错误信息${err.message}')
        }
    }

    public func loginIn(userID!: UInt64, userKey!: String): GetUserInfoOrLoginRes {
        let tempUserInfo: ZlibUserInfo = ZlibUserInfo()
        tempUserInfo.id = userID
        tempUserInfo.remixUserkey = userKey
        tempUserInfo.getPersonalInfo()
    }

    public func getRecommendBook(): GetBookRes {
        let response = httpClient.destory().setDefaultHeader().setUrl("${zlibEAPI}/book/most-popular").send()
        try {
            let res = GetBookRes.deserialize(response.getBodyDataModel())
            res
        } catch (err: Exception) {
            throw Exception('获取错误，错误信息${err.message}')
        }
    }
}
