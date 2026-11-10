package zlibraryAPI4CJ.core

import std.fs.*
import linderHttp.*

/**
 * Z-Library 调用错误的类别。
 *
 * **对外只有一种异常**：`ZlibError`。LinderHttp 的 `HttpError`、stdx 的 TLS/读写
 * 异常、文件系统异常，都会在客户端/接口边界被统一包装成 `ZlibError`
 * （原始异常放在 `ZlibError.cause` 里，需要排查时可取），
 * 所以调用方只需要 `catch (err: ZlibError)` 一个分支。
 *
 * 之所以做成枚举而不是字符串：调用方通常需要按类别决定行为
 * （未登录 → 引导登录；域名失效 → 换镜像；服务端错误 → 重试）。
 */
public enum ZlibErrorKind <: ToString & Equatable<ZlibErrorKind> {
    /** 响应不是合法 JSON，或者缺少约定的字段（多半是被风控页/登录页替换了）。 */
    | BadResponse
    /** 服务端明确返回 `success = 0`，并带有 `error` / `msg` 文案。 */
    | ApiFailure
    /** 未登录或凭证失效（服务端提示 `Please login` 之类）。 */
    | NotLoggedIn
    /** 资源不存在（书被删、id/hash 不对、接口下线返回 404）。 */
    | NotFound
    /** 被拒绝（403 / 域名被墙 / 需要个人域名才能下载）。 */
    | Forbidden
    /** 客户端已经 `close()` 仍继续使用。 */
    | Closed
    /**
     * Cangjie 生态的底层异常（对齐 bbapi：**所有**非业务错误都归这一类）。
     *
     * 包括 LinderHttp 的 `HttpError`（DNS/TLS/超时）、Cangjie `std.fs` 的文件系统
     * 异常、stdx 的读写异常等；具体来源看 `ZlibError.cause`。
     */
    | Cangjie

    /** 稳定数值码（便于日志检索与相等比较）。 */
    public prop code: Int64 {
        get() {
            match (this) {
                case BadResponse => 1
                case ApiFailure => 2
                case NotLoggedIn => 3
                case NotFound => 4
                case Forbidden => 5
                case Closed => 6
                case Cangjie => 7
            }
        }
    }

    /** 类别本身是否值得重试（`Cangjie` 要看 `cause`，见 `ZlibError.isRetryable`）。 */
    public prop isRetryable: Bool {
        get() {
            false
        }
    }

    public func toString(): String {
        let names = [
            "BadResponse",
            "ApiFailure",
            "NotLoggedIn",
            "NotFound",
            "Forbidden",
            "Closed",
            "Cangjie"
        ]
        names[code - 1]
    }

    /**
     * 相等性按「语义值」比较。
     *
     * 仓颉的无参枚举默认不支持 `==`，而调用方做 `err.kind == ZlibErrorKind.NotFound`
     * 是很自然的写法，所以这里显式实现。
     */
    public operator func ==(right: ZlibErrorKind): Bool {
        this.code == right.code
    }

    public operator func !=(right: ZlibErrorKind): Bool {
        this.code != right.code
    }
}

/**
 * Z-Library 业务调用失败时抛出的异常。
 *
 * 为什么把 `path` / `serverMessage` / `status` 都保留成公开字段：
 * Z-Library 的域名经常失效，排查时最需要知道「打的是哪个接口、服务端原话是什么」，
 * 只给一行 `Exception("something wrong")` 完全不够定位。
 *
 * 文案约定：
 * - `message`（来自 `Exception`）= **纯文案**，不含类别前缀；
 * - `detail` = `"[${kind}] " + message`，适合直接打日志。
 */
public class ZlibError <: Exception {
    /** 错误类别。 */
    public let kind: ZlibErrorKind
    /** 出错的 eapi 路径（或下载 URL）。 */
    public let path: String
    /** 服务端返回的 `error` / `msg` 原文；非业务错误时为空。 */
    public let serverMessage: String
    /** 触发错误时的 HTTP 状态码；未知为 0。 */
    public let status: UInt16
    /**
     * 被包装的原始异常（`HttpError` / stdx 异常 / 文件系统异常）。
     *
     * 绝大多数调用不需要看它；只有排查底层网络/TLS 细节时才有用。
     */
    public let cause: ?Exception
    /** 人类可读的错误描述（已带类别前缀）。 */
    public let detail: String

    public init(kind: ZlibErrorKind, message: String, path!: String = "",
        serverMessage!: String = "", status!: UInt16 = 0, cause!: ?Exception = None) {
        // 约定：message 是纯文案（不含类别前缀），detail 才带 "[kind] " 前缀。
        // 需要「可直接打日志的一行」用 detail；需要原始文案用 message。
        super(message)
        this.kind = kind
        this.path = path
        this.serverMessage = serverMessage
        this.status = status
        this.cause = cause
        this.detail = "[${kind}] ${message}"
    }

    /** 服务端返回 `success = 0` 时使用。 */
    public static func apiFailure(path: String, message: String,
        status!: UInt16 = 0): ZlibError {
        let text = if (message.isEmpty()) { "服务端返回 success=0（无错误文案）" } else { message }
        ZlibError(ZlibErrorKind.ApiFailure, text, path: path, serverMessage: message,
            status: status)
    }

    /** 响应不是 JSON 对象（风控页、登录页、空响应）时使用。 */
    public static func badResponse(path: String, body: String): ZlibError {
        let preview = truncateBytesSafe(body.trimAscii(), 160, suffix: "")
        let detail = if (preview.isEmpty()) {
            "服务端返回空响应（接口可能已下线或被拦截）"
        } else {
            "服务端返回非 JSON 响应（可能是风控页或域名失效）: ${sanitizeLine(preview)}"
        }
        ZlibError(ZlibErrorKind.BadResponse, detail, path: path)
    }

    /** 下载等二进制请求遇到非 2xx 时使用。 */
    public static func httpStatus(path: String, status: UInt16, preview: String): ZlibError {
        let kind = if (status == 404) {
            ZlibErrorKind.NotFound
        } else if (status == 401 || status == 403) {
            ZlibErrorKind.Forbidden
        } else {
            ZlibErrorKind.BadResponse
        }
        let detail = if (preview.isEmpty()) {
            "HTTP ${status}"
        } else {
            "HTTP ${status}: ${sanitizeLine(preview)}"
        }
        ZlibError(kind, detail, path: path, status: status)
    }

    /** 需要登录却没有凭证（或服务端判定凭证失效）时使用。 */
    public static func notLoggedIn(path: String): ZlibError {
        ZlibError(ZlibErrorKind.NotLoggedIn, "该接口需要登录，请先 login 并用 withCredential 派生客户端",
            path: path)
    }

    /** 客户端已关闭。 */
    public static func closed(): ZlibError {
        ZlibError(ZlibErrorKind.Closed, "ZlibClient 已关闭")
    }

    /**
     * 把 Cangjie 生态的底层异常包装成 `Cangjie`。
     *
     * 对齐 bbapi：网络（`HttpError`）、文件系统（`FSException`）、stdx 异常
     * 统一归 `Cangjie` 一类，具体来源看 `cause`；调用方用 `kind` 区分
     * 「业务失败」与「底层失败」即可。
     */
    public static func cangjie(path: String, detail: String,
        cause!: ?Exception = None): ZlibError {
        ZlibError(ZlibErrorKind.Cangjie, detail, path: path, cause: cause)
    }

    /**
     * 兜底包装：任何非 `ZlibError` 的异常都转成 `ZlibError`。
     *
     * 分类规则（对齐 bbapi：**所有**非业务错误都归 `Cangjie`，来源看 `cause`）：
     * - LinderHttp `HttpError`（DNS/TLS/超时）→ `Cangjie`
     * - Cangjie `std.fs.FSException`（本地文件）→ `Cangjie`
     * - 其它 Cangjie 运行时 / 标准库异常 → `Cangjie`
     *
     * `detail` 的文本优先用 `HttpError.describe()`：它比 `message` 信息量大得多——
     * 带错误类别、请求 URL、实际重试次数；`StatusError` 还带状态码与响应体开头。
     * 例如 `Connect [https://x/eapi/...] attempts=2: Failed to resolve address`。
     *
     * 客户端在所有公开边界调用它，保证调用方只需 `catch (err: ZlibError)`。
     */
    public static func wrapUnhandled(path: String, err: Exception): ZlibError {
        ZlibError.cangjie(path, describeUnhandled(err), cause: Some(err))
    }

    /** 生成包装后的描述文本；`HttpError` 用 `describe()`（含类别/URL/重试次数）。 */
    private static func describeUnhandled(err: Exception): String {
        match (err) {
            case http: HttpError => httpDescription(http)
            case _ => unhandledMessage(err)
        }
    }

    private static func httpDescription(err: HttpError): String {
        "底层请求失败：${err.describe()}"
    }

    private static func unhandledMessage(err: Exception): String {
        if (err.message.isEmpty()) {
            "底层异常（无消息）"
        } else {
            "底层请求失败：${err.message}"
        }
    }

    /** 是否未登录。 */
    public prop isUnauthorized: Bool {
        get() {
            kind == ZlibErrorKind.NotLoggedIn
        }
    }

    /**
     * 是否值得重试。
     *
     * 对齐 bbapi：`Cangjie` 类别看原始异常——`HttpError` 按其自身
     * `isRetryable()` 判断（超时/连接类可重试），其余底层异常为 false。
     */
    public prop isRetryable: Bool {
        get() {
            match (kind) {
                case Cangjie =>
                    match (cause) {
                        case Some(value) =>
                            match (value) {
                                case http: HttpError => http.isRetryable()
                                case _ => false
                            }
                        case None => false
                    }
                case _ => kind.isRetryable
            }
        }
    }

    public func toString(): String {
        "ZlibError(kind=${kind}, path=${path}, status=${status}, message=${message})"
    }
}

/** 把多行文本压成单行，避免把整页 HTML 塞进异常消息。 */
private func sanitizeLine(text: String): String {
    text.replace("\r", " ").replace("\n", " ").trimAscii()
}
