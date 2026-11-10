package zlibraryAPI4CJ.user

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

// eapi 路径常量集中在这里：本包接口全部挂在 `/user/**` 下。
private let PROFILE_PATH: String = "/user/profile"
private let SAVED_PATH: String = "/user/book/saved"
private let DOWNLOADED_PATH: String = "/user/book/downloaded"
private let RECOMMENDED_PATH: String = "/user/book/recommended"
private let UPDATE_PATH: String = "/user/update"
private let HIDE_BANNER_PATH: String = "/user/hide-banner"
private let DONATIONS_PATH: String = "/user/donations"

/**
 * 当前登录用户的接口。
 *
 * 所有方法第一个参数都是 `ZlibClient`，客户端必须已绑定 remix 凭证
 * （`LoginApi.loginClient(...)` 或 `client.withCredential(...)` 派生）。
 * 凭证缺失/失效时服务端返回 `success = 0`，由 `ZlibEnvelope.unwrap` 归类为
 * `ZlibErrorKind.NotLoggedIn`。
 */
public class UserApi {
    /**
     * 获取当前用户资料。
     *
     * 接口：`GET /eapi/user/profile`，响应根对象的 `user` 字段。
     *
     * 返回的 `ZlibUser` 里同时有身份信息（`id` / `email` / `remixUserKey`）与
     * 配额信息（`downloadsToday` / `downloadsLimit`），后者用
     * `downloadsLeft()` 可以直接算出今日剩余次数。
     *
     * @throws ZlibError 未登录、凭证失效或响应不是 JSON
     */
    public static func profile(client: ZlibClient): ZlibUser {
        // decoder 之后还有带默认值的 query 参数，所以这里必须显式传 lambda（不能用尾随 lambda 语法）
        client.getObject(PROFILE_PATH, "user", { obj => ZlibUser.fromJsonObject(obj) })
    }

    /**
     * 收藏列表（分页）。
     *
     * 接口：`GET /eapi/user/book/saved`，query：`order` / `page` / `limit`。
     * 响应根对象含 `books` 数组与 `pagination` 对象，直接交给
     * `BookPage.fromJsonObject` 解码。
     *
     * `order` 是服务端定义的排序枚举，客户端**原样透传**（社区抓包里的已知值有
     * `date` / `title` / `year` / `popular` 等），不做本地校验：服务端新增枚举值时
     * 旧客户端不应因此报错。
     *
     * @param order 排序方式；`None` 表示用服务端默认排序
     * @param page 页码，从 1 开始
     * @param limit 每页条数
     */
    public static func saved(client: ZlibClient, order!: ?String = None, page!: Int64 = 1,
        limit!: Int64 = 20): BookPage {
        bookPageOf(client, SAVED_PATH, order, page, limit)
    }

    /**
     * 下载历史（分页）。
     *
     * 接口：`GET /eapi/user/book/downloaded`，query 与响应形状同 `saved`。
     *
     * 注意：这里只返回「下载过哪些书」的元信息，不含下载链接；
     * 真正取下载地址要再用 `BookApi.file(...)` 换 `DownloadInfo`。
     *
     * @param order 排序方式；`None` 表示服务端默认
     * @param page 页码，从 1 开始
     * @param limit 每页条数
     */
    public static func downloaded(client: ZlibClient, order!: ?String = None,
        page!: Int64 = 1, limit!: Int64 = 20): BookPage {
        bookPageOf(client, DOWNLOADED_PATH, order, page, limit)
    }

    /**
     * 个性化推荐书单。
     *
     * 接口：`GET /eapi/user/book/recommended`，响应根对象的 `books` 数组。
     *
     * 这是按账号历史生成的推荐，**必须带登录态**；游客态会返回未登录错误。
     * 元素是 `BookInfoBrief`（列表项字段），足够展示与发起下载（`id` + `hash` 都在），
     * 需要简介/文件大小时再调 `BookApi.info(...)`。
     */
    public static func recommended(client: ZlibClient): ArrayList<BookInfoBrief> {
        // decoder 之后还有带默认值的 query 参数，所以这里必须显式传 lambda（不能用尾随 lambda 语法）
        client.getObjects(RECOMMENDED_PATH, "books",
            { obj => BookInfoBrief.fromJsonObject(obj) })
    }

    /**
     * 修改账号资料。
     *
     * 接口：`POST /eapi/user/update`，表单字段 `email` / `password` / `name` /
     * `kindle_email`。
     *
     * **只发送非 `None` 的字段**：服务端把「字段存在」当成「要更新」，
     * 无脑发送空串会把已有昵称/Kindle 邮箱清空。所以这里的 `None` 语义是
     * 「这项不改」，而不是「改成空值」。
     *
     * `kindle_email` 的下划线命名是服务端要求的关键字，别写成 `kindleEmail`。
     *
     * @param email 新邮箱（改邮箱通常要走邮箱确认流程）
     * @param password 新密码
     * @param name 新昵称
     * @param kindleEmail Kindle 推送邮箱
     * @throws ZlibError 未登录、邮箱被占用或密码不合规
     */
    public static func update(client: ZlibClient, email!: ?String = None,
        password!: ?String = None, name!: ?String = None,
        kindleEmail!: ?String = None): Unit {
        client.postFormEnvelope(UPDATE_PATH, updateForm(email, password, name, kindleEmail))
            .unwrap(path: UPDATE_PATH)
        ()
    }

    /**
     * 关闭首页横幅（banner）。
     *
     * 接口：`GET /eapi/user/hide-banner`。这是「写操作却是 GET」的历史遗留端点，
     * 副作用记在账号偏好里，所以需要登录态。
     */
    public static func hideBanner(client: ZlibClient): Unit {
        client.getEnvelope(HIDE_BANNER_PATH).unwrap(path: HIDE_BANNER_PATH)
        ()
    }

    /**
     * 获取捐赠信息。
     *
     * 接口：`GET /eapi/user/donations`。
     *
     * 返回**原始根对象**而不是强类型模型：该接口的响应形状不稳定（不同时期是
     * 对象、数组或带额外统计字段的混合结构，社区文档也只说「返回捐赠信息」），
     * 强行建模只会得到一个随时可能失真的空壳。需要哪个字段就用
     * `readInt` / `readString` 从容错读取工具里取，或直接看 `root.toString()`。
     *
     * @return 信封解包后的 JSON 根对象（已确认 `success = 1`）
     * @throws ZlibError 未登录或响应不是 JSON
     */
    public static func donations(client: ZlibClient): JsonObject {
        client.getEnvelope(DONATIONS_PATH).unwrap(path: DONATIONS_PATH)
    }
}

/**
 * 构造分页查询参数。
 *
 * 抽成函数有两个目的：`saved` / `downloaded` 共用同一套参数口径；
 * 单测可以离线验证编码结果（`order` 只在非 `None` 时出现）。
 */
internal func pagingQuery(order: ?String, page: Int64, limit: Int64): Array<(String, String)> {
    Query()
        .setIfSome("order", order)
        .setInt("page", page)
        .setInt("limit", limit)
        .toArray()
}

/** 请求分页接口并把根对象解码成 `BookPage`（`saved` / `downloaded` 共用）。 */
internal func bookPageOf(client: ZlibClient, path: String, order: ?String, page: Int64,
    limit: Int64): BookPage {
    let query = pagingQuery(order, page, limit)
    BookPage.fromJsonObject(client.getEnvelope(path, query: query).unwrap(path: path))
}

/**
 * 组装 `POST /user/update` 的表单：只收集非 `None` 字段。
 *
 * 空集合也要能正常发出（服务端会返回「没有要更新的内容」之类的业务错误，
 * 那是调用方的问题，不应该在客户端侧静默吞掉）。
 */
internal func updateForm(email: ?String, password: ?String, name: ?String,
    kindleEmail: ?String): Array<(String, String)> {
    let form = ArrayList<(String, String)>()
    if (let Some(value) <- email) {
        form.add(("email", value))
    }
    if (let Some(value) <- password) {
        form.add(("password", value))
    }
    if (let Some(value) <- name) {
        form.add(("name", value))
    }
    if (let Some(value) <- kindleEmail) {
        form.add(("kindle_email", value))
    }
    form.toArray()
}
