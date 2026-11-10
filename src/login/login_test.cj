package zlibraryAPI4CJ.login

import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 登录子包单元测试：只验证「离线可验证」的部分——凭证派生、`LoginResult` 语义。
 *
 * 网络接口（`POST /user/login` 等）不在单测里打真实请求：本机无法稳定访问
 * Z-Library 域名，测试必须离线可重复。接口路径与表单字段的正确性由
 * 代码评审 + 集成环境验证，单测锁定的是派生逻辑。
 */
@Test
class LoginCredentialTest {
    /** 登录响应 `user` 字段的真实形状（字段名与类型来自社区抓包样本）。 */
    private let USER_SAMPLE = """
{
  "id": 1234567,
  "email": "reader@example.org",
  "name": "书虫",
  "kindle_email": "kindle@example.org",
  "remix_userkey": "remix-key-abc",
  "downloads_today": 3,
  "downloads_limit": 10,
  "confirmed": 1,
  "isPremium": 0
}
"""

    /** 凭证由 user.id + user.remix_userkey 组成，语言默认取站点默认语言。 */
    @TestCase
    func testCredentialDefaultLanguage(): Unit {
        let user = ZlibUser.fromJson(USER_SAMPLE)
        let noLanguage: ?String = None
        let credential = credentialOf(user, noLanguage)
        @Expect(credential.userId, "1234567")
        @Expect(credential.userKey, "remix-key-abc")
        @Expect(credential.isLoggedIn, true)
        @Expect(credential.siteLanguage, ZLIB_DEFAULT_SITE_LANGUAGE)
    }

    /** `siteLanguage` 传值时要覆盖默认语言（影响服务端返回文案）。 */
    @TestCase
    func testCredentialLanguageOverride(): Unit {
        let user = ZlibUser.fromJson(USER_SAMPLE)
        let credential = credentialOf(user, Some("en"))
        @Expect(credential.siteLanguage, "en")
        @Expect(credential.isLoggedIn, true)
    }

    /** token 登录的种子凭证：数值 id 转字符串，语言为空回退默认。 */
    @TestCase
    func testTokenCredential(): Unit {
        let noLanguage: ?String = None
        let credential = tokenCredential(987654, "key-from-args", noLanguage)
        @Expect(credential.userId, "987654")
        @Expect(credential.userKey, "key-from-args")
        @Expect(credential.siteLanguage, ZLIB_DEFAULT_SITE_LANGUAGE)
        @Expect(credential.isLoggedIn, true)
    }

    /** `/user/profile` 回带的 key 优先于调用方给的旧 key。 */
    @TestCase
    func testCredentialPrefersFreshKey(): Unit {
        let user = ZlibUser.fromJson(USER_SAMPLE)
        let seed = tokenCredential(1, "old-key", Some("en"))
        let merged = credentialFor(user, seed)
        @Expect(merged.userId, "1234567")
        @Expect(merged.userKey, "remix-key-abc")
        @Expect(merged.siteLanguage, "en")
    }

    /** profile 响应偶发缺 `remix_userkey` 时，必须退回调用方给的凭证而不是变成游客。 */
    @TestCase
    func testCredentialFallbackWithoutKey(): Unit {
        let user = ZlibUser.fromJson("{\"id\":1234567,\"email\":\"a@b.c\"}")
        let seed = tokenCredential(1234567, "old-key", Some("de"))
        let merged = credentialFor(user, seed)
        @Expect(merged.userKey, "old-key")
        @Expect(merged.siteLanguage, "de")
        @Expect(merged.isLoggedIn, true)
    }
}

@Test
class LoginResultTest {
    private let USER_SAMPLE = """
{
  "id": 1234567,
  "email": "reader@example.org",
  "name": "书虫",
  "kindle_email": "kindle@example.org",
  "remix_userkey": "remix-key-abc",
  "downloads_today": 3,
  "downloads_limit": 10,
  "confirmed": 1,
  "isPremium": 0
}
"""

    @TestCase
    func testFields(): Unit {
        let user = ZlibUser.fromJson(USER_SAMPLE)
        let noLanguage: ?String = None
        let result = LoginResult(user, credentialOf(user, noLanguage))
        @Expect(result.user.id, 1234567)
        @Expect(result.user.name, "书虫")
        @Expect(result.user.downloadsLeft(), 7)
        @Expect(result.credential.userId, "1234567")
        @Expect(result.credential.isLoggedIn, true)
    }

    /** `withClient` 派生登录态客户端，且原客户端保持游客态（不可变语义）。 */
    @TestCase
    func testWithClient(): Unit {
        let user = ZlibUser.fromJson(USER_SAMPLE)
        let result = LoginResult(user, credentialOf(user, Some("en")))
        let guest = ZlibClient.create(baseUrl: "https://example.org")
        try {
            let mine = result.withClient(guest)
            @Expect(mine.credential.isLoggedIn, true)
            @Expect(mine.credential.siteLanguage, "en")
            @Expect(mine.baseUrl, "https://example.org")
            // 派生不会改动原客户端的凭证，否则「游客/登录并存」的用法会失效
            @Expect(guest.credential.isLoggedIn, false)
        } finally {
            guest.close()
        }
    }

    /** toString 不能泄露 remix_userkey。 */
    @TestCase
    func testToString(): Unit {
        let user = ZlibUser.fromJson(USER_SAMPLE)
        let noLanguage: ?String = None
        let result = LoginResult(user, credentialOf(user, noLanguage))
        @Expect(result.toString(), "LoginResult(user=1234567, login=true)")
        @Expect(result.toString().contains("remix-key-abc"), false)
    }
}
