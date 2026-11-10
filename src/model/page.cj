package zlibraryAPI4CJ.model

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * 分页信息（`pagination` 字段）。
 *
 * eapi 的列表接口统一返回：
 *
 * ```json
 * "pagination": { "limit": 20, "current": 1, "total_items": 1234, "total_pages": 62 }
 * ```
 *
 * 注意服务端用下划线命名，而模型用驼峰；解码时已经做了映射。
 */
public class Pagination <: ToString {
    /** 每页条数。 */
    public var limit: Int64 = 0
    /** 当前页码（从 1 开始）。 */
    public var current: Int64 = 0
    /** 总条数。 */
    public var totalItems: Int64 = 0
    /** 总页数。 */
    public var totalPages: Int64 = 0

    /** 从 JSON 对象解码（容错）。 */
    public static func fromJsonObject(obj: JsonObject): Pagination {
        let pagination = Pagination()
        pagination.limit = readInt(obj, "limit")
        pagination.current = readInt(obj, "current")
        pagination.totalItems = readInt(obj, "total_items")
        pagination.totalPages = readInt(obj, "total_pages")
        pagination
    }

    /** 是否还有下一页。 */
    public func hasMore(): Bool {
        current < totalPages
    }

    /** 下一页页码（没有下一页时返回当前页）。 */
    public func nextPage(): Int64 {
        if (hasMore()) {
            current + 1
        } else {
            current
        }
    }

    public func toString(): String {
        "Pagination(${current}/${totalPages}, ${totalItems} items)"
    }
}

/**
 * 一页图书结果（搜索、收藏列表、下载历史都用它）。
 *
 * 为什么封装成 `BookPage` 而不是裸数组：调用方需要 `hasMore()` / `nextPage()`
 * 才知道该不该继续翻页；只给数组会迫使每个调用方自己重新推一遍分页逻辑。
 */
public class BookPage <: ToString {
    /** 本页图书。 */
    public var books: ArrayList<BookInfo> = ArrayList<BookInfo>()
    /** 分页信息。 */
    public var pagination: Pagination = Pagination()

    /** 从 JSON 对象解码：读取根上的 `books` 与 `pagination`。 */
    public static func fromJsonObject(obj: JsonObject): BookPage {
        let page = BookPage()
        page.books = decodeEach<BookInfo>(arrayFieldOf(obj, "books")) { item =>
            BookInfo.fromJsonObject(item)
        }
        match (objectFieldOf(obj, "pagination")) {
            case Some(value) => page.pagination = Pagination.fromJsonObject(value)
            case None => page.pagination = Pagination()
        }
        page
    }

    /** 从 JSON 文本解码。 */
    public static func fromJson(text: String): BookPage {
        fromJsonObject(parseJsonObject(text, path: "book-page"))
    }

    /** 本页条数。 */
    public func size(): Int64 {
        books.size
    }

    /** 是否为空页。 */
    public func isEmpty(): Bool {
        books.isEmpty()
    }

    /** 是否还有下一页。 */
    public func hasMore(): Bool {
        pagination.hasMore()
    }

    /** 下一页页码。 */
    public func nextPage(): Int64 {
        pagination.nextPage()
    }

    /** 取第一本；空页返回 `None`。 */
    public func first(): ?BookInfo {
        if (books.isEmpty()) {
            return None
        }
        Some(books[0])
    }

    public func toString(): String {
        "BookPage(${books.size} books, ${pagination})"
    }
}
