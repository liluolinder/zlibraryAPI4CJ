package zlibraryAPI4CJ.model

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * 图书详细信息（`GET /eapi/book/{id}/{hash}` 的 `book` 字段）。
 *
 * 字段基本对齐 Z-Library 网页端返回的 book 对象。要点：
 *
 * - `dl` 是下载路径（可能为空：部分书只有在线阅读），**真正下载链接**要用
 *   `BookApi.file()` 换 `DownloadInfo`；
 * - `readOnlineUrl` / `readOnlineAvailable` 表示在线阅读能力；
 * - `_isUserSavedBook` / `date_saved` 只在带登录态请求时出现，所以是可选的；
 * - Z-Library 会偶发省略 `dl` 等字段，这里全部走容错读取（见 `core` 的
 *   `readString` / `readInt` / `readBool`），缺字段只回退默认值，不会抛异常。
 */
public class BookInfo <: ToString {
    /** 图书 id。 */
    public var id: Int64 = 0
    /** 内容类型（`book` / `article` …）。 */
    public var contentType: String = ""
    /** 书名。 */
    public var title: String = ""
    /** 作者；部分书没有作者信息。 */
    public var author: ?String = None
    /** 卷号。 */
    public var volume: String = ""
    /** 出版年份。 */
    public var year: Int64 = 0
    /** 版本。 */
    public var edition: ?String = None
    /** 出版社。 */
    public var publisher: ?String = None
    /** 标识符（ISBN 等）。 */
    public var identifier: ?String = None
    /** 语言。 */
    public var language: String = ""
    /** 页数。 */
    public var pages: Int64 = 0
    /** 系列名。 */
    public var series: String = ""
    /** 封面图 URL。 */
    public var cover: String = ""
    /** 术语哈希（服务端内部用）。 */
    public var termsHash: String = ""
    /** 是否激活（1/0）。 */
    public var active: Int64 = 0
    /** 是否删除（1/0）。 */
    public var deleted: Int64 = 0
    /** 文件大小（字节）。 */
    public var filesize: Int64 = 0
    /** 文件大小的可读文本（如 `12.3 MB`）。 */
    public var filesizeString: String = ""
    /** 文件扩展名（`pdf` / `epub` / `mobi` …）。 */
    public var extension: String = ""
    /** MD5。 */
    public var md5: String = ""
    /** SHA256。 */
    public var sha256: String = ""
    /** 图书页相对地址（`/book/{id}/{hash}/{slug}`）。 */
    public var href: String = ""
    /** 图书 hash（下载/详情接口都要用它）。 */
    public var hash: String = ""
    /** 是否可发送到 Kindle。 */
    public var kindleAvailable: Bool = false
    /** 是否可发送到邮箱。 */
    public var sendToEmailAvailable: Bool = false
    /** 兴趣评分（字符串，服务端原样返回）。 */
    public var interestScore: String = ""
    /** 质量评分（字符串，服务端原样返回）。 */
    public var qualityScore: String = ""
    /** 简介。 */
    public var description: String = ""
    /** 下载路径（可能为空：只有在线阅读的书没有该字段）。 */
    public var dl: String = ""
    /** 在线阅读 URL。 */
    public var readOnlineUrl: ?String = None
    /** 当前用户是否已收藏（仅登录态请求会出现）。 */
    public var isUserSavedBook: ?Bool = None
    /** 收藏日期（仅登录态请求会出现）。 */
    public var dateSaved: ?String = None
    /** 是否可在线阅读。 */
    public var readOnlineAvailable: Bool = false

    /** 从 JSON 对象解码（容错，缺字段回退默认值）。 */
    public static func fromJsonObject(obj: JsonObject): BookInfo {
        let book = BookInfo()
        book.id = readInt(obj, "id")
        book.contentType = readString(obj, "content_type")
        book.title = readString(obj, "title")
        book.author = readOptionalString(obj, "author")
        book.volume = readString(obj, "volume")
        book.year = readInt(obj, "year")
        book.edition = readOptionalString(obj, "edition")
        book.publisher = readOptionalString(obj, "publisher")
        book.identifier = readOptionalString(obj, "identifier")
        book.language = readString(obj, "language")
        book.pages = readInt(obj, "pages")
        book.series = readString(obj, "series")
        book.cover = readString(obj, "cover")
        book.termsHash = readString(obj, "terms_hash")
        book.active = readInt(obj, "active")
        book.deleted = readInt(obj, "deleted")
        book.filesize = readInt(obj, "filesize")
        book.filesizeString = readString(obj, "filesizeString")
        book.extension = readString(obj, "extension")
        book.md5 = readString(obj, "md5")
        book.sha256 = readString(obj, "sha256")
        book.href = readString(obj, "href")
        book.hash = readString(obj, "hash")
        book.kindleAvailable = readBool(obj, "kindleAvailable")
        book.sendToEmailAvailable = readBool(obj, "sendToEmailAvailable")
        book.interestScore = readString(obj, "interestScore")
        book.qualityScore = readString(obj, "qualityScore")
        book.description = readString(obj, "description")
        book.dl = readString(obj, "dl")
        book.readOnlineUrl = readOptionalString(obj, "readOnlineUrl")
        // 下划线前缀是 Z-Library 序列化时的内部字段名；社区抓包里也有无下划线的写法，
        // 两种都读，避免登录态下「已收藏」状态丢失。
        book.isUserSavedBook = optionalBoolOf(obj, "_isUserSavedBook", "isUserSavedBook")
        book.dateSaved = readOptionalString(obj, "date_saved")
        book.readOnlineAvailable = readBool(obj, "readOnlineAvailable")
        book
    }

    /** 从 JSON 文本解码。 */
    public static func fromJson(text: String): BookInfo {
        fromJsonObject(parseJsonObject(text, path: "book"))
    }

    /** 作者文本；没有作者时返回空串（便于直接拼接展示）。 */
    public func authorText(): String {
        author ?? ""
    }

    /** 文件大小文本：优先用服务端的 `filesizeString`，否则按字节数格式化。 */
    public func sizeText(): String {
        if (!filesizeString.isEmpty()) {
            return filesizeString
        }
        if (filesize <= 0) {
            return ""
        }
        if (filesize < 1024) {
            return "${filesize} B"
        }
        if (filesize < 1024 * 1024) {
            return "${filesize / 1024} KB"
        }
        "${filesize / (1024 * 1024)} MB"
    }

    /** 当前用户是否已收藏。 */
    public func saved(): Bool {
        match (isUserSavedBook) {
            case Some(value) => value
            case None => false
        }
    }

    /** 是否有可用的下载路径（只有真正下载链接要再调 `BookApi.file`）。 */
    public func downloadable(): Bool {
        !dl.isEmpty()
    }

    /**
     * 图书网页地址。
     *
     * 优先用 `href`（服务端给的相对地址）；旧响应可能没有 `href`，
     * 此时按 `/book/{id}/{hash}` 拼。域名不稳定，所以要显式传站点地址。
     */
    public func webpage(baseUrl!: String): String {
        let host = ZlibHost.of(baseUrl).url
        if (!href.isEmpty()) {
            if (href.startsWith("http")) {
                return href
            }
            if (href.startsWith("/")) {
                return "${host}${href}"
            }
            return "${host}/${href}"
        }
        "${host}/book/${id}/${hash}"
    }

    public func toString(): String {
        "BookInfo(${id}/${hash}, ${title})"
    }
}

/**
 * 图书列表项（搜索/相似/推荐等列表接口的元素）。
 *
 * 列表接口为了节省带宽只给少量字段，但**下载需要 `id` + `hash` 两个值**，
 * 所以它们一定在。
 */
public class BookInfoBrief <: ToString {
    /** 图书 id。 */
    public var id: Int64 = 0
    /** ISBN（部分书为空）。 */
    public var isbn: String = ""
    /** 图书页相对地址（如 `/book/xxx/yyy/title.html`）。 */
    public var url: String = ""
    /** 书名。 */
    public var title: String = ""
    /** 作者。 */
    public var author: String = ""
    /** 封面图 URL。 */
    public var cover: String = ""
    /** 封面懒加载用的 data 属性原文（服务端原样返回，一般用不到）。 */
    public var coverData: String = ""
    /** 图书 hash。 */
    public var hash: String = ""

    /** 从 JSON 对象解码（容错）。 */
    public static func fromJsonObject(obj: JsonObject): BookInfoBrief {
        let brief = BookInfoBrief()
        brief.id = readInt(obj, "id")
        brief.isbn = readString(obj, "isbn")
        brief.url = readString(obj, "url")
        brief.title = readString(obj, "title")
        brief.author = readString(obj, "author")
        brief.cover = readString(obj, "cover")
        brief.coverData = readString(obj, "coverData")
        brief.hash = readString(obj, "hash")
        brief
    }

    /** 从 JSON 文本解码。 */
    public static func fromJson(text: String): BookInfoBrief {
        fromJsonObject(parseJsonObject(text, path: "book-brief"))
    }

    /**
     * 图书网页地址。
     *
     * 优先用服务端给的 `url`（实测 `most-popular` / `similar` / `recently`
     * 都返回该字段，值是 `/book/{id}/{hash}/{slug}.html` 形式的相对地址或
     * 绝对地址）；没有 `url` 时退回 `/book/{id}/{hash}`。
     */
    public func webpage(baseUrl!: String): String {
        let host = ZlibHost.of(baseUrl).url
        if (!url.isEmpty()) {
            if (url.startsWith("http")) {
                return url
            }
            if (url.startsWith("/")) {
                return "${host}${url}"
            }
            return "${host}/${url}"
        }
        "${host}/book/${id}/${hash}"
    }

    public func toString(): String {
        "BookInfoBrief(${id}/${hash}, ${title})"
    }
}

/**
 * 可下载格式（`GET /book/{id}/{hash}/formats` 的 `books` 元素）。
 *
 * **2026-11-10 实测**（zh.eva101.ru）响应形如：
 *
 * ```json
 * {"success":1,"books":[
 *   {"id":35851393,"hash":"b4c3ae","extension":"azw3","filesize":5285744,"filesizeString":"5.04 MB"}
 * ]}
 * ```
 *
 * 即同一本书在不同版本/格式下各有自己的 `id` + `hash`，想下载指定格式时
 * 用对应条目的 `id` + `hash` 调 `BookApi.file()`。
 */
public class BookFormat <: ToString {
    /** 该格式版本的图书 id。 */
    public var id: Int64 = 0
    /** 该格式版本的 hash。 */
    public var hash: String = ""
    /** 扩展名（`pdf` / `epub` / `azw3` …，不含点）。 */
    public var extension: String = ""
    /** 文件大小（字节）。 */
    public var filesize: Int64 = 0
    /** 文件大小文本（如 `5.04 MB`）。 */
    public var filesizeString: String = ""

    /** 从 JSON 对象解码（容错）。 */
    public static func fromJsonObject(obj: JsonObject): BookFormat {
        let format = BookFormat()
        format.id = readInt(obj, "id")
        format.hash = readString(obj, "hash")
        format.extension = readString(obj, "extension")
        format.filesize = readInt(obj, "filesize")
        format.filesizeString = readString(obj, "filesizeString")
        format
    }

    /** 从 JSON 文本解码。 */
    public static func fromJson(text: String): BookFormat {
        fromJsonObject(parseJsonObject(text, path: "book-format"))
    }

    /** 大小文本：优先用服务端 `filesizeString`，否则按字节格式化。 */
    public func sizeText(): String {
        if (!filesizeString.isEmpty()) {
            return filesizeString
        }
        if (filesize <= 0) {
            return ""
        }
        if (filesize < 1024 * 1024) {
            return "${filesize / 1024} KB"
        }
        "${filesize / (1024 * 1024)} MB"
    }

    public func toString(): String {
        "BookFormat(${extension}, ${sizeText()})"
    }
}

/** 依次尝试多个 key 读取可选布尔（用于兼容 `_x` / `x` 两种字段名）。 */
private func optionalBoolOf(obj: JsonObject, first: String, second: String): ?Bool {
    match (obj.get(first)) {
        case Some(value) => Some(jsonToBoolOf(value))
        case None =>
            match (obj.get(second)) {
                case Some(value) => Some(jsonToBoolOf(value))
                case None => None
            }
    }
}

/** 单值转布尔的本地实现（`core` 的 `jsonToBool` 是 internal 的）。 */
private func jsonToBoolOf(value: JsonValue): Bool {
    match (value.kind()) {
        case JsBool => value.asBool().getValue()
        case JsInt => value.asInt().getValue() != 0
        case JsFloat => value.asFloat().getValue() != 0.0
        case JsString =>
            let text = value.asString().getValue().trimAscii().toAsciiLower()
            text == "true" || text == "1"
        case _ => false
    }
}
