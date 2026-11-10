package zlibraryAPI4CJ.search

import std.collection.*
import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 搜索接口。
 *
 * 全部接口函数都是 `public static func`，第一个参数是 `ZlibClient`：
 * 接口函数本身无状态，连接池 / 凭证 / 站点地址都由调用方持有的客户端决定，
 * 所以同一个客户端可以被多个线程并发复用。
 *
 * 与 `BookApi` 的分工：`SearchApi` 只负责「找书」，拿到结果后按 `BookInfoBrief`
 * 的 `id` + `hash` 再调 `BookApi.info` / `BookApi.file` 取详情与下载链接。
 */
public class SearchApi {
    /**
     * 搜索图书。
     *
     * 接口：`POST /book/search`（`application/x-www-form-urlencoded` 表单）。
     *
     * 参数要点：
     *
     * - `message` 是搜索词（必填）。本库不做本地校验，空串原样发给服务端
     *   （服务端一般返回空结果），由调用方决定是否先拦截；
     * - `languages` / `extensions` 是**数组参数**：每个元素编码成同名的
     *   `languages[]` / `extensions[]` 字段，例如
     *   `languages[]=german&languages[]=french`。同名 key 会全部发出，
     *   **不会去重也不会被合并**（合并后服务端只认最后一个值）；
     * - `yearFrom` / `yearTo` 是可选年份区间，`None` 表示该端不限制；
     * - `order` 为**原样透传**的排序名，本库不校验：社区已知值有 `year`
     *   （按出版年份）与 `popular`（按热度）等，具体枚举由服务端定义且会扩展，
     *   传错值时服务端退回默认排序，不会变成客户端异常；
     * - `page` 从 1 开始，`limit` 为每页条数。
     *
     * @param client 客户端（游客可用；登录态会得到个性化结果）
     * @param message 搜索词
     * @param yearFrom 起始年份（含）；`None` 不限制
     * @param yearTo 结束年份（含）；`None` 不限制
     * @param languages 语言过滤，如 `["german", "english"]`；空数组不过滤
     * @param extensions 扩展名过滤，如 `["pdf", "epub"]`；空数组不过滤
     * @param order 排序方式（服务端定义，原样透传）
     * @param page 页码，从 1 开始
     * @param limit 每页条数
     * @return 一页搜索结果（`books` + `pagination`）
     */
    public static func search(client: ZlibClient, message: String,
        yearFrom!: ?Int64 = None, yearTo!: ?Int64 = None,
        languages!: Array<String> = Array<String>(),
        extensions!: Array<String> = Array<String>(), order!: ?String = None,
        page!: Int64 = 1, limit!: Int64 = 20): BookPage {
        let path = "/book/search"
        let form = searchForm(message, yearFrom: yearFrom, yearTo: yearTo,
            languages: languages, extensions: extensions, order: order, page: page,
            limit: limit)
        BookPage.fromJsonObject(client.postFormEnvelope(path, form).unwrap(path: path))
    }

    /**
     * 获取最热门图书。
     *
     * 接口：`GET /book/most-popular`。
     *
     * @param switchLanguage 指定返回文案语言（query `switch-language`）；
     *                       `None` 用账号/站点设置
     */
    public static func mostPopular(client: ZlibClient,
        switchLanguage!: ?String = None): ArrayList<BookInfoBrief> {
        client.getObjects("/book/most-popular", "books",
            { obj => BookInfoBrief.fromJsonObject(obj) },
            query: switchLanguageQuery(switchLanguage))
    }

    /**
     * 获取最近上传的图书。
     *
     * 接口：`GET /book/recently`。
     *
     * 该端点没有可用参数：热门榜还能用 `switch-language` 换文案语言，
     * 最近上传只有固定列表，所以这里不提供 `switchLanguage` 参数。
     */
    public static func recently(client: ZlibClient): ArrayList<BookInfoBrief> {
        client.getObjects("/book/recently", "books",
            { obj => BookInfoBrief.fromJsonObject(obj) })
    }
}

/**
 * 构造 `POST /book/search` 的表单字段。
 *
 * 为什么单独抽成函数：
 *
 * 1. 数组参数必须保留重复 key。`Query.set` 是覆盖语义、`HashMap` 也不允许
 *    重复 key，一旦用它们「顺手去重」，`languages[]` 就只剩最后一个语言；
 *    这里用 `ArrayList<(String, String)>` 按顺序堆叠，`Body.form` 会逐条编码
 *    并原样发出；
 * 2. 这段纯逻辑可以被单元测试直接覆盖（不需要网络），是本子包唯一能离线
 *    验证的编码路径；
 * 3. 调用方若想用自己的 HTTP 客户端发同一个请求，可以复用这份字段构造。
 *
 * 发的字段与顺序：`message` → `yearFrom`（可选）→ `yearTo`（可选）→
 * `languages[]`（每个语言一个）→ `extensions[]`（每个扩展名一个）→
 * `order`（可选）→ `page` → `limit`。
 */
internal func searchForm(message: String, yearFrom!: ?Int64 = None,
    yearTo!: ?Int64 = None, languages!: Array<String> = Array<String>(),
    extensions!: Array<String> = Array<String>(), order!: ?String = None,
    page!: Int64 = 1, limit!: Int64 = 20): Array<(String, String)> {
    let form = ArrayList<(String, String)>()
    form.add(("message", message))
    if (let Some(value) <- yearFrom) {
        form.add(("yearFrom", "${value}"))
    }
    if (let Some(value) <- yearTo) {
        form.add(("yearTo", "${value}"))
    }
    for (language in languages) {
        if (!language.isEmpty()) {
            form.add(("languages[]", language))
        }
    }
    for (extension in extensions) {
        if (!extension.isEmpty()) {
            form.add(("extensions[]", extension))
        }
    }
    if (let Some(value) <- order) {
        form.add(("order", value))
    }
    form.add(("page", "${page}"))
    form.add(("limit", "${limit}"))
    form.toArray()
}

/**
 * 构造 `switch-language` 查询参数；`None` 时为空数组。
 *
 * 该参数是 eapi 的通用文案语言开关：响应里的书名/分类名会按它翻译，
 * 但**不改变**返回哪些书。游客也能用，所以不要求登录。
 */
internal func switchLanguageQuery(value: ?String): Array<(String, String)> {
    let query = ArrayList<(String, String)>()
    if (let Some(actual) <- value) {
        query.add(("switch-language", actual))
    }
    query.toArray()
}
