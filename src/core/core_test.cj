package zlibraryAPI4CJ.core

import std.collection.*
import std.fs.*
import stdx.encoding.json.*

/**
 * core 层单元测试。
 *
 * 全部离线：只测纯函数与解析逻辑（站点规范化、凭证 Cookie、查询串编码、
 * 信封/错误映射、客户端生命周期），不发起任何真实网络请求。
 * 需要联网才能验证的东西（接口是否还能用）不在单元测试范围内。
 */
@Test
class ZlibHostTest {
    @TestCase
    func testNormalize(): Unit {
        @Expect(ZlibHost.of("https://example.com/").url, "https://example.com")
        @Expect(ZlibHost.of("https://example.com/eapi").url, "https://example.com")
        @Expect(ZlibHost.of("https://example.com/eapi/").url, "https://example.com")
        @Expect(ZlibHost.of("  https://example.com/  ").url, "https://example.com")
        @Expect(ZlibHost.of("https://a.com/x").eapi, "https://a.com/x/eapi")
    }

    @TestCase
    func testOrigin(): Unit {
        @Expect(ZlibHost.of("https://a.com").origin, "https://a.com/")
        @Expect(ZlibHost.of("https://a.com").isValid, true)
        @Expect(ZlibHost.DEFAULT_URL.startsWith("https://"), true)
        @Expect(ZlibHost.MIRRORS.size > 0, true)
    }

    @TestCase
    func testEmptyThrows(): Unit {
        var caught = false
        try {
            ZlibHost.of("   ")
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.BadResponse
        }
        @Expect(caught, true)
    }

    @TestCase
    func testLocationResolve(): Unit {
        @Expect(resolveLocation("https://a.com", "/x"), "https://a.com/x")
        @Expect(resolveLocation("https://a.com/p", "https://b.com/y"), "https://b.com/y")
        @Expect(resolveLocation("https://a.com/p", "next"), "https://a.com/next")
        @Expect(originOf("https://a.com:8443/p/q"), "https://a.com:8443")
        @Expect(originOf("https://a.com"), "https://a.com")
    }
}

@Test
class ZlibCredentialTest {
    @TestCase
    func testAnonymous(): Unit {
        let credential = ZlibCredential.anonymous()
        @Expect(credential.isLoggedIn, false)
        @Expect(credential.siteLanguage, ZLIB_DEFAULT_SITE_LANGUAGE)
        // 游客也要带语言 Cookie，否则站点会按 IP 猜语言
        @Expect(credential.toCookieHeader().contains("siteLanguageV2="), true)
        @Expect(credential.toRequestHeaders().size, 0)
    }

    @TestCase
    func testLoggedIn(): Unit {
        let credential = ZlibCredential.of(42, "secret")
        @Expect(credential.isLoggedIn, true)
        @Expect(credential.userId, "42")
        @Expect(credential.toCookieHeader().contains("remix_userid=42"), true)
        @Expect(credential.toCookieHeader().contains("remix_userkey=secret"), true)
        @Expect(credential.toRequestHeaders().size, 2)
        // 不打印密钥
        @Expect(credential.toString().contains("secret"), false)
    }

    @TestCase
    func testFromCookieString(): Unit {
        let credential = ZlibCredential.fromCookieString(
            "remix_userid=123; remix_userkey=abc; siteLanguageV2=en")
        @Expect(credential.userId, "123")
        @Expect(credential.userKey, "abc")
        @Expect(credential.siteLanguage, "en")
        @Expect(credential.isLoggedIn, true)
    }

    @TestCase
    func testWithMethodsAreImmutable(): Unit {
        let base = ZlibCredential.of(1, "k")
        let updated = base.withSiteLanguage("de")
        @Expect(base.siteLanguage, ZLIB_DEFAULT_SITE_LANGUAGE)
        @Expect(updated.siteLanguage, "de")
        @Expect(updated.userKey, "k")
    }
}

@Test
class QueryTest {
    @TestCase
    func testSetOverrides(): Unit {
        let query = Query().set("page", "1").set("page", "2")
        @Expect(query.size, 1)
        @Expect(query.toArray()[0][1], "2")
        @Expect(query.encode(), "page=2")
    }

    @TestCase
    func testAddKeepsDuplicates(): Unit {
        // 数组参数必须保留重复同名 key
        let query = Query().addAll("languages[]", ["german", "english"])
        @Expect(query.size, 2)
        @Expect(query.encode(), "languages%5b%5d=german&languages%5b%5d=english")
    }

    @TestCase
    func testOptionalAndInt(): Unit {
        let query = Query().setIfSome("order", None).setIfSome("order", Some("year")).setInt("page", 3)
        @Expect(query.encode(), "order=year&page=3")
    }

    @TestCase
    func testWithQuery(): Unit {
        @Expect(withQuery("https://a.com/x", Array<(String, String)>()), "https://a.com/x")
        @Expect(withQuery("https://a.com/x", [("p", "1")]), "https://a.com/x?p=1")
        @Expect(withQuery("https://a.com/x?q=0", [("p", "1")]), "https://a.com/x?q=0&p=1")
    }

    @TestCase
    func testPercentEncode(): Unit {
        @Expect(percentEncode("abc-._~"), "abc-._~")
        @Expect(percentEncode("中文"), "%e4%b8%ad%e6%96%87")
        @Expect(percentEncode("a b"), "a%20b")
        @Expect(percentEncode("a&b=c"), "a%26b%3dc")
    }

    @TestCase
    func testAppendPair(): Unit {
        let pairs = appendPair([("a", "1")], ("b", "2"))
        @Expect(pairs.size, 2)
        @Expect(pairs[1][0], "b")
    }
}

@Test
class ZlibEnvelopeTest {
    @TestCase
    func testSuccessForms(): Unit {
        @Expect(ZlibEnvelope.parse("{\"success\":1}").ok, true)
        @Expect(ZlibEnvelope.parse("{\"success\":true}").ok, true)
        @Expect(ZlibEnvelope.parse("{\"success\":\"1\"}").ok, true)
        @Expect(ZlibEnvelope.parse("{\"success\":0}").ok, false)
        @Expect(ZlibEnvelope.parse("{}").ok, false)
    }

    @TestCase
    func testFields(): Unit {
        let envelope = ZlibEnvelope.parse(
            "{\"success\":1,\"books\":[{\"id\":1},{\"id\":2}],\"pagination\":{\"total_pages\":3}}")
        @Expect(envelope.unwrap(path: "/x").get("books").isSome(), true)
        @Expect(envelope.arrayField("books").size, 2)
        @Expect(envelope.arrayField("missing").size, 0)
        @Expect(envelope.objectField("pagination").isSome(), true)
        @Expect(envelope.objectField("missing").isNone(), true)
        @Expect(envelope.errorText, "")
    }

    @TestCase
    func testErrorNotFound(): Unit {
        let envelope = ZlibEnvelope.parse("{\"success\":0,\"error\":\"Nothing has been found\"}")
        @Expect(envelope.ok, false)
        @Expect(envelope.errorText, "Nothing has been found")
        var caught = false
        try {
            envelope.unwrap(path: "/book/1/x")
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.NotFound
        }
        @Expect(caught, true)
    }

    @TestCase
    func testErrorLogin(): Unit {
        let envelope = ZlibEnvelope.parse("{\"success\":0,\"error\":\"Please login\"}")
        var caught = false
        try {
            envelope.unwrap(path: "/user/book/saved")
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.NotLoggedIn
        }
        @Expect(caught, true)
    }

    @TestCase
    func testErrorLoginChinese(): Unit {
        // 2026-11-10 实测（zh.eva101.ru）：未登录接口返回
        // HTTP 400 + {"success":0,"error":"登录到您的账户"}
        let envelope = ZlibEnvelope.parse("{\"success\":0,\"error\":\"登录到您的账户\"}")
        var caught = false
        try {
            envelope.unwrap(path: "/book/1/x/file")
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.NotLoggedIn
        }
        @Expect(caught, true)

        // 密码错误的文案不能被误判成“未登录”
        let wrong = ZlibEnvelope.parse("{\"success\":0,\"error\":\"电子邮件或密码错误\"}")
        var kind = ZlibErrorKind.ApiFailure
        try {
            wrong.unwrap(path: "/user/login")
        } catch (err: ZlibError) {
            kind = err.kind
        }
        @Expect(kind, ZlibErrorKind.ApiFailure)
    }

    @TestCase
    func testApiFailureMessage(): Unit {
        let envelope = ZlibEnvelope.parse("{\"success\":0,\"msg\":\"some failure\"}")
        var message = ""
        try {
            envelope.unwrap(path: "/x")
        } catch (err: ZlibError) {
            message = err.serverMessage
        }
        @Expect(message, "some failure")
    }

    @TestCase
    func testNonJsonThrows(): Unit {
        var caught = false
        try {
            ZlibEnvelope.parse("<html>blocked</html>", path: "/x")
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.BadResponse
        }
        @Expect(caught, true)
        var empty = false
        try {
            ZlibEnvelope.parse("")
        } catch (_: ZlibError) {
            empty = true
        }
        @Expect(empty, true)
    }

    @TestCase
    func testLenientReaders(): Unit {
        let obj = parseJsonObject(
            "{\"i\":\"12\",\"f\":\"1.5\",\"b\":1,\"s\":123,\"n\":null,\"o\":{\"x\":1},\"a\":[1,2]}")
        @Expect(readInt(obj, "i"), 12)
        @Expect(readInt(obj, "missing"), 0)
        @Expect(readIntOr(obj, "missing", 7), 7)
        @Expect(readFloat(obj, "f"), 1.5)
        @Expect(readBool(obj, "b"), true)
        @Expect(readString(obj, "s"), "123")
        @Expect(readOptionalString(obj, "n").isNone(), true)
        @Expect(readOptionalString(obj, "missing").isNone(), true)
        @Expect(objectFieldOf(obj, "o").isSome(), true)
        @Expect(arrayFieldOf(obj, "a").size, 2)
        @Expect(arrayFieldOf(obj, "o").size, 0)
    }

    @TestCase
    func testDecodeEachSkipsBadItems(): Unit {
        let items = arrayFieldOf(
            parseJsonObject("{\"books\":[{\"id\":1},\"oops\",{\"id\":2}]}"), "books")
        let numbers = decodeEach<Int64>(items) { item =>
            let id = readInt(item, "id")
            if (id == 0) {
                throw ZlibError.apiFailure("/test", "bad item")
            }
            id
        }
        @Expect(numbers.size, 2)
        @Expect(numbers[0], 1)
        @Expect(numbers[1], 2)
    }
}

@Test
class ZlibErrorTest {
    @TestCase
    func testKinds(): Unit {
        @Expect(ZlibErrorKind.ApiFailure == ZlibErrorKind.ApiFailure, true)
        @Expect(ZlibErrorKind.NotFound == ZlibErrorKind.ApiFailure, false)
        @Expect(ZlibErrorKind.Transport.isRetryable, true)
        @Expect(ZlibErrorKind.NotFound.isRetryable, false)
        @Expect(ZlibErrorKind.Closed.toString(), "Closed")
        @Expect(ZlibErrorKind.Closed.code, 7)
    }

    @TestCase
    func testHttpStatusMapping(): Unit {
        @Expect(ZlibError.httpStatus("u", 403, "x").kind, ZlibErrorKind.Forbidden)
        @Expect(ZlibError.httpStatus("u", 404, "x").kind, ZlibErrorKind.NotFound)
        @Expect(ZlibError.httpStatus("u", 500, "x").kind, ZlibErrorKind.BadResponse)
        // 长 HTML 预览会被截断，避免异常消息过长
        var longText = ""
        var index = 0
        while (index < 1000) {
            longText += "x"
            index++
        }
        let error = ZlibError.badResponse("/x", longText)
        @Expect(error.detail.size < 400, true)
    }

    @TestCase
    func testUnauthorized(): Unit {
        @Expect(ZlibError.notLoggedIn("/x").isUnauthorized, true)
        @Expect(ZlibError.closed().isRetryable, false)
    }
}

@Test
class TextTest {
    @TestCase
    func testTruncateRunes(): Unit {
        @Expect(truncateRunes("中文abc", 2), "中文...")
        @Expect(truncateRunes("中文", 5), "中文")
        @Expect(truncateRunes("中文", 0), "")
        @Expect(truncateRunes("abcdef", 3, suffix: ""), "abc")
    }

    @TestCase
    func testTruncateBytesSafe(): Unit {
        @Expect(truncateBytesSafe("中文", 4, suffix: ""), "中")
        @Expect(truncateBytesSafe("abc", 2, suffix: ""), "ab")
        @Expect(truncateBytesSafe("abc", 10), "abc")
        @Expect(truncateBytesSafe("abc", 0, suffix: ""), "")
    }
}

@Test
class ZlibClientTest {
    @TestCase
    func testUrls(): Unit {
        let client = ZlibClient.create(baseUrl: "https://example.com/eapi")
        @Expect(client.baseUrl, "https://example.com")
        @Expect(client.eapiUrl, "https://example.com/eapi")
        @Expect(client.apiUrl("/book/1/x"), "https://example.com/eapi/book/1/x")
        @Expect(client.apiUrl("book/1/x"), "https://example.com/eapi/book/1/x")
        client.close()
    }

    @TestCase
    func testCredentialDerivationIsImmutable(): Unit {
        let client = ZlibClient.create(baseUrl: "https://example.com")
        let authed = client.withCredential(ZlibCredential.of(1, "k"))
        @Expect(client.credential.isLoggedIn, false)
        @Expect(authed.credential.isLoggedIn, true)
        @Expect(authed.baseUrl, client.baseUrl)
        client.close()
    }

    @TestCase
    func testBaseUrlDerivation(): Unit {
        let client = ZlibClient.create(baseUrl: "https://a.com")
        let moved = client.withBaseUrl("https://b.com/eapi")
        @Expect(moved.baseUrl, "https://b.com")
        @Expect(client.baseUrl, "https://a.com")
        client.close()
    }

    @TestCase
    func testClosedClientThrows(): Unit {
        let client = ZlibClient.create(baseUrl: "https://example.com")
        @Expect(client.isClosed(), false)
        client.close()
        @Expect(client.isClosed(), true)
        var caught = false
        try {
            client.getRaw("/x")
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.Closed
        }
        @Expect(caught, true)
    }

    @TestCase
    func testCredentialFromCookiesFallback(): Unit {
        let client = ZlibClient.create(baseUrl: "https://example.com",
            credential: ZlibCredential.of(9, "kk"))
        // 没有网络请求，Cookie 存储为空 → 回退到当前凭证
        @Expect(client.credentialFromCookies().userId, "9")
        client.close()
    }

    @TestCase
    func testConfigCopy(): Unit {
        let config = ZlibClientConfig()
        config.maxConnectionsPerHost = 3
        let cloned = config.copy()
        cloned.maxConnectionsPerHost = 5
        @Expect(config.maxConnectionsPerHost, 3)
        @Expect(cloned.maxConnectionsPerHost, 5)
        @Expect(config.autoRetry, true)
        @Expect(config.maxAttempts, 3)
    }
}

// ---------------------------------------------------------------------------
// 站点管理：自定义站（优先）+ 种子站（换站）+ 自动重试决策
// ---------------------------------------------------------------------------

@Test
class ZlibSitesTest {
    @TestCase
    func testDefaults(): Unit {
        let sites = ZlibSites(customUrl: "https://a.com/eapi/")
        @Expect(sites.customUrl(), "https://a.com")
        @Expect(sites.current().url, "https://a.com")
        @Expect(sites.hasSeeds(), false)
        @Expect(sites.fallbackToSeed(), true)
    }

    @TestCase
    func testSeedsNormalized(): Unit {
        let sites = ZlibSites(customUrl: "https://a.com",
            seeds: ["https://seed.com/eapi", "  ", "https://seed2.com/"])
        @Expect(sites.seedUrls().size, 2)
        @Expect(sites.seedUrls()[0], "https://seed.com")
        @Expect(sites.seedUrls()[1], "https://seed2.com")
        @Expect(sites.hasSeeds(), true)
    }

    @TestCase
    func testAdoptOverwritesCustomSite(): Unit {
        let sites = ZlibSites(customUrl: "https://old.com")
        @Expect(sites.current().url, "https://old.com")
        sites.adopt(ZlibHost.of("https://new.com"))
        // 换站后「原本的自定义站」被覆盖
        @Expect(sites.current().url, "https://new.com")
        @Expect(sites.customUrl(), "https://new.com")
        sites.setCustomUrl("https://manual.com/eapi")
        @Expect(sites.current().url, "https://manual.com")
    }

    @TestCase
    func testRefreshCooldown(): Unit {
        let sites = ZlibSites(customUrl: "https://a.com", seeds: ["https://seed.com"])
        @Expect(sites.beginRefresh(), true) // 首次允许
        @Expect(sites.beginRefresh(), false) // 冷却窗口内拒绝，避免打爆种子站
        @Expect(sites.beginRefresh(force: true), true) // 手动强制
        @Expect(sites.refreshCount(), 2)
        @Expect(sites.lastRefreshAtMillis() > 0, true)
    }

    @TestCase
    func testDerivationIsIndependent(): Unit {
        let sites = ZlibSites(customUrl: "https://a.com", seeds: ["https://seed.com"])
        let derived = sites.withCustomUrl("https://b.com")
        @Expect(sites.customUrl(), "https://a.com")
        @Expect(derived.customUrl(), "https://b.com")
        @Expect(derived.seedUrls()[0], "https://seed.com")
        let seeded = sites.withSeeds(["https://s2.com"])
        @Expect(seeded.seedUrls()[0], "https://s2.com")
        @Expect(sites.seedUrls()[0], "https://seed.com")
    }

    @TestCase
    func testSnapshot(): Unit {
        let sites = ZlibSites(customUrl: "https://a.com", seeds: ["https://seed.com"],
            refreshInterval: Duration.second * 5, fallbackToSeed: false)
        @Expect(sites.snapshot().currentUrl, "https://a.com")
        @Expect(sites.snapshot().seedUrls.size, 1)
        @Expect(sites.snapshot().refreshIntervalSeconds, 5)
        @Expect(sites.snapshot().fallbackToSeed, false)
        @Expect(sites.toString().contains("a.com"), true)
    }
}

@Test
class PlanSiteRefreshTest {
    @TestCase
    func testUsesSeedDomains(): Unit {
        // 种子站返回两个域名，只有第二个可达 → 选中第二个
        let probe: (String) -> ZlibProbe = { url =>
            ZlibProbe(url, if (url == "https://good.com") {
                UInt16(200)
            } else {
                UInt16(0)
            }, "")
        }
        let fetch: (String) -> Array<String> = { seed => ["bad.com", "good.com"] }
        let result = planSiteRefresh(["https://seed.com"], fetch, probe, true)
        @Expect(result.isSome(), true)
        @Expect(result.getOrThrow().url, "https://good.com")
    }

    @TestCase
    func testFallsBackToSeedItself(): Unit {
        let probe: (String) -> ZlibProbe = { url => ZlibProbe(url, UInt16(200), "") }
        let fetch: (String) -> Array<String> = { seed => Array<String>() }
        @Expect(planSiteRefresh(["https://seed.com"], fetch, probe, true).isSome(), true)
        // 关闭兜底后，拿不到域名就返回 None
        @Expect(planSiteRefresh(["https://seed.com"], fetch, probe, false).isNone(), true)
    }

    @TestCase
    func testSeedRespondedMeansReachable(): Unit {
        // 种子站刚返回过域名，即使对它自己 HEAD 探测失败（实际偶发超时），
        // 也应当允许直接兜底到种子站，避免换站白等一轮。
        let probe: (String) -> ZlibProbe = { url => ZlibProbe(url, UInt16(0), "") }
        let fetch: (String) -> Array<String> = { seed => ["blocked1.com", "blocked2.com"] }
        let result = planSiteRefresh(["https://seed.com"], fetch, probe, true)
        @Expect(result.isSome(), true)
        @Expect(result.getOrThrow().url, "https://seed.com")
        // 关闭兜底时仍然返回 None
        @Expect(planSiteRefresh(["https://seed.com"], fetch, probe, false).isNone(), true)
    }

    @TestCase
    func testSeedRedirect(): Unit {
        let probe: (String) -> ZlibProbe = { url =>
            ZlibProbe(url, UInt16(302), "https://moved.example")
        }
        let fetch: (String) -> Array<String> = { seed => Array<String>() }
        let result = planSiteRefresh(["https://seed.com"], fetch, probe, false)
        @Expect(result.getOrThrow().url, "https://moved.example")
    }

    @TestCase
    func testTriesSeedsInOrder(): Unit {
        let probe: (String) -> ZlibProbe = { url =>
            ZlibProbe(url, if (url == "https://good.com") {
                UInt16(200)
            } else {
                UInt16(0)
            }, "")
        }
        let fetch: (String) -> Array<String> = { seed =>
            if (seed == "https://seed2.com") {
                ["good.com"]
            } else {
                ["bad.com"]
            }
        }
        let result = planSiteRefresh(["https://seed1.com", "https://seed2.com"], fetch, probe,
            false)
        @Expect(result.getOrThrow().url, "https://good.com")
    }

    @TestCase
    func testAllFail(): Unit {
        let probe: (String) -> ZlibProbe = { url => ZlibProbe(url, UInt16(0), "") }
        let fetch: (String) -> Array<String> = { seed => Array<String>() }
        @Expect(planSiteRefresh(["https://s1.com", "https://s2.com"], fetch, probe, true).isNone(),
            true)
    }

    @TestCase
    func testCandidateCap(): Unit {
        // 6 个候选里只有最后一个可达，但默认只探测前 4 个 → 不命中
        let probe: (String) -> ZlibProbe = { url =>
            ZlibProbe(url, if (url == "https://good6.com") {
                UInt16(200)
            } else {
                UInt16(0)
            }, "")
        }
        let fetch: (String) -> Array<String> = { seed =>
            ["c1.com", "c2.com", "c3.com", "c4.com", "c5.com", "good6.com"]
        }
        @Expect(planSiteRefresh(["https://seed.com"], fetch, probe, false).isNone(), true)
        // 放宽上限后命中
        @Expect(planSiteRefresh(["https://seed.com"], fetch, probe, false,
            maxCandidates: 6).isSome(), true)
    }
}

@Test
class ExtractDomainListTest {
    @TestCase
    func testArrayOfStrings(): Unit {
        let root = parseJsonObject("{\"success\":1,\"domains\":[\"a.com\",\"b.com\"]}")
        let list = extractDomainList(root)
        @Expect(list.size, 2)
        @Expect(list[0], "a.com")
    }

    @TestCase
    func testArrayOfObjects(): Unit {
        let root = parseJsonObject(
            "{\"domains\":[{\"domain\":\"a.com\"},{\"url\":\"https://b.com/abc\"}]}")
        let list = extractDomainList(root)
        @Expect(list.size, 2)
        @Expect(list[0], "a.com")
        @Expect(list[1], "https://b.com/abc")
    }

    @TestCase
    func testMapForm(): Unit {
        let root = parseJsonObject("{\"domains\":{\"a.com\":{\"status\":1},\"b.com\":{}}}")
        let list = extractDomainList(root)
        @Expect(list.size, 2)
    }

    @TestCase
    func testCommaString(): Unit {
        let root = parseJsonObject("{\"domains\":\"a.com, b.com\"}")
        @Expect(extractDomainList(root).size, 2)
    }

    @TestCase
    func testDedupe(): Unit {
        let root = parseJsonObject("{\"domains\":[\"a.com\",\"a.com\",\"a.com\"]}")
        @Expect(extractDomainList(root).size, 1)
    }

    @TestCase
    func testNoiseIgnored(): Unit {
        // 未知形状的字符串字段（语言名）不能被当成域名
        let root = parseJsonObject("{\"success\":1,\"data\":{\"names\":[\"English\",\"German\"]}}")
        @Expect(extractDomainList(root).size, 0)
    }
}

@Test
class NormalizeDomainTest {
    @TestCase
    func testBareDomain(): Unit {
        @Expect(normalizeDomain("z-library.sk").getOrThrow().url, "https://z-library.sk")
        @Expect(normalizeDomain("https://z-library.sk/book/1").getOrThrow().url,
            "https://z-library.sk")
        @Expect(normalizeDomain("//c.com").getOrThrow().url, "https://c.com")
    }

    @TestCase
    func testRootRelativeUsesSeed(): Unit {
        @Expect(normalizeDomain("/login", seed: "https://seed.com/eapi").getOrThrow().url,
            "https://seed.com")
    }

    @TestCase
    func testInvalid(): Unit {
        @Expect(normalizeDomain("   ").isNone(), true)
        @Expect(normalizeDomain("/x").isNone(), true)
    }
}

@Test
class SwitchSiteDecisionTest {
    @TestCase
    func testDecision(): Unit {
        // 域名层面可能有问题 → 换站重试
        @Expect(shouldSwitchSite(ZlibErrorKind.Transport), true)
        @Expect(shouldSwitchSite(ZlibErrorKind.BadResponse), true)
        @Expect(shouldSwitchSite(ZlibErrorKind.Forbidden), true)
        // 业务/凭证/资源问题 → 换站无用，直接抛
        @Expect(shouldSwitchSite(ZlibErrorKind.ApiFailure), false)
        @Expect(shouldSwitchSite(ZlibErrorKind.NotLoggedIn), false)
        @Expect(shouldSwitchSite(ZlibErrorKind.NotFound), false)
        @Expect(shouldSwitchSite(ZlibErrorKind.Closed), false)
    }
}

@Test
class ClientSitesTest {
    @TestCase
    func testCreateWithSeeds(): Unit {
        let client = ZlibClient.create(baseUrl: "https://a.com", seeds: ["https://seed.com"])
        @Expect(client.baseUrl, "https://a.com")
        @Expect(client.eapiUrl, "https://a.com/eapi")
        @Expect(client.sites.seedUrls().size, 1)
        @Expect(client.sites.snapshot().currentUrl, "https://a.com")
        client.close()
    }

    @TestCase
    func testSetCustomSiteChangesRequestTarget(): Unit {
        let client = ZlibClient.create(baseUrl: "https://old.com")
        @Expect(client.apiUrl("/x"), "https://old.com/eapi/x")
        // 自动换站走的就是这个方法；这里验证「覆盖后立即生效」
        client.setCustomSite("https://new.com/eapi")
        @Expect(client.baseUrl, "https://new.com")
        @Expect(client.apiUrl("/x"), "https://new.com/eapi/x")
        client.close()
    }

    @TestCase
    func testRefreshSiteWithoutSeeds(): Unit {
        let client = ZlibClient.create(baseUrl: "https://a.com")
        @Expect(client.refreshSite(), false)
        @Expect(client.refreshSite(force: true), false)
        client.close()
    }

    @TestCase
    func testWithBaseUrlDoesNotMutateOriginal(): Unit {
        let client = ZlibClient.create(baseUrl: "https://a.com", seeds: ["https://seed.com"])
        let moved = client.withBaseUrl("https://b.com")
        @Expect(client.baseUrl, "https://a.com")
        @Expect(moved.baseUrl, "https://b.com")
        @Expect(moved.sites.seedUrls().size, 1)
        client.close()
    }
}

@Test
class RetryExecutionTest {
    @TestCase
    func testTransportFailureRetriesUpToMaxAttempts(): Unit {
        let client = ZlibClient.create(baseUrl: "https://a.com")
        let counter = TestCounters()
        var caught = false
        try {
            client.execute<Int64>({ host =>
                counter.inc()
                throw ZlibError.transport("/x", "boom")
            }, refreshOnFailure: true)
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.Transport
        }
        @Expect(counter.value, 3) // 默认 maxAttempts = 3
        @Expect(caught, true)
        client.close()
    }

    @TestCase
    func testBusinessFailureIsNotRetried(): Unit {
        let client = ZlibClient.create(baseUrl: "https://a.com")
        let counter = TestCounters()
        try {
            client.execute<Int64>({ host =>
                counter.inc()
                throw ZlibError.apiFailure("/x", "nope")
            }, refreshOnFailure: true)
        } catch (_: ZlibError) {
            ()
        }
        @Expect(counter.value, 1) // 业务失败换站无用，只尝试一次
        client.close()
    }

    @TestCase
    func testRetryUsesNewlyAdoptedSite(): Unit {
        let client = ZlibClient.create(baseUrl: "https://a.com")
        let seen = ArrayList<String>()
        var result: Int64 = 0
        try {
            result = client.execute<Int64>({ host =>
                seen.add(host.url)
                if (host.url == "https://a.com") {
                    // 模拟一次换站（真实流程由 refreshSite 调 sites.adopt）
                    client.setCustomSite("https://b.com")
                    throw ZlibError.badResponse("/x", "<html>blocked</html>")
                }
                42
            }, refreshOnFailure: true)
        } catch (_: ZlibError) {
            result = -1
        }
        @Expect(result, 42)
        @Expect(seen.size, 2)
        @Expect(seen[0], "https://a.com")
        @Expect(seen[1], "https://b.com") // 重试确实用了换站后的地址
        client.close()
    }

    @TestCase
    func testAutoRetryCanBeDisabled(): Unit {
        let config = ZlibClientConfig()
        config.autoRetry = false
        let client = ZlibClient.create(baseUrl: "https://a.com", config: config)
        let counter = TestCounters()
        try {
            client.execute<Int64>({ host =>
                counter.inc()
                throw ZlibError.transport("/x", "boom")
            }, refreshOnFailure: true)
        } catch (_: ZlibError) {
            ()
        }
        @Expect(counter.value, 1)
        client.close()
    }

    @TestCase
    func testMaxAttemptsCanBeConfigured(): Unit {
        let config = ZlibClientConfig()
        config.maxAttempts = 2
        let client = ZlibClient.create(baseUrl: "https://a.com", config: config)
        let counter = TestCounters()
        try {
            client.execute<Int64>({ host =>
                counter.inc()
                throw ZlibError.transport("/x", "boom")
            }, refreshOnFailure: true)
        } catch (_: ZlibError) {
            ()
        }
        @Expect(counter.value, 2)
        client.close()
    }
}

/**
 * 测试用可变计数器。
 *
 * 仓颉不允许逃逸闭包捕获**可变局部变量**（CJ030），所以计数放在堆对象里：
 * 闭包捕获的是不可变的 `let` 绑定，修改的是对象字段，合法。
 */
class TestCounters {
    public var value: Int64 = 0

    public func inc(): Unit {
        value++
    }
}