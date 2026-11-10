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
    /** 传输层失败（DNS / 连接 / TLS / 超时），通常换域名或重试有用。 */
    | Transport
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
    /** 本地文件系统错误（下载目录不可写、磁盘满等）。 */
    | Io

    /** 稳定数值码（便于日志检索与相等比较）。 */
    public prop code: Int64 {
        get() {
            match (this) {
                case Transport => 1
                case BadResponse => 2
                case ApiFailure => 3
                case NotLoggedIn => 4
                case NotFound => 5
                case Forbidden => 6
                case Closed => 7
                case Io => 8
            }
        }
    }

    /** 是否值得重试（只有传输层与服务端瞬时问题值得重试）。 */
    public prop isRetryable: Bool {
        get() {
            match (this) {
                case Transport => true
                case _ => false
            }
        }
    }

    public func toString(): String {
        let names = [
            "Transport",
            "BadResponse",
            "ApiFailure",
            "NotLoggedIn",
            "NotFound",
            "Forbidden",
            "Closed",
            "Io"
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
        super("[${kind}] ${message}")
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

    /** 把传输层失败包装成 `Transport`（可带原始异常）。 */
    public static func transport(path: String, detail: String,
        cause!: ?Exception = None): ZlibError {
        ZlibError(ZlibErrorKind.Transport, detail, path: path, cause: cause)
    }

    /** 把本地文件系统失败包装成 `Io`。 */
    public static func io(path: String, detail: String,
        cause!: ?Exception = None): ZlibError {
        ZlibError(ZlibErrorKind.Io, detail, path: path, cause: cause)
    }

    /**
     * 兜底包装：任何非 `ZlibError` 的异常都转成 `ZlibError`。
     *
     * - 文件系统异常 → `Io`；
     * - 其它（LinderHttp `HttpError`、stdx 的 TLS/读写异常）→ `Transport`。
     *
     * `detail` 的文本优先用 `HttpError.describe()`：它比 `message` 信息量大得多——
     * 带错误类别、请求 URL、实际重试次数；`StatusError` 还带状态码与响应体开头。
     * 例如 `Connect [https://x/eapi/...] attempts=2: Failed to resolve address`。
     *
     * 客户端在所有公开边界调用它，保证调用方只需 `catch (err: ZlibError)`。
     */
    public static func wrapUnhandled(path: String, err: Exception): ZlibError {
        let text = describeUnhandled(err)
        if (err is FSException) {
            ZlibError.io(path, text, cause: Some(err))
        } else {
            ZlibError.transport(path, text, cause: Some(err))
        }
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

    /** 是否值得重试。 */
    public prop isRetryable: Bool {
        get() {
            kind.isRetryable
        }
    }

    public func toString(): String {
        "ZlibError(kind=${kind}, path=${path}, status=${status}, message=${detail})"
    }
}

/** 把多行文本压成单行，避免把整页 HTML 塞进异常消息。 */
private func sanitizeLine(text: String): String {
    text.replace("\r", " ").replace("\n", " ").trimAscii()
}
