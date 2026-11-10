package zlibraryAPI4CJ.model

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * model 层单元测试。
 *
 * 只验证「固定 JSON 样本 → 模型字段」的解码与派生逻辑，全部离线。
 * 这些样本刻意覆盖真实响应里的脏数据形态（字段缺失、数字写成字符串、
 * 布尔写成 0/1、可选字段为 null），因为这些正是线上踩过的坑。
 */
@Test
class BookInfoTest {
    private let SAMPLE = """
{
  "id": 123456,
  "content_type": "book",
  "title": "Rust 程序设计语言",
  "author": "Steve Klabnik",
  "volume": "",
  "year": 2019,
  "edition": null,
  "publisher": "No Starch Press",
  "identifier": "9781593278281",
  "language": "english",
  "pages": 560,
  "series": "",
  "cover": "https://example.com/cover.jpg",
  "terms_hash": "abc123",
  "active": 1,
  "deleted": 0,
  "filesize": 12345678,
  "filesizeString": "11.8 MB",
  "extension": "epub",
  "md5": "d41d8cd98f00b204e9800998ecf8427e",
  "sha256": "abc",
  "href": "/book/123456/abcd1234/rust",
  "hash": "abcd1234",
  "kindleAvailable": 1,
  "sendToEmailAvailable": 0,
  "interestScore": "100",
  "qualityScore": "5",
  "description": "一本讲 Rust 的书",
  "dl": "/dl/123456",
  "readOnlineUrl": "https://example.com/read/123456",
  "_isUserSavedBook": 1,
  "date_saved": "2024-01-02",
  "readOnlineAvailable": 1
}
"""

    @TestCase
    func testDecode(): Unit {
        let book = BookInfo.fromJson(SAMPLE)
        @Expect(book.id, 123456)
        @Expect(book.contentType, "book")
        @Expect(book.title, "Rust 程序设计语言")
        @Expect(book.author.getOrThrow(), "Steve Klabnik")
        @Expect(book.year, 2019)
        @Expect(book.publisher.getOrThrow(), "No Starch Press")
        @Expect(book.language, "english")
        @Expect(book.pages, 560)
        @Expect(book.filesize, 12345678)
        @Expect(book.filesizeString, "11.8 MB")
        @Expect(book.extension, "epub")
        @Expect(book.hash, "abcd1234")
        @Expect(book.kindleAvailable, true)
        @Expect(book.sendToEmailAvailable, false)
        @Expect(book.dl, "/dl/123456")
        @Expect(book.isUserSavedBook.getOrThrow(), true)
        @Expect(book.dateSaved.getOrThrow(), "2024-01-02")
        @Expect(book.readOnlineAvailable, true)
        @Expect(book.edition.isNone(), true)
    }

    @TestCase
    func testLenientDecode(): Unit {
        // 真实响应里出现过：year 给字符串、filesize 给浮点、author 为 null、
        // dl 整条缺失、kindleAvailable 用 "1" 字符串。
        let book = BookInfo.fromJson("""
{
  "id": "777",
  "title": "只有基本字段的书",
  "author": null,
  "year": "2020",
  "filesize": 2048.0,
  "kindleAvailable": "1"
}
""")
        @Expect(book.id, 777)
        @Expect(book.author.isNone(), true)
        @Expect(book.authorText(), "")
        @Expect(book.year, 2020)
        @Expect(book.filesize, 2048)
        @Expect(book.kindleAvailable, true)
        @Expect(book.dl, "")
        @Expect(book.downloadable(), false)
        @Expect(book.saved(), false)
        @Expect(book.pages, 0)
    }

    @TestCase
    func testDerived(): Unit {
        let book = BookInfo.fromJson(SAMPLE)
        @Expect(book.authorText(), "Steve Klabnik")
        @Expect(book.sizeText(), "11.8 MB")
        @Expect(book.downloadable(), true)
        @Expect(book.saved(), true)
        @Expect(book.webpage(baseUrl: "https://a.com"), "https://a.com/book/123456/abcd1234/rust")
    }

    @TestCase
    func testSizeTextFallback(): Unit {
        let book = BookInfo.fromJson("{\"filesize\":1234}")
        @Expect(book.sizeText(), "1 KB")
        let small = BookInfo.fromJson("{\"filesize\":512}")
        @Expect(small.sizeText(), "512 B")
        let empty = BookInfo.fromJson("{}")
        @Expect(empty.sizeText(), "")
    }

    @TestCase
    func testWebpageWithoutHref(): Unit {
        let book = BookInfo.fromJson("{\"id\":1,\"hash\":\"h\"}")
        @Expect(book.webpage(baseUrl: "https://a.com"), "https://a.com/book/1/h")
    }
}

@Test
class BookInfoBriefTest {
    @TestCase
    func testDecode(): Unit {
        let brief = BookInfoBrief.fromJson(
            "{\"id\":42,\"title\":\"书名\",\"author\":\"作者\",\"cover\":\"c.jpg\",\"hash\":\"h42\"}")
        @Expect(brief.id, 42)
        @Expect(brief.title, "书名")
        @Expect(brief.author, "作者")
        @Expect(brief.hash, "h42")
        @Expect(brief.webpage(baseUrl: "https://a.com"), "https://a.com/book/42/h42")
        @Expect(brief.toString().contains("书名"), true)
    }

    @TestCase
    func testDecodeRealShape(): Unit {
        // 2026-11-10 实测 most-popular / similar 的列表项形状：
        // id, isbn, url, title, author, cover, coverData, hash
        let brief = BookInfoBrief.fromJson("""
{
  "id": 24126585,
  "isbn": "9787111495482",
  "url": "/book/V9W3MOb89Y/book.html",
  "title": "毛泽东选集",
  "author": "毛泽东",
  "cover": "https://example.com/c.jpg",
  "coverData": " data-id=24126585 data-title=毛泽东选集",
  "hash": "217fd6"
}
""")
        @Expect(brief.id, 24126585)
        @Expect(brief.isbn, "9787111495482")
        @Expect(brief.url, "/book/V9W3MOb89Y/book.html")
        @Expect(brief.coverData.contains("24126585"), true)
        // 有 url 时优先用它拼网页地址
        @Expect(brief.webpage(baseUrl: "https://zh.eva101.ru"),
            "https://zh.eva101.ru/book/V9W3MOb89Y/book.html")
        // 绝对 url 原样返回
        let absolute = BookInfoBrief.fromJson("{\"url\":\"https://x.com/book/1/2/a.html\"}")
        @Expect(absolute.webpage(baseUrl: "https://a.com"), "https://x.com/book/1/2/a.html")
    }
}

@Test
class BookFormatTest {
    @TestCase
    func testDecodeRealShape(): Unit {
        // 2026-11-10 实测 /formats 的 books 元素形状
        let format = BookFormat.fromJson(
            "{\"id\":35851393,\"hash\":\"b4c3ae\",\"extension\":\"azw3\"," +
                "\"filesize\":5285744,\"filesizeString\":\"5.04 MB\"}")
        @Expect(format.id, 35851393)
        @Expect(format.hash, "b4c3ae")
        @Expect(format.extension, "azw3")
        @Expect(format.filesize, 5285744)
        @Expect(format.sizeText(), "5.04 MB")
        @Expect(format.toString().contains("azw3"), true)
    }

    @TestCase
    func testSizeTextFallback(): Unit {
        let format = BookFormat.fromJson("{\"filesize\":2048}")
        @Expect(format.sizeText(), "2 KB")
        @Expect(BookFormat.fromJson("{}").sizeText(), "")
    }
}

@Test
class ZlibUserTest {
    private let SAMPLE = """
{
  "id": 42,
  "email": "user@example.com",
  "name": "读书人",
  "kindle_email": "kindle@example.com",
  "remix_userkey": "secret-key",
  "downloads_today": 3,
  "downloads_limit": 10,
  "confirmed": 1,
  "isPremium": 0
}
"""

    @TestCase
    func testDecode(): Unit {
        let user = ZlibUser.fromJson(SAMPLE)
        @Expect(user.id, 42)
        @Expect(user.email, "user@example.com")
        @Expect(user.name, "读书人")
        @Expect(user.kindleEmail.getOrThrow(), "kindle@example.com")
        @Expect(user.remixUserKey, "secret-key")
        @Expect(user.downloadsToday, 3)
        @Expect(user.downloadsLimit, 10)
        @Expect(user.confirmed, true)
        @Expect(user.isPremium, false)
    }

    @TestCase
    func testDerived(): Unit {
        let user = ZlibUser.fromJson(SAMPLE)
        @Expect(user.downloadsLeft(), 7)
        let credential = user.toCredential()
        @Expect(credential.userId, "42")
        @Expect(credential.userKey, "secret-key")
        @Expect(credential.isLoggedIn, true)
        // 不要泄露密钥
        @Expect(user.toString().contains("secret-key"), false)
    }

    @TestCase
    func testDownloadsLeftNeverNegative(): Unit {
        let user = ZlibUser.fromJson("{\"downloads_today\":20,\"downloads_limit\":10}")
        @Expect(user.downloadsLeft(), 0)
    }
}

@Test
class DownloadInfoTest {
    @TestCase
    func testDecode(): Unit {
        let info = DownloadInfo.fromJson("""
{
  "downloadLink": "https://dl.example.com/f/1?token=x",
  "description": "Rust 程序设计语言",
  "author": "Steve Klabnik",
  "extension": "epub",
  "allowDownload": true
}
""")
        @Expect(info.downloadLink, "https://dl.example.com/f/1?token=x")
        @Expect(info.extension, "epub")
        @Expect(info.available(), true)
        @Expect(info.fileName(), "Rust 程序设计语言 (Steve Klabnik).epub")
    }

    @TestCase
    func testFileNameFallbacks(): Unit {
        let info = DownloadInfo.fromJson("{\"downloadLink\":\"https://x\",\"extension\":\"pdf\"}")
        @Expect(info.fileName(), "book.pdf")
        // 默认允许下载（老接口不给 allowDownload 字段）
        @Expect(info.allowDownload, true)
        @Expect(info.available(), true)
        let missing = DownloadInfo.fromJson("{}")
        @Expect(missing.available(), false)
    }

    @TestCase
    func testFileNameSanitized(): Unit {
        let info = DownloadInfo.fromJson(
            "{\"downloadLink\":\"https://x\",\"description\":\"a/b:c*?\",\"extension\":\"epub\"}")
        @Expect(info.fileName(), "a_b_c__.epub")
    }
}

@Test
class PaginationTest {
    @TestCase
    func testDecodeAndNavigate(): Unit {
        let page = BookPage.fromJson("""
{
  "books": [
    {"id": 1, "title": "第一本", "hash": "h1"},
    {"id": 2, "title": "第二本", "hash": "h2"}
  ],
  "pagination": {"limit": 2, "current": 1, "total_items": 3, "total_pages": 2}
}
""")
        @Expect(page.size(), 2)
        @Expect(page.isEmpty(), false)
        @Expect(page.pagination.current, 1)
        @Expect(page.pagination.totalItems, 3)
        @Expect(page.pagination.hasMore(), true)
        @Expect(page.pagination.nextPage(), 2)
        @Expect(page.hasMore(), true)
        @Expect(page.nextPage(), 2)
        @Expect(page.first().getOrThrow().title, "第一本")
    }

    @TestCase
    func testEmptyPage(): Unit {
        let page = BookPage.fromJson("{\"books\":[]}")
        @Expect(page.isEmpty(), true)
        @Expect(page.first().isNone(), true)
        @Expect(page.pagination.current, 0)
        @Expect(page.pagination.hasMore(), false)
        // 没有分页信息时也不会崩
        @Expect(page.nextPage(), 0)
    }
}
