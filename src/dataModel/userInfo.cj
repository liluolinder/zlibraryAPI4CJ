package zlibraryAPI4CJ.dataModel

public struct GetUserInfoOrLoginRes <: Serializable<GetUserInfoOrLoginRes> {
    public var success: UInt8 = 0

    public var errorInfo: ?String = ''

    public var userInfo: ?ZlibUserInfo = None

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<UInt8>("success", success))
            .add(field<?String>("error", errorInfo))
            .add(field<?ZlibUserInfo>("user", userInfo))
    }
    public static func deserialize(dm: DataModel): GetUserInfoOrLoginRes {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = GetUserInfoOrLoginRes()
        result.success = UInt8.deserialize(dms.get("success"))
        result.errorInfo = Option<String>.deserialize(dms.get("error"))
        result.userInfo = Option<ZlibUserInfo>.deserialize(dms.get("user"))
        return result
    }
}

public class ZlibUserInfo <: Serializable<ZlibUserInfo> {
    public var id: UInt64 = 0
    public var email: String = ""
    public var name: String = ""
    public var kindleEmail: String = ""
    public var remixUserkey: String = ""
    public var todyDownloadNum: UInt64 = 0
    public var downloadLimit: UInt64 = 0
    // "donations_active": null,
    // "donations_expire": null,
    // "confirmed": 1,
    // "isPremium": 0

    public prop cookie: String {
        get() {
            'siteLanguage=zh; remix_userkey=${remixUserkey}; remix_userid=${id}'
        }
    }

    private prop header: LinderHttpHeader {
        get() {
            let header: LinderHttpHeader = LinderHttpHeader().set(key: "cookie", value: cookie)
            header
        }
    }

    public func getPersonalInfo(): GetUserInfoOrLoginRes {
        let response = httpClient
            .destory()
            .setHeader(header)
            .setUrl("${zlibEAPI}/user/profile")
            .setMehod(RequestMethod.GET)
            .send()

        try {
            let res = GetUserInfoOrLoginRes.deserialize(response.getBodyDataModel())
            res
        } catch (err: Exception) {
            throw Exception('获取错误，错误信息${err.message}')
        }
    }

    public func getSaved(page!: UInt64 = 1): GetUserSavedBookRes {
        let param = Form()
        param.add("page", "${page}")
        let response = httpClient
            .destory()
            .setHeader(header)
            .setUrl("${zlibEAPI}/user/book/saved")
            .setMehod(RequestMethod.GET)
            .setBody(param)
            .send()

        try {
            let res = GetUserSavedBookRes.deserialize(response.getBodyDataModel())
            res
        } catch (err: Exception) {
            throw Exception('获取错误，错误信息${err.message}')
        }
    }

    public func getRecommendBook(): GetBookRes {
        let response = httpClient
            .destory()
            .setHeader(header)
            .setUrl("${zlibEAPI}/user/book/recommended")
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
            .add(field<String>("email", email))
            .add(field<String>("name", name))
            .add(field<String>("kindle_email", kindleEmail))
            .add(field<String>("remix_userkey", remixUserkey))
            .add(field<UInt64>("downloads_today", todyDownloadNum))
            .add(field<UInt64>("downloads_limit", downloadLimit))
    }
    public static func deserialize(dm: DataModel): ZlibUserInfo {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = ZlibUserInfo()
        result.id = UInt64.deserialize(dms.get("id"))
        result.email = String.deserialize(dms.get("email"))
        result.name = String.deserialize(dms.get("name"))

        result.kindleEmail = String.deserialize(dms.get("kindle_email"))
        result.remixUserkey = String.deserialize(dms.get("remix_userkey"))
        result.todyDownloadNum = UInt64.deserialize(dms.get("downloads_today"))
        result.downloadLimit = UInt64.deserialize(dms.get("downloads_limit"))
        return result
    }
}
