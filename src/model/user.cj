package zlibraryAPI4CJ.model

import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * Z-Library 用户信息（登录响应与 `GET /eapi/user/profile` 的 `user` 字段）。
 *
 * 服务端在 user 对象里同时给出了「身份」（`id` + `remix_userkey`）与
 * 「配额」（`downloads_today` / `downloads_limit`）：
 *
 * | 字段 | JSON key | 说明 |
 * | --- | --- | --- |
 * | `id` | `id` | 用户 id，对应 Cookie `remix_userid` |
 * | `remixUserKey` | `remix_userkey` | 账号密钥，对应 Cookie `remix_userkey` |
 * | `email` | `email` | 注册邮箱 |
 * | `name` | `name` | 昵称 |
 * | `kindleEmail` | `kindle_email` | Kindle 推送邮箱 |
 * | `downloadsToday` | `downloads_today` | 今日已下载数 |
 * | `downloadsLimit` | `downloads_limit` | 每日下载上限 |
 *
 * 注意 `remixUserKey` 等价于密码：不要写日志、不要拼进 URL。
 */
public class ZlibUser <: ToString {
    /** 用户 id。 */
    public var id: Int64 = 0
    /** 注册邮箱。 */
    public var email: String = ""
    /** 昵称。 */
    public var name: String = ""
    /** Kindle 推送邮箱。 */
    public var kindleEmail: ?String = None
    /** 账号密钥（敏感）。 */
    public var remixUserKey: String = ""
    /** 今日已下载数。 */
    public var downloadsToday: Int64 = 0
    /** 每日下载上限。 */
    public var downloadsLimit: Int64 = 0
    /** 邮箱是否已确认。 */
    public var confirmed: Bool = false
    /** 是否付费会员。 */
    public var isPremium: Bool = false

    /** 从 JSON 对象解码（容错）。 */
    public static func fromJsonObject(obj: JsonObject): ZlibUser {
        let user = ZlibUser()
        user.id = readInt(obj, "id")
        user.email = readString(obj, "email")
        user.name = readString(obj, "name")
        user.kindleEmail = readOptionalString(obj, "kindle_email")
        user.remixUserKey = readString(obj, "remix_userkey")
        user.downloadsToday = readInt(obj, "downloads_today")
        user.downloadsLimit = readInt(obj, "downloads_limit")
        user.confirmed = readBool(obj, "confirmed")
        user.isPremium = readBool(obj, "isPremium")
        user
    }

    /** 从 JSON 文本解码。 */
    public static func fromJson(text: String): ZlibUser {
        fromJsonObject(parseJsonObject(text, path: "user"))
    }

    /** 今日剩余下载次数（下限 0）。 */
    public func downloadsLeft(): Int64 {
        let left = downloadsLimit - downloadsToday
        if (left < 0) {
            0
        } else {
            left
        }
    }

    /**
     * 转成可复用的登录凭证。
     *
     * 登录一次后把 `ZlibUser`（或其 `id`/`remixUserKey`）持久化，下次直接用
     * `ZlibCredential` 构造客户端即可，不必反复用邮箱密码登录。
     */
    public func toCredential(
        siteLanguage!: String = ZLIB_DEFAULT_SITE_LANGUAGE): ZlibCredential {
        ZlibCredential(userId: "${id}", userKey: remixUserKey, siteLanguage: siteLanguage)
    }

    public func toString(): String {
        "ZlibUser(${id}, ${name}, ${email})"
    }
}
