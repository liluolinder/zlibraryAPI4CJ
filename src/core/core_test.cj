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
    }
}
