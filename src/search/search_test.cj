package zlibraryAPI4CJ.search

import std.collection.*
import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 搜索子包的单元测试。
 *
 * 全部离线：只用固定 JSON 样本与纯函数，不发真实网络请求
 * （接口是否还能用属于集成测试，见 `bbapi` 那套 `*_integration` 工程的做法）。
 * 覆盖两件事：
 *
 * 1. 搜索表单的字段编码 —— 尤其是 `languages[]` / `extensions[]`
 *    必须保留**重复 key**，这是本子包最容易写错、也最难在联网测试里发现的地方；
 * 2. 搜索响应会走到的解码链路（`ZlibEnvelope.unwrap` → `BookPage` /
 *    `ArrayList<BookInfoBrief>`）。
 */
@Test
class SearchFormTest {
    /** 数组参数：同名 key 全部保留，且保持传入顺序。 */
    @TestCase
    func testArrayFieldsKeepDuplicateKeys(): Unit {
        let form = searchForm("Rust", languages: ["german", "english"],
            extensions: ["pdf", "epub"])
        @Expect(form.size, 7)
        @Expect(form[0][0], "message")
        @Expect(form[0][1], "Rust")
        @Expect(form[1][0], "languages[]")
        @Expect(form[1][1], "german")
        @Expect(form[2][0], "languages[]")
        @Expect(form[2][1], "english")
        @Expect(form[3][0], "extensions[]")
        @Expect(form[4][0], "extensions[]")
        @Expect(form[5][0], "page")
        @Expect(form[6][0], "limit")
    }

    /**
     * 真正发出去的表单串里也必须出现两次 `languages[]`。
     *
     * 只断言数组对不够：如果后续有人把 `form` 改成 `HashMap` 再交给
     * `Body.form`，数组仍正确但线上只剩一个语言。这里直接断言编码结果。
     */
    @TestCase
    func testEncodedFormKeepsArrayFields(): Unit {
        let form = searchForm("Rust", languages: ["german", "english"],
            extensions: ["pdf"])
        // key 的百分号编码交给 percentEncode 现算：`[`/`]` 不是 RFC 3986
        // 未保留字符，必须编码；具体十六进制大小写属于编码器细节，不写死在测试里。
        let languageKey = percentEncode("languages[]")
        let extensionKey = percentEncode("extensions[]")
        let expected = "message=Rust&${languageKey}=german&${languageKey}=english&" +
            "${extensionKey}=pdf&page=1&limit=20"
        @Expect(formEncode(form), expected)
    }

    /** 可选参数都给 `None` / 空数组时，只发 message + page + limit。 */
    @TestCase
    func testMinimalForm(): Unit {
        let form = searchForm("Rust")
        @Expect(form.size, 3)
        @Expect(form[0][0], "message")
        @Expect(form[1][0], "page")
        @Expect(form[1][1], "1")
        @Expect(form[2][0], "limit")
        @Expect(form[2][1], "20")
    }

    /** 年份与排序按传入值编码，`None` 的字段不出现。 */
    @TestCase
    func testYearAndOrderFields(): Unit {
        let form = searchForm("Rust", yearFrom: 2000, yearTo: 2024, order: "popular",
            page: 3, limit: 50)
        @Expect(form.size, 6)
        @Expect(form[1][0], "yearFrom")
        @Expect(form[1][1], "2000")
        @Expect(form[2][0], "yearTo")
        @Expect(form[2][1], "2024")
        @Expect(form[3][0], "order")
        @Expect(form[3][1], "popular")
        @Expect(form[4][1], "3")
        @Expect(form[5][1], "50")
    }

    /** 空串语言/扩展名不该制造出空字段（服务端会当成一个空筛选条件）。 */
    @TestCase
    func testEmptyArrayEntriesAreSkipped(): Unit {
        let form = searchForm("Rust", languages: ["", "german", ""],
            extensions: ["", "pdf"])
        @Expect(form.size, 5)
        @Expect(form[1][0], "languages[]")
        @Expect(form[1][1], "german")
        @Expect(form[2][0], "extensions[]")
        @Expect(form[2][1], "pdf")
    }

    /** `switch-language` 只在非 `None` 时出现。 */
    @TestCase
    func testSwitchLanguageQuery(): Unit {
        @Expect(switchLanguageQuery(None).size, 0)
        let query = switchLanguageQuery(Some("de"))
        @Expect(query.size, 1)
        @Expect(query[0][0], "switch-language")
        @Expect(query[0][1], "de")
        @Expect(withQuery("https://z/eapi/book/most-popular", query),
            "https://z/eapi/book/most-popular?switch-language=de")
        @Expect(withQuery("https://z/eapi/book/most-popular", switchLanguageQuery(None)),
            "https://z/eapi/book/most-popular")
    }
}

/** 响应解码链路：信封 → `BookPage` / `ArrayList<BookInfoBrief>`。 */
@Test
class SearchDecodeTest {
    private let SEARCH_PAGE_SAMPLE = """
{
  "success": 1,
  "books": [
    {
      "id": 101,
      "title": "Rust 程序设计语言",
      "author": "Steve Klabnik",
      "cover": "https://covers.example/101.jpg",
      "hash": "abc101",
      "year": 2019
    },
    {
      "id": 102,
      "title": "Programming Rust",
      "hash": "abc102"
    }
  ],
  "pagination": {
    "limit": 20,
    "current": 1,
    "total_items": 42,
    "total_pages": 3
  }
}
"""

    /** 搜索响应根上平铺 `books` + `pagination`，直接交给 `BookPage` 解码。 */
    @TestCase
    func testDecodeBookPage(): Unit {
        let path = "/book/search"
        let root = ZlibEnvelope.parse(SEARCH_PAGE_SAMPLE, path: path).unwrap(path: path)
        let page = BookPage.fromJsonObject(root)
        @Expect(page.size(), 2)
        @Expect(page.books[0].id, 101)
        @Expect(page.books[0].title, "Rust 程序设计语言")
        @Expect(page.books[0].authorText(), "Steve Klabnik")
        @Expect(page.books[0].hash, "abc101")
        @Expect(page.books[1].authorText(), "")
        @Expect(page.pagination.limit, 20)
        @Expect(page.pagination.current, 1)
        @Expect(page.pagination.totalItems, 42)
        @Expect(page.pagination.totalPages, 3)
        @Expect(page.hasMore(), true)
        @Expect(page.nextPage(), 2)
        @Expect(page.first().getOrThrow().id, 101)
    }

    /** 单页结果（`current == total_pages`）不应继续翻页。 */
    @TestCase
    func testLastPageHasNoMore(): Unit {
        let root = parseJsonObject("""
{"success":1,"books":[{"id":1,"title":"T","hash":"h"}],
 "pagination":{"limit":20,"current":2,"total_items":21,"total_pages":2}}
""")
        let page = BookPage.fromJsonObject(root)
        @Expect(page.size(), 1)
        @Expect(page.hasMore(), false)
        @Expect(page.nextPage(), 2)
    }

    /** 缺 `pagination` / 缺 `books` 时按空页处理，不抛异常。 */
    @TestCase
    func testMissingFieldsFallBackToEmpty(): Unit {
        let page = BookPage.fromJsonObject(parseJsonObject("{\"success\":1}"))
        @Expect(page.size(), 0)
        @Expect(page.isEmpty(), true)
        @Expect(page.pagination.totalPages, 0)
        @Expect(page.first().isNone(), true)
    }

    /**
     * `most-popular` / `recently` 的 `books` 数组走 `decodeEach` 解码成
     * `BookInfoBrief`；单条脏数据（这里是非对象元素）只跳过该条。
     */
    @TestCase
    func testDecodeBriefList(): Unit {
        let path = "/book/most-popular"
        let root = ZlibEnvelope.parse("""
{"success":1,"books":[
  {"id":7,"title":"热门一","author":"作者甲","cover":"https://c/7.jpg","hash":"h7"},
  "坏数据",
  {"id":8,"title":"热门二"}
]}
""", path: path).unwrap(path: path)
        let books = decodeEach<BookInfoBrief>(arrayFieldOf(root, "books")) { item =>
            BookInfoBrief.fromJsonObject(item)
        }
        @Expect(books.size, 2)
        @Expect(books[0].id, 7)
        @Expect(books[0].author, "作者甲")
        @Expect(books[0].hash, "h7")
        @Expect(books[1].id, 8)
        @Expect(books[1].title, "热门二")
        @Expect(books[1].cover, "")
    }

    /** `success = 0` 时 `unwrap` 必须抛 `ZlibError`，不能把错误信封当成功解码。 */
    @TestCase
    func testFailureEnvelopeThrows(): Unit {
        let envelope = ZlibEnvelope.parse(
            "{\"success\":0,\"error\":\"Nothing has been found\"}")
        @Expect(envelope.success, false)
        @Expect(envelope.errorText, "Nothing has been found")
        @ExpectThrows[ZlibError](envelope.unwrap(path: "/book/search"))
    }

    /** 服务端含 login 字样的错误映射成 `NotLoggedIn`，调用方可据此引导登录。 */
    @TestCase
    func testLoginErrorMapsToNotLoggedIn(): Unit {
        var kind = ZlibErrorKind.BadResponse
        try {
            ZlibEnvelope.parse("{\"success\":0,\"error\":\"Please login\"}").unwrap(
                path: "/book/search")
        } catch (e: ZlibError) {
            kind = e.kind
        }
        @Expect(kind == ZlibErrorKind.NotLoggedIn, true)
    }
}
