package zlibraryAPI4CJ.core

import std.collection.*
import std.fs.*
import stdx.encoding.json.*
import linderHttp.*

/**
 * Z-Library eapi 客户端。
 *
 * 把四件与业务无关、但每个接口都必须正确的事收敛到一处：
 *
 * 1. **连接**：内部只持有一个 LinderHttp `HttpClient`，连接池与 Cookie 存储共享，
 *    所以应当在进程内复用一个实例，而不是每次请求新建（那样每次都要重新 TLS 握手）；
 * 2. **身份**：凭证既写 Cookie（`remix_userid` / `remix_userkey` / `siteLanguageV2`）
 *    也写请求头（`remix-userid` / `remix-userkey`），兼容不同版本的服务端；
 * 3. **信封解包**：`{"success":1,...}` / `{"success":0,"error":"..."}` 统一解析，
 *    失败抛 `ZlibError`，子包只需要关心业务字段；
 * 4. **站点地址**：Z-Library 域名不稳定，地址属于客户端配置，可用 `withBaseUrl` 派生。
 *
 * 客户端是不可变的（`credential` / `host` 都不能原地改），派生用
 * `withCredential` / `withBaseUrl` / `withHost`，它们共享同一个连接池。
 * 实现 `Resource`，支持 try-with-resources：
 *
 * ```cangjie
 * let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
 * try {
 *     let page = SearchApi.search(client, message: "Rust")
 * } finally {
 *     client.close()
 * }
 * ```
 */
public class ZlibClient <: Resource & ToString {
    private let http: HttpClient
    private let credentialValue: ZlibCredential
    private let configValue: ZlibClientConfig
    private let hostValue: ZlibHost
    private var closedFlag: Bool = false

    private init(http: HttpClient, credential: ZlibCredential, config: ZlibClientConfig,
        host: ZlibHost) {
        this.http = http
        this.credentialValue = credential
        this.configValue = config
        this.hostValue = host
    }

    /**
     * 用默认配置创建一个客户端。
     *
     * @param baseUrl 站点根地址（可带 `/eapi`，内部会规范化）；不知道哪个域名可用时
     *                先调 `resolveZlibHost()` 探测
     * @param credential 初始凭证；默认游客
     * @param config 连接配置
     */
    public static func create(baseUrl!: String = ZlibHost.DEFAULT_URL,
        credential!: ZlibCredential = ZlibCredential.anonymous(),
        config!: ZlibClientConfig = ZlibClientConfig()): ZlibClient {
        let builder = HttpClientBuilder()
            .userAgent(config.userAgent)
            .followRedirects(config.followRedirects)
            .cookies(true)
            .readTimeout(config.readTimeout)
            .totalTimeout(config.totalTimeout)
            .maxConnectionsPerHost(config.maxConnectionsPerHost)
        if (!config.httpsProxy.isEmpty()) {
            builder.httpsProxy(config.httpsProxy)
        }
        if (!config.httpProxy.isEmpty()) {
            builder.httpProxy(config.httpProxy)
        }
        ZlibClient(builder.build(), credential, config, ZlibHost.of(baseUrl))
    }

    /**
     * 用外部已有的 `HttpClient` 创建（共享调用方的连接池/代理/日志策略）。
     *
     * 生命周期仍由 `ZlibClient.close()` 负责关闭。
     */
    public static func fromHttpClient(http: HttpClient,
        baseUrl!: String = ZlibHost.DEFAULT_URL,
        credential!: ZlibCredential = ZlibCredential.anonymous(),
        config!: ZlibClientConfig = ZlibClientConfig()): ZlibClient {
        ZlibClient(http, credential, config, ZlibHost.of(baseUrl))
    }

    /** 当前凭证。 */
    public prop credential: ZlibCredential {
        get() {
            credentialValue
        }
    }

    /** 当前配置。 */
    public prop config: ZlibClientConfig {
        get() {
            configValue
        }
    }

    /** 当前站点。 */
    public prop host: ZlibHost {
        get() {
            hostValue
        }
    }

    /** 当前站点根地址（不带尾部 `/`）。 */
    public prop baseUrl: String {
        get() {
            hostValue.url
        }
    }

    /** eapi 根地址（`<站点>/eapi`）。 */
    public prop eapiUrl: String {
        get() {
            hostValue.eapi
        }
    }

    /** 是否已关闭（`Resource` 要求的是方法而不是属性）。 */
    public func isClosed(): Bool {
        closedFlag
    }

    /**
     * 用新凭证派生客户端，共享同一个连接池与 Cookie 存储。
     *
     * 场景：同一进程里既有游客请求又有登录请求，前者不该带上 remix 凭证
     * （会影响推荐/搜索结果的个性化），派生就能干净隔离。
     */
    public func withCredential(value: ZlibCredential): ZlibClient {
        ZlibClient(http, value, configValue, hostValue)
    }

    /** 用新站点地址派生客户端（域名失效时换镜像），共享连接池。 */
    public func withBaseUrl(url: String): ZlibClient {
        ZlibClient(http, credentialValue, configValue, ZlibHost.of(url))
    }

    /** 用新的 `ZlibHost` 派生客户端。 */
    public func withHost(value: ZlibHost): ZlibClient {
        ZlibClient(http, credentialValue, configValue, value)
    }

    /**
     * 从底层 Cookie 存储重新组装凭证。
     *
     * 登录接口既会在响应体里返回 `user`，也会通过 `Set-Cookie` 下发
     * `remix_userid` / `remix_userkey`。后者被 `HttpClient` 的 Cookie 存储收下，
     * 但客户端持有的凭证是不可变值、不会自动更新；本方法把存储里的值捞出来，
     * 供 `withCredential` 派生登录态客户端，避免「登录成功但后续仍游客态」。
     */
    public func credentialFromCookies(): ZlibCredential {
        let store = match (http.cookies()) {
            case Some(value) => value
            case None => return credentialValue
        }
        var userId = ""
        var userKey = ""
        var language = ""
        for (cookie in store.all()) {
            match (cookie.name) {
                case "remix_userid" => userId = cookie.value
                case "remix_userkey" => userKey = cookie.value
                case "siteLanguageV2" => language = cookie.value
                case "siteLanguage" => if (language.isEmpty()) {
                    language = cookie.value
                }
                case _ => ()
            }
        }
        if (userId.isEmpty() && userKey.isEmpty()) {
            return credentialValue
        }
        ZlibCredential(
            userId: if (!userId.isEmpty()) {
                userId
            } else {
                credentialValue.userId
            },
            userKey: if (!userKey.isEmpty()) {
                userKey
            } else {
                credentialValue.userKey
            },
            siteLanguage: if (!language.isEmpty()) {
                language
            } else {
                credentialValue.siteLanguage
            })
    }

    // ---------- 请求 ----------

    /** 拼出完整 eapi 地址（`path` 可以带或不带前导 `/`）。 */
    public func apiUrl(path: String): String {
        if (path.startsWith("/")) {
            "${eapiUrl}${path}"
        } else {
            "${eapiUrl}/${path}"
        }
    }

    /** GET 并返回响应体文本（不解包信封）。 */
    public func getRaw(path: String,
        query!: Array<(String, String)> = Array<(String, String)>()): String {
        ensureOpen()
        let url = withQuery(apiUrl(path), query)
        let response = http.get(url, headers: requestHeaders(), timeouts: None)
        response.text()
    }

    /** POST 表单并返回响应体文本（eapi 的写操作都是 urlencoded 表单）。 */
    public func postFormRaw(path: String, form: Array<(String, String)>): String {
        ensureOpen()
        let response = http.post(apiUrl(path), Body.form(form),
            headers: requestHeaders(hasBody: true))
        response.text()
    }

    /** GET 并解析信封（调用方自己决定怎么处理 `success`）。 */
    public func getEnvelope(path: String,
        query!: Array<(String, String)> = Array<(String, String)>()): ZlibEnvelope {
        ZlibEnvelope.parse(getRaw(path, query: query), path: path)
    }

    /** POST 表单并解析信封。 */
    public func postFormEnvelope(path: String,
        form: Array<(String, String)>): ZlibEnvelope {
        ZlibEnvelope.parse(postFormRaw(path, form), path: path)
    }

    /**
     * GET 并解出根上某个对象字段的强类型值（如图书详情里的 `book`、登录的 `user`）。
     *
     * 用「解码函数」而不是泛型静态接口调用：仓颉当前不支持对泛型形参做静态
     * 接口成员分派，传 `{ obj => BookInfo.fromJsonObject(obj) }` 既类型安全又零反射。
     */
    public func getObject<T>(path: String, field: String, decoder: (JsonObject) -> T,
        query!: Array<(String, String)> = Array<(String, String)>()): T {
        let root = getEnvelope(path, query: query).unwrap(path: path)
        match (objectFieldOf(root, field)) {
            case Some(obj) => decoder(obj)
            case None => throw ZlibError.badResponse(path, "响应缺少 ${field} 对象")
        }
    }

    /** GET 并解出根上某个数组字段的强类型列表。 */
    public func getObjects<T>(path: String, field: String, decoder: (JsonObject) -> T,
        query!: Array<(String, String)> = Array<(String, String)>()): ArrayList<T> {
        let root = getEnvelope(path, query: query).unwrap(path: path)
        decodeEach<T>(arrayFieldOf(root, field)) { obj => decoder(obj) }
    }

    /** POST 表单并解出根上某个对象字段的强类型值（登录接口用）。 */
    public func postFormObject<T>(path: String, field: String, form: Array<(String, String)>,
        decoder: (JsonObject) -> T): T {
        let root = postFormEnvelope(path, form).unwrap(path: path)
        match (objectFieldOf(root, field)) {
            case Some(obj) => decoder(obj)
            case None => throw ZlibError.badResponse(path, "响应缺少 ${field} 对象")
        }
    }

    // ---------- 二进制 ----------

    /**
     * 下载一个绝对 URL 到本地文件。
     *
     * 与 API 请求共享连接池，但使用独立的请求头（不带 remix 凭证：
     * 下载链接是签名过的绝对地址，凭据对文件域名没有意义，还可能触发跨域校验）。
     *
     * @param overwrite `false` 时若目标已存在会自动改名（`file(1).ext`）
     * @return 写入的字节数
     */
    public func download(url: String, path: Path, overwrite!: Bool = false): Int64 {
        ensureOpen()
        let response = http.get(url, headers: fileHeaders())
        if (!response.ok) {
            let preview = truncateBytesSafe(response.text(), 200, suffix: "")
            throw ZlibError.httpStatus(url, response.status, preview)
        }
        response.saveTo(path, overwrite: overwrite)
    }

    /** 取一个绝对 URL 的字节内容（封面图等）。 */
    public func fetchBytes(url: String): Array<Byte> {
        ensureOpen()
        let response = http.get(url, headers: fileHeaders())
        if (!response.ok) {
            let preview = truncateBytesSafe(response.text(), 200, suffix: "")
            throw ZlibError.httpStatus(url, response.status, preview)
        }
        response.bytes()
    }

    // ---------- 内部工具 ----------

    private func ensureOpen(): Unit {
        if (closedFlag) {
            throw ZlibError.closed()
        }
    }

    /**
     * 组装 API 请求头。
     *
     * `Accept` 用 `application/json` 是因为 eapi 的响应就是 JSON；部分镜像会按
     * `Accept` 返回 HTML 登录页，缺这个头会让「明明接口可用」的请求变成非 JSON 错误。
     */
    private func requestHeaders(hasBody!: Bool = false): Headers {
        let headers = Headers()
        headers.set("User-Agent", configValue.userAgent)
        headers.set("Accept", "application/json, text/plain, */*")
        headers.set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        headers.set("Referer", hostValue.origin)
        headers.set("Origin", hostValue.url)
        if (hasBody) {
            headers.set("Content-Type", "application/x-www-form-urlencoded")
        }
        headers.set("Cookie", credentialValue.toCookieHeader())
        for (pair in credentialValue.toRequestHeaders()) {
            headers.set(pair[0], pair[1])
        }
        headers
    }

    /** 下载/图片请求头：只带 UA 与 Referer，不带凭证。 */
    private func fileHeaders(): Headers {
        let headers = Headers()
        headers.set("User-Agent", configValue.userAgent)
        headers.set("Accept", "*/*")
        headers.set("Referer", hostValue.origin)
        headers
    }

    /** 关闭底层连接池。 */
    public func close(): Unit {
        if (closedFlag) {
            return
        }
        closedFlag = true
        http.close()
    }

    public func toString(): String {
        "ZlibClient(login=${credentialValue.isLoggedIn}, host=${hostValue.url}, closed=${closedFlag})"
    }
}

/**
 * 客户端可调配置。
 *
 * 与 `ZlibCredential` 分开：凭证是「我是谁」，配置是「怎么连」，
 * 两者的生命周期与敏感度都不同。
 */
public class ZlibClientConfig <: ToString {
    /** UA。默认用桌面版 Chrome：Z-Library 的后端对非常规 UA 更严格。 */
    public var userAgent: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    /** 单次读取超时。eapi 偶尔很慢（尤其是 search + 大 limit）。 */
    public var readTimeout: Duration = Duration.second * 30
    /** 整次请求（含重试）总超时。 */
    public var totalTimeout: Duration = Duration.second * 60
    /** 每 host 最大并发连接数。 */
    public var maxConnectionsPerHost: Int64 = 8
    /** 是否跟随重定向。默认跟随：镜像入口常有 3xx。 */
    public var followRedirects: Bool = true
    /** HTTP 代理；空串表示不使用。 */
    public var httpProxy: String = ""
    /** HTTPS 代理；空串表示不使用。 */
    public var httpsProxy: String = ""

    public init() {}

    public func copy(): ZlibClientConfig {
        let cloned = ZlibClientConfig()
        cloned.userAgent = userAgent
        cloned.readTimeout = readTimeout
        cloned.totalTimeout = totalTimeout
        cloned.maxConnectionsPerHost = maxConnectionsPerHost
        cloned.followRedirects = followRedirects
        cloned.httpProxy = httpProxy
        cloned.httpsProxy = httpsProxy
        cloned
    }

    public func toString(): String {
        "ZlibClientConfig(readTimeout=${readTimeout}, totalTimeout=${totalTimeout})"
    }
}
