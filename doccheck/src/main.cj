/*
 * zlibraryAPI4CJ 文档示例编译校验工程。
 *
 * 本文件把 `API_USAGE.md` 里的**每一段示例**落成一个函数。
 * 函数体不需要真实执行（`main` 不调用它们），只要能被编译器检查类型即可：
 * 一旦文档里写了不存在的 API、错的位置参数、错的类型，`cjpm build` 就会失败。
 *
 * 约定：
 * - 每个函数名对应 API_USAGE.md 的章节号（如 `doc9_1` = 第 9.1 节）；
 * - 新增文档示例时同步加函数；
 * - 改 public 签名时，先改这里看编译错误，再改文档。
 *
 * 验收：`cd doccheck && cjpm build`
 */
package zlibraryAPI4CJ_doccheck

import std.collection.*
import std.fs.*
import stdx.encoding.json.*
import linderHttp.*
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*
import zlibraryAPI4CJ.book.*
import zlibraryAPI4CJ.search.*
import zlibraryAPI4CJ.user.*
import zlibraryAPI4CJ.info.*

// ===========================================================================
// 2. 安装与依赖：最小可运行示例
// ===========================================================================
func doc2_minimal(): Int64 {
    let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        let book = BookApi.info(client, 123456, "abcdef123456")
        println("${book.title} / ${book.authorText()} / ${book.sizeText()}")
    } finally {
        client.close()
    }
    0
}

// ===========================================================================
// 3.1 创建
// ===========================================================================
func doc3_1(): Unit {
    // 1) 默认配置 + 游客态
    let anon = ZlibClient.create()

    // 2) 指定站点
    let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")

    // 3) 指定站点 + 已有凭证
    let credential = ZlibCredential.fromCookieString(
        "remix_userid=123456; remix_userkey=xxxxxxxx")
    let authed = ZlibClient.create(baseUrl: "https://your-zlib-domain",
        credential: credential)

    // 4) 复用外部 HttpClient
    let http = HttpClientBuilder().userAgent("my-agent").build()
    let shared = ZlibClient.fromHttpClient(http, baseUrl: "https://your-zlib-domain")

    println("${anon.baseUrl} ${client.baseUrl} ${authed.credential.isLoggedIn} ${shared.baseUrl}")
    anon.close()
    client.close()
    shared.close()
}

// ===========================================================================
// 3.2 配置
// ===========================================================================
func doc3_2(): Unit {
    let config = ZlibClientConfig()
    config.readTimeout = Duration.second * 20
    config.totalTimeout = Duration.second * 45
    config.httpsProxy = "http://127.0.0.1:7890"
    config.maxConnectionsPerHost = 4

    let client = ZlibClient.create(baseUrl: "https://your-zlib-domain", config: config)

    // 需要改动共享配置时先 copy()，避免污染别处持有的实例
    let cloned = client.config.copy()
    cloned.readTimeout = Duration.second * 10

    println("${cloned.readTimeout}")
    client.close()
}

// ===========================================================================
// 3.3 只读属性
// ===========================================================================
func doc3_3(): Unit {
    let client = ZlibClient.create(baseUrl: "https://example.com/eapi/")
    println(client.baseUrl)               // https://example.com
    println(client.eapiUrl)               // https://example.com/eapi
    println(client.credential.isLoggedIn) // false
    println("${client.host} ${client.config.maxConnectionsPerHost}")
    client.close()
}

// ===========================================================================
// 3.4 派生
// ===========================================================================
func doc3_4(client: ZlibClient): Unit {
    // 换身份
    let authed = client.withCredential(ZlibCredential.of(123456, "xxxxxxxx"))

    // 换站点
    let moved = client.withBaseUrl("https://another-mirror.example")

    // 直接给一个 ZlibHost
    let viaHost = client.withHost(ZlibHost.of("https://third-mirror.example"))

    println("${authed.credential.isLoggedIn} ${moved.baseUrl} ${viaHost.baseUrl}")
}

// ===========================================================================
// 3.5 credentialFromCookies
// ===========================================================================
func doc3_5(): Unit {
    let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    // ... 某处发过登录请求（例如别的库代登录）...
    let credential = client.credentialFromCookies()
    let authed = client.withCredential(credential)
    println(authed.credential.isLoggedIn)
    client.close()
}

// ===========================================================================
// 3.6 底层请求方法
// ===========================================================================
func doc3_6(client: ZlibClient): Unit {
    // 原始文本（不解析 JSON）
    let text = client.getRaw("/info/languages")

    // 自己构造 query（同名参数可重复）
    let query = Query().setIfSome("order", Some("year")).setInt("page", 2).toArray()
    let text2 = client.getRaw("/user/book/saved", query: query)

    // 自己处理 success 而不是让它抛异常
    let envelope = client.getEnvelope("/user/profile")
    if (envelope.success) {
        let root = envelope.root
        println(readString(root, "user"))
    } else {
        println("失败：${envelope.errorText}")
    }

    // 取强类型对象
    let book = client.getObject("/book/1/abcdef", "book",
        { obj => BookInfo.fromJsonObject(obj) })

    // POST 表单 + 取对象字段（decoder 是最后一个参数，可用尾随 lambda）
    let user = client.postFormObject("/user/login", "user",
        [("email", "a@b.com"), ("password", "pw")]) { obj =>
        ZlibUser.fromJsonObject(obj)
    }

    println("${text.size} ${text2.size} ${book.title} ${user.name}")
}

// ===========================================================================
// 3.7 下载与二进制
// ===========================================================================
func doc3_7(client: ZlibClient): Unit {
    // 落盘：同名默认自动改名
    let written = client.download("https://dl.example.com/f/1?token=x",
        Path("./downloads/a.epub"))

    // 明确覆盖已有文件
    let overwritten = client.download("https://dl.example.com/f/2", Path("./downloads/b.pdf"),
        overwrite: true)

    // 只要字节（例如封面）
    let bytes = client.fetchBytes("https://example.com/cover.jpg")
    println("封面 ${bytes.size} 字节，写入 ${written} / ${overwritten}")
}

// ===========================================================================
// 3.8 资源管理
// ===========================================================================
func doc3_8(): Unit {
    let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        println(client.isClosed()) // false
    } finally {
        client.close()
    }

    // 显式关闭 + 幂等（重复 close 不报错）
    client.close()
    client.close()
    println(client.isClosed()) // true
}

// ===========================================================================
// 4.1 三种构造方式（含 4.2 / 4.3）
// ===========================================================================
func doc4_1(): Unit {
    // 1) 游客
    let anonymous = ZlibCredential.anonymous()
    println(anonymous.isLoggedIn) // false

    // 2) 逐字段构造（全具名参数）
    let manual = ZlibCredential(userId: "123456", userKey: "xxxxxxxx", siteLanguage: "en")

    // 3) 用数值 id 构造
    let fromId = ZlibCredential.of(123456, "xxxxxxxx")

    // 4) 从浏览器复制出来的 Cookie 串解析
    let fromCookie = ZlibCredential.fromCookieString(
        "remix_userid=123456; remix_userkey=xxxxxxxx; siteLanguageV2=zh")
    println(fromCookie.userId)       // 123456
    println(fromCookie.siteLanguage) // zh

    // 不可变派生
    let changed = manual.withSiteLanguage("de").withUserId("42").withUserKey("kk")
    println("${fromId.isLoggedIn} ${changed.language}")

    // Cookie / 请求头格式
    println(fromCookie.toCookieHeader())
    println(fromCookie.toRequestHeaders().size)
}

func doc4_3(): Unit {
    // 做法一：按字段存（读回来时逐字段构造）
    let stored = ZlibCredential(userId: "123456", userKey: "xxxxxxxx", siteLanguage: "zh")

    // 做法二：直接存 toCookieHeader() 的字符串，读时用 fromCookieString 还原
    let cookie = stored.toCookieHeader()
    let restored = ZlibCredential.fromCookieString(cookie)
    println(restored.isLoggedIn)
}

// ===========================================================================
// 5.1 ZlibHost
// ===========================================================================
func doc5_1(): Unit {
    let host = ZlibHost.of("  https://example.com/eapi/  ")
    println(host.url)     // https://example.com
    println(host.eapi)    // https://example.com/eapi
    println(host.origin)  // https://example.com/
    println(host.isValid) // true

    println(ZlibHost.DEFAULT_URL)
    println(ZlibHost.MIRRORS.size)
}

// ===========================================================================
// 5.2 探测
// ===========================================================================
func doc5_2(): Unit {
    // 单点探测
    let probe = probeSite("https://z-library.sk")
    println("status=${probe.status} redirect=${probe.isRedirect} reachable=${probe.reachable}")
    if (probe.isRedirect && !probe.location.isEmpty()) {
        println("镜像把入口指向：${probe.location}")
    }

    // 快速巡检
    println(checkAccess("https://your-zlib-domain"))
    println(canAccessZlib(baseUrl: "https://your-zlib-domain", autoRedirect: true))

    // 从候选列表里找一个可用的
    match (resolveZlibHost()) {
        case Some(host) => println("可用：${host.url}")
        case None => println("候选镜像全部不可达，请手动指定 baseUrl")
    }
}

// ===========================================================================
// 6.1 / 6.3 错误处理
// ===========================================================================
func doc6_1(err: ZlibError): Bool {
    if (err.kind == ZlibErrorKind.NotFound) {
        println("找不到这本书")
    }
    err.kind == ZlibErrorKind.Transport
}

func doc6_2(): Unit {
    // 错误对象的字段与派生属性
    let error = ZlibError.apiFailure("/book/1/x", "boom")
    println("${error.kind} ${error.kind.code} ${error.kind.isRetryable}")
    println("${error.path} ${error.serverMessage} ${error.status} ${error.detail}")
    println("${error.isUnauthorized} ${error.isRetryable}")

    // 静态构造
    let custom = ZlibError(ZlibErrorKind.BadResponse, "自定义错误", path: "/x",
        serverMessage: "raw", status: 502)
    println(custom.detail)
    println(ZlibError.badResponse("/x", "<html>").detail)
    println(ZlibError.httpStatus("u", 403, "no").kind)
    println(ZlibError.notLoggedIn("/x").isUnauthorized)
    println(ZlibError.closed().kind)
    println(ZlibError.transport("/x", "tls").kind)
}

func doc6_3(client: ZlibClient): Unit {
    try {
        let book = BookApi.info(client, 123456, "abcdef123456")
        println(book.title)
    } catch (err: ZlibError) {
        match (err.kind) {
            case ZlibErrorKind.NotLoggedIn => println("请先登录：${err.detail}")
            case ZlibErrorKind.NotFound => println("资源不存在：${err.serverMessage}")
            case ZlibErrorKind.Forbidden => println("被拒绝（可能需要个人域名）")
            case ZlibErrorKind.Transport => println("网络/域名问题，考虑换镜像")
            case ZlibErrorKind.Closed => println("客户端已关闭")
            case _ => println(err.detail)
        }
    } catch (err: HttpError) {
        // 传输层：DNS / TLS / 超时 / 连接池
        println("${err.kind} url=${err.url} attempts=${err.attempts} retryable=${err.isRetryable()}")
    }
}

// ===========================================================================
// 8.2 LoginApi.login
// ===========================================================================
func doc8_2(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        let result = LoginApi.login(guest, "you@example.org", "your-password")
        println("hi ${result.user.name}，今日剩余 ${result.user.downloadsLeft()} 次下载")

        // 关键一步：派生登录态客户端；guest 本身仍是游客
        let mine = result.withClient(guest)
        println(mine.credential.isLoggedIn) // true

        // 把凭证存起来，下次就不用再登录
        let cookieText = result.credential.toCookieHeader()
        println(cookieText.contains("remix_userid="))
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 8.3 LoginApi.loginWithToken
// ===========================================================================
func doc8_3(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        // 校验凭证是否仍然有效（服务端改密码/风控后会立即失效）
        let result = LoginApi.loginWithToken(guest, 123456, "xxxxxxxx")
        let mine = result.withClient(guest)
        println("凭证有效：${mine.credential.isLoggedIn}")
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 8.4 loginClient / loginTokenClient
// ===========================================================================
func doc8_4(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        let mine = LoginApi.loginClient(guest, "you@example.org", "your-password")
        println(mine.credential.isLoggedIn)   // true
        println(guest.credential.isLoggedIn)  // false

        let again = LoginApi.loginTokenClient(guest, 123456, "xxxxxxxx")
        println(again.credential.isLoggedIn)  // true
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 8.5 register
// ===========================================================================
func doc8_5(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        LoginApi.register(guest, "new@example.org", "a-strong-password", "读书人")
        println("注册请求已提交（注意查收确认邮件）")
    } catch (err: ZlibError) {
        println("注册失败：${err.detail}")
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 8.6 requestPasswordRecovery
// ===========================================================================
func doc8_6(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        LoginApi.requestPasswordRecovery(guest, "you@example.org")
        println("找回密码邮件已请求发送")
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 8.7 resendConfirmation
// ===========================================================================
func doc8_7(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        let mine = LoginApi.loginClient(guest, "you@example.org", "your-password")
        LoginApi.resendConfirmation(mine)
        println("确认邮件已重发")
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 8.8 tokenSignIn
// ===========================================================================
func doc8_8(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        let result = LoginApi.tokenSignIn(guest, "google", "eyJhbGciOi...")
        let mine = result.withClient(guest)
        println("第三方登录成功：${result.user.email} ${mine.credential.isLoggedIn}")
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 9.1 BookApi.info
// ===========================================================================
func doc9_1(client: ZlibClient): Unit {
    let book = BookApi.info(client, 123456, "abcdef123456")
    println("${book.title} / ${book.authorText()} / ${book.sizeText()}")
    println("格式=${book.extension} 页数=${book.pages} 年份=${book.year}")
    println("网页地址=${book.webpage(baseUrl: client.baseUrl)}")

    // 指定文案语言
    let english = BookApi.info(client, 123456, "abcdef123456", switchLanguage: "en")
    println(english.title)
}

// ===========================================================================
// 9.2 infoOf
// ===========================================================================
func doc9_2(client: ZlibClient): Unit {
    // 从搜索/推荐列表里拿到的 brief
    let brief = BookInfoBrief()
    brief.id = 123456
    brief.hash = "abcdef123456"

    let detail = BookApi.infoOf(client, brief)
    println(detail.title)
}

// ===========================================================================
// 9.3 similar
// ===========================================================================
func doc9_3(client: ZlibClient): Unit {
    let similar = BookApi.similar(client, 123456, "abcdef123456")
    for (item in similar) {
        println("${item.title} / ${item.author} / ${item.webpage(baseUrl: client.baseUrl)}")
    }
}

// ===========================================================================
// 9.4 similarOf
// ===========================================================================
func doc9_4(client: ZlibClient): Unit {
    let book = BookApi.info(client, 123456, "abcdef123456")
    let similar = BookApi.similarOf(client, book)
    println("相似图书 ${similar.size} 本")
}

// ===========================================================================
// 9.5 file
// ===========================================================================
func doc9_5(client: ZlibClient): Unit {
    let info = BookApi.file(client, 123456, "abcdef123456")
    println("文件名=${info.fileName()}")
    println("可下载=${info.available()} 允许=${info.allowDownload}")
    if (info.available()) {
        println("链接=${info.downloadLink}")
    }
}

// ===========================================================================
// 9.6 fileOf
// ===========================================================================
func doc9_6(client: ZlibClient): Unit {
    let book = BookApi.info(client, 123456, "abcdef123456")
    let info = BookApi.fileOf(client, book)
    println(info.fileName())
}

// ===========================================================================
// 9.7 formats
// ===========================================================================
func doc9_7(client: ZlibClient): Unit {
    let root = BookApi.formats(client, 123456, "abcdef123456")
    // 形状不稳定：用容错读取工具按需取
    for (item in arrayFieldOf(root, "formats")) {
        let obj = item.asObject()
        println("格式=${readString(obj, "extension")} 大小=${readInt(obj, "filesize")}")
    }
    // 也可以用强类型的扩展名判断
    let fileInfo = BookApi.file(client, 123456, "abcdef123456")
    println("服务端给的默认格式：${fileInfo.extension}")
}

// ===========================================================================
// 9.8 ~ 9.13 收藏 / 取消 / 删除 / 发送
// ===========================================================================
func doc9_8(client: ZlibClient): Unit {
    BookApi.save(client, 123456)
    println("已收藏")
}

func doc9_9(client: ZlibClient): Unit {
    let brief = BookInfoBrief()
    brief.id = 123456
    brief.hash = "abcdef123456"
    BookApi.saveBrief(client, brief)
}

func doc9_10(client: ZlibClient): Unit {
    BookApi.unsave(client, 123456)
    println("已取消收藏")
}

func doc9_11(client: ZlibClient, brief: BookInfoBrief): Unit {
    BookApi.unsaveBrief(client, brief)
}

func doc9_12(client: ZlibClient): Unit {
    BookApi.remove(client, 123456)
}

func doc9_13(client: ZlibClient): Unit {
    BookApi.sendTo(client, 123456, "abcdef123456", "kindle")
    println("已请求发送到 Kindle")
}

// ===========================================================================
// 9.14 download
// ===========================================================================
func doc9_14(client: ZlibClient): Unit {
    let dir = Path("./downloads")
    let info = BookApi.file(client, 123456, "abcdef123456")
    if (info.available()) {
        let bytes = BookApi.download(client, info, dir)
        println("已保存 ${info.fileName()}（${bytes} 字节）")
    }

    // 明确覆盖
    let info2 = BookApi.file(client, 654321, "deadbeef0000")
    let bytes2 = BookApi.download(client, info2, dir, overwrite: true)
    println("覆盖写入 ${bytes2} 字节")
}

// ===========================================================================
// 9.15 downloadBook
// ===========================================================================
func doc9_15(client: ZlibClient): Unit {
    let bytes = BookApi.downloadBook(client, 123456, "abcdef123456", Path("./downloads"))
    println("下载完成：${bytes} 字节")
}

// ===========================================================================
// 10.1 SearchApi.search
// ===========================================================================
func doc10_1(client: ZlibClient): Unit {
    // 基本搜索
    let page = SearchApi.search(client, "Rust")
    println("共 ${page.pagination.totalItems} 条，本页 ${page.size()} 本")
    for (book in page.books) {
        println("${book.title} / ${book.authorText()}")
    }

    // 带过滤
    let filtered = SearchApi.search(client, "functional programming",
        yearFrom: 2000,
        yearTo: 2024,
        languages: ["english", "german"],
        extensions: ["pdf", "epub"],
        order: "year",
        page: 1,
        limit: 10)
    if (let Some(first) <- filtered.first()) {
        println("第一条：${first.title}")
    }

    // 翻页
    var current = SearchApi.search(client, "Rust", page: 1, limit: 20)
    while (current.hasMore()) {
        println("下一页页码：${current.nextPage()}")
        current = SearchApi.search(client, "Rust", page: current.nextPage(), limit: 20)
        if (current.isEmpty()) {
            break
        }
    }
}

// ===========================================================================
// 10.2 mostPopular / 10.3 recently
// ===========================================================================
func doc10_2(client: ZlibClient): Unit {
    let popular = SearchApi.mostPopular(client)
    for (item in popular) {
        println("${item.title} / ${item.author}")
    }

    // 指定文案语言
    let popularEn = SearchApi.mostPopular(client, switchLanguage: "en")
    println("英文榜单 ${popularEn.size} 本")
}

func doc10_3(client: ZlibClient): Unit {
    let recent = SearchApi.recently(client)
    println("最近上传 ${recent.size} 本")
    if (!recent.isEmpty()) {
        println(recent[0].title)
    }
}

// ===========================================================================
// 11.1 UserApi.profile
// ===========================================================================
func doc11_1(client: ZlibClient): Unit {
    let user = UserApi.profile(client)
    println("${user.name} <${user.email}>")
    println("今日已用 ${user.downloadsToday} / 上限 ${user.downloadsLimit}")
    println("剩余 ${user.downloadsLeft()} 次")
    println("会员=${user.isPremium} 邮箱已确认=${user.confirmed}")
}

// ===========================================================================
// 11.2 UserApi.saved
// ===========================================================================
func doc11_2(client: ZlibClient): Unit {
    let saved = UserApi.saved(client)
    println("收藏 ${saved.pagination.totalItems} 本，共 ${saved.pagination.totalPages} 页")
    for (book in saved.books) {
        println(book.title)
        if (book.saved()) {
            println("  （已收藏标记）")
        }
    }

    // 按日期排序 + 翻页
    var page = UserApi.saved(client, order: "date", page: 1, limit: 20)
    while (page.hasMore()) {
        println("下一页：${page.nextPage()}")
        page = UserApi.saved(client, order: "date", page: page.nextPage(), limit: 20)
        if (page.isEmpty()) {
            break
        }
    }
}

// ===========================================================================
// 11.3 UserApi.downloaded
// ===========================================================================
func doc11_3(client: ZlibClient): Unit {
    let history = UserApi.downloaded(client)
    for (book in history.books) {
        println("${book.title} / ${book.filesizeString}")
    }

    let page2 = UserApi.downloaded(client, order: "year", page: 2, limit: 10)
    println("第 2 页 ${page2.size()} 条")
}

// ===========================================================================
// 11.4 UserApi.recommended
// ===========================================================================
func doc11_4(client: ZlibClient): Unit {
    let recommended = UserApi.recommended(client)
    for (item in recommended) {
        println("${item.title} / ${item.author}")
        // 要详情就再调一次
        let detail = BookApi.infoOf(client, item)
        println("  ${detail.sizeText()}")
    }
}

// ===========================================================================
// 11.5 UserApi.update
// ===========================================================================
func doc11_5(client: ZlibClient): Unit {
    // 只改昵称：其余字段不传 = 不修改
    UserApi.update(client, name: "新昵称")

    // 同时改 Kindle 邮箱
    UserApi.update(client, kindleEmail: "me@kindle.com")

    // 改密码
    UserApi.update(client, password: "new-strong-password")
}

// ===========================================================================
// 11.6 hideBanner / 11.7 donations
// ===========================================================================
func doc11_6(client: ZlibClient): Unit {
    UserApi.hideBanner(client)
    println("已关闭横幅")
}

func doc11_7(client: ZlibClient): Unit {
    let root = UserApi.donations(client)
    let total = readInt(root, "total")
    let donors = readString(root, "donors")
    println("total=${total} donors=${donors}")
    println(root.toString())
}

// ===========================================================================
// 12.1 InfoApi.site
// ===========================================================================
func doc12_1(client: ZlibClient): Unit {
    let root = InfoApi.site(client)
    println("站点名=${readString(root, "name")}")
    println("默认语言=${readString(root, "defaultLanguage")}")

    let siteEn = InfoApi.site(client, switchLanguage: "en")
    println(siteEn.toString())
}

// ===========================================================================
// 12.2 InfoApi.languages
// ===========================================================================
func doc12_2(client: ZlibClient): Unit {
    let root = InfoApi.languages(client)
    for (item in arrayFieldOf(root, "languages")) {
        let language = item.asObject()
        println("${readString(language, "name")} -> ${readString(language, "code")}")
    }

    // 取到的值可以直接传给搜索
    let langs: Array<String> = ["german", "english"]
    let page = SearchApi.search(client, "philosophy", languages: langs)
    println(page.size())
}

// ===========================================================================
// 12.3 InfoApi.extensions
// ===========================================================================
func doc12_3(client: ZlibClient): Unit {
    let root = InfoApi.extensions(client)
    let names = ArrayList<String>()
    for (item in arrayFieldOf(root, "extensions")) {
        names.add(readString(item.asObject(), "name"))
    }
    println("支持格式：${names.size} 种")

    // 用扩展名过滤搜索
    let page = SearchApi.search(client, "Rust", extensions: ["pdf", "epub"])
    println(page.size())
}

// ===========================================================================
// 12.4 InfoApi.domains
// ===========================================================================
func doc12_4(client: ZlibClient): Unit {
    let root = InfoApi.domains(client)
    for (item in arrayFieldOf(root, "domains")) {
        println(readString(item.asObject(), "domain"))
    }

    // 拿到的域名可以作为换站点的候选，但是否可达仍要探测
    if (checkAccess("https://another-mirror.example")) {
        let moved = client.withBaseUrl("https://another-mirror.example")
        println(moved.baseUrl)
    }
}

// ===========================================================================
// 12.5 InfoApi.plans
// ===========================================================================
func doc12_5(client: ZlibClient): Unit {
    let plans = InfoApi.plans(client)
    println(plans.toString())

    // 需要判断「当前账号是否付费」时，用 profile 的 isPremium 更可靠
    let user = UserApi.profile(client)
    println("会员=${user.isPremium}")
}

// ===========================================================================
// 13.1 ~ 13.6 数据模型
// ===========================================================================
func doc13_1(): Unit {
    let book = BookInfo.fromJson("{\"id\":1,\"title\":\"Rust\",\"filesize\":1234}")
    println(book.authorText())   // ""
    println(book.sizeText())     // 1 KB
    println(book.saved())        // false
    println(book.downloadable()) // false
}

func doc13_2(): Unit {
    let brief = BookInfoBrief.fromJson(
        "{\"id\":42,\"title\":\"书名\",\"author\":\"作者\",\"hash\":\"h42\"}")
    println(brief.webpage(baseUrl: "https://example.com"))
}

func doc13_3(): Unit {
    let user = ZlibUser.fromJson(
        "{\"id\":42,\"name\":\"读书人\",\"remix_userkey\":\"k\",\"downloads_today\":3,\"downloads_limit\":10}")
    println(user.downloadsLeft())   // 7
    let credential = user.toCredential()
    println(credential.isLoggedIn)  // true
}

func doc13_4(): Unit {
    let info = DownloadInfo.fromJson(
        "{\"downloadLink\":\"https://x/f/1\",\"description\":\"Rust 程序设计语言\",\"author\":\"Steve Klabnik\",\"extension\":\"epub\"}")
    println(info.available()) // true
    println(info.fileName())  // Rust 程序设计语言 (Steve Klabnik).epub
}

func doc13_6(): Unit {
    let page = BookPage.fromJson("""
{
  "books": [{"id": 1, "title": "第一本", "hash": "h1"}],
  "pagination": {"limit": 1, "current": 1, "total_items": 2, "total_pages": 2}
}
""")
    println("${page.size()} / ${page.pagination.totalItems}")
    if (let Some(book) <- page.first()) {
        println(book.title)
    }
}

// ===========================================================================
// 14.1 Query
// ===========================================================================
func doc14_1(client: ZlibClient): Unit {
    // 普通标量参数用 set（覆盖语义）
    let plain = Query().set("page", "1").set("page", "2").toArray()
    println("${plain.size}")

    // 数组参数用 addAll（保留重复 key）
    let array = Query().addAll("languages[]", ["german", "english"])
    println(array.encode())

    // 可选参数用 setIfSome
    let optional = Query().setIfSome("order", None).setIfSome("order", Some("year"))
    println(optional.encode())

    // 直接传给 client
    let q = Query().setIfSome("order", Some("date")).setInt("page", 1).setInt("limit", 20).toArray()
    let text = client.getRaw("/user/book/saved", query: q)
    println(text.size)

    // 其余方法：of / merge / size
    let merged = Query.of([("a", "1")]).merge([("b", "2")])
    println("${merged.size} ${merged.toArray().size}")
}

// ===========================================================================
// 14.2 编码工具
// ===========================================================================
func doc14_2(): Unit {
    println(formEncode([("a", "1"), ("a", "2")]))            // a=1&a=2
    println(withQuery("https://x.com/p", [("p", "1")]))      // https://x.com/p?p=1
    println(withQuery("https://x.com/p?q=0", [("p", "1")]))  // ...?q=0&p=1
    println(appendPair([("a", "1")], ("b", "2")).size)       // 2
    println(percentEncode("中文"))                            // %e4%b8%ad%e6%96%87
    println(percentEncode("a b"))                             // a%20b
}

// ===========================================================================
// 14.3 宽松 JSON 读取
// ===========================================================================
func doc14_3(): Unit {
    let obj = parseJsonObject(
        "{\"i\":\"12\",\"f\":\"1.5\",\"b\":1,\"s\":123,\"n\":null,\"o\":{\"x\":1},\"a\":[1,2]}")
    println(readInt(obj, "i"))                    // 12
    println(readInt(obj, "missing"))              // 0
    println(readIntOr(obj, "missing", 7))         // 7
    println(readFloat(obj, "f"))                  // 1.5
    println(readBool(obj, "b"))                   // true
    println(readString(obj, "s"))                 // 123
    println(readOptionalString(obj, "n").isNone()) // true
    println(readStringOr(obj, "missing", "fallback"))
    println(readBoolOr(obj, "missing", true))
    println(objectFieldOf(obj, "o").isSome())      // true
    println(arrayFieldOf(obj, "a").size)           // 2

    // 列表解码：一条脏数据不让整页作废
    let items = arrayFieldOf(parseJsonObject("{\"books\":[{\"id\":1},\"oops\",{\"id\":2}]}"), "books")
    let ids = decodeEach<Int64>(items) { item => readInt(item, "id") }
    let strict = decodeEachOrThrow<Int64>(items) { item => readInt(item, "id") }
    println("${ids.size} ${strict.size}")
}

// ===========================================================================
// 14.4 文本安全截断
// ===========================================================================
func doc14_4(): Unit {
    println(truncateRunes("中文abc", 2))             // 中文...
    println(truncateRunes("abcdef", 3, suffix: ""))  // abc
    println(truncateBytesSafe("中文", 4, suffix: "")) // 中
    println(truncateBytesSafe("abc", 2, suffix: ""))  // ab
}

// ===========================================================================
// 14.5 ZlibEnvelope
// ===========================================================================
func doc14_5(): Unit {
    let envelope = ZlibEnvelope.parse("{\"success\":1,\"books\":[{\"id\":1}]}")
    println(envelope.ok)                        // true
    println(envelope.arrayField("books").size)  // 1
    let root = envelope.unwrap()

    // 失败时自己处理，而不是让它抛
    let bad = ZlibEnvelope.parse("{\"success\":0,\"error\":\"Please login\"}")
    if (!bad.ok) {
        println(bad.errorText) // Please login
    }
    println("${root.toString().size} ${envelope.success} ${envelope.objectField("books").isNone()}")
}

// ===========================================================================
// 15.1 登录 → 收藏 → 换下载链接 → 落盘
// ===========================================================================
func doc15_1_fetchAndSave(domain: String, email: String, password: String,
    bookId: Int64, bookHash: String, dir: Path): Int64 {
    let guest = ZlibClient.create(baseUrl: domain)
    try {
        // 1) 登录并派生登录态客户端（guest 保持游客态）
        let mine = LoginApi.loginClient(guest, email, password)

        // 2) 收藏（只需要 id）
        BookApi.save(mine, bookId)

        // 3) 换签名下载链接（带时效，过期要重换）
        let info = BookApi.file(mine, bookId, bookHash)
        if (!info.available()) {
            return 0
        }

        // 4) 落盘：目录自动创建，同名默认自动改名
        let bytes = BookApi.download(mine, info, dir)
        println("已保存 ${info.fileName()}（${bytes} 字节）")
        return bytes
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 15.2 搜索并翻页
// ===========================================================================
func doc15_2_searchAll(client: ZlibClient, message: String, maxPages: Int64): Int64 {
    var current: Int64 = 1
    var pages: Int64 = 0
    while (pages < maxPages) {
        let page = SearchApi.search(client, message, page: current, limit: 20)
        for (book in page.books) {
            // 搜索返回的 books 是完整 BookInfo，不需要再逐本调 info
            println("${book.title} / ${book.authorText()} / ${book.sizeText()}")
        }
        pages++
        if (!page.hasMore()) {
            break
        }
        current = page.nextPage()
    }
    pages
}

// ===========================================================================
// 15.3 域名失效换镜像并重试
// ===========================================================================
func doc15_3_searchWithRetry(domain: String, message: String): Int64 {
    var client = ZlibClient.create(baseUrl: domain)
    try {
        try {
            return SearchApi.search(client, message).size()
        } catch (err: ZlibError) {
            println("第一次失败：${err.detail}")
        }

        // 重新探测可用站点（只返回结果，不改全局状态）
        match (resolveZlibHost()) {
            case Some(host) =>
                let moved = client.withBaseUrl(host.url)
                return SearchApi.search(moved, message).size()
            case None => return 0
        }
    } finally {
        client.close()
    }
}

// ===========================================================================
// 15.4 按语言 / 年份 / 格式过滤
// ===========================================================================
func doc15_4(client: ZlibClient): Unit {
    let page = SearchApi.search(client, "algorithms",
        yearFrom: 2010,
        yearTo: 2024,
        languages: ["english", "german", "french"],
        extensions: ["pdf", "epub"],
        order: "year")
    println("命中 ${page.pagination.totalItems} 条")
}

// ===========================================================================
// 15.5 保存凭证、下次复用
// ===========================================================================
func doc15_5_remember(result: LoginResult): String {
    result.credential.toCookieHeader()
}

func doc15_5_restore(domain: String, savedCookie: String): ZlibClient {
    let credential = ZlibCredential.fromCookieString(savedCookie)
    ZlibClient.create(baseUrl: domain, credential: credential)
}

func doc15_5_restoreByFields(domain: String, userId: String, userKey: String,
    language: String): ZlibClient {
    let credential = ZlibCredential(userId: userId, userKey: userKey, siteLanguage: language)
    ZlibClient.create(baseUrl: domain, credential: credential)
}

// ===========================================================================
// 15.6 游客与登录客户端并存
// ===========================================================================
func doc15_6(): Unit {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        // 游客搜索：不带 remix 凭证，结果不个性化
        let publicResult = SearchApi.search(guest, "Rust")

        // 登录客户端：共享连接池，但请求带凭证
        let mine = LoginApi.loginClient(guest, "you@example.org", "your-password")
        let personalResult = SearchApi.search(mine, "Rust")

        println("游客 ${publicResult.size()} 本 / 登录 ${personalResult.size()} 本")
    } finally {
        guest.close()
    }
}

// ===========================================================================
// 15.7 用底层方法打未覆盖的接口
// ===========================================================================
func doc15_7_rawInfo(client: ZlibClient): String {
    // 未封装的 GET：先看文本，确认是 JSON 再解析
    let text = client.getRaw("/info/extensions")
    println(text)

    // 自己解析信封并处理 success
    let envelope = client.getEnvelope("/info/languages")
    if (envelope.ok) {
        return envelope.root.toString()
    }
    envelope.errorText
}

// ===========================================================================
// 入口：不执行任何联网示例，只做「被引用即编译」的检查
// ===========================================================================
main(): Int64 {
    println("zlibraryAPI4CJ doccheck: 所有文档示例已通过编译检查")
    0
}
