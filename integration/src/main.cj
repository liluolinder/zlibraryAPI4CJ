/*
 * zlibraryAPI4CJ 真实网络集成测试。
 *
 * 与 `doccheck/` 的分工：
 * - `doccheck/` 只验证「文档示例能编译」，不联网；
 * - 本工程验证「接口真的还能用」：用 2026-11-10 实测可用的镜像
 *   `https://zh.eva101.ru` 跑真实请求，检查返回数据与错误映射，
 *   并现场验证 2.1.0 的「自定义站失败 → 种子站换站 → 自动重试」。
 *
 * 运行：
 *   cd integration
 *   cjpm run
 *
 * 注意：本工程会真实访问网络。镜像失效时先跑
 * `InfoApi`/`probeSite` 相关检查看域名是否还通；域名换了就改 `DOMAIN`。
 *
 * 验收：`cjpm run` 输出 `RESULT: PASSED=n FAILED=0` 且退出码 0。
 *
 * 可选环境变量（账号密码只放环境变量，绝不写进仓库）：
 *   ZLIB_TEST_EMAIL / ZLIB_TEST_PASSWORD
 *       登录后链路：登录 → profile → 收藏/推荐/历史 → 收藏/取消收藏 → 换下载链接
 *       →（可选）真实下载并清理。
 *   ZLIB_TEST_ONLY_AUTH=1        只跑登录后链路（跳过探测/换站等前置检查）
 *   ZLIB_TEST_STAGE=login|credential|token|read|write|file|cleanup
 *       分段调试；cleanup 用于清理被中断的收藏测试留下的书
 *   ZLIB_TEST_DOWNLOAD=1         真正下载一个文件（消耗 1 次每日配额，默认跳过）
 */
package zlibraryAPI4CJ_integration

import std.collection.*
import std.env.*
import std.fs.*
import std.time.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*
import zlibraryAPI4CJ.book.*
import zlibraryAPI4CJ.search.*
import zlibraryAPI4CJ.user.*
import zlibraryAPI4CJ.info.*

/** 实测可用的镜像（2026-11-10）。镜像会轮换，失效时改这里。 */
let DOMAIN: String = "https://zh.eva101.ru"

/** 测试期间的假自定义站（DNS 必定失败，用来触发换站）。 */
let DEAD_DOMAIN: String = "https://definitely-dead.invalid"

/** 断言计数器。 */
class Checks {
    public var passed: Int64 = 0
    public var failed: Int64 = 0

    public func check(name: String, ok: Bool, detail!: String = ""): Unit {
        let suffix = if (detail.isEmpty()) {
            ""
        } else {
            " — ${detail}"
        }
        if (ok) {
            passed++
            println("[PASS] ${name}${suffix}")
        } else {
            failed++
            println("[FAIL] ${name}${suffix}")
        }
    }

    /** 有失败返回 1，全通过返回 0。 */
    public func summary(): Int64 {
        println("")
        println("RESULT: PASSED=${passed} FAILED=${failed}")
        if (failed == 0) {
            0
        } else {
            1
        }
    }
}

main(): Int64 {
    logStep("main start")
    println("=== zlibraryAPI4CJ live integration ===")
    println("domain: ${DOMAIN}")
    println("")

    let checks = Checks()
    // 只调试登录后链路时设 ZLIB_TEST_ONLY_AUTH=1（跳过较慢的换站等前置检查）
    var onlyAuth = false
    if (let Some(flag) <- getVariable("ZLIB_TEST_ONLY_AUTH")) {
        onlyAuth = flag.trimAscii() == "1"
    }
    if (onlyAuth) {
        println("[MODE] 只跑登录后链路")
        checkAuthenticatedFromEnv(checks)
        return checks.summary()
    }
    logStep("base: probe")
    checkProbe(checks)
    logStep("base: search")
    checkSearch(checks)
    logStep("base: book")
    checkBook(checks)
    logStep("base: info")
    checkInfo(checks)
    logStep("base: error-mapping")
    checkErrorMapping(checks)
    logStep("base: auto-switch")
    checkAutoSwitch(checks)
    // 登录后链路：只有设置了 ZLIB_TEST_EMAIL / ZLIB_TEST_PASSWORD 才执行，
    // 避免把真实账号写进仓库（见 integration/README 说明）。
    checkAuthenticatedFromEnv(checks)
    checks.summary()
}

// ---------------------------------------------------------------------------
// 登录后链路（可选）：邮箱密码登录 → profile → 收藏/取消收藏 → 下载 → 清理
// ---------------------------------------------------------------------------

func checkAuthenticatedFromEnv(checks: Checks): Unit {
    let email = getVariable("ZLIB_TEST_EMAIL")
    let password = getVariable("ZLIB_TEST_PASSWORD")
    match (email) {
        case Some(mail) =>
            match (password) {
                case Some(pwd) => checkAuthenticated(checks, mail, pwd)
                case None => println("[SKIP] 未设置 ZLIB_TEST_PASSWORD，跳过登录后链路")
            }
        case None => println("[SKIP] 未设置 ZLIB_TEST_EMAIL，跳过登录后链路")
    }
}

func checkAuthenticated(checks: Checks, email: String, password: String): Unit {
    let stage = authStage()
    logStep("checkAuthenticated start, stage=${stage}")
    // 登录后链路会下载文件：读/总超时放宽（下载本身用 config.downloadTimeout）
    // 实测该镜像偶发 read timeout，API 请求保留自动重试（maxAttempts=3）
    let config = ZlibClientConfig()
    config.readTimeout = Duration.second * 45
    config.totalTimeout = Duration.second * 180
    config.maxAttempts = 3
    config.downloadTimeout = Duration.second * 90
    let guest = ZlibClient.create(baseUrl: DOMAIN, seeds: [DOMAIN], config: config)
    try {
        // 1) 邮箱 + 密码登录（不打印密码，邮箱只打印掩码）
        logStep("login begin")
        let result = LoginApi.login(guest, email, password)
        checks.check("邮箱密码登录成功", result.user.id > 0,
            detail: "uid=${result.user.id} email=${maskEmail(result.user.email)}")
        checks.check("登录返回可用凭证", result.credential.isLoggedIn,
            detail: "userId=${result.credential.userId}")
        checks.check("下载配额可读", result.user.downloadsLimit > 0,
            detail: "今日剩余 ${result.user.downloadsLeft()}/${result.user.downloadsLimit}")
        logStep("login done, uid=${result.user.id}")
        if (stage == "login") {
            return
        }

        // 2) 启动时直接带凭证：验证凭证真的被加载（bbapi 曾出现「传了但没生效」的 bug）
        logStep("startup-credential begin")
        checkStartupCredential(checks, result.credential, result.user.id)
        logStep("startup-credential done")
        if (stage == "credential") {
            return
        }

        // 3) 派生登录态客户端（与 guest 共享连接池）
        let client = result.withClient(guest)

        // 2.1) 清理被中断的测试留下的收藏痕迹（仅在 ZLIB_TEST_STAGE=cleanup 时执行）
        if (stage == "cleanup") {
            let artifactId: Int64 = 17309781
            let before = UserApi.saved(client, page: 1, limit: 20).pagination.totalItems
            let detail = BookApi.info(client, artifactId, "625607")
            if (detail.saved()) {
                BookApi.unsave(client, artifactId)
            }
            let after = UserApi.saved(client, page: 1, limit: 20).pagination.totalItems
            checks.check("清理测试遗留收藏", !detail.saved() || after < before,
                detail: "收藏数 before=${before} after=${after} artifact=${artifactId}")
            return
        }

        // 3) 用返回的 remix 凭证再登录一次（不重复密码，验证 token 登录路径）
        logStep("token login begin")
        let tokenSession = LoginApi.loginWithToken(guest, result.user.id,
            result.credential.userKey)
        checks.check("remix 凭证登录（loginWithToken）", tokenSession.credential.isLoggedIn,
            detail: "uid=${tokenSession.user.id}")
        logStep("token login done")
        if (stage == "token") {
            return
        }

        // 4) profile / 只读接口
        logStep("read begin")
        let profile = UserApi.profile(client)
        checks.check("登录后 profile 成功", profile.id == result.user.id,
            detail: "name=${profile.name} 剩余下载=${profile.downloadsLeft()}")
        let page = SearchApi.search(client, "rust", limit: 3)
        checks.check("登录态搜索可用", page.size() > 0, detail: "${page.size()} 条")
        logStep("saved/recommended/downloaded begin")
        let saved = UserApi.saved(client, page: 1, limit: 5)
        checks.check("收藏列表可读", true,
            detail: "本页 ${saved.size()} 本 / 共 ${saved.pagination.totalItems} 本")
        let recommended = UserApi.recommended(client)
        checks.check("个性化推荐可读", recommended.size > 0, detail: "${recommended.size} 本")
        let downloaded = UserApi.downloaded(client, page: 1, limit: 5)
        checks.check("下载历史可读", true,
            detail: "本页 ${downloaded.size()} 本 / 共 ${downloaded.pagination.totalItems} 本")
        logStep("read done")
        if (stage == "read") {
            return
        }

        // 5) 收藏 / 取消收藏（可逆；如果该书本来就已收藏则跳过，避免改坏用户数据）
        logStep("save/unsave begin")
        checkSaveUnsave(checks, client)
        logStep("save/unsave done")
        if (stage == "write") {
            return
        }

        // 6) 换下载链接 →（可选）真正下载 → 校验 → 清理
        logStep("download-link begin")
        checkDownload(checks, client)
        logStep("download-link done")

        // 7) Cookie 回捞（信息性输出，不参与断言：不同服务端是否 Set-Cookie 不一致）
        println("       登录后 credentialFromCookies().isLoggedIn=" +
            "${client.credentialFromCookies().isLoggedIn}")
    } catch (err: ZlibError) {
        logStep("EXCEPTION ZlibError: ${err}")
        checks.check("登录后链路", false, detail: err.toString())
    } finally {
        logStep("checkAuthenticated end")
        guest.close()
    }
}

/**
 * 启动时直接带凭证创建客户端：凭证必须**真正加载到请求里**，而不只是存了个字段。
 *
 * 背景：bbapi 曾出现「`create(credential: ...)` 传了参数但请求没带凭证」的 bug。
 * 根因是 LinderHttp 的 Cookie 存储在**收到任意 Set-Cookie 后**会用存储内容覆盖
 * 调用方手写的 Cookie 头；新客户端若只靠手写 Cookie，第二次请求就会丢凭证。
 * 这里用一个全新的客户端：profile → 普通请求（触发 Set-Cookie）→ 再 profile，
 * 连续三次都必须保持登录态。
 */
func checkStartupCredential(checks: Checks, credential: ZlibCredential,
    expectedUserId: Int64): Unit {
    // A. create(credential:)：全新 HttpClient / 空 Cookie 存储
    let byCreate = ZlibClient.create(baseUrl: DOMAIN, credential: credential, seeds: [DOMAIN])
    try {
        let first = UserApi.profile(byCreate)
        checks.check("启动凭证·首次 profile 生效", first.id == expectedUserId,
            detail: "uid=${first.id}")
        // 普通 GET 会触发服务端下发 Set-Cookie（实测为 bsrv=...）
        let _ = SearchApi.search(byCreate, "rust", limit: 2)
        let second = UserApi.profile(byCreate)
        checks.check("启动凭证·普通请求后仍生效", second.id == expectedUserId,
            detail: "uid=${second.id}")
        let third = UserApi.profile(byCreate)
        checks.check("启动凭证·连续请求仍生效", third.id == expectedUserId,
            detail: "uid=${third.id}")
        checks.check("client.credential 已保存", byCreate.credential.userId == credential.userId,
            detail: byCreate.credential.userId)
    } catch (err: ZlibError) {
        checks.check("启动凭证·create(credential:)", false, detail: err.toString())
    } finally {
        byCreate.close()
    }

    // B. createWithSites(credential:)：共享 ZlibSites 的启动路径
    let sites = ZlibSites(customUrl: DOMAIN)
    let bySites = ZlibClient.createWithSites(sites, credential: credential)
    try {
        let me = UserApi.profile(bySites)
        checks.check("启动凭证·createWithSites 生效", me.id == expectedUserId,
            detail: "uid=${me.id}")
    } catch (err: ZlibError) {
        checks.check("启动凭证·createWithSites", false, detail: err.toString())
    } finally {
        bySites.close()
    }

    // C. cookie 串往返（持久化后下次启动的典型路径）
    let restored = ZlibCredential.fromCookieString(credential.toCookieHeader())
    let byCookie = ZlibClient.create(baseUrl: DOMAIN, credential: restored)
    try {
        let me = UserApi.profile(byCookie)
        checks.check("启动凭证·fromCookieString 往返生效", me.id == expectedUserId,
            detail: "uid=${me.id}")
        checks.check("fromCookieString 还原 userId",
            restored.userId == credential.userId, detail: restored.userId)
    } catch (err: ZlibError) {
        checks.check("启动凭证·fromCookieString 往返", false, detail: err.toString())
    } finally {
        byCookie.close()
    }

    // D. 游客对照：必须 NotLoggedIn，证明服务端不是对谁都返回 profile
    let anon = ZlibClient.create(baseUrl: DOMAIN)
    try {
        let me = UserApi.profile(anon)
        checks.check("启动凭证·游客对照应 NotLoggedIn", false, detail: "uid=${me.id}")
    } catch (err: ZlibError) {
        checks.check("启动凭证·游客对照应 NotLoggedIn",
            err.kind == ZlibErrorKind.NotLoggedIn, detail: err.kind.toString())
    } finally {
        anon.close()
    }
}

func checkSaveUnsave(checks: Checks, client: ZlibClient): Unit {
    let page = SearchApi.search(client, "rust", limit: 5)
    let book = match (page.first()) {
        case Some(value) => value
        case None => return
    }
    let detail = BookApi.info(client, book.id, book.hash)
    logStep("save/unsave: book id=${book.id} alreadySaved=${detail.saved()}")
    if (detail.saved()) {
        // 用户自己的收藏，不做写操作
        checks.check("收藏/取消收藏（跳过：该书本来就在收藏里）", true,
            detail: "id=${book.id}")
        return
    }
    BookApi.save(client, book.id)
    var savedNow = BookApi.info(client, book.id, book.hash).saved()
    if (!savedNow) {
        sleep(Duration.second * 2)
        savedNow = BookApi.info(client, book.id, book.hash).saved()
    }
    checks.check("收藏成功（详情回显已收藏）", savedNow, detail: "id=${book.id}")

    BookApi.unsave(client, book.id)
    var unsaved = !BookApi.info(client, book.id, book.hash).saved()
    if (!unsaved) {
        sleep(Duration.second * 2)
        unsaved = !BookApi.info(client, book.id, book.hash).saved()
    }
    checks.check("取消收藏成功（状态已还原）", unsaved, detail: "id=${book.id}")
}

func checkDownload(checks: Checks, client: ZlibClient): Unit {
    let me = UserApi.profile(client)
    if (me.downloadsLeft() <= 0) {
        checks.check("下载测试（跳过：今日下载配额已用完）", true,
            detail: "limit=${me.downloadsLimit} today=${me.downloadsToday}")
        return
    }

    // 从热门榜里挑一本有可用格式的书，并选其中最小的文件（少占带宽/配额）
    var chosen: ?BookFormat = None
    let popular = SearchApi.mostPopular(client)
    var index: Int64 = 0
    while (index < popular.size && index < 2) {
        let brief = popular[index]
        println("       扫描格式：id=${brief.id} hash=${brief.hash} ...")
        let formats = BookApi.formats(client, brief.id, brief.hash)
        println("       该书可用格式：${formats.size} 个")
        for (format in formats) {
            if (format.filesize <= 0) {
                continue
            }
            chosen = match (chosen) {
                case Some(current) => if (format.filesize < current.filesize) {
                    Some(format)
                } else {
                    Some(current)
                }
                case None => Some(format)
            }
        }
        index++
    }
    let target = match (chosen) {
        case Some(value) => value
        case None =>
            checks.check("找到可下载格式", false)
            return
    }
    checks.check("找到可下载格式", true,
        detail: "${target.extension} ${target.sizeText()} id=${target.id}")

    let info = BookApi.file(client, target.id, target.hash)
    checks.check("file() 返回可用下载链接", info.available(), detail: info.fileName())
    if (!info.available()) {
        return
    }
    // 下载走独立域名/CDN（不是站点域名，也不会换站）；打印主机便于诊断
    println("       下载主机: ${hostOf(info.downloadLink)}")
    logStep("file() ok host=${hostOf(info.downloadLink)} name=${info.fileName()}")
    if (authStage() == "file") {
        return
    }

    // 真正下载会消耗 1 次每日配额且依赖下载域名可达，默认不跑；
    // 需要完整验证时设置环境变量 ZLIB_TEST_DOWNLOAD=1。
    var doDownload = false
    if (let Some(flag) <- getVariable("ZLIB_TEST_DOWNLOAD")) {
        doDownload = flag.trimAscii() == "1"
    }
    if (!doDownload) {
        checks.check("下载测试（跳过：未设置 ZLIB_TEST_DOWNLOAD=1）", true,
            detail: "file() 链接已获取，实际下载未执行")
        return
    }

    let dirName = "target\\authenticated_downloads"
    let dir = Path(dirName)
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    let before = UserApi.profile(client).downloadsLeft()
    let bytes = BookApi.download(client, info, dir, overwrite: true)
    let after = UserApi.profile(client).downloadsLeft()
    let targetPath = dir.join(info.fileName())
    checks.check("下载字节>0", bytes > 0,
        detail: "${bytes} 字节 → ${dirName}/${info.fileName()}")
    checks.check("文件已落盘", exists(targetPath), detail: "${dirName}/${info.fileName()}")
    checks.check("下载配额扣减（前后对比）", after <= before,
        detail: "下载前剩余 ${before}，下载后剩余 ${after}")

    // 不在工作区留受版权保护的文件
    removeIfExists(targetPath)
    checks.check("已清理下载文件", !exists(targetPath), detail: "${dirName}/${info.fileName()}")
}

/** 邮箱掩码：只保留前两位与 @ 之后部分，避免日志泄露完整邮箱。 */
func maskEmail(email: String): String {
    var result = "***"
    if (let Some(index) <- email.indexOf("@")) {
        if (index > 2) {
            result = "${email[0..2]}***${email[index..email.size]}"
        } else {
            result = "***${email[index..email.size]}"
        }
    }
    result
}

/** 只取 URL 的 `scheme://host` 部分（用于打印下载主机，不泄露 token/路径）。 */
func hostOf(url: String): String {
    let schemeParts = url.split("://")
    if (schemeParts.size < 2) {
        return url
    }
    let pathParts = schemeParts[1].split("/")
    pathParts[0]
}

/**
 * 把步骤写进 `integration/target/auth_debug.log`。
 *
 * 为什么不用 println：Windows 上 stdout 被重定向时会缓冲，进程异常退出时
 * 日志会整段丢失；File.appendTo 每次调用即落盘，能定位「崩在哪一步」。
 */
func logStep(text: String): Unit {
    File.appendTo(Path("target\\auth_debug.log"), "[STEP] ${text}\n".toArray())
}

/** 登录链路的分段调试开关（ZLIB_TEST_STAGE=login/token/read/write/file/all）。 */
func authStage(): String {
    var stage = "all"
    if (let Some(value) <- getVariable("ZLIB_TEST_STAGE")) {
        stage = value.trimAscii()
    }
    stage
}

// ---------------------------------------------------------------------------
// 站点探测
// ---------------------------------------------------------------------------

func checkProbe(checks: Checks): Unit {
    var probe = probeSite(DOMAIN, timeoutSeconds: 15)
    // 网络偶发抖动：失败时重试两次再判定
    var probeAttempt: Int64 = 0
    while (!probe.reachable && probeAttempt < 2) {
        sleep(Duration.second * 2)
        probe = probeSite(DOMAIN, timeoutSeconds: 15)
        probeAttempt++
    }
    // 该镜像 HEAD / 返回 503（维护页）但 eapi 正常，所以 503 也算可达
    checks.check("probeSite 可达", probe.reachable,
        detail: "status=${probe.status} attempts=${probeAttempt + 1}")
    // 网络偶发抖动：最多重试 3 次再判定（HEAD 有时会慢到超过默认超时）
    var access = false
    var attempt: Int64 = 0
    while (attempt < 3 && !access) {
        access = checkAccess(DOMAIN)
        if (!access) {
            sleep(Duration.second * 2)
        }
        attempt++
    }
    checks.check("checkAccess", access, detail: "url=${probe.url} attempts=${attempt}")
    let resolved = resolveZlibHost(candidates: [DOMAIN])
    var resolvedHost = resolved
    var resolveAttempt: Int64 = 0
    while (resolvedHost.isNone() && resolveAttempt < 2) {
        sleep(Duration.second * 2)
        resolvedHost = resolveZlibHost(candidates: [DOMAIN])
        resolveAttempt++
    }
    checks.check("resolveZlibHost 命中", resolvedHost.isSome(),
        detail: if (resolvedHost.isSome()) {
            resolvedHost.getOrThrow().url
        } else {
            "None"
        })
}

// ---------------------------------------------------------------------------
// 搜索 / 榜单
// ---------------------------------------------------------------------------

func checkSearch(checks: Checks): Unit {
    let client = ZlibClient.create(baseUrl: DOMAIN, seeds: [DOMAIN])
    try {
        let page = SearchApi.search(client, "rust", limit: 5)
        checks.check("search 非空", page.size() > 0, detail: "size=${page.size()}")
        checks.check("search 总数>0", page.pagination.totalItems > 0,
            detail: "total=${page.pagination.totalItems} pages=${page.pagination.totalPages}")
        checks.check("search 当前页=1", page.pagination.current == 1,
            detail: "${page.pagination.current}")

        match (page.first()) {
            case Some(book) =>
                checks.check("search 首条 title 非空", !book.title.isEmpty(), detail: book.title)
                checks.check("search 首条 hash 非空", !book.hash.isEmpty(), detail: book.hash)
                checks.check("search 首条 extension 非空", !book.extension.isEmpty(),
                    detail: book.extension)
                checks.check("search 首条 author 非空", !book.authorText().isEmpty(),
                    detail: book.authorText())
            case None => checks.check("search 首条存在", false)
        }

        let popular = SearchApi.mostPopular(client)
        checks.check("mostPopular 非空", popular.size > 0, detail: "size=${popular.size}")
        if (popular.size > 0) {
            let brief = popular[0]
            checks.check("mostPopular 首条 id>0", brief.id > 0, detail: "${brief.id}")
            checks.check("mostPopular 首条 hash 非空", !brief.hash.isEmpty(), detail: brief.hash)
            // 实测列表项带 url（相对地址）；webpage() 会优先用它
            checks.check("mostPopular 首条 webpage 可拼", brief.webpage(baseUrl: DOMAIN)
                .contains("/book/"), detail: brief.webpage(baseUrl: DOMAIN))
        }

        let page2 = SearchApi.search(client, "rust", page: 2, limit: 5)
        checks.check("search 第 2 页成功", page2.size() > 0, detail: "size=${page2.size()}")
    } catch (err: ZlibError) {
        checks.check("search 请求", false, detail: err.toString())
    } finally {
        client.close()
    }
}

// ---------------------------------------------------------------------------
// 图书详情 / 相似 / 格式 / 未登录错误映射
// ---------------------------------------------------------------------------

func checkBook(checks: Checks): Unit {
    let client = ZlibClient.create(baseUrl: DOMAIN)
    try {
        let page = SearchApi.search(client, "rust", limit: 5)
        let book = match (page.first()) {
            case Some(value) => value
            case None => throw ZlibError.apiFailure("/book", "搜索没有返回图书")
        }
        let detail = BookApi.info(client, book.id, book.hash)
        checks.check("book info title 非空", !detail.title.isEmpty(), detail: detail.title)
        checks.check("book info hash 匹配", detail.hash == book.hash,
            detail: "${detail.hash} vs ${book.hash}")
        checks.check("book info 文件大小>0", detail.filesize > 0, detail: "${detail.filesize}")

        logStep("book: similar")
        let similar = BookApi.similar(client, book.id, book.hash)
        checks.check("similar 非空", similar.size > 0, detail: "size=${similar.size}")

        logStep("book: formats")
        let formats = BookApi.formats(client, book.id, book.hash)
        // 服务端对部分书确实返回空列表（2026-11-10 实测 17309781/625607 → books:[]），
        // 所以这里先验证「能正常解析」，非空时再校验每项字段。
        checks.check("formats 解析正常", true, detail: "size=${formats.size}")
        var allHaveExtension = true
        var extensionSummary = ""
        for (format in formats) {
            if (format.extension.isEmpty()) {
                allHaveExtension = false
            }
            if (extensionSummary.size < 80) {
                extensionSummary += "${format.extension} "
            }
        }
        if (formats.size > 0) {
            checks.check("formats 每项有扩展名", allHaveExtension,
                detail: extensionSummary.trimAscii())
        }
        // 换一本已知有多格式版本的书，验证非空解析路径
        logStep("book: known-formats")
        let knownFormats = BookApi.formats(client, 24126585, "217fd6")
        checks.check("已知书 formats 非空", knownFormats.size > 0,
            detail: "size=${knownFormats.size}")
        if (knownFormats.size > 0) {
            checks.check("formats 首项有扩展名", !knownFormats[0].extension.isEmpty(),
                detail: knownFormats[0].toString())
        }

        // 匿名访问下载信息：实测返回 HTTP 400 + {"success":0,"error":"登录到您的账户"}
        var caught = false
        var kind = ZlibErrorKind.Transport
        var message = ""
        logStep("book: anonymous file()")
        try {
            let info = BookApi.file(client, book.id, book.hash)
            checks.check("匿名 file() 不应该成功", false, detail: info.fileName())
        } catch (err: ZlibError) {
            caught = true
            kind = err.kind
            message = err.serverMessage
        }
        checks.check("匿名 file() → NotLoggedIn", caught && kind == ZlibErrorKind.NotLoggedIn,
            detail: "kind=${kind} msg=${message}")
    } catch (err: ZlibError) {
        checks.check("book 请求", false, detail: err.toString())
    } finally {
        client.close()
    }
}

// ---------------------------------------------------------------------------
// 站点信息（实测响应形状）
// ---------------------------------------------------------------------------

func checkInfo(checks: Checks): Unit {
    let client = ZlibClient.create(baseUrl: DOMAIN)
    try {
        let extensions = arrayFieldOf(InfoApi.extensions(client), "extensions")
        checks.check("info/extensions 非空", extensions.size > 0, detail: "size=${extensions.size}")
        var hasPdf = false
        for (item in extensions) {
            match (item.kind()) {
                case JsString => if (item.asString().getValue() == "pdf") {
                    hasPdf = true
                }
                case _ => ()
            }
        }
        checks.check("info/extensions 含 pdf", hasPdf)

        match (objectFieldOf(InfoApi.languages(client), "languages")) {
            case Some(languages) =>
                checks.check("info/languages 非空", languages.size() > 0,
                    detail: "${languages.size()} 种")
            case None => checks.check("info/languages 是对象", false)
        }

        let domains = extractDomainList(InfoApi.domains(client))
        checks.check("info/domains 可解析", domains.size > 0, detail: "${domains.size} 个")
        var domainText = ""
        for (domain in domains) {
            domainText += "${domain} "
        }
        println("       候选域名: ${domainText.trimAscii()}")

        let siteRoot = InfoApi.site(client)
        let bookCount = readInt(siteRoot, "books")
        checks.check("info 站点书籍数>0", bookCount > 0, detail: "${bookCount} 本")
    } catch (err: ZlibError) {
        checks.check("info 请求", false, detail: err.toString())
    } finally {
        client.close()
    }
}

// ---------------------------------------------------------------------------
// 错误映射（未登录 / 密码错误）
// ---------------------------------------------------------------------------

func checkErrorMapping(checks: Checks): Unit {
    let client = ZlibClient.create(baseUrl: DOMAIN)
    try {
        var profileCaught = false
        var profileKind = ZlibErrorKind.ApiFailure
        try {
            let profile = UserApi.profile(client)
            checks.check("匿名 profile 不应该成功", false, detail: "${profile.id}")
        } catch (err: ZlibError) {
            profileCaught = true
            profileKind = err.kind
        }
        checks.check("匿名 profile → NotLoggedIn",
            profileCaught && profileKind == ZlibErrorKind.NotLoggedIn,
            detail: profileKind.toString())

        var loginCaught = false
        var loginMessage = ""
        var loginKind = ZlibErrorKind.Transport
        try {
            LoginApi.login(client, "fake@example.com", "definitely-wrong-password")
            checks.check("错误密码登录不应该成功", false)
        } catch (err: ZlibError) {
            loginCaught = true
            loginMessage = err.serverMessage
            loginKind = err.kind
        }
        checks.check("错误密码 → ApiFailure", loginCaught && loginKind == ZlibErrorKind.ApiFailure,
            detail: loginMessage)
    } catch (err: ZlibError) {
        checks.check("错误映射检查", false, detail: err.toString())
    } finally {
        client.close()
    }
}

// ---------------------------------------------------------------------------
// 2.1.0 新能力：自定义站失败 → 种子站换新地址 → 覆盖自定义站 → 自动重试
// ---------------------------------------------------------------------------

func checkAutoSwitch(checks: Checks): Unit {
    let config = ZlibClientConfig()
    config.readTimeout = Duration.second * 8
    config.totalTimeout = Duration.second * 12
    config.maxAttempts = 2
    // 故意把自定义站设成 DNS 必失败域名，种子站设成实测可用镜像
    let sites = ZlibSites(customUrl: DEAD_DOMAIN, seeds: [DOMAIN],
        refreshInterval: Duration.second * 0)
    let client = ZlibClient.createWithSites(sites, config: config)
    try {
        // 第一步：单独验证「种子站刷新」能拿到新地址并覆盖自定义站
        let refreshed = client.refreshSite(force: true)
        checks.check("refreshSite(force) 换站成功", refreshed, detail: client.currentSiteUrl())
        checks.check("刷新后站点=种子站", client.currentSiteUrl() == DOMAIN,
            detail: client.currentSiteUrl())
        checks.check("换站计数>=1", client.sites.refreshCount() >= 1,
            detail: "${client.sites.refreshCount()}")

        // 第二步：把自定义站改回死站，验证「请求失败 → 自动换站 → 自动重试」
        client.setCustomSite(DEAD_DOMAIN)
        let page = SearchApi.search(client, "rust", limit: 3)
        checks.check("死自定义站 → 自动换站后搜索成功", page.size() > 0,
            detail: "size=${page.size()}")
        checks.check("自动换站覆盖自定义站", client.currentSiteUrl() == DOMAIN,
            detail: client.currentSiteUrl())
        let snapshot = client.sites.snapshot()
        checks.check("snapshot.currentUrl 同步", snapshot.currentUrl == DOMAIN,
            detail: snapshot.currentUrl)
    } catch (err: ZlibError) {
        checks.check("自动换站", false, detail: err.toString())
    } finally {
        client.close()
    }
}
