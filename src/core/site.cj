package zlibraryAPI4CJ.core

import std.collection.*
import std.sync.*
import std.time.*
import stdx.encoding.json.*
import linderHttp.*

/**
 * 站点管理：**自定义站（优先）+ 种子站（兜底换站）**。
 *
 * Z-Library 的可用域名会轮换，写死一个地址的库迟早会失效。本类把两类地址
 * 分开管理：
 *
 * | 概念 | 来源 | 作用 |
 * | --- | --- | --- |
 * | **自定义站**（`customUrl`） | 调用方指定 | **所有请求优先用它** |
 * | **种子站**（`seed`） | 调用方指定的**单个**稳定引导站 | 自定义站失败时，向它查询最新域名（3xx `Location` 或域名列表） |
 *
 * 换站规则（由 `ZlibClient` 的自动重试触发）：
 *
 * 1. 请求打到当前自定义站；
 * 2. 失败且属于「换站可能有用」的错误（连不上 / 非 JSON 风控页 / 403）；
 * 3. `planSiteRefresh` 依次看：**当前站自己的 3xx `Location`** → 种子站的 3xx
 *    `Location` → 种子站本身（`fallbackToSeed` 时才允许）；
 * 4. 探到新地址后**覆盖自定义站**（`adopt`），下一次尝试立即生效。
 *
 * 域名列表接口（`fetchSeedDomains` / `extractDomainList` / `normalizeDomain`）
 * 仍保留为工具函数，但**不再参与**自动换站。
 *
 * 线程安全：`ZlibSites` 内部用 `Mutex` 保护地址状态，多个线程共享同一个
 * `ZlibClient` 并发请求时不会互相覆盖出脏地址。所有派生客户端
 * （`withCredential` / `withBaseUrl`）默认共享同一个 `ZlibSites` 实例，
 * 所以「一处换站，全局生效」。
 *
 * 注意：本类**只管理地址**，不发请求；探测与拉取由 `core/host.cj` 的
 * 函数完成，`ZlibClient` 负责把两者串起来。
 */
public class ZlibSites {
    private let mutex: Mutex = Mutex()
    /** 当前自定义站（换站后会被覆盖）。 */
    private var customUrlValue: String
    /** 种子站（单个引导站；空串表示未配置，自动换站不启用）。 */
    private var seedUrlValue: String
    /** 两次种子刷新之间的最小间隔，避免失败风暴时把种子站打爆。 */
    private let refreshIntervalValue: Duration
    /** 从种子站拿不到域名时，是否允许退而使用种子站本身。 */
    private let fallbackToSeedValue: Bool
    /** 上次刷新时间（Unix 毫秒，0 表示从未刷新）。 */
    private var lastRefreshAtValue: Int64 = 0
    /** 累计成功/尝试的刷新次数（便于日志与排查）。 */
    private var refreshCountValue: Int64 = 0

    /**
     * @param customUrl 初始自定义站（优先使用）
     * @param seed 种子站（单个引导站）；空表示不启用换站，只做同址重试
     * @param refreshInterval 两次种子刷新最小间隔（默认 30 秒）
     * @param fallbackToSeed 种子站拿不到域名时，是否允许直接用可达的种子站本身
     */
    public init(customUrl!: String,
        seed!: String = "",
        refreshInterval!: Duration = Duration.second * 30,
        fallbackToSeed!: Bool = true) {
        this.customUrlValue = ZlibHost.of(customUrl).url
        let seedText = seed.trimAscii()
        this.seedUrlValue = if (seedText.isEmpty()) {
            ""
        } else {
            ZlibHost.of(seedText).url
        }
        this.refreshIntervalValue = if (refreshInterval.toSeconds() < 0) {
            Duration.second * 30
        } else {
            refreshInterval
        }
        this.fallbackToSeedValue = fallbackToSeed
    }

    /** 当前使用的站点（每次请求前读取，换站后立即生效）。 */
    public func current(): ZlibHost {
        synchronized(mutex) {
            ZlibHost.of(customUrlValue)
        }
    }

    /** 当前自定义站地址（规范化后）。 */
    public func customUrl(): String {
        synchronized(mutex) {
            customUrlValue
        }
    }

    /** 种子站地址（规范化后；空串表示未配置）。 */
    public func seedUrl(): String {
        synchronized(mutex) {
            seedUrlValue
        }
    }

    /** 是否配置了种子站（没配置时自动换站无意义）。 */
    public func hasSeed(): Bool {
        synchronized(mutex) {
            !seedUrlValue.isEmpty()
        }
    }

    /** 刷新冷却间隔。 */
    public func refreshInterval(): Duration {
        refreshIntervalValue
    }

    /** 从种子站拿不到域名时是否退用种子站本身。 */
    public func fallbackToSeed(): Bool {
        fallbackToSeedValue
    }

    /** 上次刷新时间（Unix 毫秒，0 表示尚未刷新过）。 */
    public func lastRefreshAtMillis(): Int64 {
        synchronized(mutex) {
            lastRefreshAtValue
        }
    }

    /** 累计刷新尝试次数。 */
    public func refreshCount(): Int64 {
        synchronized(mutex) {
            refreshCountValue
        }
    }

    /**
     * 覆盖当前自定义站。
     *
     * 自动换站与手动切换都走这里；调用方也可在持久化后重启时用
     * `ZlibClient.createWithSites(...)` 恢复。
     */
    public func adopt(host: ZlibHost): Unit {
        synchronized(mutex) {
            customUrlValue = host.url
        }
    }

    /** 覆盖当前自定义站（字符串形式，内部会规范化）。 */
    public func adoptUrl(url: String): Unit {
        adopt(ZlibHost.of(url))
    }

    /** 手动指定自定义站（等价于 `adoptUrl`，语义更明确）。 */
    public func setCustomUrl(url: String): Unit {
        adoptUrl(url)
    }

    /** 手动替换种子站（空串表示关闭自动换站）。 */
    public func setSeedUrl(seed: String): Unit {
        let text = seed.trimAscii()
        let value = if (text.isEmpty()) {
            ""
        } else {
            ZlibHost.of(text).url
        }
        synchronized(mutex) {
            seedUrlValue = value
        }
    }

    /**
     * 申请一次刷新许可（带冷却窗口）。
     *
     * 为什么要冷却：一次请求失败会触发换站，而并发场景下「一批请求同时失败」
     * 很常见；如果每个失败都去查种子站，就等于对种子站发起 DDoS。
     * 返回 `false` 表示处于冷却期，本次不刷新（重试会直接用当前地址）。
     *
     * @param force 忽略冷却窗口（手动刷新用）
     */
    public func beginRefresh(force!: Bool = false): Bool {
        synchronized(mutex) {
            let now = nowMillis()
            let intervalMillis = refreshIntervalValue.toSeconds() * 1000
            if (force || lastRefreshAtValue == 0 || now - lastRefreshAtValue >= intervalMillis) {
                lastRefreshAtValue = now
                refreshCountValue++
                return true
            }
            false
        }
    }

    /** 当前站点状态的不可变快照（用于日志、持久化、诊断）。 */
    public func snapshot(): ZlibSiteSnapshot {
        synchronized(mutex) {
            ZlibSiteSnapshot(customUrlValue, seedUrlValue, lastRefreshAtValue,
                refreshCountValue, refreshIntervalValue.toSeconds(), fallbackToSeedValue)
        }
    }

    /**
     * 派生一个「换过自定义站」的副本：种子站与刷新策略沿用，刷新时间清零。
     *
     * `ZlibClient.withBaseUrl` 用它，保证「显式换站」不会污染原客户端。
     */
    public func withCustomUrl(url: String): ZlibSites {
        ZlibSites(customUrl: url, seed: seedUrl(),
            refreshInterval: refreshIntervalValue, fallbackToSeed: fallbackToSeedValue)
    }

    /** 派生一个「换过种子站」的副本。 */
    public func withSeed(seed: String): ZlibSites {
        ZlibSites(customUrl: customUrl(), seed: seed,
            refreshInterval: refreshIntervalValue, fallbackToSeed: fallbackToSeedValue)
    }

    public func toString(): String {
        synchronized(mutex) {
            "ZlibSites(custom=${customUrlValue}, seed=${seedUrlValue}, refreshCount=${refreshCountValue})"
        }
    }
}

/** `ZlibSites` 的不可变快照。 */
public class ZlibSiteSnapshot <: ToString {
    /** 当前自定义站（实际请求用的地址）。 */
    public let currentUrl: String
    /** 种子站（单个引导站；空串表示未配置）。 */
    public let seedUrl: String
    /** 上次刷新时间（Unix 毫秒，0 表示尚未刷新）。 */
    public let lastRefreshAtMillis: Int64
    /** 累计刷新尝试次数。 */
    public let refreshCount: Int64
    /** 刷新冷却间隔（秒）。 */
    public let refreshIntervalSeconds: Int64
    /** 是否允许退用种子站本身。 */
    public let fallbackToSeed: Bool

    public init(currentUrl: String, seedUrl: String, lastRefreshAtMillis: Int64,
        refreshCount: Int64, refreshIntervalSeconds: Int64, fallbackToSeed: Bool) {
        this.currentUrl = currentUrl
        this.seedUrl = seedUrl
        this.lastRefreshAtMillis = lastRefreshAtMillis
        this.refreshCount = refreshCount
        this.refreshIntervalSeconds = refreshIntervalSeconds
        this.fallbackToSeed = fallbackToSeed
    }

    public func toString(): String {
        "ZlibSiteSnapshot(current=${currentUrl}, seed=${seedUrl}, refreshCount=${refreshCount})"
    }
}

// ---------------------------------------------------------------------------
// 换站计划（纯逻辑，网络能力由回调注入，便于离线单测）
// ---------------------------------------------------------------------------

/**
 * 计算「该换到哪个站」。
 *
 * 与产品约定一致，按顺序：
 * 1. 当前站请求失败后，先探测**当前站本身**是不是 3xx 跳转
 *    （客户端默认跟随重定向，看到的往往不是 302 而是跳转后的 HTML，
 *    所以这里要用不跟随重定向的探测）；是 → 用响应头 `Location` 作为新站；
 * 2. 当前站不是跳转（真失败）→ 退回**种子站**，同样探测它的 3xx `Location`；
 * 3. 种子站也失败 → 返回 `None`，由调用方抛错。
 *
 * @param currentUrl 当前站（请求失败的那个）
 * @param seed 种子站（空 = 未配置）
 * @param probe 站点探测（不跟随重定向；生产实现是 `probeSite`）
 * @param fallbackToSeed 种子站可达但没有跳转时，是否直接用种子站本身
 */
public func planSiteRefresh(currentUrl: String, seed: String,
    probe: (String) -> ZlibProbe,
    fallbackToSeed: Bool): ?ZlibHost {
    // 1) 当前站是跳转入口 → 用它的 Location
    let currentProbe = probe(currentUrl)
    if (currentProbe.isRedirect && !currentProbe.location.isEmpty()) {
        return Some(ZlibHost.of(currentProbe.location))
    }
    // 2) 当前站不是跳转 → 退到种子站
    let seedText = seed.trimAscii()
    if (seedText.isEmpty()) {
        return None
    }
    let seedHost = match (tryHostOf(seedText)) {
        case Some(value) => value
        case None => return None
    }
    let seedProbe = probe(seedHost.url)
    if (seedProbe.isRedirect && !seedProbe.location.isEmpty()) {
        return Some(ZlibHost.of(seedProbe.location))
    }
    // 3) 种子站可达但没有跳转：允许兜底就直接用它，否则失败（由调用方抛错）
    if (fallbackToSeed && isReachableStatus(seedProbe)) {
        return Some(seedHost)
    }
    None
}

/** 200（正常）与 503（维护页）都视为站点可达。 */
internal func isReachableStatus(result: ZlibProbe): Bool {
    result.status == 200 || result.status == 503
}

/**
 * 把「域名列表里的一项」规范成 `ZlibHost`。
 *
 * 真实返回可能是裸域名（`z-library.sk`）、带协议（`https://z-library.sk`）、
 * 带路径（`https://z-library.sk/book/...`）或根相对路径（`/login`，
 * 相对种子站解析）。无法解析时返回 `None` 而不是抛异常。
 */
public func normalizeDomain(raw: String, seed!: String = ""): ?ZlibHost {
    var text = raw.trimAscii()
    if (text.isEmpty()) {
        return None
    }
    if (text.startsWith("//")) {
        // 协议相对地址（//host/path）先补协议，否则会被下面的根相对分支误判
        text = "https:${text}"
    } else if (text.startsWith("/")) {
        if (seed.trimAscii().isEmpty()) {
            return None
        }
        text = "${originOf(ZlibHost.of(seed).url)}${text}"
    }
    if (!text.startsWith("http://") && !text.startsWith("https://")) {
        text = "https://${text}"
    }
    // 域名列表可能带路径/查询串，只保留 scheme://host[:port]
    text = originOf(text)
    try {
        Some(ZlibHost.of(text))
    } catch (_: Exception) {
        None
    }
}

/**
 * 从 `/eapi/info/domains` 的响应根对象里宽松提取域名列表。
 *
 * 该接口没有官方文档，常见形状都被覆盖：
 *
 * - `{"success":1,"domains":["a.com","b.com"]}`
 * - `{"domains":[{"domain":"a.com"},{"url":"https://b.com/x"}]}`
 * - `{"domains":{"a.com":{...},"b.com":{...}}}`（map 形态，用 key 当域名）
 * - `{"domains":"a.com,b.com"}`
 *
 * 提取结果保持出现顺序（种子站列表本身有优先级），并去重。
 */
public func extractDomainList(root: JsonObject): Array<String> {
    let raw = ArrayList<String>()
    let knownKeys = ["domains", "list", "items", "urls", "sites", "data"]
    var found = false
    for (key in knownKeys) {
        match (root.get(key)) {
            case Some(value) =>
                collectDomains(value, raw, 0)
                found = true
            case None => ()
        }
    }
    for (key in ["domain", "url", "host", "site"]) {
        match (root.get(key)) {
            case Some(value) =>
                collectDomains(value, raw, 0)
                found = true
            case None => ()
        }
    }
    if (!found) {
        // 未知形状：把「key 像域名」的字段当域名，其余值继续向下找
        for ((key, value) in root.getFields()) {
            let name = key.trimAscii()
            if (looksLikeDomain(name)) {
                raw.add(name)
            } else if (name != "success" && name != "error" && name != "msg" &&
                name != "pagination") {
                collectDomains(value, raw, 0)
            }
        }
    }
    dedupeDomains(raw)
}

/** 递归收集候选域名（深度上限 3，避免异常结构导致无限递归）。 */
private func collectDomains(value: JsonValue, result: ArrayList<String>, depth: Int64): Unit {
    if (depth > 3) {
        return
    }
    match (value.kind()) {
        case JsString => addDomainText(value.asString().getValue(), result)
        case JsArray =>
            for (item in value.asArray().getItems()) {
                collectDomains(item, result, depth + 1)
            }
        case JsObject =>
            let obj = value.asObject()
            for (key in ["domains", "list", "items", "urls", "sites", "data", "domain", "url",
                "host", "link", "site"]) {
                match (obj.get(key)) {
                    case Some(inner) => collectDomains(inner, result, depth + 1)
                    case None => ()
                }
            }
            // map 形态：{"a.com": {...}} —— key 自身就是域名
            for ((key, inner) in obj.getFields()) {
                if (looksLikeDomain(key.trimAscii())) {
                    result.add(key.trimAscii())
                } else {
                    match (inner.kind()) {
                        case JsObject => collectDomains(inner, result, depth + 1)
                        case _ => ()
                    }
                }
            }
        case _ => ()
    }
}

/** 字符串可能是逗号/分号/空白分隔的多个域名，逐个拆开。 */
private func addDomainText(text: String, result: ArrayList<String>): Unit {
    let normalized = text.replace(",", " ").replace(";", " ").replace("\r", " ").replace("\n", " ").replace("\t", " ")
    for (part in normalized.split(" ")) {
        let item = part.trimAscii()
        if (!item.isEmpty()) {
            result.add(item)
        }
    }
}

/** 粗判一个字符串是否像站点地址（含协议或以点分隔的域名）。 */
private func looksLikeDomain(text: String): Bool {
    if (text.isEmpty() || text.contains(" ")) {
        return false
    }
    if (text.startsWith("http://") || text.startsWith("https://") || text.startsWith("//")) {
        return true
    }
    text.contains(".") && !text.contains("/")
}

/** 保序去重，并过滤掉不像地址的噪声（例如响应里的名称/语言字符串）。 */
private func dedupeDomains(items: ArrayList<String>): Array<String> {
    let seen = HashSet<String>()
    let result = ArrayList<String>()
    for (item in items) {
        let text = item.trimAscii()
        if (text.isEmpty() || !looksLikeDomain(text)) {
            continue
        }
        if (seen.contains(text)) {
            continue
        }
        seen.add(text)
        result.add(text)
    }
    result.toArray()
}

// ---------------------------------------------------------------------------
// 网络实现：从种子站拉域名列表（失败返回空数组，由上层回退）
// ---------------------------------------------------------------------------

/**
 * 向种子站请求 `GET /eapi/info/domains` 并提取域名列表。
 *
 * 失败（连不上、非 JSON、没有域名）一律返回空数组：换站流程会继续尝试
 * 「3xx Location」与「种子站自身可用」两条兜底路径，不该因为查询失败就整体失败。
 *
 * 这里刻意不复用 `ZlibClient`：`ZlibClient` 的请求层带自动重试/换站，
 * 换站过程中再调它会形成递归。本函数用一次性短超时客户端，只发一次请求。
 */
public func fetchSeedDomains(seedUrl: String): Array<String> {
    let host = match (tryHostOf(seedUrl)) {
        case Some(value) => value
        case None => return Array<String>()
    }
    let client = HttpClientBuilder()
        .readTimeout(Duration.second * 8)
        .totalTimeout(Duration.second * 12)
        .followRedirects(true)
        .cookies(false)
        .build()
    var body = ""
    try {
        let headers = Headers()
        headers.set("User-Agent", seedUserAgent())
        headers.set("Accept", "application/json, text/plain, */*")
        headers.set("Referer", host.origin)
        let response = client.get("${host.eapi}/info/domains", headers: headers)
        if (response.ok) {
            body = response.text()
        }
    } catch (_: Exception) {
        body = ""
    }
    client.close()
    if (body.trimAscii().isEmpty()) {
        return Array<String>()
    }
    let root = match (tryParseObject(body)) {
        case Some(value) => value
        case None => return Array<String>()
    }
    extractDomainList(root)
}

/** 种子站请求用的 UA（与客户端默认 UA 保持一致，避免被当成爬虫）。 */
private func seedUserAgent(): String {
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

private func tryHostOf(url: String): ?ZlibHost {
    try {
        Some(ZlibHost.of(url))
    } catch (_: Exception) {
        None
    }
}

private func tryParseObject(text: String): ?JsonObject {
    try {
        Some(parseJsonObject(text, path: "/info/domains"))
    } catch (_: Exception) {
        None
    }
}

/** 当前 Unix 毫秒时间戳（冷却窗口计算用）。 */
internal func nowMillis(): Int64 {
    DateTime.now().toUnixTimeStamp().toSeconds() * 1000
}

/**
 * 该错误是否值得「换站后重试」。
 *
 * 只有「域名层面可能有问题」的错误才换站：
 *
 * | 类别 | 换站 | 理由 |
 * | --- | --- | --- |
 * | `Transport` | ✅ | 连不上：域名失效/被墙/DNS 污染，换站最有效 |
 * | `BadResponse` | ✅ | 返回了 HTML 风控页/登录页，通常也是域名被针对性拦截 |
 * | `Forbidden` | ✅ | 403：镜像拒绝服务或需要个人域名 |
 * | `ApiFailure` | ❌ | 服务端已明确业务失败（如书不存在），换站无用 |
 * | `NotLoggedIn` | ❌ | 凭证问题，换站无用 |
 * | `NotFound` | ❌ | 资源不存在，换站无用 |
 * | `Closed` | ❌ | 客户端已关闭，换站无用 |
 */
internal func shouldSwitchSite(kind: ZlibErrorKind): Bool {
    match (kind) {
        case BadResponse => return true
        case Forbidden => return true
        case ApiFailure => return false
        case NotLoggedIn => return false
        case NotFound => return false
        case Closed => return false
        case Cangjie => return false
    }
}