package zlibraryAPI4CJ.book

import std.collection.*
import std.fs.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 图书接口。
 *
 * 全部接口函数都是 `public static func`，第一个参数是 `ZlibClient`：
 * 接口函数本身无状态，客户端生命周期与凭证完全由调用方掌握，
 * 因此可以并发复用同一个客户端。
 *
 * 路径里的 `{id}` / `{hash}` 必须来自**同一本书**：搜索/相似列表返回的
 * `BookInfoBrief` 同时带了两者，直接用 `infoOf` / `similarOf` / `fileOf` 即可。
 */
public class BookApi {
    /**
     * 获取图书详情。
     *
     * 接口：`GET /book/{id}/{hash}`。
     *
     * @param id 图书 id
     * @param hash 图书 hash
     * @param switchLanguage 指定返回文案语言（对应 query `switch-language`）；`None` 用账号设置
     */
    public static func info(client: ZlibClient, id: Int64, hash: String,
        switchLanguage!: ?String = None): BookInfo {
        client.getObject("/book/${id}/${hash}", "book", { obj => BookInfo.fromJsonObject(obj) },
            query: switchLanguageQuery(switchLanguage))
    }

    /** 用列表项（`BookInfoBrief`）取详情，省去手动传 id/hash。 */
    public static func infoOf(client: ZlibClient, brief: BookInfoBrief,
        switchLanguage!: ?String = None): BookInfo {
        info(client, brief.id, brief.hash, switchLanguage: switchLanguage)
    }

    /**
     * 获取相似图书。
     *
     * 接口：`GET /book/{id}/{hash}/similar`。
     *
     * 返回的是列表项（简要信息）；要详情需要再对每个元素调 `info()`。
     */
    public static func similar(client: ZlibClient, id: Int64,
        hash: String): ArrayList<BookInfoBrief> {
        client.getObjects("/book/${id}/${hash}/similar", "books",
            { obj => BookInfoBrief.fromJsonObject(obj) })
    }

    /** 用图书详情取相似图书。 */
    public static func similarOf(client: ZlibClient,
        book: BookInfo): ArrayList<BookInfoBrief> {
        similar(client, book.id, book.hash)
    }

    /**
     * 获取下载信息。
     *
     * 接口：`GET /book/{id}/{hash}/file`。
     *
     * 返回的 `DownloadInfo.downloadLink` 是**签名过的绝对链接**，
     * 且常常指向用户的个人域名；不要缓存太久，失效时重新调用本方法换新链接。
     *
     * 需要登录态：游客调用通常得到 `success=0` 或 `allowDownload=false`。
     */
    public static func file(client: ZlibClient, id: Int64, hash: String): DownloadInfo {
        client.getObject("/book/${id}/${hash}/file", "file",
            { obj => DownloadInfo.fromJsonObject(obj) })
    }

    /** 用图书详情取下载信息。 */
    public static func fileOf(client: ZlibClient, book: BookInfo): DownloadInfo {
        file(client, book.id, book.hash)
    }

    /**
     * 获取可用格式。
     *
     * 接口：`GET /book/{id}/{hash}/formats`。
     *
     * 返回的面板字段不稳定（不同账号/不同书差异很大），因此直接返回原始
     * JSON 根对象，调用方按需读取（通常是 `formats` 数组）。需要强类型时
     * 建议先用 `book.file()` 的 `extension` 判断目标格式是否可下载。
     */
    public static func formats(client: ZlibClient, id: Int64, hash: String): JsonObject {
        let path = "/book/${id}/${hash}/formats"
        client.getEnvelope(path).unwrap(path: path)
    }

    /**
     * 收藏图书。
     *
     * 接口：`GET /user/book/{id}/save`。
     *
     * ⚠ 与详情接口不同，收藏**只需要 `id`**，不需要 hash。
     * 失败（未登录、书不存在）抛 `ZlibError`，而不是返回 Bool——
     * 调用方需要知道「为什么没收藏上」，静默 false 会掩盖登录过期。
     */
    public static func save(client: ZlibClient, id: Int64): Unit {
        let path = "/user/book/${id}/save"
        client.getEnvelope(path).unwrap(path: path)
        ()
    }

    /** 用列表项收藏（`BookInfoBrief` 自带 id）。 */
    public static func saveBrief(client: ZlibClient, brief: BookInfoBrief): Unit {
        save(client, brief.id)
    }

    /**
     * 取消收藏。
     *
     * 接口：`GET /user/book/{id}/unsave`。
     */
    public static func unsave(client: ZlibClient, id: Int64): Unit {
        let path = "/user/book/${id}/unsave"
        client.getEnvelope(path).unwrap(path: path)
        ()
    }

    /** 用列表项取消收藏。 */
    public static func unsaveBrief(client: ZlibClient, brief: BookInfoBrief): Unit {
        unsave(client, brief.id)
    }

    /**
     * 从「我的收藏 / 已下载」列表里删除。
     *
     * 接口：`GET /user/book/{id}/delete`。
     *
     * 注意与 `unsave` 的区别：`unsave` 只取消收藏状态，`delete` 是把条目
     * 从账号的书籍列表里整体移除（服务端行为由站点实现，二者都可能存在）。
     */
    public static func remove(client: ZlibClient, id: Int64): Unit {
        let path = "/user/book/${id}/delete"
        client.getEnvelope(path).unwrap(path: path)
        ()
    }

    /**
     * 把图书发送到 Kindle / 邮箱。
     *
     * 接口：`GET /book/{id}/{hash}/send-to-{type}`。
     *
     * @param target 目标类型，直接拼进路径。社区客户端使用过 `kindle` 与 `email`，
     *               但服务端并未公开枚举；本库不做枚举约束，避免写死过期值。
     *               该操作通常要求账号已绑定 Kindle 邮箱/已验证邮箱。
     */
    public static func sendTo(client: ZlibClient, id: Int64, hash: String,
        target: String): Unit {
        let kind = target.trimAscii()
        if (kind.isEmpty()) {
            throw ZlibError(ZlibErrorKind.BadResponse, "sendTo 的 target 不能为空（如 kindle / email）")
        }
        let path = "/book/${id}/${hash}/send-to-${kind}"
        client.getEnvelope(path).unwrap(path: path)
        ()
    }

    /**
     * 把已获取的下载信息落盘。
     *
     * 文件名由 `DownloadInfo.fileName()` 生成（`描述 (作者).扩展名`），
     * 保存目录不存在时自动递归创建。
     *
     * @param dir 保存目录
     * @param overwrite `false`（默认）时若同名文件存在会自动改名（`file(1).ext`），
     *                  不会覆盖用户已有文件
     * @return 写入的字节数
     */
    public static func download(client: ZlibClient, info: DownloadInfo, dir: Path,
        overwrite!: Bool = false): Int64 {
        if (info.downloadLink.isEmpty()) {
            throw ZlibError(ZlibErrorKind.BadResponse,
                "下载链接为空：请先用 BookApi.file() 换取 DownloadInfo")
        }
        if (!info.allowDownload) {
            throw ZlibError.apiFailure("book/download", "服务端标记该书不可下载（allowDownload=false）")
        }
        Directory.create(dir, recursive: true)
        client.download(info.downloadLink, dir.join(info.fileName()), overwrite: overwrite)
    }

    /**
     * 一步完成「换取下载信息 + 落盘」。
     *
     * 等价于 `download(client, file(client, id, hash), dir)`；
     * 需要自己控制重试/换链接时，分开调用两步更灵活。
     */
    public static func downloadBook(client: ZlibClient, id: Int64, hash: String,
        dir: Path, overwrite!: Bool = false): Int64 {
        download(client, file(client, id, hash), dir, overwrite: overwrite)
    }
}

/** 构造 `switch-language` 查询参数（`None` 时为空数组）。 */
internal func switchLanguageQuery(value: ?String): Array<(String, String)> {
    let query = ArrayList<(String, String)>()
    if (let Some(actual) <- value) {
        query.add(("switch-language", actual))
    }
    query.toArray()
}
