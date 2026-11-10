package zlibraryAPI4CJ.core

import std.collection.*

/**
 * Z-Library 登录凭证聚合。
 *
 * Z-Library 的「身份」不是 Bearer token，而是两条 remix 凭证，服务端同时接受
 * **Cookie** 与**请求头**两种携带方式（官方 eapi 文档原文：
 * "provide a `remix-userid` header as well as a `remix-userkey` header.
 * In some cases, it may also be necessary to provide the login as the
 * cookies `remix_userid` and `remix_userkey`"）。本库两种都发，兼容性最好。
 *
 * | 字段 | 来源 | 作用 |
 * | --- | --- | --- |
 * | `userId` | 登录响应 `user.id` | remix_userid，标识账号 |
 * | `userKey` | 登录响应 `user.remix_userkey` | remix_userkey，相当于密码 |
 * | `siteLanguage` | 用户选择 | 写入 `siteLanguage` / `siteLanguageV2` Cookie，影响返回文案 |
 *
 * 该类型是**不可变值**：所有 `with*` 方法返回新实例，可以安全地在多线程间共享。
 * 派生客户端用 `ZlibClient.withCredential`，不要修改已有客户端的凭证。
 */
public class ZlibCredential <: ToString {
    /** 账号 id（`remix_userid`）。用字符串保存，避免服务端偶发返回字符串时丢信息。 */
    public let userId: String
    /** 账号密钥（`remix_userkey`）。视为密码，不要打日志。 */
    public let userKey: String
    /** 站点语言（`zh` / `en` / `de` …）。 */
    public let siteLanguage: String

    public init(userId!: String = "", userKey!: String = "",
        siteLanguage!: String = ZLIB_DEFAULT_SITE_LANGUAGE) {
        this.userId = userId.trimAscii()
        this.userKey = userKey.trimAscii()
        this.siteLanguage = if (siteLanguage.trimAscii().isEmpty()) {
            ZLIB_DEFAULT_SITE_LANGUAGE
        } else {
            siteLanguage.trimAscii()
        }
    }

    /** 游客凭证：只能访问免登录接口。 */
    public static func anonymous(): ZlibCredential {
        ZlibCredential()
    }

    /** 用数值 id 构造（登录响应里的 `user.id` 是数字）。 */
    public static func of(userId: Int64, userKey: String,
        siteLanguage!: String = ZLIB_DEFAULT_SITE_LANGUAGE): ZlibCredential {
        ZlibCredential(userId: "${userId}", userKey: userKey, siteLanguage: siteLanguage)
    }

    /** 是否持有登录态（userId 与 userKey 都非空才算）。 */
    public prop isLoggedIn: Bool {
        get() {
            !userId.isEmpty() && !userKey.isEmpty()
        }
    }

    /** 站点语言。 */
    public prop language: String {
        get() {
            siteLanguage
        }
    }

    public func withUserId(value: String): ZlibCredential {
        ZlibCredential(userId: value, userKey: userKey, siteLanguage: siteLanguage)
    }

    public func withUserKey(value: String): ZlibCredential {
        ZlibCredential(userId: userId, userKey: value, siteLanguage: siteLanguage)
    }

    public func withSiteLanguage(value: String): ZlibCredential {
        ZlibCredential(userId: userId, userKey: userKey, siteLanguage: value)
    }

    /**
     * 解析浏览器里复制出来的 Cookie 字符串（`a=1; b=2`）。
     *
     * 键名大小写不敏感；同时接受新旧两套语言 Cookie（`siteLanguage` / `siteLanguageV2`），
     * 因为 Z-Library 前端历史上有过改名。
     */
    public static func fromCookieString(cookie: String): ZlibCredential {
        var userId = ""
        var userKey = ""
        var language = ""
        for (pair in cookie.split(";")) {
            let item = pair.trimAscii()
            if (item.isEmpty()) {
                continue
            }
            let position = item.indexOf("=")
            if (position.isNone()) {
                continue
            }
            let index = position.getOrThrow()
            let key = item[0..index].trimAscii().toAsciiLower()
            let value = item[(index + 1)..item.size].trimAscii()
            match (key) {
                case "remix_userid" => userId = value
                case "remix_userkey" => userKey = value
                case "sitelanguage" => if (language.isEmpty()) {
                    language = value
                }
                case "sitelanguagev2" => language = value
                case _ => ()
            }
        }
        ZlibCredential(userId: userId, userKey: userKey,
            siteLanguage: if (language.isEmpty()) {
                ZLIB_DEFAULT_SITE_LANGUAGE
            } else {
                language
            })
    }

    /**
     * 生成请求用 Cookie 头。
     *
     * 同时写 `siteLanguage`（旧）与 `siteLanguageV2`（新）：两个都发只是多几十字节，
     * 但能兼容不同版本的站点后端，避免「登录了却拿到英文/未登录页面」。
     */
    public func toCookieHeader(): String {
        let parts = ArrayList<String>()
        parts.add("siteLanguage=${siteLanguage}")
        parts.add("siteLanguageV2=${siteLanguage}")
        if (!userId.isEmpty()) {
            parts.add("remix_userid=${userId}")
        }
        if (!userKey.isEmpty()) {
            parts.add("remix_userkey=${userKey}")
        }
        String.join(parts.toArray(), delimiter: "; ")
    }

    /** 生成 remix 身份请求头（`remix-userid` / `remix-userkey`）。 */
    public func toRequestHeaders(): Array<(String, String)> {
        let headers = ArrayList<(String, String)>()
        if (!userId.isEmpty()) {
            headers.add(("remix-userid", userId))
        }
        if (!userKey.isEmpty()) {
            headers.add(("remix-userkey", userKey))
        }
        headers.toArray()
    }

    public func toString(): String {
        // 不打印 userKey 原文，避免日志泄露凭据
        "ZlibCredential(login=${isLoggedIn}, userId=${userId}, language=${siteLanguage})"
    }
}
