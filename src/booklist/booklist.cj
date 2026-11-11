package zlibraryAPI4CJ.booklist

import std.collection.*
import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 书单相关接口（静态函数，第一个参数是 `ZlibClient`）。
 *
 * 这些端点来自网站前端的 papi（eapi 没有书单接口），响应形状与 eapi
 * 一样是 JSON，但根上有自己的字段（`readlists` / `booksGrouped`）。
 */
public class BooklistApi {
    /**
     * 公开书单列表。
     *
     * 接口：`GET /papi/booklist/get-page/{page}?order=…&searchQuery=…&color=…&access=…`
     *
     * @param page 页码（从 1 开始）
     * @param order 排序：`popular`（默认）/ `newest` / …（服务端定义，原样透传）
     * @param searchQuery 搜索关键词；空串表示不按关键词过滤
     * @param color 配色筛选（`all` 或具体颜色编号）
     * @param access `public`（默认）/ `private`（需登录）
     * @return 书单列表页（含作者信息与预览书籍）
     */
    public static func list(client: ZlibClient, page!: Int64 = 1,
        order!: String = "popular", searchQuery!: String = "",
        color!: ?String = None, access!: ?String = None): BooklistPage {
        let query = ArrayList<(String, String)>()
        query.add(("order", order))
        query.add(("searchQuery", searchQuery))
        if (let Some(value) <- color) {
            query.add(("color", value))
        }
        if (let Some(value) <- access) {
            query.add(("access", value))
        }
        let root = client.getPapiJson("/booklist/get-page/${page}", query: query.toArray())
        BooklistPage.fromRoot(root)
    }

    /**
     * 我的书单（需要登录）。
     *
     * 等价于 `list(..., access: "private")`；未登录时服务端通常返回空列表
     * 或 `success=0`（客户端会抛 `ZlibError`）。
     */
    public static func my(client: ZlibClient, page!: Int64 = 1,
        order!: String = "popular", searchQuery!: String = ""): BooklistPage {
        list(client, page: page, order: order, searchQuery: searchQuery,
            color: None<String>, access: Some("private"))
    }

    /**
     * 某个书单里的书。
     *
     * 接口：`POST /papi/booklist/{readlistId}/get-books/{page}`，表单 `page=…`。
     *
     * @return 书籍页（每本按 `BookInfo` 解码，含分页信息）
     */
    public static func books(client: ZlibClient, readlistId: Int64,
        page!: Int64 = 1): BooklistBooksPage {
        let root = client.postPapiFormJson("/booklist/${readlistId}/get-books/${page}",
            [("page", "${page}")])
        BooklistBooksPage.fromRoot(root)
    }
}
