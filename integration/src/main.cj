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
 */
package zlibraryAPI4CJ_integration

import std.collection.*
import std.time.*
import stdx.encoding.json.*
import linderHttp.*
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
    println("=== zlibraryAPI4CJ live integration ===")
    println("domain: ${DOMAIN}")
    println("")

    let checks = Checks()
    checkProbe(checks)
    checkSearch(checks)
    checkBook(checks)
    checkInfo(checks)
    checkErrorMapping(checks)
    checkAutoSwitch(checks)
    checks.summary()
}

// ---------------------------------------------------------------------------
// 站点探测
// ---------------------------------------------------------------------------

func checkProbe(checks: Checks): Unit {
    let probe = probeSite(DOMAIN, timeoutSeconds: 15)
    // 该镜像 HEAD / 返回 503（维护页）但 eapi 正常，所以 503 也算可达
    checks.check("probeSite 可达", probe.reachable, detail: "status=${probe.status}")
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
    checks.check("resolveZlibHost 命中", resolved.isSome(),
        detail: if (resolved.isSome()) {
            resolved.getOrThrow().url
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
    } catch (err: Exception) {
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

        let similar = BookApi.similar(client, book.id, book.hash)
        checks.check("similar 非空", similar.size > 0, detail: "size=${similar.size}")

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
    } catch (err: Exception) {
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
    } catch (err: Exception) {
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
    } catch (err: Exception) {
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
    } catch (err: HttpError) {
        checks.check("自动换站", false,
            detail: "HttpError kind=${err.kind} url=${err.url} attempts=${err.attempts} msg=${err.message}")
    } catch (err: ZlibError) {
        checks.check("自动换站", false, detail: err.toString())
    } catch (err: Exception) {
        checks.check("自动换站", false, detail: err.toString())
    } finally {
        client.close()
    }
}
