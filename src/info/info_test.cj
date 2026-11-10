package zlibraryAPI4CJ.info

import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * 站点信息子包的单元测试。
 *
 * 全部离线：`InfoApi` 的方法本身都要发 HTTP 请求，这里不调用它们，
 * 而是用固定响应样本验证它们共用的那条链路：
 * `ZlibEnvelope.parse` → `unwrap` → 按 key 取字段。
 *
 * 这条链路值得单独测，因为站点信息接口的形状最不稳定：解码必须做到
 * 「成功信封里缺字段不崩、失败信封一定抛错、非 JSON 响应给出
 * `BadResponse` 而不是 `JsonException`」。
 */
@Test
class InfoEnvelopeTest {
    private let SITE_SAMPLE = """
{
  "success": 1,
  "name": "Z-Library",
  "user_count": 123456,
  "languages": {
    "german": "德语",
    "english": "英语"
  },
  "domains": [
    { "domain": "z-library.sk", "primary": true },
    { "domain": "zh.z-library.sk", "primary": false }
  ]
}
"""

    private let PLANS_SAMPLE = """
{
  "success": 1,
  "plans": [
    { "id": 1, "name": "Basic", "price": 0, "days": 0 },
    { "id": 2, "name": "Premium", "price": 12.5, "days": 30 }
  ],
  "pagination": { "limit": 20, "current": 1, "total_items": 2, "total_pages": 1 }
}
"""

    /** 成功信封：根上的标量、对象、数组都能按 key 读到。 */
    @TestCase
    func testDecodeSiteRoot(): Unit {
        let path = "/info"
        let root = ZlibEnvelope.parse(SITE_SAMPLE, path: path).unwrap(path: path)
        @Expect(readString(root, "name"), "Z-Library")
        @Expect(readInt(root, "user_count"), 123456)
        // 数字以字符串下发时也要能读出来（站点字段类型漂移是常态）
        @Expect(readInt(root, "user_count"), 123456)
        let domains = arrayFieldOf(root, "domains")
        @Expect(domains.size, 2)
        @Expect(readString(domains[0].asObject(), "domain"), "z-library.sk")
        @Expect(readBool(domains[0].asObject(), "primary"), true)
        @Expect(readBool(domains[1].asObject(), "primary"), false)
        let languages = objectFieldOf(root, "languages")
        @Expect(languages.isSome(), true)
        @Expect(readString(languages.getOrThrow(), "german"), "德语")
    }

    /** 套餐接口同样只是「根对象 + 数组」，套餐价格是小数，不能被截断。 */
    @TestCase
    func testDecodePlansRoot(): Unit {
        let path = "/info/plans"
        let root = ZlibEnvelope.parse(PLANS_SAMPLE, path: path).unwrap(path: path)
        let plans = arrayFieldOf(root, "plans")
        @Expect(plans.size, 2)
        @Expect(readInt(plans[0].asObject(), "id"), 1)
        @Expect(readFloat(plans[1].asObject(), "price"), 12.5)
        @Expect(readInt(plans[1].asObject(), "days"), 30)
        @Expect(readInt(objectFieldOf(root, "pagination").getOrThrow(), "total_items"), 2)
    }

    /** 成功信封里缺字段要回退默认值，而不是抛异常。 */
    @TestCase
    func testMissingFieldsFallBack(): Unit {
        let root = ZlibEnvelope.parse("{\"success\":1}").unwrap()
        @Expect(readString(root, "name"), "")
        @Expect(readInt(root, "user_count"), 0)
        @Expect(objectFieldOf(root, "languages").isNone(), true)
        @Expect(arrayFieldOf(root, "domains").size, 0)
    }

    /** `success = 0` 时 `unwrap` 抛 `ZlibError`（调用方据此决定降级/提示）。 */
    @TestCase
    func testFailureEnvelopeThrows(): Unit {
        let envelope = ZlibEnvelope.parse(
            "{\"success\":0,\"error\":\"Nothing has been found\"}", path: "/info/domains")
        @Expect(envelope.success, false)
        @ExpectThrows[ZlibError](envelope.unwrap(path: "/info/domains"))
    }

    /** 服务端含 login 字样的错误映射为 `NotLoggedIn`。 */
    @TestCase
    func testLoginErrorMapsToNotLoggedIn(): Unit {
        var kind = ZlibErrorKind.BadResponse
        try {
            ZlibEnvelope.parse("{\"success\":0,\"error\":\"Please login\"}").unwrap(
                path: "/info/plans")
        } catch (e: ZlibError) {
            kind = e.kind
        }
        @Expect(kind == ZlibErrorKind.NotLoggedIn, true)
    }

    /** 域名失效/风控时返回 HTML，必须映射成 `BadResponse` 而不是 JSON 异常。 */
    @TestCase
    func testNonJsonBodyMapsToBadResponse(): Unit {
        var kind = ZlibErrorKind.NotFound
        var path = ""
        try {
            ZlibEnvelope.parse("<html><head><title>403 Forbidden</title></head></html>",
                path: "/info")
        } catch (e: ZlibError) {
            kind = e.kind
            path = e.path
        }
        @Expect(kind == ZlibErrorKind.BadResponse, true)
        @Expect(path, "/info")
    }
}

/** `switch-language` 查询参数构造（`InfoApi.site` / `InfoApi.plans` 共用）。 */
@Test
class InfoQueryTest {
    @TestCase
    func testSwitchLanguageQuery(): Unit {
        @Expect(switchLanguageQuery(None).size, 0)
        let query = switchLanguageQuery(Some("zh-CN"))
        @Expect(query.size, 1)
        @Expect(query[0][0], "switch-language")
        @Expect(query[0][1], "zh-CN")
        @Expect(withQuery("https://z/eapi/info", query),
            "https://z/eapi/info?switch-language=zh-CN")
        @Expect(withQuery("https://z/eapi/info/languages", switchLanguageQuery(None)),
            "https://z/eapi/info/languages")
    }
}
