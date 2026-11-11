package zlibraryAPI4CJ.booklist

import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 书单模型单元测试。
 *
 * 样本取自 2026-11-11 真实 papi 响应（截断到单条），只验证离线可验证的
 * JSON 解码语义；网络请求由集成环境验证。
 */
@Test
class BooklistDecodeTest {
    private let PAGE_SAMPLE = """
{
  "success": 1,
  "nextPage": 3,
  "readlists": [
    {
      "id": 36258,
      "user_id": 10224915,
      "title": "BTS's recommendations",
      "description": "Books that the members have read",
      "languages": "en",
      "public": true,
      "adult": false,
      "editors_choice": false,
      "views_count": 873,
      "books_count": 7,
      "favorites_count": 79,
      "comments_count": 0,
      "color": 0,
      "date_updated": "2026-11-11T01:11:52.000000Z",
      "date": "2021-08-27T01:29:55.000000Z",
      "link": "/booklist/36258/31302b/btss-recommendations.html"
    }
  ],
  "readlistsOwners": {
    "10224915": {"id": 10224915, "link": "/profile/10224915/9d31a8", "name": "brunaaardp", "avatar": ""}
  },
  "booksGrouped": {
    "36258": [
      {"id": 5730292, "title": "Almond", "author": "Won-pyung Sohn", "cover": "a.jpg",
       "storage": "userbooks", "identifier": "9780062961372", "language": "english",
       "link": "/book/PxGOjl0qxG/almond.html",
       "coverUrl": "https://example.org/covers/almond.jpg"}
    ]
  }
}
"""

    private let BOOKS_SAMPLE = """
{
  "success": 1,
  "books": [
    {"book": {
      "id": 1309401, "title": "The Noonday Demon", "author": "Andrew Solomon",
      "year": 2002, "language": "english", "extension": "epub",
      "filesize": 766976, "filesizeString": "749 KB",
      "hash": "f247aa", "href": "/book/Lb5DoboR9g/the-noonday-demon.html",
      "cover": "https://example.org/covers/demon.jpg", "description": "desc"
    }}
  ],
  "pagination": {"limit": 20, "current": 1, "before": false, "next": false,
                 "total_items": 7, "total_pages": 1}
}
"""

    @TestCase
    func testBooklistPageDecode(): Unit {
        let page = BooklistPage.fromRoot(parseJsonObject(PAGE_SAMPLE))
        @Expect(page.readlists.size, 1)
        @Expect(page.nextPage, 3)
        let readlist = page.readlists[0]
        @Expect(readlist.id, 36258)
        @Expect(readlist.title, "BTS's recommendations")
        @Expect(readlist.booksCount, 7)
        @Expect(readlist.favoritesCount, 79)
        @Expect(readlist.publicReadlist, true)
        @Expect(readlist.link, "/booklist/36258/31302b/btss-recommendations.html")
        @Expect(readlist.ownerName(page), "brunaaardp")
        @Expect(page.owners.size, 1)
        @Expect(page.owners.get("10224915").isSome(), true)
    }

    @TestCase
    func testBooklistPreviewDecode(): Unit {
        let page = BooklistPage.fromRoot(parseJsonObject(PAGE_SAMPLE))
        let previews = page.previewOf(36258)
        @Expect(previews.isSome(), true)
        let books = previews.getOrThrow()
        @Expect(books.size, 1)
        @Expect(books[0].id, 5730292)
        @Expect(books[0].title, "Almond")
        @Expect(books[0].coverUrl, "https://example.org/covers/almond.jpg")
    }

    @TestCase
    func testBooklistBooksDecode(): Unit {
        let page = BooklistBooksPage.fromRoot(parseJsonObject(BOOKS_SAMPLE))
        @Expect(page.books.size, 1)
        @Expect(page.totalItems, 7)
        @Expect(page.totalPages, 1)
        @Expect(page.current, 1)
        @Expect(page.limit, 20)
        let book = page.books[0]
        @Expect(book.id, 1309401)
        @Expect(book.title, "The Noonday Demon")
        @Expect(book.extension, "epub")
        @Expect(book.filesizeString, "749 KB")
        @Expect(book.hash, "f247aa")
    }

    @TestCase
    func testEmptyBooklistPage(): Unit {
        let page = BooklistPage.fromRoot(parseJsonObject("{\"success\":1,\"readlists\":[]}"))
        @Expect(page.readlists.size, 0)
        @Expect(page.nextPage, 0)
        @Expect(page.previewOf(1).isNone(), true)
    }
}
