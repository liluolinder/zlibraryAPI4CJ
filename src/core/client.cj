package zlibraryAPI4CJ.core

import std.collection.*
import std.fs.*
import stdx.encoding.json.*
import linderHttp.*

/**
 * Z-Library eapi 客户端。
 *
 * 把五件与业务无关、但每个接口都必须正确的事收敛到一处：
 *
 * 1. **连接**：内部只持有一个 LinderHttp `HttpClient`，连接池与 Cookie 存储共享，
 *    所以应当在进程内复用一个实例，而不是每次请求新建（那样每次都要重新 TLS 握手）；
 * 2. **身份**：凭证既写 Cookie（`remix_userid` / `remix_userkey` / `siteLanguageV2`）
 *    也写请求头（`remix-userid` / `remix-userkey`），兼容不同版本的服务端；
 * 3. **信封解包**：`{"success":1,...}` / `{"success":0,"error":"..."}` 统一解析，
 *    失败抛 `ZlibError`，子包只需要关心业务字段；
 * 4. **站点管理**：自定义站优先 + 种子站兜底换站（详见 `ZlibSites`）；
 * 5. **自动重试**：请求失败且「换站可能有用」时，先向种子站换到新地址再重试，
 *    新地址会覆盖自定义站，后续请求立即生效。
 *
 * ## 站点与重试的协作方式
 *
 * ```
 * 业务 API
 *   └─ client.getObject / getEnvelope / getRaw …
 *        └─ execute(operation)                     ← 自动重试外壳
 *             ├─ 第 1 次：sites.current()（自定义站）
 *             ├─ 失败（Transport / BadResponse / Forbidden）
 *             │    └─ refreshSite()：种子站 -> 新地址 -> adopt（覆盖自定义站）
 *             └─ 第 2..N 次：用新地址重试
 * ```
 *
 * 重试只在「换站有意义」的错误上做：域名失效、被墙、非 JSON 风控页、403。
 * 业务错误（未登录、书不存在、`success=0`）**不会**重试，避免重复消耗
 * 下载配额或制造无意义的请求。
 *
 * 客户端对「凭证 / 显式站点」仍保持不可变语义：
 * `withCredential` / `withBaseUrl` 派生新客户端并共享连接池；
 * 但 `ZlibSites` 内部的地址是受控可变的——自动换站是运行期行为，
 * 这样一次换站后所有共享该 `ZlibSites` 的客户端都会立即生效。
 *
 * 实现 `Resource`，支持 try-with-resources：
 *
 * ```cangjie
 * let client = ZlibClient.create(baseUrl: "https://your-zlib-domain",
 *     seeds: ["https://seed-domain"])
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
    private let sitesValue: ZlibSites
    private var closedFlag: Bool = false

    private init(http: HttpClient, credential: ZlibCredential, config: ZlibClientConfig,
        sites: ZlibSites) {
        this.http = http
        this.credentialValue = credential
        this.configValue = config
        this.sitesValue = sites
        // 启动时就把凭证写进 Cookie 存储，否则第一次请求之后会被 LinderHttp 的
        // Cookie 存储覆盖掉手写的 Cookie 头（见 seedCredentialCookies 注释）。
        seedCredentialCookies()
    }

    /**
     * 把凭证预置进 LinderHttp 的 Cookie 存储。
     *
     * 为什么必须做：LinderHttp 在 Cookie 存储**非空**时，会用存储内容覆盖调用方
     * 手写的 `Cookie` 头（`mergeHeaders` 里最后一步）。启动时只靠手写 Cookie 的话：
     * 第一次请求能通过（存储为空），但服务端会下发 `Set-Cookie`（实测
     * `bsrv=...; path=/`），第二次请求的 Cookie 头就只剩存储内容，
     * `remix_userid` / `remix_userkey` 丢失 → 后端按游客处理（bbapi 曾出现
     * 同类「传了凭证但没实际加载」的问题）。
     *
     * 预置进存储后，存储拼出的 Cookie 始终包含凭证，服务端下发的 Cookie 也会叠加。
     */
    private func seedCredentialCookies(): Unit {
        if (!credentialValue.isLoggedIn) {
            return
        }
        match (http.cookies()) {
            case Some(store) =>
                let headers = ArrayList<String>()
                headers.add("remix_userid=${credentialValue.userId}; Path=/; Max-Age=31536000")
                headers.add("remix_userkey=${credentialValue.userKey}; Path=/; Max-Age=31536000")
                headers.add("siteLanguage=${credentialValue.siteLanguage}; Path=/; Max-Age=31536000")
                headers.add("siteLanguageV2=${credentialValue.siteLanguage}; Path=/; Max-Age=31536000")
                store.store(sitesValue.current().url, headers.toArray())
            case None => ()
        }
    }

    /**
     * 确保**当前站点**的 Cookie 存储里有凭证；没有就补种（换站后域名会变）。
     *
     * 在每次请求尝试前调用，开销是「一次 headerFor + 最多一次 store」。
     */
    private func ensureCredentialCookies(): Unit {
        if (!credentialValue.isLoggedIn) {
            return
        }
        match (http.cookies()) {
            case Some(store) =>
                let hasCredential = match (store.headerFor("${sitesValue.current().url}/eapi/")) {
                    case Some(line) => line.contains("remix_userid=")
                    case None => false
                }
                if (!hasCredential) {
                    seedCredentialCookies()
                }
            case None => ()
        }
    }

    /**
     * 用默认配置创建一个客户端。
     *
     * @param baseUrl 自定义站（**优先使用**；可带 `/eapi`，内部会规范化）
     * @param credential 初始凭证；默认游客
     * @param config 连接与重试配置
     * @param seeds 种子站列表：自定义站失败时用它换新地址；空表示只做同址重试
     */
    public static func create(baseUrl!: String = ZlibHost.DEFAULT_URL,
        credential!: ZlibCredential = ZlibCredential.anonymous(),
        config!: ZlibClientConfig = ZlibClientConfig(),
        seeds!: Array<String> = Array<String>()): ZlibClient {
        createWithSites(ZlibSites(customUrl: baseUrl, seeds: seeds), credential: credential,
            config: config)
    }

    /**
     * 用现成的 `ZlibSites` 创建客户端。
     *
     * 适合需要共享/持久化站点状态的场景：把同一个 `ZlibSites` 交给多个客户端，
     * 任何一处换站都会立即被所有客户端看到。
     */
    public static func createWithSites(sites: ZlibSites,
        credential!: ZlibCredential = ZlibCredential.anonymous(),
        config!: ZlibClientConfig = ZlibClientConfig()): ZlibClient {
        ZlibClient(buildHttpClient(config), credential, config, sites)
    }

    /**
     * 用外部已有的 `HttpClient` 创建（共享调用方的连接池/代理/日志策略）。
     *
     * 生命周期仍由 `ZlibClient.close()` 负责关闭。
     */
    public static func fromHttpClient(http: HttpClient,
        baseUrl!: String = ZlibHost.DEFAULT_URL,
        credential!: ZlibCredential = ZlibCredential.anonymous(),
        config!: ZlibClientConfig = ZlibClientConfig(),
        seeds!: Array<String> = Array<String>()): ZlibClient {
        ZlibClient(http, credential, config, ZlibSites(customUrl: baseUrl, seeds: seeds))
    }

    /** 用外部 `HttpClient` + 现成 `ZlibSites` 创建。 */
    public static func fromHttpClientWithSites(http: HttpClient, sites: ZlibSites,
        credential!: ZlibCredential = ZlibCredential.anonymous(),
        config!: ZlibClientConfig = ZlibClientConfig()): ZlibClient {
        ZlibClient(http, credential, config, sites)
    }

    private static func buildHttpClient(config: ZlibClientConfig): HttpClient {
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
        // 统一异常类型：构造 HttpClient 失败也包成 ZlibError
        try {
            builder.build()
        } catch (err: ZlibError) {
            throw err
        } catch (err: Exception) {
            throw ZlibError.wrapUnhandled("", err)
        }
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

    /** 站点管理器（自定义站 + 种子站 + 刷新状态）。 */
    public prop sites: ZlibSites {
        get() {
            sitesValue
        }
    }

    /** 当前站点（自动换站后是最新地址）。 */
    public prop host: ZlibHost {
        get() {
            sitesValue.current()
        }
    }

    /** 当前自定义站地址（不带尾部 `/`）。 */
    public prop baseUrl: String {
        get() {
            sitesValue.current().url
        }
    }

    /** eapi 根地址（`<当前站点>/eapi`）。 */
    public prop eapiUrl: String {
        get() {
            sitesValue.current().eapi
        }
    }

    /** 是否已关闭（`Resource` 要求的是方法而不是属性）。 */
    public func isClosed(): Bool {
        closedFlag
    }

    /**
     * 用新凭证派生客户端，共享同一个连接池、Cookie 存储与站点管理器。
     *
     * 场景：同一进程里既有游客请求又有登录请求，前者不该带上 remix 凭证
     * （会影响推荐/搜索结果的个性化），派生就能干净隔离。
     */
    public func withCredential(value: ZlibCredential): ZlibClient {
        ZlibClient(http, value, configValue, sitesValue)
    }

    /**
     * 显式换站：用新地址派生客户端。
     *
     * 与两处行为相关：
     * - 派生出的客户端使用**新的** `ZlibSites`（种子站与刷新策略沿用），
     *   原客户端的地址不受影响；
     * - 若想让「自动换到的新地址」对原客户端也生效，直接用
     *   `client.setCustomSite(url)` 或 `client.sites.adopt(...)`。
     */
    public func withBaseUrl(url: String): ZlibClient {
        ZlibClient(http, credentialValue, configValue, sitesValue.withCustomUrl(url))
    }

    /** 用新的 `ZlibHost` 显式换站。 */
    public func withHost(value: ZlibHost): ZlibClient {
        withBaseUrl(value.url)
    }

    /** 替换站点管理器（种子站、冷却策略等整体替换）。 */
    public func withSites(value: ZlibSites): ZlibClient {
        ZlibClient(http, credentialValue, configValue, value)
    }

    /**
     * 手动覆盖当前自定义站（自动换站内部也走它）。
     *
     * 持久化场景：换站后把 `client.currentSiteUrl()` 存下来，下次启动
     * 作为 `create(baseUrl: ...)` 的入参。
     */
    public func setCustomSite(url: String): Unit {
        sitesValue.setCustomUrl(url)
    }

    /** 当前实际使用的站点地址。 */
    public func currentSiteUrl(): String {
        sitesValue.customUrl()
    }

    /**
     * 立即向种子站换一次地址（带冷却窗口，`force` 可跳过）。
     *
     * 自动重试内部也用它；返回值表示本轮是否真的换到了新地址。
     * 失败的诊断信息在 `client.sites.snapshot()` 里（刷新次数、上次时间）。
     */
    public func refreshSite(force!: Bool = false): Bool {
        ensureOpen()
        if (!sitesValue.hasSeeds()) {
            return false
        }
        if (!sitesValue.beginRefresh(force: force)) {
            return false
        }
        let refreshed = planSiteRefresh(sitesValue.seedUrls(),
            { seed => fetchSeedDomains(seed) },
            { url => probeSite(url, timeoutSeconds: 5) },
            sitesValue.fallbackToSeed())
        match (refreshed) {
            case Some(host) =>
                sitesValue.adopt(host)
                return true
            case None => return false
        }
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

    /** 拼出完整 eapi 地址（`path` 可以带或不带前导 `/`，站点取当前地址）。 */
    public func apiUrl(path: String): String {
        hostApiUrl(sitesValue.current(), path)
    }

    /** GET 并返回响应体文本（不解包信封，仍享受自动重试/换站）。 */
    public func getRaw(path: String,
        query!: Array<(String, String)> = Array<(String, String)>()): String {
        ensureOpen()
        execute<String>({ host => sendGet(host, path, query) }, refreshOnFailure: true,
            path: path)
    }

    /** POST 表单并返回响应体文本（eapi 的写操作都是 urlencoded 表单）。 */
    public func postFormRaw(path: String, form: Array<(String, String)>): String {
        ensureOpen()
        execute<String>({ host => sendPostForm(host, path, form) }, refreshOnFailure: true,
            path: path)
    }

    /** GET 并解析信封（调用方自己决定怎么处理 `success`）。 */
    public func getEnvelope(path: String,
        query!: Array<(String, String)> = Array<(String, String)>()): ZlibEnvelope {
        ensureOpen()
        execute<ZlibEnvelope>({ host =>
            ZlibEnvelope.parse(sendGet(host, path, query), path: path)
        }, refreshOnFailure: true, path: path)
    }

    /** POST 表单并解析信封。 */
    public func postFormEnvelope(path: String,
        form: Array<(String, String)>): ZlibEnvelope {
        ensureOpen()
        execute<ZlibEnvelope>({ host =>
            ZlibEnvelope.parse(sendPostForm(host, path, form), path: path)
        }, refreshOnFailure: true, path: path)
    }

    /**
     * GET 并解出根上某个对象字段的强类型值（如图书详情里的 `book`、登录的 `user`）。
     *
     * 用「解码函数」而不是泛型静态接口调用：仓颉当前不支持对泛型形参做静态
     * 接口成员分派，传 `{ obj => BookInfo.fromJsonObject(obj) }` 既类型安全又零反射。
     */
    public func getObject<T>(path: String, field: String, decoder: (JsonObject) -> T,
        query!: Array<(String, String)> = Array<(String, String)>()): T {
        ensureOpen()
        execute<T>({ host =>
            let root = ZlibEnvelope.parse(sendGet(host, path, query), path: path)
                .unwrap(path: path)
            match (objectFieldOf(root, field)) {
                case Some(obj) => decoder(obj)
                case None => throw ZlibError.badResponse(path, "响应缺少 ${field} 对象")
            }
        }, refreshOnFailure: true, path: path)
    }

    /** GET 并解出根上某个数组字段的强类型列表。 */
    public func getObjects<T>(path: String, field: String, decoder: (JsonObject) -> T,
        query!: Array<(String, String)> = Array<(String, String)>()): ArrayList<T> {
        ensureOpen()
        execute<ArrayList<T>>({ host =>
            let root = ZlibEnvelope.parse(sendGet(host, path, query), path: path)
                .unwrap(path: path)
            decodeEach<T>(arrayFieldOf(root, field)) { obj => decoder(obj) }
        }, refreshOnFailure: true, path: path)
    }

    /** POST 表单并解出根上某个对象字段的强类型值（登录接口用）。 */
    public func postFormObject<T>(path: String, field: String, form: Array<(String, String)>,
        decoder: (JsonObject) -> T): T {
        ensureOpen()
        execute<T>({ host =>
            let root = ZlibEnvelope.parse(sendPostForm(host, path, form), path: path)
                .unwrap(path: path)
            match (objectFieldOf(root, field)) {
                case Some(obj) => decoder(obj)
                case None => throw ZlibError.badResponse(path, "响应缺少 ${field} 对象")
            }
        }, refreshOnFailure: true, path: path)
    }

    // ---------- 二进制 ----------

    /**
     * 下载一个绝对 URL 到本地文件。
     *
     * 与 API 请求共享连接池，但使用独立的请求头（不带 remix 凭证：
     * 下载链接是签名过的绝对地址，凭据对文件域名没有意义，还可能触发跨域校验）。
     *
     * 下载**不触发换站**：下载链接指向账号的个人域名/CDN，换站点地址对它没有帮助；
     * 但传输层抖动仍会按 `maxAttempts` 重试同一链接。
     *
     * @param overwrite `false` 时若目标已存在会自动改名（`file(1).ext`）
     * @return 写入的字节数
     */
    public func download(url: String, path: Path, overwrite!: Bool = false): Int64 {
        ensureOpen()
        execute<Int64>({ host =>
            let response = http.get(url, headers: fileHeaders(host),
                timeouts: Timeouts(read: configValue.downloadTimeout,
                    write: configValue.downloadTimeout))
            if (!response.ok) {
                let preview = truncateBytesSafe(response.text(), 200, suffix: "")
                throw ZlibError.httpStatus(url, response.status, preview)
            }
            response.saveTo(path, overwrite: overwrite)
        }, refreshOnFailure: false, path: url)
    }

    /** 取一个绝对 URL 的字节内容（封面图等）。 */
    public func fetchBytes(url: String): Array<Byte> {
        ensureOpen()
        execute<Array<Byte>>({ host =>
            let response = http.get(url, headers: fileHeaders(host),
                timeouts: Timeouts(read: configValue.downloadTimeout,
                    write: configValue.downloadTimeout))
            if (!response.ok) {
                let preview = truncateBytesSafe(response.text(), 200, suffix: "")
                throw ZlibError.httpStatus(url, response.status, preview)
            }
            response.bytes()
        }, refreshOnFailure: false, path: url)
    }

    // ---------- 重试与站点刷新 ----------

    /** 一次请求最多尝试几次（含首次）。 */
    private func attemptLimit(): Int64 {
        if (!configValue.autoRetry || configValue.maxAttempts < 1) {
            return 1
        }
        configValue.maxAttempts
    }

    /**
     * 重试外壳：所有请求/解码都经过这里。
     *
     * 重试判断（内部细节，调用方不需要关心）：
     * - `ZlibError` 中可换站的类别（`Transport` / `BadResponse` / `Forbidden`）：
     *   先换站再重试；其它类别立即抛；
     * - `HttpError`（LinderHttp 传输层）与未包装的 stdx 异常：属于瞬时问题，
     *   按次数重试（并换站）；
     * - 文件系统异常（`FSException`）：本地问题，重试无意义，直接包成 `Io` 抛出。
     *
     * **对外统一异常类型**：全部尝试失败后，非 `ZlibError` 的原始异常会被
     * 包装成 `ZlibError`（原始异常保留在 `cause`），所以调用方只需要
     * `catch (err: ZlibError)` 一个分支。
     */
    internal func execute<T>(operation: (ZlibHost) -> T, refreshOnFailure!: Bool,
        path!: String = ""): T {
        let attempts = attemptLimit()
        var attempt: Int64 = 1
        var lastError: ?Exception = None
        while (attempt <= attempts) {
            let host = sitesValue.current()
            ensureCredentialCookies()
            try {
                return operation(host)
            } catch (err: ZlibError) {
                lastError = err
                if (!refreshOnFailure || !shouldSwitchSite(err.kind) || attempt >= attempts) {
                    throw err
                }
            } catch (err: HttpError) {
                lastError = err
                if (attempt >= attempts) {
                    break
                }
            } catch (err: Exception) {
                // 本地文件系统错误：重试没有意义，直接终止并归类为 Io
                if (err is FSException) {
                    throw ZlibError.wrapUnhandled(path, err)
                }
                // 兜底重试：LinderHttp 偶尔把底层 stdx 异常直接漏到外层
                // （实测 "read response timeout and the connection is closed"），
                // 这类本质仍是传输失败，按瞬时故障重试（并换站），
                // 否则一次网络抖动就会让业务调用直接失败。
                lastError = err
                if (attempt >= attempts) {
                    break
                }
            }
            attempt++
            if (refreshOnFailure && attempt <= attempts) {
                tryRefreshSite()
            }
        }
        let last = lastError.getOrThrow()
        match (last) {
            case known: ZlibError => throw known
            case other => throw ZlibError.wrapUnhandled(path, other)
        }
    }

    /** 失败后尝试换站（无种子站或处于冷却窗口时静默跳过）。 */
    private func tryRefreshSite(): Unit {
        if (!sitesValue.hasSeeds()) {
            return
        }
        let _ = refreshSite()
    }

    // ---------- 内部工具 ----------

    private func ensureOpen(): Unit {
        if (closedFlag) {
            throw ZlibError.closed()
        }
    }

    /** 当前站点 + eapi 路径 -> 完整 URL。 */
    private func hostApiUrl(host: ZlibHost, path: String): String {
        if (path.startsWith("/")) {
            "${host.eapi}${path}"
        } else {
            "${host.eapi}/${path}"
        }
    }

    /** 发一次 GET，返回响应体文本（不做重试，重试由 `execute` 负责）。 */
    private func sendGet(host: ZlibHost, path: String,
        query: Array<(String, String)>): String {
        let url = withQuery(hostApiUrl(host, path), query)
        let response = http.get(url, headers: requestHeaders(host), timeouts: None)
        response.text()
    }

    /** 发一次 POST 表单，返回响应体文本。 */
    private func sendPostForm(host: ZlibHost, path: String,
        form: Array<(String, String)>): String {
        let response = http.post(hostApiUrl(host, path), Body.form(form),
            headers: requestHeaders(host, hasBody: true))
        response.text()
    }

    /**
     * 组装 API 请求头。
     *
     * `Accept` 用 `application/json` 是因为 eapi 的响应就是 JSON；部分镜像会按
     * `Accept` 返回 HTML 登录页，缺这个头会让「明明接口可用」的请求变成非 JSON 错误。
     */
    private func requestHeaders(host: ZlibHost, hasBody!: Bool = false): Headers {
        let headers = Headers()
        headers.set("User-Agent", configValue.userAgent)
        headers.set("Accept", "application/json, text/plain, */*")
        headers.set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        headers.set("Referer", host.origin)
        headers.set("Origin", host.url)
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
    private func fileHeaders(host: ZlibHost): Headers {
        let headers = Headers()
        headers.set("User-Agent", configValue.userAgent)
        headers.set("Accept", "*/*")
        headers.set("Referer", host.origin)
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
        "ZlibClient(login=${credentialValue.isLoggedIn}, site=${sitesValue.customUrl()}, " +
            "closed=${closedFlag})"
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
    /** 是否开启请求自动重试（含失败换站）。默认开启。 */
    public var autoRetry: Bool = true
    /** 单次请求最多尝试次数（含首次）。默认 3；小于 1 时按 1 处理。 */
    public var maxAttempts: Int64 = 3
    /**
     * 下载 / 取字节的读写超时。默认 5 分钟。
     *
     * API 请求的 30 秒读超时对文件下载太短（实测下载链接响应慢时会
     * `read data timeout`），下载单独用更宽松的超时。
     */
    public var downloadTimeout: Duration = Duration.minute * 5

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
        cloned.autoRetry = autoRetry
        cloned.maxAttempts = maxAttempts
        cloned.downloadTimeout = downloadTimeout
        cloned
    }

    public func toString(): String {
        "ZlibClientConfig(readTimeout=${readTimeout}, totalTimeout=${totalTimeout}, " +
            "autoRetry=${autoRetry}, maxAttempts=${maxAttempts})"
    }
}
