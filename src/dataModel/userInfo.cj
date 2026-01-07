package zlibraryAPI4CJ.dataModel

public struct GetUserInfoOrLoginRes <: Serializable<GetUserInfoOrLoginRes> {
    public var success: UInt8 = 0

    public var errorInfo: ?String = ''

    public var userInfo: ?UserInfo = None

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<UInt8>("success", success))
            .add(field<?String>("error", errorInfo))
            .add(field<?UserInfo>("user", userInfo))
    }

    public static func deserialize(dm: DataModel): GetUserInfoOrLoginRes {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = GetUserInfoOrLoginRes()
        result.success = UInt8.deserialize(dms.get("success"))
        result.errorInfo = Option<String>.deserialize(dms.get("error"))
        result.userInfo = Option<UserInfo>.deserialize(dms.get("user"))
        return result
    }
}

public struct UserInfo <: Serializable<UserInfo> {
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

    public static func deserialize(dm: DataModel): UserInfo {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = UserInfo()
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
