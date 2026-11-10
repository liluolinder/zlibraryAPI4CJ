/**
 * `zlibraryAPI4CJ.core` —— 与业务无关的基础设施层。
 *
 * 这一层只做「每个接口都逃不掉」的四件事，刻意不包含任何业务模型：
 *
 * 1. **连接与身份**（`client.cj` / `credential.cj`）：一个 `ZlibClient`
 *    内部只持有一个 LinderHttp `HttpClient`，连接池与 Cookie 存储共享；
 *    凭证是不可变值，通过 `withCredential` 派生新客户端。
 * 2. **站点地址**（`host.cj`）：Z-Library 没有稳定的官方域名，必须允许
 *    运行期指定与探测；`resolveZlibHost` 会按候选列表逐个 HEAD 探测。
 * 3. **响应信封与错误**（`envelope.cj` / `error.cj`）：eapi 统一返回
 *    `{"success": 1, ...}` / `{"success": 0, "error": "..."}`；业务失败统一
 *    抛 `ZlibError`，HTTP 层失败仍由 LinderHttp 的 `HttpError` 抛出，两者可分别捕获。
 * 4. **容错读取与编码**（`envelope.cj` 的 `readXxx`、`query.cj`、`text.cj`）：
 *    Z-Library 的字段类型并不稳定（同一字段可能给数字或字符串、可选字段会缺），
 *    所以模型解码一律走宽松读取，单条脏数据不能拖垮整页结果。
 *
 * 文件划分：
 *
 * | 文件 | 内容 |
 * | --- | --- |
 * | `client.cj`     | `ZlibClient` / `ZlibClientConfig`：请求、信封解包、下载 |
 * | `credential.cj` | `ZlibCredential`：remix_userid / remix_userkey / 语言 |
 * | `host.cj`       | `ZlibHost` / `checkAccess` / `canAccessZlib` / `resolveZlibHost` |
 * | `envelope.cj`   | `ZlibEnvelope` + 宽松 JSON 读取工具 |
 * | `error.cj`      | `ZlibErrorKind` / `ZlibError` |
 * | `site.cj`       | `ZlibSites`：自定义站（优先）+ 种子站（失败换站），换站计划与域名列表提取 |
 * | `query.cj`      | `Query` / `withQuery` / `formEncode` / 百分号编码 |
 * | `text.cj`       | UTF-8 安全截断 |
 */
package zlibraryAPI4CJ.core

/** eapi 路径前缀。所有业务接口都挂在 `<站点地址>/eapi` 下。 */
public let ZLIB_API_PREFIX: String = "/eapi"

/** 默认站点语言（写入 `siteLanguage` / `siteLanguageV2` Cookie，并影响服务端返回文案）。 */
public let ZLIB_DEFAULT_SITE_LANGUAGE: String = "zh"
