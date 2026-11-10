package zlibraryAPI4CJ.user

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * user 子包单元测试：锁定解码与参数构造，**不发真实网络请求**。
 *
 * 网络部分（`GET /user/profile` 等）依赖站点可用性与账号状态，本机无法稳定
 * 访问 Z-Library，所以这里统一用固定 JSON 样本喂 `ZlibEnvelope` / 解码函数，
 * 验证的是「服务端给我们这种形状时，我们解析成什么」。
 */
@Test
class UserBookPageTest {
    /** `/user/book/saved`、`/user/book/downloaded` 的响应形状：books + pagination。 */
    private let SAVED_SAMPLE = """
{
  "success": 1,
  "books": [
    {
      "id": 1001,
      "title": "仓颉语言编程",
      "author": "华为",
      "cover": "https://example.org/cover/1.jpg",
      "hash": "hash-a",
      "extension": "pdf",
      "filesize": 2097152
    },
    {
      "id": 1002,
      "title": "Z-Library 使用指南",
      "author": "匿名",
      "cover": "",
      "hash": "hash-b"
    }
  ],
  "pagination": {
    "limit": 20,
    "current": 2,
    "total_items": 42,
    "total_pages": 3
  }
}
"""

    @TestCase
    func testSavedPageDecode(): Unit {
        let envelope = ZlibEnvelope.parse(SAVED_SAMPLE, path: "/user/book/saved")
        let page = BookPage.fromJsonObject(envelope.unwrap(path: "/user/book/saved"))
        @Expect(page.size(), 2)
        @Expect(page.isEmpty(), false)
        @Expect(page.books[0].id, 1001)
        @Expect(page.books[0].title, "仓颉语言编程")
        @Expect(page.books[0].hash, "hash-a")
        @Expect(page.books[1].title, "Z-Library 使用指南")
        @Expect(page.pagination.totalItems, 42)
        @Expect(page.pagination.totalPages, 3)
    }

    @TestCase
    func testPaginationDerived(): Unit {
        let envelope = ZlibEnvelope.parse(SAVED_SAMPLE, path: "/user/book/saved")
        let page = BookPage.fromJsonObject(envelope.unwrap(path: "/user/book/saved"))
        @Expect(page.pagination.current, 2)
        @Expect(page.hasMore(), true)
        @Expect(page.nextPage(), 3)
        @Expect(page.first().getOrThrow().id, 1001)
    }

    /** 服务端给空列表时不能崩，`hasMore` 必须是 false。 */
    @TestCase
    func testEmptyPage(): Unit {
        let text = "{\"success\":1,\"books\":[],\"pagination\":" +
            "{\"limit\":20,\"current\":1,\"total_items\":0,\"total_pages\":0}}"
        let page = BookPage.fromJsonObject(parseJsonObject(text, path: "empty-page"))
        @Expect(page.isEmpty(), true)
        @Expect(page.size(), 0)
        @Expect(page.hasMore(), false)
        @Expect(page.first().isNone(), true)
    }

    /** 缺 `pagination` 的响应也要能解出（旧镜像/精简响应）。 */
    @TestCase
    func testPageWithoutPagination(): Unit {
        let text = "{\"success\":1,\"books\":[{\"id\":9,\"title\":\"T\",\"hash\":\"h\"}]}"
        let page = BookPage.fromJsonObject(parseJsonObject(text, path: "no-pagination"))
        @Expect(page.size(), 1)
        @Expect(page.pagination.totalPages, 0)
        @Expect(page.hasMore(), false)
    }
}

@Test
class UserRecommendedTest {
    /** `/user/book/recommended` 的响应形状：根上直接一个 books 数组。 */
    private let RECOMMENDED_SAMPLE = """
{
  "success": 1,
  "books": [
    { "id": 7, "title": "推荐一", "author": "作者甲", "hash": "h7" },
    { "id": 8, "title": "推荐二", "author": "作者乙", "hash": "h8" }
  ]
}
"""

    @TestCase
    func testRecommendedDecode(): Unit {
        let envelope = ZlibEnvelope.parse(RECOMMENDED_SAMPLE,
            path: "/user/book/recommended")
        let books = decodeEach<BookInfoBrief>(envelope.arrayField("books")) { obj =>
            BookInfoBrief.fromJsonObject(obj)
        }
        @Expect(books.size, 2)
        @Expect(books[0].id, 7)
        @Expect(books[0].title, "推荐一")
        @Expect(books[1].hash, "h8")
    }

    /** 缺 `books` 字段时返回空列表，而不是抛异常（接口偶发返回精简结构）。 */
    @TestCase
    func testRecommendedMissingField(): Unit {
        let envelope = ZlibEnvelope.parse("{\"success\":1}", path: "/user/book/recommended")
        let books = decodeEach<BookInfoBrief>(envelope.arrayField("books")) { obj =>
            BookInfoBrief.fromJsonObject(obj)
        }
        @Expect(books.size, 0)
    }
}

@Test
class UserProfileTest {
    /** `/user/profile` 的响应形状：根上 `user` 对象。 */
    private let PROFILE_SAMPLE = """
{
  "success": 1,
  "user": {
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
}
"""

    @TestCase
    func testProfileDecode(): Unit {
        let envelope = ZlibEnvelope.parse(PROFILE_SAMPLE, path: "/user/profile")
        let user = ZlibUser.fromJsonObject(envelope.objectField("user").getOrThrow())
        @Expect(user.id, 1234567)
        @Expect(user.email, "reader@example.org")
        @Expect(user.name, "书虫")
        @Expect(user.kindleEmail ?? "", "kindle@example.org")
        @Expect(user.downloadsToday, 3)
        @Expect(user.downloadsLimit, 10)
        @Expect(user.downloadsLeft(), 7)
        @Expect(user.confirmed, true)
        @Expect(user.isPremium, false)
    }

    /** 未登录时服务端返回 `success = 0` + "Please login"，应归类为 NotLoggedIn。 */
    @TestCase
    func testNotLoggedInEnvelope(): Unit {
        let envelope = ZlibEnvelope.parse("{\"success\":0,\"error\":\"Please login\"}",
            path: "/user/profile")
        var kind = ZlibErrorKind.BadResponse
        try {
            envelope.unwrap(path: "/user/profile")
        } catch (error: ZlibError) {
            kind = error.kind
        }
        @Expect(kind == ZlibErrorKind.NotLoggedIn, true)
    }
}

@Test
class UserQueryTest {
    /** 分页 query：`order` 只在非 None 时出现，page/limit 总是出现。 */
    @TestCase
    func testPagingQuery(): Unit {
        let noOrder: ?String = None
        @Expect(formEncode(pagingQuery(noOrder, 1, 20)), "page=1&limit=20")
        @Expect(formEncode(pagingQuery(Some("date"), 3, 10)),
            "order=date&page=3&limit=10")
    }

    /** 排序值是服务端枚举，客户端原样透传但要百分号编码。 */
    @TestCase
    func testPagingQueryEncodesValue(): Unit {
        @Expect(formEncode(pagingQuery(Some("date added"), 1, 20)),
            "order=date%20added&page=1&limit=20")
    }

    /** `update` 只发非 None 字段，且 Kindle 邮箱用服务端关键字 `kindle_email`。 */
    @TestCase
    func testUpdateForm(): Unit {
        let none: ?String = None
        let form = updateForm(Some("new@example.org"), none, Some("新昵称"),
            Some("kindle@example.org"))
        @Expect(form.size, 3)
        @Expect(form[0][0], "email")
        @Expect(form[0][1], "new@example.org")
        @Expect(form[1][0], "name")
        @Expect(form[1][1], "新昵称")
        @Expect(form[2][0], "kindle_email")
        @Expect(form[2][1], "kindle@example.org")
    }

    /** 全 None 时表单为空（服务端会拒绝，但客户端不应伪造空字段覆盖资料）。 */
    @TestCase
    func testUpdateFormEmpty(): Unit {
        let none: ?String = None
        @Expect(updateForm(none, none, none, none).size, 0)
    }
}

@Test
class UserDonationsTest {
    /** 捐赠接口形状不稳定，本库只保证「能解包出根对象」，不建模字段。 */
    private let DONATIONS_SAMPLE = """
{
  "success": 1,
  "donations": {
    "total": 2,
    "currency": "USD",
    "items": [ { "amount": 5 }, { "amount": 10 } ]
  }
}
"""

    @TestCase
    func testDonationsRoot(): Unit {
        let root = ZlibEnvelope.parse(DONATIONS_SAMPLE, path: "/user/donations")
            .unwrap(path: "/user/donations")
        @Expect(readInt(root, "success"), 1)
        let donations = objectFieldOf(root, "donations")
        @Expect(donations.isSome(), true)
        @Expect(readInt(donations.getOrThrow(), "total"), 2)
        @Expect(readString(donations.getOrThrow(), "currency"), "USD")
    }
}
