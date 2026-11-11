package zlibraryAPI4CJ.comment

import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 评论接口（papi，静态函数，第一个参数是 `ZlibClient`）。
 *
 * 只有两个对象类型：书与书单。接口匿名可读；登录后返回的
 * `reactionsInfo` 里会带「当前用户是否已赞」。
 */
public class CommentApi {
    /**
     * 某本书的评论。
     *
     * 接口：`GET /papi/comments/book/{bookId}/{offset}?limit=500`
     *
     * @param bookId 书 id（**不是 hash**）
     * @param offset 跳过前 N 条（0 = 从第一条开始）
     * @return 评论页（按时间升序，最多 100 条；`nextOffset(offset)` 给下一段）
     */
    public static func book(client: ZlibClient, bookId: Int64,
        offset!: Int64 = 0): BookCommentsPage {
        fetch(client, "book", bookId, offset)
    }

    /**
     * 某份书单的评论。
     *
     * 接口：`GET /papi/comments/booklist/{readlistId}/{offset}?limit=500`
     */
    public static func booklist(client: ZlibClient, readlistId: Int64,
        offset!: Int64 = 0): BookCommentsPage {
        fetch(client, "booklist", readlistId, offset)
    }

    /** 统一入口：对象类型只用于拼路径。 */
    private static func fetch(client: ZlibClient, objectType: String, objectId: Int64,
        offset: Int64): BookCommentsPage {
        let path = "/comments/${objectType}/${objectId}/${offset}"
        // limit 服务端忽略（固定最多 100 条），这里发 500 与网站前端保持一致，
        // 避免将来服务端改成「按 limit 生效」时反而变少
        let root = client.getPapiJson(path, query: [("limit", "500")])
        BookCommentsPage.fromRoot(root)
    }
}
