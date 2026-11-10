package zlibraryAPI4CJ.model

import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * 下载信息（`GET /eapi/book/{id}/{hash}/file` 的 `file` 字段）。
 *
 * 服务端返回的是一个**签名过的绝对下载链接**（`downloadLink`），
 * 以及用于命名文件的元信息。要点：
 *
 * - 链接带时效/签名，不要缓存太久；失效后重新调 `BookApi.file()` 换新的；
 * - `downloadLink` 的主机名可能和站点域名不同（下载走专门的 CDN/个人域名），
 *   所以下载时不应携带站点的 remix 凭证；
 * - 文件名由 `description` + `author` + `extension` 拼出，
 *   服务端不直接给文件名，这里用 `fileName()` 统一生成。
 */
public class DownloadInfo <: ToString {
    /** 签名过的下载链接。 */
    public var downloadLink: String = ""
    /** 文件描述，通常就是书名（也用作文件名主体）。 */
    public var description: ?String = None
    /** 作者（拼进文件名）。 */
    public var author: ?String = None
    /** 文件扩展名（`pdf` / `epub` …，不含点）。 */
    public var extension: String = ""
    /** 是否允许下载；老接口会显式给，缺省视为允许。 */
    public var allowDownload: Bool = true

    /** 从 JSON 对象解码（容错）。 */
    public static func fromJsonObject(obj: JsonObject): DownloadInfo {
        let info = DownloadInfo()
        info.downloadLink = readString(obj, "downloadLink")
        info.description = readOptionalString(obj, "description")
        info.author = readOptionalString(obj, "author")
        info.extension = readString(obj, "extension")
        info.allowDownload = readBoolOr(obj, "allowDownload", true)
        info
    }

    /** 从 JSON 文本解码。 */
    public static func fromJson(text: String): DownloadInfo {
        fromJsonObject(parseJsonObject(text, path: "download"))
    }

    /** 是否有可下载的链接。 */
    public func available(): Bool {
        allowDownload && !downloadLink.isEmpty()
    }

    /**
     * 生成文件名（含扩展名）。
     *
     * 规则与社区客户端一致：`描述 (作者).扩展名`，缺哪段就省略哪段；
     * 描述为空时退化成 `book.扩展名`。文件名里的路径分隔符与 Windows
     * 非法字符统一替换成 `_`，避免 `Path.join` 时被当成多级目录。
     */
    public func fileName(): String {
        var base = description ?? ""
        base = base.trimAscii()
        if (base.isEmpty()) {
            base = "book"
        }
        if (let Some(value) <- author) {
            let name = value.trimAscii()
            if (!name.isEmpty()) {
                base = "${base} (${name})"
            }
        }
        let ext = extension.trimAscii()
        let name = if (ext.isEmpty()) {
            base
        } else {
            "${base}.${ext}"
        }
        sanitizeFileName(name)
    }

    public func toString(): String {
        "DownloadInfo(${fileName()}, available=${available()})"
    }
}

/** 去掉文件名中的路径分隔符与 Windows 非法字符。 */
private func sanitizeFileName(name: String): String {
    var result = name
    for (ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\r", "\n", "\t"]) {
        result = result.replace(ch, "_")
    }
    result.trimAscii()
}
