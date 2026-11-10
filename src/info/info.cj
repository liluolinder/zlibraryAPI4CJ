package zlibraryAPI4CJ.info

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * 站点信息接口。
 *
 * 与其它子包的差别：这里全部方法返回**原始 `JsonObject`**（信封成功后的根对象），
 * 不做强类型建模。原因见 `info_pkg.cj` 的包注释：站点元数据的形状随镜像/版本
 * 漂移，强类型模型只会让整个接口因为一个字段类型变化而失效。
 *
 * 失败语义与其它子包一致：`success = 0` 时 `unwrap` 抛 `ZlibError`
 * （服务端提示 login 的会映射成 `ZlibErrorKind.NotLoggedIn`）。
 *
 * 典型用法：
 *
 * ```cangjie
 * let root = InfoApi.languages(client)
 * for (item in arrayFieldOf(root, "languages")) {
 *     println(readString(item.asObject(), "name"))
 * }
 * ```
 */
public class InfoApi {
    /**
     * 获取站点总览信息。
     *
     * 接口：`GET /info`。
     *
     * 返回里通常含站点域名、公告、默认语言、分类等；字段集合不稳定，
     * 调用方应只读自己需要的 key，缺字段时按空值处理。
     *
     * @param switchLanguage 指定返回文案语言（query `switch-language`）；
     *                       `None` 用站点默认
     */
    public static func site(client: ZlibClient, switchLanguage!: ?String = None): JsonObject {
        let path = "/info"
        client.getEnvelope(path, query: switchLanguageQuery(switchLanguage)).unwrap(path: path)
    }

    /**
     * 获取站点支持的语言列表。
     *
     * 接口：`GET /info/languages`。
     *
     * 这些值就是搜索/筛选用到的语言标识（如 `german`、`english`），
     * 可以直接传给 `SearchApi.search` 的 `languages` 参数。
     */
    public static func languages(client: ZlibClient): JsonObject {
        infoRoot(client, "/info/languages")
    }

    /**
     * 获取站点支持的图书扩展名列表。
     *
     * 接口：`GET /info/extensions`。
     *
     * 返回值可用于 `SearchApi.search` 的 `extensions` 过滤；
     * 注意「站点支持的格式」与「某本书可下载的格式」是两回事，
     * 后者要看 `BookApi.file` 返回的 `DownloadInfo.extension`。
     */
    public static func extensions(client: ZlibClient): JsonObject {
        infoRoot(client, "/info/extensions")
    }

    /**
     * 获取当前可用域名列表。
     *
     * 接口：`GET /info/domains`。
     *
     * Z-Library 主域名会轮换、账号还有「个人域名」，所以这里拿到的列表
     * 可以作为 `ZlibClient.withBaseUrl` 换站点的候选；是否真的可达仍需
     * `probeSite` / `checkAccess` 探测。
     */
    public static func domains(client: ZlibClient): JsonObject {
        infoRoot(client, "/info/domains")
    }

    /**
     * 获取会员/套餐信息。
     *
     * 接口：`GET /info/plans`。
     *
     * 响应形状不稳定（不同站点版本差异较大），因此同样只返回原始根对象；
     * 需要判断「当前账号是否付费」时，用 `UserApi.profile` 的
     * `ZlibUser.isPremium` 更可靠。
     *
     * @param switchLanguage 指定返回文案语言（query `switch-language`）；
     *                       `None` 用站点默认
     */
    public static func plans(client: ZlibClient, switchLanguage!: ?String = None): JsonObject {
        let path = "/info/plans"
        client.getEnvelope(path, query: switchLanguageQuery(switchLanguage)).unwrap(path: path)
    }
}

/** GET 一个 info 端点并解出信封根对象（无参数版本共用）。 */
private func infoRoot(client: ZlibClient, path: String): JsonObject {
    client.getEnvelope(path).unwrap(path: path)
}

/**
 * 构造 `switch-language` 查询参数；`None` 时为空数组。
 *
 * 该参数只影响响应文案的语言（书名/分类名的翻译），不改变返回内容，
 * 游客同样可用。
 */
internal func switchLanguageQuery(value: ?String): Array<(String, String)> {
    let query = ArrayList<(String, String)>()
    if (let Some(actual) <- value) {
        query.add(("switch-language", actual))
    }
    query.toArray()
}
