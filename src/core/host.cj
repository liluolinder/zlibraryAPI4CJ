package zlibraryAPI4CJ.core

import std.collection.*
import linderHttp.*

/**
 * Z-Library 站点地址。
 *
 * Z-Library 没有长期稳定的官方域名：主站域名会被封、镜像会轮换，登录后
 * 账号还会被分配「个人域名」（官方 eapi 文档明确说明：下载必须使用
 * personal zlibrary domains）。所以站点点位必须是可配置的一等公民，
 * 而不是写死在常量里。
 *
 * 用法：
 * - 已知可用域名 → `ZlibClient.create(baseUrl: "https://xxx")`；
 * - 不知道哪个能用 → `resolveZlibHost()` 按 `ZLIB_MIRRORS` 逐个探测；
 * - 已探测到但运行中失效 → `client.withBaseUrl(newUrl)` 派生新客户端（共享连接池）。
 *
 * 注意：`ZlibHost` 只做地址规范化（去尾部 `/`、去误加的 `/eapi`），不发请求。
 */
public class ZlibHost <: ToString {
    /** 规范化后的站点根地址，保证不带尾部 `/`，也不带 `/eapi` 前缀。 */
    public let url: String

    private init(url: String) {
        this.url = url
    }

    /**
     * 默认站点地址。
     *
     * 这是老版本项目使用的第三方镜像。它**随时可能失效**，生产环境请显式传
     * `baseUrl` 或先用 `resolveZlibHost()` 探测。之所以不写成官方域名，
     * 是因为官方域名本身也在轮换，写死任何一个都会很快过期。
     */
    public static let DEFAULT_URL: String = "https://tw.jiaoyuan.ru"

    /**
     * 候选镜像列表，供 `resolveZlibHost()` 探测。
     *
     * 来源：官方 eapi 文档提到的可用域（`1lib.fr` / `singlelogin.me`）与
     * 社区客户端长期使用的域名。列表只是「候选」，不保证每个都可用；
     * 探测失败会自动跳到下一个。
     */
    public static let MIRRORS: Array<String> = [
        "https://tw.jiaoyuan.ru",
        "https://z-library.sk",
        "https://zh.z-library.sk",
        "https://1lib.sk",
        "https://z-lib.gs",
        "https://z-lib.fm",
        "https://singlelogin.re"
    ]

    /**
     * 规范化一个站点地址。
     *
     * - 去掉首尾空白与尾部 `/`；
     * - 去掉误加的 `/eapi`（用户常把接口地址整条贴进来）；
     * - 空串直接抛 `ZlibError`，避免后续请求打到 `/eapi/eapi`。
     */
    public static func of(url: String): ZlibHost {
        var value = url.trimAscii()
        while (value.size > 0 && value[(value.size - 1)..value.size] == "/") {
            value = value[0..(value.size - 1)]
        }
        if (value.size >= 5 && value[(value.size - 5)..value.size] == ZLIB_API_PREFIX) {
            value = value[0..(value.size - 5)]
        }
        while (value.size > 0 && value[(value.size - 1)..value.size] == "/") {
            value = value[0..(value.size - 1)]
        }
        if (value.isEmpty()) {
            throw ZlibError(ZlibErrorKind.BadResponse, "站点地址不能为空")
        }
        ZlibHost(value)
    }

    /** eapi 根地址（`<站点>/eapi`）。 */
    public prop eapi: String {
        get() {
            "${url}${ZLIB_API_PREFIX}"
        }
    }

    /** 是否是形如 `https://host` 的地址。 */
    public prop isValid: Bool {
        get() {
            url.startsWith("https://") || url.startsWith("http://")
        }
    }

    /** 站点主页地址（带尾部 `/`），用于拼 `Referer`。 */
    public prop origin: String {
        get() {
            "${url}/"
        }
    }

    public func toString(): String {
        url
    }
}

/** 站点可达性探测结果。 */
public class ZlibProbe <: ToString {
    /** 被探测的地址。 */
    public let url: String
    /** HTTP 状态码；0 表示连接失败（DNS/超时/TLS）。 */
    public let status: UInt16
    /** 3xx 重定向目标（已按需补全为绝对地址）；无重定向为空串。 */
    public let location: String

    public init(url: String, status: UInt16, location: String) {
        this.url = url
        this.status = status
        this.location = location
    }

    /** 是否可达：200/503（站点维护页）或有重定向都算。 */
    public prop reachable: Bool {
        get() {
            isRedirect || status == 200 || status == 503
        }
    }

    /** 是否是 3xx 重定向。 */
    public prop isRedirect: Bool {
        get() {
            status >= 300 && status < 400
        }
    }

    public func toString(): String {
        "ZlibProbe(${url} -> ${status}, location=${location})"
    }
}

/**
 * 探测单个地址。
 *
 * **必须关掉自动重定向**：Z-Library 的镜像入口正是靠 3xx 的 `Location`
 * 把请求转到真正可用的站点；跟随重定向就看不到 `Location` 了。
 */
public func probeSite(url: String): ZlibProbe {
    let client = HttpClientBuilder()
        .readTimeout(Duration.second * 10)
        .totalTimeout(Duration.second * 15)
        .followRedirects(false)
        .cookies(false)
        .build()
    var result = ZlibProbe(url, 0, "")
    try {
        let response = client.head(url)
        var location = ""
        match (response.location) {
            case Some(value) => location = resolveLocation(url, value)
            case None => ()
        }
        result = ZlibProbe(url, response.status, location)
    } catch (_: Exception) {
        result = ZlibProbe(url, 0, "")
    }
    client.close()
    result
}

/**
 * 判断单个 URL 是否可访问。
 *
 * 与 `probeSite` 的区别：只回 Bool，方便快速巡检。
 * 200（正常）与 503（站点维护页）都视为「连得上」。
 */
public func checkAccess(url: String): Bool {
    var target = url
    match (url.indexOf(ZLIB_API_PREFIX)) {
        case Some(index) => target = url[0..index]
        case None => ()
    }
    let result = probeSite(target)
    result.status == 200 || result.status == 503
}

/**
 * 判断站点是否可访问（兼容旧版 `canAccessZlib` 的调用习惯）。
 *
 * @param baseUrl 站点根地址
 * @param autoRedirect 为 `true` 时，3xx 也算「可用」（真实地址用 `resolveZlibHost` 取）
 */
public func canAccessZlib(baseUrl!: String = ZlibHost.DEFAULT_URL,
    autoRedirect!: Bool = false): Bool {
    let result = probeSite(baseUrl)
    if (autoRedirect && result.isRedirect) {
        return true
    }
    result.status == 200 || result.status == 503
}

/**
 * 按候选列表探测出一个可用站点。
 *
 * 探测顺序：先看 3xx 的 `Location`（镜像入口会给出真实域名），
 * 再看 200/503（直接可访问）。全部失败返回 `None`，由调用方决定报错文案
 * ——「找不到镜像」和「接口报错」是两种完全不同的故障，不该混成一个异常。
 */
public func resolveZlibHost(candidates!: Array<String> = ZlibHost.MIRRORS): ?ZlibHost {
    for (candidate in candidates) {
        let result = probeSite(candidate)
        if (result.isRedirect && !result.location.isEmpty()) {
            return Some(ZlibHost.of(result.location))
        }
        if (result.status == 200 || result.status == 503) {
            return Some(ZlibHost.of(candidate))
        }
    }
    None
}

/** 把 `Location` 解析成绝对地址：支持绝对 URL、根相对路径与相对路径。 */
internal func resolveLocation(baseUrl: String, location: String): String {
    let target = location.trimAscii()
    if (target.startsWith("http://") || target.startsWith("https://")) {
        return target
    }
    let origin = originOf(baseUrl)
    if (target.startsWith("/")) {
        return "${origin}${target}"
    }
    if (target.isEmpty()) {
        return baseUrl
    }
    "${origin}/${target}"
}

/** 从 URL 里取 `scheme://host[:port]`。 */
internal func originOf(url: String): String {
    let marker = url.indexOf("://")
    match (marker) {
        case Some(index) =>
            var position = index + 3
            while (position < url.size && url[position..(position + 1)] != "/") {
                position++
            }
            url[0..position]
        case None => url
    }
}
