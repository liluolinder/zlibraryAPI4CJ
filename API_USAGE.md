# zlibraryAPI4CJ API 使用说明

> 版本对应：仓颉 1.2.0 / LinderHttp 2.0 / `output-type = "static"` / 库版本 `2.2.0`。
>
> 本文件是**面向调用方**的完整使用手册：装依赖、建客户端、拿凭证、探测站点、
> 处理错误，然后逐个接口查参数与返回类型。
>
> 想看「为什么这么设计」「踩过什么坑」，见 [`MEMORY.md`](MEMORY.md)；
> 想改这个库本身，见 [`Agent.md`](Agent.md)；
> 从旧版（v1）迁移过来，见 [`doc/feature_api.md`](doc/feature_api.md)；
> 端点事实与资料来源，见 [`doc/eapi-endpoints.md`](doc/eapi-endpoints.md)。
>
> 本文所有示例都由 [`doccheck/`](doccheck) 工程逐段编译校验
> （`cd doccheck && cjpm build`）。

---

## 目录

1. [总览](#1-总览)
2. [安装与依赖](#2-安装与依赖)
3. [客户端 ZlibClient](#3-客户端-zlibclient)
4. [凭证 ZlibCredential](#4-凭证-zlibcredential)
5. [站点管理：自定义站 + 种子站 + 自动换站](#5-站点管理自定义站--种子站--自动换站)
6. [错误处理](#6-错误处理)
7. [接口速查表](#7-接口速查表)
8. [login 登录与注册](#8-login-登录与注册)
9. [book 图书](#9-book-图书)
10. [search 搜索](#10-search-搜索)
11. [user 用户](#11-user-用户)
12. [info 站点信息](#12-info-站点信息)
13. [数据模型](#13-数据模型)
14. [工具函数](#14-工具函数)
15. [常见任务配方](#15-常见任务配方)
16. [已知限制](#16-已知限制)

---

## 1. 总览

`zlibraryAPI4CJ` 把 Z-Library 的 eapi（Android 客户端逆向接口）按功能拆成
7 个子包。**所有接口函数都是 `public static func`，第一个参数永远是
`ZlibClient`**——接口函数本身无状态，客户端生命周期与凭证完全由调用方掌握，
同一个客户端可以被多个线程并发复用。

```
zlibraryAPI4CJ (root：public import core.* 与 model.*)
├── core    客户端 / 凭证 / 站点探测 / 信封 / 错误 / 查询串 / UTF-8 安全截断
├── model   共享数据模型：BookInfo / BookInfoBrief / ZlibUser / DownloadInfo / Pagination / BookPage
├── login   LoginApi / LoginResult：邮箱密码登录、remix 凭证登录、注册、找回密码、token 登录
├── book    BookApi：详情 / 相似 / 下载信息 / 格式 / 收藏 / 取消 / 删除 / 发送 / 落盘
├── search  SearchApi：搜索（年份 / 语言 / 扩展名 / 排序）、最热门、最近上传
├── user    UserApi：资料 / 收藏列表 / 下载历史 / 推荐 / 资料更新 / 横幅 / 捐赠
└── info    InfoApi：站点 / 语言 / 扩展名 / 域名 / 套餐（原始 JSON）
```

**依赖方向严格单向：`core ← model ← 业务子包`，业务子包之间互不 import。**
所有共享类型都在 `model` 里，所以 `SearchApi` 返回的 `BookInfo` 可以直接喂给
`BookApi`，不需要类型转换。

### 三条必须记住的约定

| 约定 | 说明 |
| --- | --- |
| **静态 API + client 首参** | 形如 `BookApi.info(client, id, hash)`；接口类不需要实例化 |
| **`None` 优先于异常** | 「可能没有数据」返回 `?T` 或空集合；「业务失败」抛 `ZlibError` |
| **分页返回 `BookPage`** | 带 `pagination` / `hasMore()` / `nextPage()` / `first()`，别自己推分页 |

### 一次请求的完整链路

```
业务 API（如 BookApi.info）
  └─ client.getObject(path, field, decoder)
       ├─ client.getRaw / postFormRaw   → LinderHttp HttpClient（连接池 + Cookie）
       ├─ ZlibEnvelope.parse(body)      → 判断 success，失败抛 ZlibError
       └─ decoder(obj)                  → 容错解码成模型（缺字段回退默认值）
```

### import 约定

```cangjie
import zlibraryAPI4CJ.*          // ZlibClient / ZlibCredential / ZlibHost / ZlibError
                                 // + 全部数据模型（BookInfo / ZlibUser / BookPage …）
import zlibraryAPI4CJ.login.*    // 业务子包必须显式导入
import zlibraryAPI4CJ.book.*
import zlibraryAPI4CJ.search.*
import zlibraryAPI4CJ.user.*
import zlibraryAPI4CJ.info.*
```

> 根包只 `public import` 了 `core.*` 与 `model.*`。业务接口（`BookApi` 等）
> **必须**显式 import 对应子包，否则会报「未声明的标识符」。

---

## 2. 安装与依赖

本库以源码形式作为 `path` 依赖引入。消费工程的 `cjpm.toml`：

```toml
[package]
  cjc-version = "1.2.0"
  name = "my_app"
  output-type = "executable"

[dependencies]
  zlibraryAPI4CJ = { path = "C:/Project/Cangjie/zlibraryAPI4CJ" }
  linderHttp     = { path = "C:/Project/Cangjie/LinderHttp" }

[target.x86_64-w64-mingw32]
compile-option = "--cfg \"ohos=false\""
link-option = "-lcrypt32"
[target.x86_64-w64-mingw32.bin-dependencies]
path-option = ["${CANGJIE_STDX_PATH}/windows_x86_64_cjnative/static/stdx"]
```

> ⚠ 三个必读点：
> 1. 依赖名大小写必须与对方 `cjpm.toml` 的 `name` **完全一致**
>    （`linderHttp` 不是 `linderhttp`，`zlibraryAPI4CJ` 不是 `zlibraryapi4cj`）；
> 2. `path` 依赖**不会传递 target 段**，上面 `[target.x86_64-w64-mingw32]` 的三项
>    必须自己抄一遍，否则链接期会报 `undefined reference`；
> 3. `-lcrypt32` 是 Windows 上 TLS 证书校验所需，stdx 的 `path-option`
>    是 JSON 解析（`stdx.encoding.json`）所需。

### 最小可运行示例

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.book.*

main(): Int64 {
    let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        let book = BookApi.info(client, 123456, "abcdef123456")
        println("${book.title} / ${book.authorText()} / ${book.sizeText()}")
    } finally {
        client.close()
    }
    0
}
```

---

## 3. 客户端 ZlibClient

`ZlibClient` 把五件与业务无关、但每个接口都必须正确的事收敛到一处：

1. **连接**：内部只持有一个 LinderHttp `HttpClient`，连接池与 Cookie 存储共享；
2. **身份**：凭证既写 Cookie（`remix_userid` / `remix_userkey` / `siteLanguageV2`）
   也写请求头（`remix-userid` / `remix-userkey`）；
3. **信封解包**：`{"success":1,...}` / `{"success":0,"error":"..."}` 统一处理；
4. **站点管理**：自定义站优先 + 种子站兜底换站（`ZlibSites`，见第 5 章）；
5. **自动重试**：域名类失败先向种子站换新地址再重试，新地址覆盖自定义站。

客户端对「凭证 / 显式站点」保持**不可变语义**（`withCredential` / `withBaseUrl`
派生新客户端、共享连接池），但 `ZlibSites` 里的地址是**受控可变**的——
自动换站是运行期行为，换一次后所有共享该 `ZlibSites` 的客户端立即生效。
实现 `Resource`，支持 `try-finally` 释放。

### 3.1 创建

```cangjie
import linderHttp.*   // HttpClientBuilder（复用外部 HttpClient 时）

// 1) 默认配置 + 游客态
let anon = ZlibClient.create()

// 2) 指定自定义站
let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")

// 3) 自定义站 + 种子站：自定义站失败时自动向种子站换新地址并重试
let resilient = ZlibClient.create(baseUrl: "https://your-zlib-domain",
    seeds: ["https://seed1.example", "https://seed2.example"])

// 4) 指定站点 + 已有凭证
let credential = ZlibCredential.fromCookieString(
    "remix_userid=123456; remix_userkey=xxxxxxxx")
let authed = ZlibClient.create(baseUrl: "https://your-zlib-domain",
    credential: credential, seeds: ["https://seed1.example"])

// 5) 复用外部 HttpClient（已有统一连接池 / 代理 / 日志策略时）
let http = HttpClientBuilder().userAgent("my-agent").build()
let shared = ZlibClient.fromHttpClient(http, baseUrl: "https://your-zlib-domain",
    seeds: ["https://seed1.example"])

// 6) 用现成的 ZlibSites 创建（多个客户端共享同一份站点状态）
let sites = ZlibSites(customUrl: "https://your-zlib-domain",
    seeds: ["https://seed1.example"], refreshInterval: Duration.second * 30)
let sharedSites = ZlibClient.createWithSites(sites)
let sharedHttpSites = ZlibClient.fromHttpClientWithSites(http, sites)
```

`create` 参数：

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `baseUrl` | `String` | `ZlibHost.DEFAULT_URL` | 自定义站（**优先使用**）；可带 `/eapi`（内部会规范化掉），也可带尾部 `/` |
| `credential` | `ZlibCredential` | `ZlibCredential.anonymous()` | 初始凭证 |
| `config` | `ZlibClientConfig` | `ZlibClientConfig()` | 连接与重试配置 |
| `seeds` | `Array<String>` | `Array<String>()` | 种子站列表；空表示不换站（只做同址重试） |

`createWithSites` 参数：

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `sites` | `ZlibSites` | — | 站点管理器（位置参数），多个客户端可共享 |
| `credential` | `ZlibCredential` | `ZlibCredential.anonymous()` | 初始凭证 |
| `config` | `ZlibClientConfig` | `ZlibClientConfig()` | 连接与重试配置 |

`fromHttpClient` 参数：

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `http` | `HttpClient` | 外部已有客户端（位置参数） |
| `baseUrl` | `String` | 同 `create` |
| `credential` | `ZlibCredential` | 同上 |
| `config` | `ZlibClientConfig` | 同上；超时/代理等**以传入的 `HttpClient` 为准** |
| `seeds` | `Array<String>` | 同上 |

`fromHttpClientWithSites` 参数：`http: HttpClient`（位置）、`sites: ZlibSites`（位置）、
`credential!`、`config!`。

> `fromHttpClient` / `fromHttpClientWithSites` 创建出来的客户端，`close()` 一样会关闭
> 传入的 `HttpClient`。如果这个 `HttpClient` 是全局共享的，请勿对它调用 `close()`。

### 3.2 配置 ZlibClientConfig

```cangjie
let config = ZlibClientConfig()
config.readTimeout = Duration.second * 20
config.totalTimeout = Duration.second * 45
config.httpsProxy = "http://127.0.0.1:7890"
config.maxConnectionsPerHost = 4

// 重试：3 次尝试（含首次）；关掉则失败立刻抛
config.autoRetry = true
config.maxAttempts = 3

// 下载/取图片等大响应的读写超时（默认 5 分钟；API 请求的 30 秒读超时对文件太短）
config.downloadTimeout = Duration.minute * 5

let client = ZlibClient.create(baseUrl: "https://your-zlib-domain", config: config)

// 需要改动共享配置时先 copy()，避免污染别处持有的实例
let cloned = client.config.copy()
cloned.readTimeout = Duration.second * 10
cloned.maxAttempts = 1
```

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `userAgent` | `String` | 桌面版 Chrome 120 | 服务端对非常规 UA 更严格 |
| `readTimeout` | `Duration` | 30 秒 | 单次读取超时（search + 大 limit 偶尔很慢） |
| `totalTimeout` | `Duration` | 60 秒 | 整次请求（含重试）总超时 |
| `maxConnectionsPerHost` | `Int64` | `8` | 每 host 最大并发连接数 |
| `followRedirects` | `Bool` | `true` | 镜像入口常有 3xx |
| `httpProxy` | `String` | `""` | 空串表示不用代理 |
| `httpsProxy` | `String` | `""` | 空串表示不用代理 |
| `autoRetry` | `Bool` | `true` | 是否开启请求自动重试（含失败换站） |
| `maxAttempts` | `Int64` | `3` | 单次请求最多尝试次数（含首次）；小于 1 按 1 处理 |
| `downloadTimeout` | `Duration` | 5 分钟 | 下载 / 取字节的读写超时（实测下载链接偶尔很慢） |

方法：`copy(): ZlibClientConfig`（返回副本，已同步复制 `autoRetry` / `maxAttempts` / `downloadTimeout`）。

> `ZlibClientConfig` 是**可变类**，但客户端内部持有它；创建客户端之后再改
> `config` 不会影响已建好的客户端（内部按值使用各字段）。
> 想「运行期改配置」就派生新客户端。

### 3.3 只读属性

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `credential` | `ZlibCredential` | 当前凭证 |
| `config` | `ZlibClientConfig` | 当前配置 |
| `sites` | `ZlibSites` | 站点管理器（自定义站 + 种子站 + 刷新状态） |
| `host` | `ZlibHost` | **当前**站点值对象（自动换站后返回新地址） |
| `baseUrl` | `String` | **当前**站点根地址（不带尾部 `/`；换站后会变） |
| `eapiUrl` | `String` | **当前** eapi 根地址（`<当前站点>/eapi`） |

```cangjie
let client = ZlibClient.create(baseUrl: "https://example.com/eapi/",
    seeds: ["https://seed.example"])
println(client.baseUrl)              // https://example.com
println(client.eapiUrl)              // https://example.com/eapi
println(client.credential.isLoggedIn) // false
println(client.sites.hasSeeds())      // true
```

> `host` / `baseUrl` / `eapiUrl` 是**动态读取**的：自动换站或
> `setCustomSite(...)` 之后，下一次读就是新地址。

### 3.4 派生：withCredential / withBaseUrl / withHost / withSites

派生出的客户端**共享同一个底层连接池与 Cookie 存储**，所以很廉价；
原客户端不受影响（不可变语义）。

```cangjie
// 换身份（游客 → 登录，或登录 → 另一个账号）：站点管理器共享
let authed = client.withCredential(ZlibCredential.of(123456, "xxxxxxxx"))

// 显式换站：派生客户端使用**新的** ZlibSites（种子站与策略沿用）
let moved = client.withBaseUrl("https://another-mirror.example")

// 直接给一个 ZlibHost
let viaHost = client.withHost(ZlibHost.of("https://third-mirror.example"))

// 整体替换站点管理器（例如换成另一套种子站/冷却策略）
let otherSites = ZlibSites(customUrl: "https://another-mirror.example",
    seeds: ["https://seed3.example"], refreshInterval: Duration.second * 60)
let replaced = client.withSites(otherSites)
```

| 方法 | 参数 | 返回 | 说明 |
| --- | --- | --- | --- |
| `withCredential(value: ZlibCredential)` | 新凭证 | `ZlibClient` | 与 A 共享连接池**和** `ZlibSites` |
| `withBaseUrl(url: String)` | 新站点 | `ZlibClient` | 共享连接池；用 `sites.withCustomUrl(url)` 的**独立副本**，不影响原客户端 |
| `withHost(value: ZlibHost)` | 新站点值对象 | `ZlibClient` | 等价于 `withBaseUrl(value.url)` |
| `withSites(value: ZlibSites)` | 新站点管理器 | `ZlibClient` | 共享连接池；换整个站点状态 |

> ⚠ 派生客户端共享底层 `HttpClient`：对**任意一个**派生客户端调用 `close()`，
> 等于关闭整组。需要独立生命周期时用 `ZlibClient.create(...)` 另建。
>
> 选择策略：
> - 「登录后继续用同一个站点、自动换站要全局生效」→ `withCredential`（共享 sites）；
> - 「只是想这次请求打到另一个地址」→ `withBaseUrl`（独立 sites 副本）。

### 3.5 credentialFromCookies

登录接口除了在响应体里返回 `user`，还会通过 `Set-Cookie` 下发
`remix_userid` / `remix_userkey`。这些 Cookie 被 `HttpClient` 的 Cookie 存储收下，
但客户端持有的 `credential` 是不可变值、不会自动更新。本方法把存储里的值捞出来：

```cangjie
let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
// ... 某处发过登录请求（例如别的库代登录）...
let credential = client.credentialFromCookies()
let authed = client.withCredential(credential)
```

`credentialFromCookies()` 的行为：

- 从 Cookie 存储里读 `remix_userid` / `remix_userkey` / `siteLanguageV2`
  （`siteLanguage` 作为旧版备份）；
- 一个都没有 → 返回当前 `credential`（不报错）；
- 只有其中一个 → 另一个沿用当前 `credential` 的值。

> 用 `LoginApi.login` / `LoginApi.loginWithToken` 时**不需要**它：
> 那两个方法已经把凭证放进 `LoginResult` 了。本方法用于「Cookie 是别人写进去的」场景。

### 3.6 底层请求方法（逃生口）

子包没覆盖的接口，可以直接用客户端打。

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `apiUrl(path: String)` | `String` | 拼出完整 eapi 地址（`path` 可带或不带前导 `/`） |
| `getRaw(path: String, query!: Array<(String, String)> = ...)` | `String` | GET 响应体文本，**不解包信封** |
| `postFormRaw(path: String, form: Array<(String, String)>)` | `String` | POST urlencoded 表单，返回响应体文本 |
| `getEnvelope(path: String, query!: Array<(String, String)> = ...)` | `ZlibEnvelope` | GET 并解析信封 |
| `postFormEnvelope(path: String, form: Array<(String, String)>)` | `ZlibEnvelope` | POST 表单并解析信封 |
| `getObject<T>(path, field, decoder, query!)` | `T` | 取根上某对象字段并解码 |
| `getObjects<T>(path, field, decoder, query!)` | `ArrayList<T>` | 取根上某数组字段并逐项解码 |
| `postFormObject<T>(path, field, form, decoder)` | `T` | POST 表单后取根上某对象字段并解码 |

```cangjie
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
```

> `getObject` / `getObjects` 的 `query` 在 decoder 之后，**不能用尾随 lambda**，
> 必须显式写 `{ obj => ... }`；`postFormObject` 的 decoder 是最后一个参数，
> 可以用尾随 lambda 语法。
>
> 这些底层方法**同样享受自动重试与换站**：失败后先向种子站换地址，再用新地址重发
> （规则见 5.7 节）。想完全关掉重试，把 `config.autoRetry` 设为 `false`。

### 3.7 下载与二进制

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `download(url: String, path: Path, overwrite!: Bool = false)` | `Int64` | 下载绝对 URL 到本地文件，返回写入字节数 |
| `fetchBytes(url: String)` | `Array<Byte>` | 取绝对 URL 的字节内容（封面图等） |

```cangjie
import std.fs.*

// 落盘：父目录需已存在（BookApi.download 会自动建目录），同名默认自动改名
let written = client.download("https://dl.example.com/f/1?token=x", Path("./downloads/a.epub"))

// 明确覆盖已有文件
let overwritten = client.download("https://dl.example.com/f/2", Path("./downloads/b.pdf"),
    overwrite: true)

// 只要字节（例如封面）
let bytes = client.fetchBytes("https://example.com/cover.jpg")
println("封面 ${bytes.size} 字节")
```

下载请求使用**独立的请求头**（只有 `User-Agent` / `Accept` / `Referer`，
不带 remix 凭证）：下载链接是签名过的绝对地址，主机名常常是 CDN 或个人域名，
带站点的登录凭证没有意义，还可能触发跨域校验。

非 2xx 响应会抛 `ZlibError`（`404 → NotFound`、`401/403 → Forbidden`、
其它 → `BadResponse`），异常里带 HTTP 状态码与截断后的响应片段。

> **下载不触发换站**：下载链接指向账号的个人域名/CDN，换站点地址对它没有帮助；
> 但传输层抖动（底层 `HttpError`）仍会按 `maxAttempts` 重试**同一链接**。
> 链接本身过期（403/404）时需要重新 `BookApi.file()` 换新链接，而不是换站点。

### 3.8 资源管理

`ZlibClient` 实现 `Resource`：`close()` 关闭底层连接池，`isClosed()` 查询状态。
关闭后再发请求会抛 `ZlibError`（`kind == ZlibErrorKind.Closed`）。

```cangjie
// 写法一：try-finally（推荐，执行到 finally 一定关）
let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    // 用 client
    println(client.isClosed())   // false
} finally {
    client.close()
}

// 写法二：显式关闭 + 幂等（重复 close 不报错）
client.close()
client.close()
println(client.isClosed())       // true
```

> `close()` 是幂等的；但关闭后**不能**再用它发请求。

### 3.9 站点管理入口

客户端上直接暴露了最常用的站点操作（详细语义见第 5 章）：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `sites` | `ZlibSites` | 站点管理器（属性）：自定义站、种子站、刷新状态 |
| `setCustomSite(url: String)` | `Unit` | 手动覆盖当前自定义站（立即生效，原客户端也变） |
| `currentSiteUrl()` | `String` | 当前实际使用的站点地址 |
| `refreshSite(force!: Bool = false)` | `Bool` | 立即向种子站换一次地址；`force` 跳过冷却窗口；无种子站/冷却中返回 `false` |
| `withSites(value: ZlibSites)` | `ZlibClient` | 派生客户端并整体替换站点管理器 |

```cangjie
let client = ZlibClient.create(baseUrl: "https://your-zlib-domain",
    seeds: ["https://seed1.example", "https://seed2.example"])
try {
    // 手动切到另一个已知可用地址（会影响所有共享 sites 的客户端）
    client.setCustomSite("https://another-mirror.example")
    println(client.currentSiteUrl())   // https://another-mirror.example

    // 立即向种子站要一次新地址（force 跳过 30s 冷却）
    if (client.refreshSite(force: true)) {
        println("已换到 ${client.currentSiteUrl()}")
    }

    // 观察站点状态（日志/持久化用）
    let snapshot = client.sites.snapshot()
    println(snapshot)
} finally {
    client.close()
}
```

> 自动换站（请求失败时）走的是内部同一套逻辑：`beginRefresh` 申请冷却窗口 →
> `planSiteRefresh` 探测 → `adopt` 覆盖自定义站。所以手动 `refreshSite` 与自动
> 换站不会互相放大请求量。

---

## 4. 凭证 ZlibCredential

Z-Library 的身份不是 Bearer token，而是两条 remix 凭证，服务端同时接受
**Cookie** 与**请求头**两种携带方式。`ZlibCredential` 是**不可变值**，
所有 `with*` 方法返回新实例，可安全跨线程共享。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `userId` | `String` | 账号 id（`remix_userid`）；用字符串保存，避免服务端偶发返回字符串时丢信息 |
| `userKey` | `String` | 账号密钥（`remix_userkey`），**视为密码，不要打日志** |
| `siteLanguage` | `String` | 站点语言（`zh` / `en` / `de` …），默认 `zh` |

| 属性 / 方法 | 返回 | 说明 |
| --- | --- | --- |
| `isLoggedIn` | `Bool` | `userId` 与 `userKey` 都非空才为 `true` |
| `language` | `String` | `siteLanguage` 的别名属性 |
| `toCookieHeader()` | `String` | 生成 Cookie 头（含语言 Cookie 与 remix Cookie） |
| `toRequestHeaders()` | `Array<(String, String)>` | 生成 `remix-userid` / `remix-userkey` 请求头 |
| `withUserId(value: String)` | `ZlibCredential` | 派生新凭证 |
| `withUserKey(value: String)` | `ZlibCredential` | 派生新凭证 |
| `withSiteLanguage(value: String)` | `ZlibCredential` | 派生新凭证 |

### 4.1 三种构造方式

```cangjie
// 1) 游客（只能访问免登录接口）
let anonymous = ZlibCredential.anonymous()
println(anonymous.isLoggedIn)   // false

// 2) 逐字段构造（全具名参数）
let manual = ZlibCredential(userId: "123456", userKey: "xxxxxxxx", siteLanguage: "en")

// 3) 用数值 id 构造（登录响应里的 user.id 是数字）
let fromId = ZlibCredential.of(123456, "xxxxxxxx")

// 4) 从浏览器复制出来的 Cookie 串解析（键名大小写不敏感）
let fromCookie = ZlibCredential.fromCookieString(
    "remix_userid=123456; remix_userkey=xxxxxxxx; siteLanguageV2=zh")
println(fromCookie.userId)       // 123456
println(fromCookie.siteLanguage) // zh
```

`fromCookieString` 的解析规则：

- 按 `;` 分段，每段 `key=value`，两侧空白会 trim；
- 键名**大小写不敏感**（`Remix_UserID` 也能识别）；
- 同时接受旧 Cookie `siteLanguage` 与新的 `siteLanguageV2`
  （旧的先到先得，新的覆盖）；
- 没有语言 Cookie 或语言为空 → 回退默认 `zh`；
- 解析不到 `remix_userid` / `remix_userkey` 时得到游客凭证（不抛异常）。

### 4.2 Cookie 格式

`toCookieHeader()` 生成形如：

```
siteLanguage=zh; siteLanguageV2=zh; remix_userid=123456; remix_userkey=xxxxxxxx
```

- 语言 Cookie 两种都发（旧 `siteLanguage` + 新 `siteLanguageV2`），
  避免「登录了却拿到英文/未登录页面」；
- `remix_userid` / `remix_userkey` 只在非空时出现；
- 游客凭证也会带语言 Cookie（否则站点会按 IP 猜语言）。

`toRequestHeaders()` 生成：

```
[("remix-userid", "123456"), ("remix-userkey", "xxxxxxxx")]
```

### 4.3 持久化与复用

`ZlibCredential` 是纯数据对象，**本库不负责落盘**。推荐两种做法：

```cangjie
// 做法一：按字段存（推荐，语义清晰）
// 存：自己写文件/配置中心，字段为 userId / userKey / siteLanguage
// 读：
let stored = ZlibCredential(userId: "123456", userKey: "xxxxxxxx", siteLanguage: "zh")

// 做法二：直接存 toCookieHeader() 的字符串，读时用 fromCookieString 还原
let cookie = stored.toCookieHeader()
let restored = ZlibCredential.fromCookieString(cookie)
```

登录一次后把凭证存起来，下次直接 `ZlibClient.create(credential: ...)`，
不必反复用邮箱密码登录（也少一次风控风险）。

> ⚠ `toString()` 刻意不打印 `userKey` 原文：
> `ZlibCredential(login=true, userId=123456, language=zh)`。
> 自己打日志时也请保持这个习惯。

---

## 5. 站点管理：自定义站 + 种子站 + 自动换站

Z-Library 没有长期稳定的官方域名：主站会被封、镜像会轮换，登录后账号还会被
分配「个人域名」（官方社区文档明确说明：**下载必须使用 personal zlibrary domains**）。
所以站点地址是**客户端的一等配置**，不是常量。

从 **2.1.0** 起，本库把这套「域名会死」的现实做成了内建能力：

- **自定义站**（`customUrl`）：调用方指定的地址，**所有请求优先用它**；
- **种子站**（`seeds`）：稳定的引导站，自定义站失败时向它查询最新域名；
- **自动换站 + 自动重试**：请求失败且属于「域名类错误」时，先向种子站换到新地址，
  用新地址重试，并把新地址**覆盖**回自定义站（后续请求立即生效）。

### 5.1 两个概念

| 概念 | 来源 | 作用 |
| --- | --- | --- |
| **自定义站**（`customUrl`） | 调用方指定（`create(baseUrl: ...)` / `ZlibSites(customUrl: ...)`） | 所有请求优先使用；自动换站后会被**覆盖** |
| **种子站**（`seeds`） | 调用方指定的稳定引导站列表 | 自定义站失败时，向它查询最新域名并探测 |

```
请求 A ──> sites.current() = 自定义站
             │ 成功 → 返回
             │ 失败（Transport / BadResponse / Forbidden）
             ▼
        refreshSite()：种子站 GET /eapi/info/domains → 候选域名 → probeSite
             │ 探到可用站
             ▼
        sites.adopt(新地址)          ← 覆盖自定义站
             │
             ▼
请求 A（重试）──> sites.current() = 新地址
```

> **只用自定义站、不配置种子站**也是合法用法：行为退化为「同址重试」
> （只重试传输层抖动，不会换站）。

### 5.2 ZlibSites

`ZlibSites` 是站点管理器：**只管理地址，不发请求**。
内部用 `Mutex` 保护地址状态，多个线程共享同一个实例时不会互相覆盖出脏地址。

构造：

```cangjie
public init(customUrl!: String = ZlibHost.DEFAULT_URL,
    seeds!: Array<String> = Array<String>(),
    refreshInterval!: Duration = Duration.second * 30,
    fallbackToSeed!: Bool = true)
```

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `customUrl` | `String` | `ZlibHost.DEFAULT_URL` | 初始自定义站（优先使用） |
| `seeds` | `Array<String>` | `Array<String>()` | 种子站列表（按优先级从左到右）；空表示不启用换站 |
| `refreshInterval` | `Duration` | 30 秒 | 两次种子刷新之间的最小间隔（负数按 30 秒处理） |
| `fallbackToSeed` | `Bool` | `true` | 从种子站拿不到域名时，是否允许退用可达的种子站本身 |

方法与属性：

| 成员 | 返回 | 说明 |
| --- | --- | --- |
| `current()` | `ZlibHost` | 当前站点（每次请求前读取，换站后立即生效） |
| `customUrl()` | `String` | 当前自定义站（规范化后） |
| `seedUrls()` | `Array<String>` | 种子站列表副本（改副本不影响本实例） |
| `hasSeeds()` | `Bool` | 是否配置了种子站（没配置时换站无意义） |
| `refreshInterval()` | `Duration` | 刷新冷却间隔 |
| `fallbackToSeed()` | `Bool` | 是否允许退用种子站本身 |
| `lastRefreshAtMillis()` | `Int64` | 上次刷新时间（Unix 毫秒，0 = 从未刷新） |
| `refreshCount()` | `Int64` | 累计刷新尝试次数 |
| `adopt(host: ZlibHost)` | `Unit` | 覆盖当前自定义站（自动换站内部用） |
| `adoptUrl(url: String)` | `Unit` | 覆盖当前自定义站（字符串形式，会规范化） |
| `setCustomUrl(url: String)` | `Unit` | 手动指定自定义站（等价 `adoptUrl`，语义更明确） |
| `setSeedUrls(seeds: Array<String>)` | `Unit` | 替换种子站列表（空数组 = 关闭自动换站） |
| `beginRefresh(force!: Bool = false)` | `Bool` | 申请一次刷新许可（带冷却窗口）；`force` 跳过冷却 |
| `snapshot()` | `ZlibSiteSnapshot` | 当前状态的不可变快照（日志/持久化/诊断） |
| `withCustomUrl(url: String)` | `ZlibSites` | 派生副本：换自定义站，种子站与策略沿用，刷新时间清零 |
| `withSeeds(seeds: Array<String>)` | `ZlibSites` | 派生副本：换种子站 |
| `toString()` | `String` | `ZlibSites(custom=..., seeds=N, refreshCount=...)` |

```cangjie
// 典型构造：自定义站 + 两个种子站
let sites = ZlibSites(
    customUrl: "https://your-zlib-domain/eapi/",   // 会规范化成 https://your-zlib-domain
    seeds: ["https://seed1.example", "https://seed2.example"],
    refreshInterval: Duration.second * 30,
    fallbackToSeed: true)

println(sites.current().url)      // https://your-zlib-domain
println(sites.customUrl())        // https://your-zlib-domain
println(sites.seedUrls().size)    // 2
println(sites.hasSeeds())         // true

// 手动覆盖当前自定义站（自动换站内部也走这个方法）
sites.setCustomUrl("https://another-mirror.example")
println(sites.current().url)      // https://another-mirror.example

// 派生独立副本（不影响原实例）
let moved = sites.withCustomUrl("https://third-mirror.example")
let reseeded = sites.withSeeds(["https://seed3.example"])
println("${moved.current().url} / ${reseeded.seedUrls()[0]}")
```

注意事项：

- `seeds` 里的空串会被跳过，地址会走 `ZlibHost.of` 规范化（去尾部 `/`、去误加的 `/eapi`）；
- `seedUrls()` 返回的是**副本**，改它不会影响管理器；
- 派生出的 `withCustomUrl` / `withSeeds` 是**独立实例**，刷新时间清零；
- `ZlibSites` 的可变性是**受控的**：只有地址/种子/刷新状态可变，
  凭证与配置仍在客户端上保持不可变。

### 5.3 ZlibSiteSnapshot

`ZlibSiteSnapshot` 是 `ZlibSites` 的不可变快照，适合打日志、存配置、做诊断面板：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `currentUrl` | `String` | 当前自定义站（实际请求用的地址） |
| `seedUrls` | `Array<String>` | 种子站列表 |
| `lastRefreshAtMillis` | `Int64` | 上次刷新时间（Unix 毫秒，0 = 尚未刷新） |
| `refreshCount` | `Int64` | 累计刷新尝试次数 |
| `refreshIntervalSeconds` | `Int64` | 刷新冷却间隔（秒） |
| `fallbackToSeed` | `Bool` | 是否允许退用种子站本身 |

```cangjie
let snapshot = client.sites.snapshot()
println(snapshot.currentUrl)                 // 当前站点
println(snapshot.refreshCount)               // 换过几次
println(snapshot.lastRefreshAtMillis)        // 上次换站时间
println(snapshot.refreshIntervalSeconds)     // 30
println(snapshot.seedUrls.size)
println(snapshot)                            // toString 一行摘要
```

### 5.4 ZlibHost

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `DEFAULT_URL` | `String` | 默认站点 `https://zh.eva101.ru`（2026-11-10 实测 eapi 可用；镜像会轮换，**仍可能失效**） |
| `MIRRORS` | `Array<String>` | 候选镜像列表（首个是实测可用的 `zh.eva101.ru`），供 `resolveZlibHost()` 探测 |
| `ZlibHost.of(url: String)` | `ZlibHost` | 规范化地址（静态方法） |
| `url` | `String` | 规范化后的站点根地址（无尾部 `/`、无 `/eapi`） |
| `eapi` | `String` | `<站点>/eapi` |
| `isValid` | `Bool` | 是否以 `http://` / `https://` 开头 |
| `origin` | `String` | 站点主页地址（带尾部 `/`），用于拼 `Referer` |

`ZlibHost.of` 的规范化规则：

- 去掉首尾空白与尾部 `/`；
- 去掉误加的 `/eapi`（用户常把接口地址整条贴进来）；
- 空串直接抛 `ZlibError`（`kind == BadResponse`），避免后续请求打到 `/eapi/eapi`。

```cangjie
let host = ZlibHost.of("  https://example.com/eapi/  ")
println(host.url)      // https://example.com
println(host.eapi)     // https://example.com/eapi
println(host.origin)   // https://example.com/
println(host.isValid)  // true
```

### 5.5 ZlibProbe 与探测函数

`ZlibProbe` 是探测结果值对象：

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `url` | `String` | 被探测的地址 |
| `status` | `UInt16` | HTTP 状态码；`0` 表示连接失败（DNS/超时/TLS） |
| `location` | `String` | 3xx 重定向目标（已补全为绝对地址）；无重定向为空串 |
| `reachable` | `Bool` | 3xx / 200 / 503 都算可达 |
| `isRedirect` | `Bool` | 是否 3xx |
| `ZlibProbe(url, status, location)` | `ZlibProbe` | 公共构造器（位置参数） |

四个探测函数：

| 函数 | 返回 | 说明 |
| --- | --- | --- |
| `probeSite(url: String, timeoutSeconds!: Int64 = 10)` | `ZlibProbe` | 探测单个地址（HEAD、不跟随重定向、不带 Cookie）；`timeoutSeconds` 为读超时，总超时 = 读超时 + 5 秒 |
| `checkAccess(url: String)` | `Bool` | 只回 Bool；会把 URL 里的 `/eapi` 之前部分拿来探 |
| `canAccessZlib(baseUrl!: String = ZlibHost.DEFAULT_URL, autoRedirect!: Bool = false)` | `Bool` | 兼容旧版习惯；`autoRedirect=true` 时 3xx 也算可用 |
| `resolveZlibHost(candidates!: Array<String> = ZlibHost.MIRRORS)` | `?ZlibHost` | 按候选列表探测出一个可用站点，全失败返回 `None` |

```cangjie
// 单点探测：能拿到状态码与重定向目标
let probe = probeSite("https://z-library.sk")
println("status=${probe.status} redirect=${probe.isRedirect} reachable=${probe.reachable}")
if (probe.isRedirect && !probe.location.isEmpty()) {
    println("镜像把入口指向：${probe.location}")
}

// 换站流程里会用更短的超时（5 秒），避免一次刷新卡太久
let quick = probeSite("https://z-library.sk", timeoutSeconds: 5)
println(quick.status)

// 快速巡检
println(checkAccess("https://your-zlib-domain"))
println(canAccessZlib(baseUrl: "https://your-zlib-domain", autoRedirect: true))

// 从候选列表里找一个可用的
match (resolveZlibHost()) {
    case Some(host) => println("可用：${host.url}")
    case None => println("候选镜像全部不可达，请手动指定 baseUrl")
}
```

**为什么探测必须关掉自动重定向**：镜像入口正是靠 3xx 的 `Location`
把请求转到真正可用的站点；跟随重定向就看不到 `Location` 了。
`probeSite` 内部固定 `followRedirects(false)` 且 `cookies(false)`。

**为什么 503 算可达**：503 常是站点的维护页——说明 DNS/TLS/HTTP 链路都是通的，
站点本身还活着，只是暂时不服务。把它当「不可达」会误判整批镜像死亡。

> `resolveZlibHost` 全失败返回 `None` 而不是抛异常：
> 「找不到镜像」和「接口报错」是两种完全不同的故障，
> 调用方需要不同的处理（换网络 vs 换账号），不该混成一个异常。

### 5.6 换站流程：planSiteRefresh 与域名列表解析

换站计划是**纯逻辑**（网络能力用回调注入），所以可以完全离线测试：

```cangjie
public func planSiteRefresh(seeds: Array<String>,
    fetchDomains: (String) -> Array<String>,
    probe: (String) -> ZlibProbe,
    fallbackToSeed: Bool,
    maxCandidates!: Int64 = 4): ?ZlibHost
```

依次尝试：

1. 对每个种子站调用 `fetchDomains` 拉候选域名，逐个 `normalizeDomain` + `probe`，
   返回第一个 200/503 的地址（每个种子站最多探测 `maxCandidates` 个，默认 4）；
2. **种子站刚返回过域名 → 说明它本身可达**：`fallbackToSeed = true` 时直接用它，
   不再对它做一次 HEAD（实测 HEAD 偶发超过 5 秒超时，会让换站白等一轮）；
3. 拿不到域名时才探测种子站本身：3xx → 用 `Location`；200/503 → 直接用种子站；
4. 全部失败 → `None`（由调用方决定是否报错，不在这里抛异常）。

```cangjie
// 生产写法：域名列表来自种子站，探测用 probeSite
let fetch: (String) -> Array<String> = { seed => fetchSeedDomains(seed) }
let probe: (String) -> ZlibProbe = { url => probeSite(url, timeoutSeconds: 5) }
let target = planSiteRefresh(["https://seed1.example", "https://seed2.example"],
    fetch, probe, true)
if (let Some(host) <- target) {
    println("换到：${host.url}")
}

// 离线单测写法：注入假实现，不联网
let fakeProbe: (String) -> ZlibProbe = { url =>
    ZlibProbe(url, if (url == "https://good.com") { UInt16(200) } else { UInt16(0) }, "")
}
let fakeFetch: (String) -> Array<String> = { _ => ["bad.com", "good.com"] }
let picked = planSiteRefresh(["https://seed.example"], fakeFetch, fakeProbe, true)
println(picked.getOrThrow().url)   // https://good.com
```

配套的四个公开函数：

| 函数 | 返回 | 说明 |
| --- | --- | --- |
| `fetchSeedDomains(seedUrl: String)` | `Array<String>` | 向种子站 `GET /eapi/info/domains` 并提取域名列表；失败返回**空数组**（不抛异常） |
| `extractDomainList(root: JsonObject)` | `Array<String>` | 从响应根对象里宽松提取域名列表（多形态、保序去重） |
| `normalizeDomain(raw: String, seed!: String = "")` | `?ZlibHost` | 把列表里的单项规范成站点地址；无法解析返回 `None` |
| `planSiteRefresh(...)` | `?ZlibHost` | 上文的换站计划（`maxCandidates` 控制每个种子站的候选探测上限） |

`extractDomainList` 兼容的响应形态（`/eapi/info/domains` 没有官方文档）：

| 形态 | 示例 |
| --- | --- |
| 字符串数组 | `{"domains":["a.com","b.com"]}` |
| 对象数组 | `{"domains":[{"domain":"a.com"},{"url":"https://b.com/x"}]}` |
| map 形态 | `{"domains":{"a.com":{...},"b.com":{...}}}` |
| 逗号/分号串 | `{"domains":"a.com,b.com"}` |
| 单字段 | `{"domain":"a.com"}` / `{"url":"https://b.com"}` |

```cangjie
// 直接调用（已有响应文本时）
let root = parseJsonObject("{\"success\":1,\"domains\":[\"a.com\",\"b.com\"]}")
for (domain in extractDomainList(root)) {
    println(domain)
}

// 规范化单项
println(normalizeDomain("z-library.sk").getOrThrow().url)          // https://z-library.sk
println(normalizeDomain("https://b.com/book/1").getOrThrow().url)  // https://b.com
println(normalizeDomain("//c.com").getOrThrow().url)               // https://c.com
println(normalizeDomain("/login", seed: "https://seed.com").getOrThrow().url)
// https://seed.com

// 从种子站拉一次域名列表（失败返回空数组）
let domains = fetchSeedDomains("https://seed1.example")
println("拿到 ${domains.size} 个候选域名")
```

`normalizeDomain` 处理的形态：

- 裸域名 `z-library.sk` → 补 `https://`；
- 带协议、带路径 `https://z-library.sk/book/1` → 只保留 `scheme://host[:port]`；
- 协议相对地址 `//c.com` → 补 `https://`；
- 根相对路径 `/login` → 相对 `seed` 解析（没给 `seed` 时返回 `None`）；
- 空串、无法解析 → `None`（不抛异常）。

> `fetchSeedDomains` 刻意**不复用** `ZlibClient`：客户端的请求层带自动重试/换站，
> 换站过程中再调它会形成递归。这个函数用一次性短超时客户端，只发一次请求。

### 5.7 自动重试规则

所有 API 请求（`getRaw` / `postFormRaw` / `getEnvelope` / `postFormEnvelope` /
`getObject` / `getObjects` / `postFormObject`）都经过同一个重试外壳：

| 情况 | 是否重试 | 是否换站 | 理由 |
| --- | --- | --- | --- |
| `ZlibError(Transport)` | ✅ 到 `maxAttempts` 次 | ✅ | 连不上：域名失效/被墙/DNS 污染，换站最有效 |
| `ZlibError(BadResponse)` | ✅ | ✅ | 返回 HTML 风控页，通常也是域名被针对性拦截 |
| `ZlibError(Forbidden)` | ✅ | ✅ | 403：镜像拒绝服务或需要个人域名 |
| `ZlibError(ApiFailure)` | ❌ | ❌ | 服务端已明确业务失败（如书不存在），换站无用 |
| `ZlibError(NotLoggedIn)` | ❌ | ❌ | 凭证问题，换站无用 |
| `ZlibError(NotFound)` | ❌ | ❌ | 资源不存在，换站无用 |
| `ZlibError(Closed)` | ❌ | ❌ | 客户端已关闭，换站无用 |
| 底层 `HttpError`（内部判断，不对外暴露） | ✅ 到 `maxAttempts` 次 | ✅（API 请求） | DNS 失败/连不上是最常见的换站触发点；先换站再重试 |
| 未包装的底层异常（非上述两类） | ✅ 到 `maxAttempts` 次 | ✅（API 请求） | 实测 LinderHttp 偶发把 stdx 的 TLS/读写异常直接漏到外层；本质仍是传输失败，漏掉重试会让一次抖动直接变业务失败 |

补充规则：

- 次数由 `config.maxAttempts` 控制（默认 **3**，含首次；小于 1 按 1 处理），
  `config.autoRetry = false` 时等同每次只试 1 次；
- 每次重试前**重新读** `sites.current()`，所以换站立即生效；
- 全部尝试失败时**统一抛 `ZlibError`**：底层 `HttpError`、stdx 的 TLS/读写异常会被
  包成 `ZlibError(Transport)`，原始异常保留在 `err.cause`（调用方只需一个 catch）；
- 下载 / 取字节：`refreshOnFailure = false`，**不触发换站**，但 `HttpError` 与未包装异常
  仍按次数重试，并使用 `config.downloadTimeout`（默认 5 分钟）而不是 API 的 30 秒读超时；
- 换站本身有冷却窗口（见 5.8），失败风暴不会把种子站打爆。

```cangjie
// 想要「失败立刻抛」：关掉自动重试
let config = ZlibClientConfig()
config.autoRetry = false
let strict = ZlibClient.create(baseUrl: "https://your-zlib-domain", config: config)

// 想更激进一点：最多试 5 次
let config2 = ZlibClientConfig()
config2.maxAttempts = 5
let patient = ZlibClient.create(baseUrl: "https://your-zlib-domain",
    seeds: ["https://seed1.example"], config: config2)
```

> 重试是**有代价**的：写操作（收藏/发送到 Kindle）重试可能重复执行。
> 服务端对多数写操作是幂等的，但如果不放心，把 `autoRetry` 关掉只在读接口上开。
>
> 另外，本库的重试**不区分幂等性**：`BookApi.save` 失败后重试会再发一次 save，
> 语义上仍是「保存」，不会重复扣配额；但 `sendTo` 这类操作请自行评估。

### 5.8 换站时机与冷却窗口

- **冷却窗口**：`ZlibSites.beginRefresh()` 用 `lastRefreshAtMillis` + `refreshInterval`
  （默认 **30 秒**）限制换站频率。并发场景下「一批请求同时失败」很常见，
  如果每个失败都去查种子站，等于对种子站发起 DDoS；
- **Mutex**：`ZlibSites` 内部用 `Mutex` 串行化地址状态读写，
  多线程共享同一客户端时不会出现脏地址；
- **force**：`refreshSite(force: true)` 跳过冷却，供手动急救用；
- **无种子站**：`refreshSite()` 直接返回 `false`，不会发任何请求。

```cangjie
// 观察换站是否被冷却拦住
if (!client.refreshSite()) {
    println("可能在冷却窗口内，或没有可用新地址")
}
// 手动急救：强制忽略冷却
let refreshed = client.refreshSite(force: true)
println("强制换站结果：${refreshed}")
println("累计刷新次数：${client.sites.refreshCount()}")
```

### 5.9 站点状态的持久化建议

换站后可以把当前地址存下来，下次启动直接作为自定义站，省掉一次探测：

```cangjie
// 存：换站后把当前地址记下来（随凭证一起存）
let savedSite = client.currentSiteUrl()
let savedCookie = client.credential.toCookieHeader()

// 读：启动时恢复
let restored = ZlibClient.create(
    baseUrl: savedSite,
    credential: ZlibCredential.fromCookieString(savedCookie),
    seeds: ["https://seed1.example", "https://seed2.example"])
```

也可以存整个快照（多一个 `refreshCount` 之类的诊断信息）：

```cangjie
let snapshot = client.sites.snapshot()
println("当前=${snapshot.currentUrl} 种子=${snapshot.seedUrls.size} 刷新=${snapshot.refreshCount}")
// 自己序列化 snapshot 的字段；本库不负责落盘
```

### 5.10 个人域名与下载

- `GET /book/{id}/{hash}/file` 返回的 `DownloadInfo.downloadLink` 是**签名过的
  绝对地址**，主机名可能是 CDN 或个人域名，**与站点域名不同**；
- 链接带时效，过期后 403/404，需要重新调用 `BookApi.file()` 换取；
- 下载时**不要**带站点的 remix 凭证（本库已内置独立请求头）；
- 下载失败**不触发换站**（换站点对个人域名链接没有帮助），
  但传输层抖动会按 `maxAttempts` 重试同一链接；
- 官方社区文档明确说明：现代 Z-Library 的下载必须走「个人域名」，
  换账号/换域名后旧链接会失效。

---

## 6. 错误处理

**对外只有一种异常：`ZlibError`。一个 `catch` 管理所有错误。**

| 层 | 异常类型 | 触发场景 | 典型处理 |
| --- | --- | --- | --- |
| 业务层 | `ZlibError` | 服务端返回 `success=0`、非 JSON 风控页、资源不存在、未登录、客户端已关闭 | 看 `kind` 决定：引导登录 / 换域名 / 重试 / 放弃 |
| 传输层 | `ZlibError(Transport)` | DNS、TCP、TLS、超时、连接池占满；原始 `HttpError` 被包装进 `cause` | 库内已自动重试/换站；仍失败再提示用户换网络 |
| 文件系统 | `ZlibError(Io)` | 下载目录不可写、磁盘满、路径非法 | 修正本地路径/权限 |

> **2.2.0 起统一异常类型**：`ZlibClient` 在所有公开边界（请求、下载、构造客户端）
> 把 `HttpError`、stdx 的 TLS/读写异常、文件系统异常统一包装成 `ZlibError`，
> 原始异常保留在 `err.cause`。调用方不再需要 `catch (err: HttpError)`，
> 只写一个 `catch (err: ZlibError)` 即可。

### 6.1 ZlibErrorKind

| 枚举值 | `code` | `isRetryable` | 含义 |
| --- | --- | --- | --- |
| `Transport` | 1 | `true` | 传输层失败（DNS / 连接 / TLS / 超时） |
| `BadResponse` | 2 | `false` | 响应不是合法 JSON 或缺约定字段（多半被风控页/登录页替换） |
| `ApiFailure` | 3 | `false` | 服务端明确 `success = 0` 且带 `error` / `msg` |
| `NotLoggedIn` | 4 | `false` | 未登录或凭证失效（服务端提示 `Please login` 之类） |
| `NotFound` | 5 | `false` | 资源不存在（书被删、id/hash 不对、接口 404） |
| `Forbidden` | 6 | `false` | 被拒绝（403 / 域名被墙 / 需要个人域名才能下载） |
| `Closed` | 7 | `false` | 客户端已经 `close()` 仍继续使用 |
| `Io` | 8 | `false` | 本地文件系统错误（下载目录不可写、磁盘满等） |

`ZlibErrorKind` 是无参枚举，但显式实现了 `Equatable` 与 `==` / `!=`，
所以可以直接比较：

```cangjie
if (err.kind == ZlibErrorKind.NotFound) {
    println("找不到这本书")
}
```

### 6.2 ZlibError

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `kind` | `ZlibErrorKind` | 错误类别 |
| `path` | `String` | 出错的 eapi 路径（或下载 URL） |
| `serverMessage` | `String` | 服务端返回的 `error` / `msg` 原文；非业务错误时为空 |
| `status` | `UInt16` | 触发错误时的 HTTP 状态码；未知为 0 |
| `cause` | `?Exception` | 被包装的原始异常（`HttpError` / stdx 异常 / 文件系统异常）；排查底层细节用 |
| `detail` | `String` | 人类可读描述（已带类别前缀） |
| `isUnauthorized` | `Bool` | 是否未登录 |
| `isRetryable` | `Bool` | 是否值得重试（等价于 `kind.isRetryable`） |

静态构造（需要自己抛同类错误时用）：

| 方法 | 说明 |
| --- | --- |
| `ZlibError(kind, message, path!, serverMessage!, status!, cause!)` | 公共构造器（`message` 位置参数） |
| `ZlibError.apiFailure(path, message, status!)` | `success = 0` |
| `ZlibError.badResponse(path, body)` | 非 JSON 响应（会截断并压成单行做预览） |
| `ZlibError.httpStatus(path, status, preview)` | 下载等二进制请求遇到非 2xx |
| `ZlibError.notLoggedIn(path)` | 需要登录却没有凭证 |
| `ZlibError.closed()` | 客户端已关闭 |
| `ZlibError.transport(path, detail, cause!)` | 包装传输层失败 |
| `ZlibError.io(path, detail, cause!)` | 包装本地文件系统失败 |
| `ZlibError.wrapUnhandled(path, err)` | 兜底：任意异常 → `Transport`（`FSException` → `Io`） |

### 6.3 标准捕获写法（一个 catch）

```cangjie
try {
    let book = BookApi.info(client, 123456, "abcdef123456")
    println(book.title)
} catch (err: ZlibError) {
    match (err.kind) {
        case ZlibErrorKind.NotLoggedIn => println("请先登录：${err.detail}")
        case ZlibErrorKind.NotFound => println("资源不存在：${err.serverMessage}")
        case ZlibErrorKind.Forbidden => println("被拒绝（可能需要个人域名）")
        case ZlibErrorKind.Transport => println("网络/域名问题，考虑换镜像")
        case ZlibErrorKind.Io => println("本地文件错误：${err.detail}")
        case ZlibErrorKind.Closed => println("客户端已关闭")
        case _ => println(err.detail)
    }
    // 需要排查底层网络/TLS 细节时才看 cause
    if (let Some(cause) <- err.cause) {
        println("底层异常：${cause}")
    }
}
```

### 6.4 常见失败与判断

| 现象 | 异常 | 判断/处理 |
| --- | --- | --- |
| 提示 `Please login` | `ZlibError(NotLoggedIn)` | 用 `LoginApi.loginClient` 重新登录；或检查凭证是否过期 |
| 返回一段 HTML | `ZlibError(BadResponse)` | 域名失效/被风控；`resolveZlibHost()` 换站点 |
| `success=0` + 英文文案 | `ZlibError(ApiFailure)` | 看 `serverMessage` 原文 |
| 书详情 404 | `ZlibError(NotFound)` | id/hash 不匹配或书已删 |
| 下载 403 | `ZlibError(Forbidden)` | 链接过期/需要个人域名；重新 `BookApi.file()` |
| 请求卡住/超时 | `ZlibError(Transport)`（`cause` 是 `HttpError`） | 库内已重试；`err.isRetryable` 为 true，可换网络再试 |
| 下载写盘失败 | `ZlibError(Io)` | 检查目录权限/磁盘；`cause` 是 `FSException` |
| 关闭后继续用 | `ZlibError(Closed)` | 不要把 `client` 用在 `close()` 之后 |

> 错误的 `toString()` 形如
> `ZlibError(kind=NotFound, path=/book/1/x, status=0, message=[NotFound] ...)`，
> 直接打进日志即可，不会泄露凭证。

---
## 7. 接口速查表

「鉴权」列：**需要** = 通常要求登录态；**可选** = 游客可用，登录后结果更完整；
**否** = 不需要。

### 7.1 login（`zlibraryAPI4CJ.login`）

| 方法 | HTTP | 路径 | 鉴权 | 返回 |
| --- | --- | --- | --- | --- |
| `LoginApi.login(client, email, password, siteLanguage!)` | POST | `/user/login` | 否 | `LoginResult` |
| `LoginApi.loginWithToken(client, userId, userKey, siteLanguage!)` | GET | `/user/profile` | 需要 | `LoginResult` |
| `LoginApi.loginClient(client, email, password, siteLanguage!)` | POST | `/user/login` | 否 | `ZlibClient` |
| `LoginApi.loginTokenClient(client, userId, userKey, siteLanguage!)` | GET | `/user/profile` | 需要 | `ZlibClient` |
| `LoginApi.register(client, email, password, name)` | POST | `/user/registration` | 否 | `Unit` |
| `LoginApi.requestPasswordRecovery(client, email)` | POST | `/user/password-recovery` | 否 | `Unit` |
| `LoginApi.resendConfirmation(client)` | POST | `/user/email/confirmation/resend` | 需要 | `Unit` |
| `LoginApi.tokenSignIn(client, name, idToken)` | POST | `/user/token-sign-in` | 否 | `LoginResult` |

### 7.2 book（`zlibraryAPI4CJ.book`）

| 方法 | HTTP | 路径 | 鉴权 | 返回 |
| --- | --- | --- | --- | --- |
| `BookApi.info(client, id, hash, switchLanguage!)` | GET | `/book/{id}/{hash}` | 可选 | `BookInfo` |
| `BookApi.infoOf(client, brief, switchLanguage!)` | GET | 同上 | 可选 | `BookInfo` |
| `BookApi.similar(client, id, hash)` | GET | `/book/{id}/{hash}/similar` | 可选 | `ArrayList<BookInfoBrief>` |
| `BookApi.similarOf(client, book)` | GET | 同上 | 可选 | `ArrayList<BookInfoBrief>` |
| `BookApi.file(client, id, hash)` | GET | `/book/{id}/{hash}/file` | 需要 | `DownloadInfo` |
| `BookApi.fileOf(client, book)` | GET | 同上 | 需要 | `DownloadInfo` |
| `BookApi.formats(client, id, hash)` | GET | `/book/{id}/{hash}/formats` | 可选（匿名实测可用） | `ArrayList<BookFormat>` |
| `BookApi.save(client, id)` | GET | `/user/book/{id}/save` | 需要 | `Unit` |
| `BookApi.saveBrief(client, brief)` | GET | 同上 | 需要 | `Unit` |
| `BookApi.unsave(client, id)` | GET | `/user/book/{id}/unsave` | 需要 | `Unit` |
| `BookApi.unsaveBrief(client, brief)` | GET | 同上 | 需要 | `Unit` |
| `BookApi.remove(client, id)` | GET | `/user/book/{id}/delete` | 需要 | `Unit` |
| `BookApi.sendTo(client, id, hash, target)` | GET | `/book/{id}/{hash}/send-to-{target}` | 需要 | `Unit` |
| `BookApi.download(client, info, dir, overwrite!)` | — | （用 `DownloadInfo.downloadLink`） | 需要链接 | `Int64` |
| `BookApi.downloadBook(client, id, hash, dir, overwrite!)` | GET | `/book/{id}/{hash}/file` + 下载 | 需要 | `Int64` |

### 7.3 search（`zlibraryAPI4CJ.search`）

| 方法 | HTTP | 路径 | 鉴权 | 返回 |
| --- | --- | --- | --- | --- |
| `SearchApi.search(client, message, yearFrom!, yearTo!, languages!, extensions!, order!, page!, limit!)` | POST | `/book/search` | 可选 | `BookPage` |
| `SearchApi.mostPopular(client, switchLanguage!)` | GET | `/book/most-popular` | 可选 | `ArrayList<BookInfoBrief>` |
| `SearchApi.recently(client)` | GET | `/book/recently` | 可选 | `ArrayList<BookInfoBrief>` |

### 7.4 user（`zlibraryAPI4CJ.user`）

| 方法 | HTTP | 路径 | 鉴权 | 返回 |
| --- | --- | --- | --- | --- |
| `UserApi.profile(client)` | GET | `/user/profile` | 需要 | `ZlibUser` |
| `UserApi.saved(client, order!, page!, limit!)` | GET | `/user/book/saved` | 需要 | `BookPage` |
| `UserApi.downloaded(client, order!, page!, limit!)` | GET | `/user/book/downloaded` | 需要 | `BookPage` |
| `UserApi.recommended(client)` | GET | `/user/book/recommended` | 需要 | `ArrayList<BookInfoBrief>` |
| `UserApi.update(client, email!, password!, name!, kindleEmail!)` | POST | `/user/update` | 需要 | `Unit` |
| `UserApi.hideBanner(client)` | GET | `/user/hide-banner` | 需要 | `Unit` |
| `UserApi.donations(client)` | GET | `/user/donations` | 需要 | `JsonObject` |

### 7.5 info（`zlibraryAPI4CJ.info`）

| 方法 | HTTP | 路径 | 鉴权 | 返回 |
| --- | --- | --- | --- | --- |
| `InfoApi.site(client, switchLanguage!)` | GET | `/info` | 否 | `JsonObject` |
| `InfoApi.languages(client)` | GET | `/info/languages` | 否 | `JsonObject` |
| `InfoApi.extensions(client)` | GET | `/info/extensions` | 否 | `JsonObject` |
| `InfoApi.domains(client)` | GET | `/info/domains` | 否 | `JsonObject` |
| `InfoApi.plans(client, switchLanguage!)` | GET | `/info/plans` | 否 | `JsonObject` |

> **本章之后所有示例的约定**：`client` 已按第 3 章创建（游客或登录态）；
> 例如片段若省略建客户端的代码，指的是「持有 `client` 的上下文」。
> 每章开头给出该章需要额外 import 的子包。

---

## 8. login 登录与注册

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*
```

### 8.1 LoginResult

一次成功登录的结果。`user` / `credential` 都是 `let`，可安全跨线程共享。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `user` | `ZlibUser` | 服务端返回的用户资料（含 id / 邮箱 / 配额） |
| `credential` | `ZlibCredential` | 由 `user` 派生的登录凭证 |
| `withClient(client: ZlibClient)` | `ZlibClient` | 把凭证绑到新客户端（共享连接池），原客户端不变 |

> 登录的结果**不是「客户端变成登录态」，而是一个 `LoginResult`**。
> `ZlibClient` 与 `ZlibCredential` 都不可变，必须用 `withClient` 派生新客户端。

### 8.2 LoginApi.login

邮箱 + 密码登录。

- 接口：`POST /user/login`，表单 `email` / `password`
- 返回：`LoginResult`
- 鉴权：不需要（游客客户端即可）

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端（站点地址取自它） |
| `email` | `String` | — | 注册邮箱 |
| `password` | `String` | — | 密码 |
| `siteLanguage` | `?String` | `None` | 站点语言覆盖值（如 `"en"`）；`None` 用默认语言 |

```cangjie
let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    let result = LoginApi.login(guest, "you@example.org", "your-password")
    println("hi ${result.user.name}，今日剩余 ${result.user.downloadsLeft()} 次下载")

    // 关键一步：派生登录态客户端；guest 本身仍是游客
    let mine = result.withClient(guest)
    println(mine.credential.isLoggedIn)   // true

    // 把凭证存起来，下次就不用再登录
    // （存储方式由调用方决定，见 4.3 节）
    let cookieText = result.credential.toCookieHeader()
    println(cookieText.contains("remix_userid="))
} finally {
    guest.close()
}
```

注意事项：

- 失败抛 `ZlibError`：密码错误、账号未确认、响应不是 JSON 等；
- 服务端同时会下发 `Set-Cookie`，但客户端凭证不会自动更新——
  所以本方法从响应里的 `user` 显式派生凭证，避免「登录成功但后续仍游客态」；
- `result.user` 里已带 `downloadsToday` / `downloadsLimit`，不需要再查 `/user/profile`。

### 8.3 LoginApi.loginWithToken

用已有 remix 凭证登录（所谓「token 登录」）。Z-Library 没有 OAuth token，
token 就是 `remix_userid` + `remix_userkey` 这对值。

- 接口：`GET /user/profile`（先用凭证派生临时客户端，再请求 profile 验证）
- 返回：`LoginResult`
- 鉴权：需要（本次调用就是在验证凭证）

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端（站点地址取自它） |
| `userId` | `Int64` | — | 用户 id（`remix_userid`，即登录响应里的 `user.id`） |
| `userKey` | `String` | — | 账号密钥（`remix_userkey`） |
| `siteLanguage` | `?String` | `None` | 站点语言覆盖值 |

```cangjie
let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    // 校验凭证是否仍然有效（服务端改密码/风控后会立即失效）
    let result = LoginApi.loginWithToken(guest, 123456, "xxxxxxxx")
    let mine = result.withClient(guest)
    println("凭证有效：${mine.credential.isLoggedIn}")
} finally {
    guest.close()
}
```

注意事项：

- 真的会打一次 `/user/profile`，不是本地假定凭证有效；
- `/user/profile` 偶尔不回带 `remix_userkey`，本方法会退回调用方给的那一份，
  不会把「凭证明明有效」变成静默游客态。

### 8.4 LoginApi.loginClient / loginTokenClient

`login` / `loginWithToken` 的便捷版：只想要登录态客户端时用它们，
省掉 `.withClient(...)` 一步。

| 方法 | 等价于 | 返回 |
| --- | --- | --- |
| `loginClient(client, email, password, siteLanguage!)` | `login(...).withClient(client)` | `ZlibClient` |
| `loginTokenClient(client, userId, userKey, siteLanguage!)` | `loginWithToken(...).withClient(client)` | `ZlibClient` |

```cangjie
let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    let mine = LoginApi.loginClient(guest, "you@example.org", "your-password")
    // mine 已绑定凭证；guest 仍是游客
    println(mine.credential.isLoggedIn)   // true
    println(guest.credential.isLoggedIn)  // false

    let again = LoginApi.loginTokenClient(guest, 123456, "xxxxxxxx")
    println(again.credential.isLoggedIn)  // true
} finally {
    guest.close()
}
```

### 8.5 LoginApi.register

注册新账号。

- 接口：`POST /user/registration`，表单 `email` / `password` / `name`
- 返回：`Unit`（只关心成功与否）
- 鉴权：不需要

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 客户端 |
| `email` | `String` | 邮箱 |
| `password` | `String` | 密码 |
| `name` | `String` | 昵称 |

```cangjie
let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    LoginApi.register(guest, "new@example.org", "a-strong-password", "读书人")
    println("注册请求已提交（注意查收确认邮件）")
} catch (err: ZlibError) {
    println("注册失败：${err.detail}")
} finally {
    guest.close()
}
```

注意事项：

- 注册成功后通常还要邮件确认；未确认账号登录会失败，
  可用 `resendConfirmation` 重发；
- 邮箱已注册、密码强度不足等会被服务端拒绝（`ZlibError.ApiFailure`）。

### 8.6 LoginApi.requestPasswordRecovery

发送找回密码邮件。

- 接口：`POST /user/password-recovery`，表单 `email`
- 返回：`Unit`

```cangjie
let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    LoginApi.requestPasswordRecovery(guest, "you@example.org")
    println("找回密码邮件已请求发送")
} finally {
    guest.close()
}
```

> 出于防枚举考虑，服务端对「邮箱不存在」也可能返回 `success = 1`，
> **不要**用本方法判断邮箱是否注册过。

### 8.7 LoginApi.resendConfirmation

重发注册确认邮件。

- 接口：`POST /user/email/confirmation/resend`，无表单字段
- 返回：`Unit`
- 鉴权：需要（服务端要知道给哪个账号发信）

```cangjie
let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    // 需要登录态客户端：账号还没确认而完全无法登录时，
    // 客户端侧没有自助路径（服务端要知道给哪个账号发信）。
    let mine = LoginApi.loginClient(guest, "you@example.org", "your-password")
    LoginApi.resendConfirmation(mine)
    println("确认邮件已重发")
} finally {
    guest.close()
}
```

### 8.8 LoginApi.tokenSignIn

第三方（Google / Apple）`id_token` 登录。

- 接口：`POST /user/token-sign-in`，表单 `name` / `id_token`
- 返回：`LoginResult`

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 客户端 |
| `name` | `String` | 身份提供方名（社区客户端传 `"google"` / `"apple"`） |
| `idToken` | `String` | OIDC 的 id_token 原文 |

```cangjie
let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    let result = LoginApi.tokenSignIn(guest, "google", "eyJhbGciOi...")
    let mine = result.withClient(guest)
    println("第三方登录成功：${result.user.email}")
} finally {
    guest.close()
}
```

> 该接口没有语言参数（服务端按账号存储的语言返回），
> 所以派生出的凭证使用默认语言。

---

## 9. book 图书

```cangjie
import std.fs.*            // Path（下载需要）
import stdx.encoding.json.* // JsonObject（formats 需要）
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.book.*
```

路径里的 `{id}` / `{hash}` 必须来自**同一本书**：搜索/相似列表返回的
`BookInfoBrief` 同时带了两者，直接用 `infoOf` / `similarOf` / `fileOf` 即可。

### 9.1 BookApi.info

获取图书详情。

- 接口：`GET /book/{id}/{hash}`，query `switch-language`（可选）
- 返回：`BookInfo`
- 鉴权：可选（登录态会多出 `isUserSavedBook` / `dateSaved`）

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端 |
| `id` | `Int64` | — | 图书 id |
| `hash` | `String` | — | 图书 hash |
| `switchLanguage` | `?String` | `None` | 返回文案语言（query `switch-language`） |

```cangjie
let book = BookApi.info(client, 123456, "abcdef123456")
println("${book.title} / ${book.authorText()} / ${book.sizeText()}")
println("格式=${book.extension} 页数=${book.pages} 年份=${book.year}")
println("网页地址=${book.webpage(baseUrl: client.baseUrl)}")

// 指定文案语言
let english = BookApi.info(client, 123456, "abcdef123456", switchLanguage: "en")
println(english.title)
```

注意事项：

- `BookInfo.dl` 可能为空（只有在线阅读的书没有该字段），
  真正下载链接要再用 `BookApi.file()` 换；
- `isUserSavedBook` / `dateSaved` 只在带登录态请求时出现，模型里是可选值；
- 单条响应里字段缺失/类型漂移不会抛异常，缺字段回退默认值。

### 9.2 BookApi.infoOf

用列表项（`BookInfoBrief`）取详情，省去手动传 id/hash。

- 参数：`client: ZlibClient`、`brief: BookInfoBrief`、`switchLanguage!: ?String = None`
- 返回：`BookInfo`

```cangjie
// 从搜索/推荐列表里拿到的 brief
let brief = BookInfoBrief()
brief.id = 123456
brief.hash = "abcdef123456"

let detail = BookApi.infoOf(client, brief)
println(detail.title)
```

### 9.3 BookApi.similar

获取相似图书（返回列表项，不含简介等详情字段）。

- 接口：`GET /book/{id}/{hash}/similar`
- 返回：`ArrayList<BookInfoBrief>`
- 鉴权：可选

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 客户端 |
| `id` | `Int64` | 图书 id |
| `hash` | `String` | 图书 hash |

```cangjie
let similar = BookApi.similar(client, 123456, "abcdef123456")
for (item in similar) {
    println("${item.title} / ${item.author} / ${item.webpage(baseUrl: client.baseUrl)}")
}
```

### 9.4 BookApi.similarOf

用图书详情取相似图书。

- 参数：`client: ZlibClient`、`book: BookInfo`
- 返回：`ArrayList<BookInfoBrief>`

```cangjie
let book = BookApi.info(client, 123456, "abcdef123456")
let similar = BookApi.similarOf(client, book)
println("相似图书 ${similar.size} 本")
```

### 9.5 BookApi.file

获取下载信息。

- 接口：`GET /book/{id}/{hash}/file`
- 返回：`DownloadInfo`（含签名下载链接）
- 鉴权：需要（游客调用通常得到 `success=0` 或 `allowDownload=false`）

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 登录态客户端 |
| `id` | `Int64` | 图书 id |
| `hash` | `String` | 图书 hash |

```cangjie
let info = BookApi.file(client, 123456, "abcdef123456")
println("文件名=${info.fileName()}")
println("可下载=${info.available()} 允许=${info.allowDownload}")
if (info.available()) {
    println("链接=${info.downloadLink}")
}
```

注意事项：

- `downloadLink` 是**签名过的绝对链接**，常常指向用户的个人域名；
- 不要缓存太久，失效时重新调用本方法换新链接；
- 链接过期后下载会抛 `ZlibError`（`Forbidden` / `NotFound`）。

### 9.6 BookApi.fileOf

用图书详情取下载信息。

- 参数：`client: ZlibClient`、`book: BookInfo`
- 返回：`DownloadInfo`

```cangjie
let book = BookApi.info(client, 123456, "abcdef123456")
let info = BookApi.fileOf(client, book)
println(info.fileName())
```

### 9.7 BookApi.formats

获取可用下载格式。

**2026-11-10 实测**（`zh.eva101.ru`）：响应是
`{"success":1,"books":[{"id":...,"hash":"...","extension":"azw3","filesize":...,"filesizeString":"5.04 MB"}, ...]}`，
匿名即可调用；部分书会返回空数组（表示没有可下载版本）。

- 接口：`GET /book/{id}/{hash}/formats`
- 返回：`ArrayList<BookFormat>`
- 鉴权：可选（匿名实测可用）

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 客户端 |
| `id` | `Int64` | 图书 id |
| `hash` | `String` | 图书 hash |

```cangjie
let formats = BookApi.formats(client, 123456, "abcdef123456")
if (formats.isEmpty()) {
    println("该书没有可下载版本")
} else {
    for (format in formats) {
        println("${format.extension} ${format.sizeText()} id=${format.id} hash=${format.hash}")
    }
    // 每个格式版本有自己的 id/hash：下载指定格式时用对应条目换下载链接
    let target = formats[0]
    let info = BookApi.file(client, target.id, target.hash)
    println("下载链接：${info.downloadLink}")
}
```

> 注意：`formats` 里每个条目的 `id` + `hash` 指向**该格式的独立版本**，
> 不要拿原书的 `id`/`hash` 去下载指定格式；原书 `BookApi.file()` 返回的是
> 服务端默认格式（见 `BookInfo.extension`）。

### 9.8 BookApi.save

收藏图书。**只需要 `id`**，不需要 hash。

- 接口：`GET /user/book/{id}/save`
- 返回：`Unit`
- 鉴权：需要

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 登录态客户端 |
| `id` | `Int64` | 图书 id |

```cangjie
// 失败（未登录、书不存在）抛 ZlibError，而不是返回 Bool——
// 调用方需要知道「为什么没收藏上」，静默 false 会掩盖登录过期
BookApi.save(client, 123456)
println("已收藏")
```

### 9.9 BookApi.saveBrief

用列表项收藏（`BookInfoBrief` 自带 id）。

- 参数：`client: ZlibClient`、`brief: BookInfoBrief`
- 返回：`Unit`

```cangjie
let brief = BookInfoBrief()
brief.id = 123456
brief.hash = "abcdef123456"
BookApi.saveBrief(client, brief)
```

### 9.10 BookApi.unsave

取消收藏。

- 接口：`GET /user/book/{id}/unsave`
- 返回：`Unit`
- 鉴权：需要

```cangjie
BookApi.unsave(client, 123456)
println("已取消收藏")
```

### 9.11 BookApi.unsaveBrief

用列表项取消收藏。

- 参数：`client: ZlibClient`、`brief: BookInfoBrief`
- 返回：`Unit`

```cangjie
BookApi.unsaveBrief(client, brief)
```

### 9.12 BookApi.remove

从「我的收藏 / 已下载」列表里删除条目。

- 接口：`GET /user/book/{id}/delete`
- 返回：`Unit`
- 鉴权：需要

```cangjie
// 与 unsave 的区别：unsave 只取消收藏状态，
// delete 是把条目从账号的书籍列表里整体移除
BookApi.remove(client, 123456)
```

### 9.13 BookApi.sendTo

把图书发送到 Kindle / 邮箱。

- 接口：`GET /book/{id}/{hash}/send-to-{target}`
- 返回：`Unit`
- 鉴权：需要（通常要求账号已绑定 Kindle 邮箱或已验证邮箱）

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 登录态客户端 |
| `id` | `Int64` | 图书 id |
| `hash` | `String` | 图书 hash |
| `target` | `String` | 目标类型，直接拼进路径（社区客户端用过 `kindle` / `email`） |

```cangjie
BookApi.sendTo(client, 123456, "abcdef123456", "kindle")
println("已请求发送到 Kindle")
```

注意事项：

- `target` 不能为空（空串抛 `ZlibError.BadResponse`）；
- 服务端未公开枚举，本库不做枚举约束，避免写死过期值；
- 该操作通常要求账号已绑定 Kindle 邮箱/已验证邮箱。

### 9.14 BookApi.download

把已获取的下载信息落盘。

- 返回：`Int64`（写入字节数）
- 文件名由 `DownloadInfo.fileName()` 生成；保存目录不存在时自动递归创建，
  **目录已存在也可安全调用**（库内部先判断再创建；实测 `Directory.create` 对已存在目录会抛 `FSException`）
- 下载使用 `config.downloadTimeout`（默认 5 分钟）而不是 API 的 30 秒读超时

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端 |
| `info` | `DownloadInfo` | — | `BookApi.file()` 的返回值 |
| `dir` | `Path` | — | 保存目录 |
| `overwrite` | `Bool` | `false` | `false` 时同名文件自动改名（`file(1).ext`），不覆盖用户已有文件 |

```cangjie
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
```

注意事项：

- `downloadLink` 为空 → 抛 `ZlibError.BadResponse`
  （提示先用 `BookApi.file()` 换 `DownloadInfo`）；
- `allowDownload == false` → 抛 `ZlibError.ApiFailure`；
- 目录会由本方法创建，不需要自己 `Directory.create`；
- **实测（2026-11-10）**：下载域名是 `dln1.ncdn.ec`（Cloudflare CDN），与站点域名不同，
  且签名链接不需要 Cookie；本库下载时会自动改用 `fileHeaders`（不带 `remix-userid/key`）。
  一次真实下载 723637 字节成功、文件落盘后已清理。

### 9.15 BookApi.downloadBook

一步完成「换取下载信息 + 落盘」。等价于
`download(client, file(client, id, hash), dir, overwrite)`。

- 返回：`Int64`
- 鉴权：需要

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 登录态客户端 |
| `id` | `Int64` | — | 图书 id |
| `hash` | `String` | — | 图书 hash |
| `dir` | `Path` | — | 保存目录 |
| `overwrite` | `Bool` | `false` | 同名是否覆盖 |

```cangjie
let bytes = BookApi.downloadBook(client, 123456, "abcdef123456", Path("./downloads"))
println("下载完成：${bytes} 字节")
```

> 需要自己控制重试/换链接时，分开调用 `file()` + `download()` 更灵活。

---

## 10. search 搜索

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.search.*
```

`SearchApi` 只负责「找书」；拿到 `BookInfoBrief` 的 `id` + `hash` 后再调
`BookApi.info` / `BookApi.file` 取详情与下载链接。

### 10.1 SearchApi.search

搜索图书。

- 接口：`POST /book/search`（`application/x-www-form-urlencoded` 表单）
- 返回：`BookPage`（`books` + `pagination`）
- 鉴权：可选（游客可用；登录态会得到个性化结果）

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端 |
| `message` | `String` | — | 搜索词（必填；空串原样发给服务端） |
| `yearFrom` | `?Int64` | `None` | 起始年份（含），`None` 不限制 |
| `yearTo` | `?Int64` | `None` | 结束年份（含），`None` 不限制 |
| `languages` | `Array<String>` | `Array<String>()` | 语言过滤，如 `["german", "english"]`；空数组不过滤 |
| `extensions` | `Array<String>` | `Array<String>()` | 扩展名过滤，如 `["pdf", "epub"]`；空数组不过滤 |
| `order` | `?String` | `None` | 排序方式（服务端定义，原样透传：`year` / `popular` …） |
| `page` | `Int64` | `1` | 页码，从 1 开始 |
| `limit` | `Int64` | `20` | 每页条数 |

```cangjie
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
```

参数编码细节（写自定义客户端时需要一致）：

- 表单字段顺序：`message` → `yearFrom`（可选）→ `yearTo`（可选）→
  `languages[]`（每个语言一个）→ `extensions[]`（每个扩展名一个）→
  `order`（可选）→ `page` → `limit`；
- `languages[]` / `extensions[]` 是**数组参数**，每个元素一个同名 key，
  **同名 key 全部保留，不去重、不合并**（合并后服务端只认最后一个值）；
- 空字符串语言/扩展名会被跳过，避免发出 `languages[]=`；
- `order` 原样透传：本库不校验，传错值由服务端退回默认排序，不会变成本地异常。

### 10.2 SearchApi.mostPopular

获取最热门图书。

- 接口：`GET /book/most-popular`，query `switch-language`（可选）
- 返回：`ArrayList<BookInfoBrief>`
- 鉴权：可选

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端 |
| `switchLanguage` | `?String` | `None` | 返回文案语言；`None` 用账号/站点设置 |

```cangjie
let popular = SearchApi.mostPopular(client)
for (item in popular) {
    println("${item.title} / ${item.author}")
}

// 指定文案语言
let popularEn = SearchApi.mostPopular(client, switchLanguage: "en")
println("英文榜单 ${popularEn.size} 本")
```

> `switch-language` 只影响文案翻译，**不改变**返回哪些书，游客也能用。

### 10.3 SearchApi.recently

获取最近上传的图书。

- 接口：`GET /book/recently`
- 返回：`ArrayList<BookInfoBrief>`
- 鉴权：可选
- 参数：只有 `client`

```cangjie
let recent = SearchApi.recently(client)
println("最近上传 ${recent.size} 本")
if (!recent.isEmpty()) {
    println(recent[0].title)
}
```

> 该端点没有可用参数（没有 `switch-language`），所以本方法不提供语言参数。

---

## 11. user 用户

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.user.*
import zlibraryAPI4CJ.book.*   // 11.4 取推荐详情时用到 BookApi
```

本子包全部是**需要登录态**的接口。调用前必须用 `LoginApi.loginClient(...)`
或 `client.withCredential(...)` 派生登录客户端；否则服务端返回 `success=0`，
本库统一抛 `ZlibErrorKind.NotLoggedIn`。

### 11.1 UserApi.profile

获取当前用户资料。

- 接口：`GET /user/profile`
- 返回：`ZlibUser`
- 鉴权：需要

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 登录态客户端 |

```cangjie
let user = UserApi.profile(client)
println("${user.name} <${user.email}>")
println("今日已用 ${user.downloadsToday} / 上限 ${user.downloadsLimit}")
println("剩余 ${user.downloadsLeft()} 次")
println("会员=${user.isPremium} 邮箱已确认=${user.confirmed}")
```

> `ZlibUser` 里的 `remixUserKey` 等价于密码：**不要写日志、不要拼进 URL**。

### 11.2 UserApi.saved

收藏列表（分页）。

- 接口：`GET /user/book/saved`，query `order` / `page` / `limit`
- 返回：`BookPage`
- 鉴权：需要

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 登录态客户端 |
| `order` | `?String` | `None` | 排序方式（服务端定义，原样透传：`date` / `title` / `year` / `popular` …） |
| `page` | `Int64` | `1` | 页码，从 1 开始 |
| `limit` | `Int64` | `20` | 每页条数 |

```cangjie
var saved = UserApi.saved(client)
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
```

注意事项：

- 返回的 `BookPage.books` 元素是**完整** `BookInfo`（与搜索一致）；
- `order` 是服务端枚举，本库不校验：服务端新增枚举值时旧客户端不应因此报错；
- 服务端偶尔不给 `pagination`，此时 `hasMore()` 为 `false`——
  要能区分「到底了」与「服务端没给分页」。

### 11.3 UserApi.downloaded

下载历史（分页）。

- 接口：`GET /user/book/downloaded`，query 与响应形状同 `saved`
- 返回：`BookPage`
- 鉴权：需要
- 参数同 `saved`：`client`、`order!`、`page!`、`limit!`

```cangjie
var history = UserApi.downloaded(client)
for (book in history.books) {
    println("${book.title} / ${book.filesizeString}")
}

let page2 = UserApi.downloaded(client, order: "year", page: 2, limit: 10)
println("第 2 页 ${page2.size()} 条")
```

> 这里只返回「下载过哪些书」的元信息，**不含下载链接**；
> 真正取地址要再用 `BookApi.file(...)` 换 `DownloadInfo`。

### 11.4 UserApi.recommended

个性化推荐书单。

- 接口：`GET /user/book/recommended`
- 返回：`ArrayList<BookInfoBrief>`
- 鉴权：需要（游客态会返回未登录错误）

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `client` | `ZlibClient` | 登录态客户端 |

```cangjie
let recommended = UserApi.recommended(client)
for (item in recommended) {
    println("${item.title} / ${item.author}")
    // 要详情就再调一次
    let detail = BookApi.infoOf(client, item)
    println("  ${detail.sizeText()}")
}
```

> 元素是 `BookInfoBrief`（列表项字段），足够展示与发起下载（`id` + `hash` 都在），
> 需要简介/文件大小时再调 `BookApi.info`。

### 11.5 UserApi.update

修改账号资料。

- 接口：`POST /user/update`，表单 `email` / `password` / `name` / `kindle_email`
- 返回：`Unit`
- 鉴权：需要

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 登录态客户端 |
| `email` | `?String` | `None` | 新邮箱（改邮箱通常要走邮箱确认流程） |
| `password` | `?String` | `None` | 新密码 |
| `name` | `?String` | `None` | 新昵称 |
| `kindleEmail` | `?String` | `None` | Kindle 推送邮箱（发出去的表单 key 是 `kindle_email`） |

```cangjie
// 只改昵称：其余字段不传 = 不修改
UserApi.update(client, name: "新昵称")

// 同时改 Kindle 邮箱
UserApi.update(client, kindleEmail: "me@kindle.com")

// 改密码
UserApi.update(client, password: "new-strong-password")
```

注意事项：

- **只发送非 `None` 的字段**：服务端把「字段存在」当成「要更新」，
  无脑发送空串会把已有昵称/Kindle 邮箱清空；
- `kindleEmail` 发出去的表单 key 是 `kindle_email`（下划线，服务端要求）；
- 全都不传也能发出（服务端会返回「没有要更新的内容」之类的业务错误）。

### 11.6 UserApi.hideBanner

关闭首页横幅（banner）。

- 接口：`GET /user/hide-banner`（「写操作却是 GET」的历史遗留端点）
- 返回：`Unit`
- 鉴权：需要

```cangjie
UserApi.hideBanner(client)
println("已关闭横幅")
```

### 11.7 UserApi.donations

获取捐赠信息。

- 接口：`GET /user/donations`
- 返回：`JsonObject`（**原始根对象**，形状不稳定）
- 鉴权：需要

```cangjie
let root = UserApi.donations(client)
// 形状不稳定：按键名容错读取，缺了就按空值处理
let total = readInt(root, "total")
let donors = readString(root, "donors")
println("total=${total} donors=${donors}")
println(root.toString())
```

> 该接口的响应形状不稳定（不同时期是对象、数组或带额外统计字段的混合结构），
> 所以本库不造模型。需要哪个字段就用 `readInt` / `readString` 从容错读取工具里取，
> 或直接看 `root.toString()`。

---

## 12. info 站点信息

```cangjie
import std.collection.*        // ArrayList（12.3 收集扩展名）
import stdx.encoding.json.*    // JsonObject 读取
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.info.*
import zlibraryAPI4CJ.search.* // 12.2 / 12.3 用查到的过滤值发起搜索
import zlibraryAPI4CJ.user.*   // 12.5 用 profile 判断会员
```

`InfoApi` 全部方法返回**原始 `JsonObject`**（信封成功后的根对象），
不做强类型建模：站点元数据的形状随镜像/版本漂移，强类型模型只会让整个接口
因为一个字段类型变化而失效。

失败语义与其它子包一致：`success = 0` 时 `unwrap` 抛 `ZlibError`。

### 12.1 InfoApi.site

获取站点总览信息。

- 接口：`GET /info`，query `switch-language`（可选）
- 返回：`JsonObject`
- 鉴权：否

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端 |
| `switchLanguage` | `?String` | `None` | 返回文案语言；`None` 用站点默认 |

```cangjie
let root = InfoApi.site(client)
// 返回里通常含站点域名、公告、默认语言、分类等；只读自己需要的 key
println("站点名=${readString(root, "name")}")
println("默认语言=${readString(root, "defaultLanguage")}")

let siteEn = InfoApi.site(client, switchLanguage: "en")
println(siteEn.toString())
```

### 12.2 InfoApi.languages

获取站点支持的语言列表。这些值就是搜索用的语言标识。

- 接口：`GET /info/languages`
- 返回：`JsonObject`
- 鉴权：否
- 参数：只有 `client`

```cangjie
let root = InfoApi.languages(client)
for (item in arrayFieldOf(root, "languages")) {
    let language = item.asObject()
    println("${readString(language, "name")} -> ${readString(language, "code")}")
}

// 取到的值可以直接传给搜索
let langs: Array<String> = ["german", "english"]
let page = SearchApi.search(client, "philosophy", languages: langs)
println(page.size())
```

### 12.3 InfoApi.extensions

获取站点支持的图书扩展名列表。

- 接口：`GET /info/extensions`
- 返回：`JsonObject`
- 参数：只有 `client`

```cangjie
let root = InfoApi.extensions(client)
let names = ArrayList<String>()
for (item in arrayFieldOf(root, "extensions")) {
    names.add(readString(item.asObject(), "name"))
}
println("支持格式：${names.size} 种")

// 用扩展名过滤搜索
let page = SearchApi.search(client, "Rust", extensions: ["pdf", "epub"])
println(page.size())
```

> 注意「站点支持的格式」与「某本书可下载的格式」是两回事：
> 后者要看 `BookApi.file` 返回的 `DownloadInfo.extension`。

### 12.4 InfoApi.domains

获取当前可用域名列表。

- 接口：`GET /info/domains`
- 返回：`JsonObject`
- 参数：只有 `client`

```cangjie
let root = InfoApi.domains(client)
for (item in arrayFieldOf(root, "domains")) {
    println(readString(item.asObject(), "domain"))
}

// 拿到的域名可以作为换站点的候选，但是否可达仍要探测
if (checkAccess("https://another-mirror.example")) {
    let moved = client.withBaseUrl("https://another-mirror.example")
    println(moved.baseUrl)
}
```

> Z-Library 主域名会轮换、账号还有「个人域名」，所以这里拿到的列表只能当候选，
> 是否真的可达仍需 `probeSite` / `checkAccess` 探测。

### 12.5 InfoApi.plans

获取会员/套餐信息。

- 接口：`GET /info/plans`，query `switch-language`（可选）
- 返回：`JsonObject`
- 鉴权：否

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `client` | `ZlibClient` | — | 客户端 |
| `switchLanguage` | `?String` | `None` | 返回文案语言；`None` 用站点默认 |

```cangjie
let plans = InfoApi.plans(client)
println(plans.toString())

// 需要判断「当前账号是否付费」时，用 profile 的 isPremium 更可靠
let user = UserApi.profile(client)
println("会员=${user.isPremium}")
```

> 响应形状不稳定，本库只返回原始根对象；
> 判断付费状态请用 `UserApi.profile` 的 `ZlibUser.isPremium`。

---

## 13. 数据模型

所有模型都在 `zlibraryAPI4CJ.model`，根包已 re-export，`import zlibraryAPI4CJ.*` 即可用。
共同约定：

- 字段一律 `public var` + 默认值，**缺字段不会让解码失败**；
- 解码走容错读取（数字/字符串/布尔互转），解码入口是 `fromJsonObject(obj)`
  （或 `fromJson(text)`）；
- 派生属性/方法（`webpage()` / `fileName()` / `hasMore()`）不落字段。

### 13.1 BookInfo（图书详情）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `Int64` | 图书 id |
| `contentType` | `String` | 内容类型（`book` / `article` …） |
| `title` | `String` | 书名 |
| `author` | `?String` | 作者；部分书没有 |
| `volume` | `String` | 卷号 |
| `year` | `Int64` | 出版年份 |
| `edition` | `?String` | 版本 |
| `publisher` | `?String` | 出版社 |
| `identifier` | `?String` | 标识符（ISBN 等） |
| `language` | `String` | 语言 |
| `pages` | `Int64` | 页数 |
| `series` | `String` | 系列名 |
| `cover` | `String` | 封面图 URL |
| `termsHash` | `String` | 术语哈希（服务端内部用） |
| `active` | `Int64` | 是否激活（1/0） |
| `deleted` | `Int64` | 是否删除（1/0） |
| `filesize` | `Int64` | 文件大小（字节） |
| `filesizeString` | `String` | 文件大小可读文本（如 `12.3 MB`） |
| `extension` | `String` | 文件扩展名（`pdf` / `epub` …） |
| `md5` | `String` | MD5 |
| `sha256` | `String` | SHA256 |
| `href` | `String` | 图书页相对地址（`/book/{id}/{hash}/{slug}`） |
| `hash` | `String` | 图书 hash（下载/详情必需） |
| `kindleAvailable` | `Bool` | 是否可发送到 Kindle |
| `sendToEmailAvailable` | `Bool` | 是否可发送到邮箱 |
| `interestScore` | `String` | 兴趣评分（服务端原样字符串） |
| `qualityScore` | `String` | 质量评分（服务端原样字符串） |
| `description` | `String` | 简介 |
| `dl` | `String` | 下载路径（可能为空：只有在线阅读的书没有） |
| `readOnlineUrl` | `?String` | 在线阅读 URL |
| `isUserSavedBook` | `?Bool` | 当前用户是否已收藏（仅登录态出现） |
| `dateSaved` | `?String` | 收藏日期（仅登录态出现） |
| `readOnlineAvailable` | `Bool` | 是否可在线阅读 |

方法：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `BookInfo.fromJsonObject(obj: JsonObject)` | `BookInfo` | 从 JSON 对象解码（容错） |
| `BookInfo.fromJson(text: String)` | `BookInfo` | 从 JSON 文本解码 |
| `authorText()` | `String` | 作者文本；没有作者返回空串 |
| `sizeText()` | `String` | 文件大小文本：优先 `filesizeString`，否则按字节格式化 |
| `saved()` | `Bool` | 当前用户是否已收藏（`None` 视为 false） |
| `downloadable()` | `Bool` | 是否有可用下载路径（`dl` 非空） |
| `webpage(baseUrl!: String = ZlibHost.DEFAULT_URL)` | `String` | 图书网页地址（优先 `href`，否则按 `/book/{id}/{hash}` 拼） |
| `toString()` | `String` | `BookInfo(id/hash, title)` |

```cangjie
let book = BookInfo.fromJson("{\"id\":1,\"title\":\"Rust\",\"filesize\":1234}")
println(book.authorText())   // ""
println(book.sizeText())     // 1 KB
println(book.saved())        // false
println(book.downloadable()) // false
```

### 13.2 BookInfoBrief（列表项）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `Int64` | 图书 id |
| `isbn` | `String` | ISBN（部分书为空） |
| `url` | `String` | 图书页相对地址（实测列表项都带它） |
| `title` | `String` | 书名 |
| `author` | `String` | 作者 |
| `cover` | `String` | 封面图 URL |
| `coverData` | `String` | 封面懒加载 data 属性原文（服务端原样返回） |
| `hash` | `String` | 图书 hash |

方法：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `BookInfoBrief.fromJsonObject(obj: JsonObject)` | `BookInfoBrief` | 解码 |
| `BookInfoBrief.fromJson(text: String)` | `BookInfoBrief` | 解码 |
| `webpage(baseUrl!: String = ZlibHost.DEFAULT_URL)` | `String` | 图书网页地址：优先用 `url`，没有时按 `/book/{id}/{hash}` 拼 |

```cangjie
let brief = BookInfoBrief.fromJson(
    "{\"id\":42,\"title\":\"书名\",\"author\":\"作者\",\"hash\":\"h42\"}")
println(brief.webpage(baseUrl: "https://example.com"))
```

### 13.3 ZlibUser（用户）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `Int64` | 用户 id |
| `email` | `String` | 注册邮箱 |
| `name` | `String` | 昵称 |
| `kindleEmail` | `?String` | Kindle 推送邮箱 |
| `remixUserKey` | `String` | 账号密钥（敏感，等价密码） |
| `downloadsToday` | `Int64` | 今日已下载数 |
| `downloadsLimit` | `Int64` | 每日下载上限 |
| `confirmed` | `Bool` | 邮箱是否已确认 |
| `isPremium` | `Bool` | 是否付费会员 |

方法：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `ZlibUser.fromJsonObject(obj)` | `ZlibUser` | 解码 |
| `ZlibUser.fromJson(text)` | `ZlibUser` | 解码 |
| `downloadsLeft()` | `Int64` | 今日剩余次数（下限 0） |
| `toCredential(siteLanguage!: String = ZLIB_DEFAULT_SITE_LANGUAGE)` | `ZlibCredential` | 转成可复用凭证 |

```cangjie
let user = ZlibUser.fromJson(
    "{\"id\":42,\"name\":\"读书人\",\"remix_userkey\":\"k\",\"downloads_today\":3,\"downloads_limit\":10}")
println(user.downloadsLeft())   // 7
let credential = user.toCredential()
println(credential.isLoggedIn)  // true
```

### 13.4 DownloadInfo（下载信息）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `downloadLink` | `String` | 签名过的下载链接 |
| `description` | `?String` | 文件描述（通常就是书名，文件名主体） |
| `author` | `?String` | 作者（拼进文件名） |
| `extension` | `String` | 扩展名（不含点） |
| `allowDownload` | `Bool` | 是否允许下载；缺省视为允许 |

方法：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `DownloadInfo.fromJsonObject(obj)` | `DownloadInfo` | 解码 |
| `DownloadInfo.fromJson(text)` | `DownloadInfo` | 解码 |
| `available()` | `Bool` | `allowDownload && downloadLink 非空` |
| `fileName()` | `String` | 生成文件名（`描述 (作者).扩展名`，非法字符替换为 `_`） |

```cangjie
let info = DownloadInfo.fromJson(
    "{\"downloadLink\":\"https://x/f/1\",\"description\":\"Rust 程序设计语言\",\"author\":\"Steve Klabnik\",\"extension\":\"epub\"}")
println(info.available())   // true
println(info.fileName())    // Rust 程序设计语言 (Steve Klabnik).epub
```

文件名规则：`描述 (作者).扩展名`，缺哪段省略哪段；描述为空退化成
`book.扩展名`；`/`、`\`、`:`、`*`、`?`、`"`、`<`、`>`、`|`、换行等替换成 `_`。

### 13.5 Pagination（分页信息）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `limit` | `Int64` | 每页条数 |
| `current` | `Int64` | 当前页码（从 1 开始） |
| `totalItems` | `Int64` | 总条数 |
| `totalPages` | `Int64` | 总页数 |

方法：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `Pagination.fromJsonObject(obj)` | `Pagination` | 解码 |
| `hasMore()` | `Bool` | `current < totalPages` |
| `nextPage()` | `Int64` | 下一页页码（没有下一页返回当前页） |

### 13.6 BookPage（一页图书）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `books` | `ArrayList<BookInfo>` | 本页图书 |
| `pagination` | `Pagination` | 分页信息 |

方法：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `BookPage.fromJsonObject(obj)` | `BookPage` | 解码（读根上的 `books` 与 `pagination`） |
| `BookPage.fromJson(text)` | `BookPage` | 解码 |
| `size()` | `Int64` | 本页条数 |
| `isEmpty()` | `Bool` | 是否空页 |
| `hasMore()` | `Bool` | 是否还有下一页 |
| `nextPage()` | `Int64` | 下一页页码 |
| `first()` | `?BookInfo` | 第一本；空页返回 `None` |

```cangjie
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
```

### 13.7 BookFormat（可下载格式）

`BookApi.formats()` 返回的元素。**2026-11-10 实测**响应形如：

```json
{"id":35851393,"hash":"b4c3ae","extension":"azw3","filesize":5285744,"filesizeString":"5.04 MB"}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | `Int64` | 该格式版本的图书 id |
| `hash` | `String` | 该格式版本的 hash |
| `extension` | `String` | 扩展名（不含点） |
| `filesize` | `Int64` | 字节数 |
| `filesizeString` | `String` | 可读大小 |
| `BookFormat.fromJsonObject(obj)` / `fromJson(text)` | `BookFormat` | 解码 |
| `sizeText()` | `String` | 大小文本（优先 `filesizeString`） |

```cangjie
let format = BookFormat.fromJson(
    "{\"id\":35851393,\"hash\":\"b4c3ae\",\"extension\":\"azw3\",\"filesize\":5285744}")
println("${format.extension} ${format.sizeText()}")   // azw3 5.04 MB 级别的文本
```

> 同一本书的每个格式版本都有**独立的 `id` + `hash`**；下载指定格式时用对应条目
> 调 `BookApi.file()`，而不是原书。

---

## 14. 工具函数

全部在 `zlibraryAPI4CJ.core`（根包已 re-export），`import zlibraryAPI4CJ.*` 即可用。

### 14.1 Query（查询参数构造）

eapi 的 GET 接口几乎全靠 query 传参。`Query` 的关键点：
**同名参数允许重复**（数组参数不能合并），空格编码成 `%20` 而不是 `+`。

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `Query()` | `Query` | 空查询 |
| `Query.of(items: Array<(String, String)>)` | `Query` | 以初始参数构造 |
| `add(name: String, value: String)` | `Query` | 追加参数；同名**不覆盖** |
| `addAll(name: String, values: Array<String>)` | `Query` | 追加一组同名参数 |
| `set(name: String, value: String)` | `Query` | 设置参数；同名先删再追加 |
| `setIfSome(name: String, value: ?String)` | `Query` | `None` 时跳过 |
| `setInt(name: String, value: Int64)` | `Query` | 设置整型参数 |
| `merge(items: Array<(String, String)>)` | `Query` | 合并另一组参数（覆盖语义） |
| `toArray()` | `Array<(String, String)>` | 转成参数数组 |
| `size` | `Int64` | 参数个数（属性） |
| `encode()` | `String` | 拼成查询串（不含前导 `?`） |

```cangjie
// 普通标量参数用 set（覆盖语义）
let plain = Query().set("page", "1").set("page", "2").toArray()
println(plain.size)   // 1

// 数组参数用 addAll（保留重复 key）
let array = Query().addAll("languages[]", ["german", "english"])
println(array.encode())  // languages%5b%5d=german&languages%5b%5d=english

// 可选参数用 setIfSome
let optional = Query().setIfSome("order", None).setIfSome("order", Some("year"))
println(optional.encode())  // order=year

// 直接传给 client
let q = Query().setIfSome("order", Some("date")).setInt("page", 1).setInt("limit", 20).toArray()
let text = client.getRaw("/user/book/saved", query: q)
```

### 14.2 formEncode / withQuery / appendPair / percentEncode

| 函数 | 返回 | 说明 |
| --- | --- | --- |
| `formEncode(fields: Array<(String, String)>)` | `String` | 编码成 `a=1&b=2`（保留全部同名参数） |
| `withQuery(url: String, params: Array<(String, String)>)` | `String` | 把参数拼到 url（已有 `?` 用 `&`；空参数原样返回） |
| `appendPair(items: Array<(String, String)>, pair: (String, String))` | `Array<(String, String)>` | 追加一个参数对，返回新数组 |
| `percentEncode(value: String)` | `String` | RFC 3986 百分号编码（小写十六进制，空格 `%20`） |

```cangjie
println(formEncode([("a", "1"), ("a", "2")]))    // a=1&a=2
println(withQuery("https://x.com/p", [("p", "1")]))  // https://x.com/p?p=1
println(withQuery("https://x.com/p?q=0", [("p", "1")])) // ...?q=0&p=1
println(appendPair([("a", "1")], ("b", "2")).size)  // 2
println(percentEncode("中文"))  // %e4%b8%ad%e6%96%87
println(percentEncode("a b"))   // a%20b
```

### 14.3 宽松 JSON 读取

Z-Library 的字段类型不稳定（同一字段可能是数字或字符串、布尔可能是 `0/1`、
可选字段会整条缺失），所以模型解码**一律**走这些函数：

| 函数 | 返回 | 说明 |
| --- | --- | --- |
| `readString(obj, key)` | `String` | 字符串；数字/布尔转文本；缺失返回 `""` |
| `readStringOr(obj, key, fallback)` | `String` | 同上，空串时用 `fallback` |
| `readOptionalString(obj, key)` | `?String` | 缺失/`null`/空串 → `None` |
| `readInt(obj, key)` | `Int64` | 兼容整数、浮点、数字字符串、布尔 |
| `readIntOr(obj, key, fallback)` | `Int64` | 缺失时用 `fallback` |
| `readFloat(obj, key)` | `Float64` | 兼容整数与数字字符串 |
| `readBool(obj, key)` | `Bool` | 兼容 `0/1`、`"true"/"false"`、`"yes"` |
| `readBoolOr(obj, key, fallback)` | `Bool` | 缺失时用 `fallback` |
| `objectFieldOf(obj, key)` | `?JsonObject` | 对象字段；缺失或类型不符 → `None` |
| `arrayFieldOf(obj, key)` | `ArrayList<JsonValue>` | 数组字段；缺失或类型不符 → 空数组 |
| `decodeEach<T>(items, decoder)` | `ArrayList<T>` | 逐条解码，**跳过单条失败** |
| `decodeEachOrThrow<T>(items, decoder)` | `ArrayList<T>` | 逐条解码，任一条失败即抛错 |
| `parseJsonObject(text, path!)` | `JsonObject` | 从 JSON 文本解析对象；失败抛 `ZlibError`（BadResponse） |

```cangjie
let obj = parseJsonObject(
    "{\"i\":\"12\",\"f\":\"1.5\",\"b\":1,\"s\":123,\"n\":null,\"o\":{\"x\":1},\"a\":[1,2]}")
println(readInt(obj, "i"))          // 12
println(readInt(obj, "missing"))    // 0
println(readIntOr(obj, "missing", 7))  // 7
println(readFloat(obj, "f"))        // 1.5
println(readBool(obj, "b"))         // true
println(readString(obj, "s"))       // 123
println(readOptionalString(obj, "n").isNone())  // true
println(objectFieldOf(obj, "o").isSome())       // true
println(arrayFieldOf(obj, "a").size)            // 2

// 列表解码：一条脏数据不让整页作废
let items = arrayFieldOf(parseJsonObject("{\"books\":[{\"id\":1},\"oops\",{\"id\":2}]}"), "books")
let ids = decodeEach<Int64>(items) { item => readInt(item, "id") }
println(ids.size)  // 2（"oops" 那条被 readInt 读成 0，仍然计入）
```

> `decodeEach` 只吞**抛出的异常**；如果解码器不抛异常而是返回默认值
> （像上面这样），脏数据会以默认值的形式留下。需要严格语义时用
> `decodeEachOrThrow` 或自行校验。

### 14.4 文本安全截断

`String.size` 是**字节数**，`text[a..b]` 是**字节下标切片**——
切在多字节汉字中间会产生非法 UTF-8，后续输出/日志会抛
`Invalid utf8 byte sequence`。所以截断一律用这两个函数：

| 函数 | 返回 | 说明 |
| --- | --- | --- |
| `truncateRunes(text: String, maxRunes: Int64, suffix!: String = "...")` | `String` | 按字符（Rune）截断 |
| `truncateBytesSafe(text: String, maxBytes: Int64, suffix!: String = "...")` | `String` | 按字节截断，但不切碎 UTF-8 字符 |

```cangjie
println(truncateRunes("中文abc", 2))            // 中文...
println(truncateRunes("abcdef", 3, suffix: "")) // abc
println(truncateBytesSafe("中文", 4, suffix: "")) // 中
println(truncateBytesSafe("abc", 2, suffix: ""))  // ab
```

### 14.5 ZlibEnvelope（响应信封）

| 成员 | 返回 | 说明 |
| --- | --- | --- |
| `ZlibEnvelope.parse(body: String, path!: String = "")` | `ZlibEnvelope` | 从响应体文本解析（非 JSON 抛 `BadResponse`） |
| `root` | `JsonObject` | 原始 JSON 根对象（属性） |
| `success` / `ok` | `Bool` | 是否成功（`1` / `true` / `"1"` 都算成功） |
| `errorText` | `String` | 服务端错误文案（优先 `error`，其次 `msg`） |
| `unwrap(path!: String = "")` | `JsonObject` | 成功返回根对象，失败抛 `ZlibError` |
| `objectField(name: String)` | `?JsonObject` | 取根上对象字段 |
| `arrayField(name: String)` | `ArrayList<JsonValue>` | 取根上数组字段 |

```cangjie
let envelope = ZlibEnvelope.parse("{\"success\":1,\"books\":[{\"id\":1}]}")
println(envelope.ok)          // true
println(envelope.arrayField("books").size)  // 1
let root = envelope.unwrap()

// 失败时自己处理，而不是让它抛
let bad = ZlibEnvelope.parse("{\"success\":0,\"error\":\"Please login\"}")
if (!bad.ok) {
    println(bad.errorText)    // Please login
}
```

---

## 15. 常见任务配方

> 以下配方默认已 `import zlibraryAPI4CJ.*` 与所用到的业务子包；
> 每段开头列出该段额外的 import。`client` 的创建见第 3 章。

### 15.1 登录 → 收藏 → 换下载链接 → 落盘

```cangjie
import std.fs.*
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*
import zlibraryAPI4CJ.book.*

func fetchAndSave(domain: String, email: String, password: String,
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

main(): Int64 {
    // 真实使用时替换成你自己的域名/账号
    let written = fetchAndSave("https://your-zlib-domain", "you@example.org",
        "your-password", 123456, "abcdef123456", Path("./downloads"))
    println(written)
    0
}
```

要点：`guest.close()` 也会关闭派生的 `mine`（共享连接池），所以只关一次。

### 15.2 搜索并翻页，按需取详情

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.search.*
import zlibraryAPI4CJ.book.*

func searchAll(client: ZlibClient, message: String, maxPages: Int64): Int64 {
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
```

要点：

- 搜索返回的 `books` 是完整 `BookInfo`，**不需要**再逐本调 `info`；
- 榜单/推荐/相似返回的才是 `BookInfoBrief`，需要详情时用
  `BookApi.infoOf(client, brief)`；
- `hasMore()` 依赖服务端给的 `pagination`；缺分页时它是 `false`。

### 15.3 域名失效自动换站并重试（2.1.0）

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.search.*

func searchWithRecovery(domain: String, seeds: Array<String>,
    message: String): Int64 {
    // 自定义站优先；失败时向种子站换新地址并覆盖自定义站，然后自动重试
    let client = ZlibClient.create(baseUrl: domain, seeds: seeds)
    try {
        // 不需要手写重试：execute 层已经做了（默认 3 次、30 秒换站冷却）
        let size = SearchApi.search(client, message).size()
        println("当前站点：${client.currentSiteUrl()}")
        println("累计换站：${client.sites.refreshCount()} 次")
        return size
    } finally {
        // 换站结果可持久化：currentSiteUrl() / sites.snapshot()
        println("本次使用的站点：${client.currentSiteUrl()}")
        client.close()
    }
}
```

等价写法（业务代码里显式控制）：

```cangjie
let client = ZlibClient.create(baseUrl: domain, seeds: seeds)
try {
    let page = SearchApi.search(client, message)
} catch (err: ZlibError) {
    // 走完 maxAttempts 仍失败才会到这里；可以手动强制换一次再试
    if (client.refreshSite(force: true)) {
        println("已换到 ${client.currentSiteUrl()}，请重试业务操作")
    }
} finally {
    client.close()
}
```

要点：

- **默认就会自动换站重试**，不需要自己 catch 再 `withBaseUrl`；
- `refreshSite(force: true)` 用于手动急救（绕过 30 秒冷却）；
- `withBaseUrl(url)` 派生独立站点状态；想让所有共享客户端的请求都切过去，
  用 `client.setCustomSite(url)`；
- 换站状态可持久化：`currentSiteUrl()` 或 `sites.snapshot()`。

### 15.4 按语言 / 年份 / 格式过滤

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.search.*

// 片段：假设在函数体内，client 已创建
let page = SearchApi.search(client, "algorithms",
    yearFrom: 2010,
    yearTo: 2024,
    languages: ["english", "german", "french"],
    extensions: ["pdf", "epub"],
    order: "year")
println("命中 ${page.pagination.totalItems} 条")
```

- 语言标识可以先用 `InfoApi.languages(client)` 查站点支持的取值；
- 扩展名用 `InfoApi.extensions(client)` 查；
- `order` 原样透传，社区已知值有 `year` / `popular`。

### 15.5 保存凭证、下次复用

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*   // LoginResult

// 首次：登录后把凭据存起来（存哪里由调用方决定）
func remember(result: LoginResult): String {
    result.credential.toCookieHeader()
}

// 下次启动：从持久化的字符串还原，不必再登录
func restore(domain: String, savedCookie: String): ZlibClient {
    let credential = ZlibCredential.fromCookieString(savedCookie)
    ZlibClient.create(baseUrl: domain, credential: credential)
}

// 也可以逐字段存（更清晰）：
func restoreByFields(domain: String, userId: String, userKey: String,
    language: String): ZlibClient {
    let credential = ZlibCredential(userId: userId, userKey: userKey, siteLanguage: language)
    ZlibClient.create(baseUrl: domain, credential: credential)
}
```

要点：

- 凭证等价于密码，别写进仓库、日志或公开渠道；
- `fromCookieString` 对键名大小写不敏感，也认旧的 `siteLanguage` Cookie；
- 凭证失效时 `LoginApi.loginWithToken` 会抛 `NotLoggedIn`，那时再走密码登录。

### 15.6 游客与登录客户端并存

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*
import zlibraryAPI4CJ.search.*

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
```

### 15.7 用底层方法打未覆盖的接口

```cangjie
import zlibraryAPI4CJ.*

func rawInfo(client: ZlibClient): String {
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
```

---

## 16. 已知限制

1. **已在真实站点做过一轮联调**：2026-11-10 用 `https://zh.eva101.ru` 跑
   `integration/`（36/36 通过），验证了搜索/榜单/详情/相似/格式/站点信息/
   错误映射/自动换站重试。但镜像会轮换、服务端字段仍可能变，
   `doc/eapi-endpoints.md` 里的可信度标注仍以「社区文档 / v2 实测 / 推断」区分。
2. **域名必须由调用方提供**：`ZlibHost.DEFAULT_URL` / `MIRRORS` 只是候选，
   随时可能过期；生产环境请显式传 `baseUrl` 并配置 `seeds`，或先
   `resolveZlibHost()` 探测。
3. **下载依赖个人域名**：现代 Z-Library 的下载链接指向每个账号的专属域名，
   换账号/换域名后旧链接会失效，必须重新 `BookApi.file()`。
4. **形状不稳定的接口返回原始 JSON**：`donations`、`info/*`（`formats` 已在
   2.1.0 按实测形状强类型化为 `ArrayList<BookFormat>`）不承诺字段名，
   需要调用方自行按需读取；`getEnvelope(...).unwrap()` 可以拿到根对象。
5. **未覆盖的能力**：注册验证码流程（`/papi`、`/rpc.php`）、书单（booklist）、
   用户头像等不在本库范围内；可用第 15.7 节的底层方法自行尝试。
6. **重试有代价**：自动重试对 POST 写操作（注册/更新资料等）在传输层失败时也会重发，
   理论上存在重复提交风险；不希望重试就设 `ZlibClientConfig.autoRetry = false`。
7. **一次换站可能耗时几十秒**：失败后会串行探测最多 4 个候选域名（每个 5 秒超时），
   再退到种子站；实测一次换站约 20~55 秒。需要更快可关掉 `autoRetry` 或手动
   `refreshSite`。
8. **静态库不能独立运行**：可运行验证必须通过消费工程
   （[`doccheck/`](doccheck) 编译校验、[`integration/`](integration) 联网验证，
   或调用方自己的项目）。
9. **凭证安全由调用方负责**：本库不落盘、不打日志，但调用方打印或持久化时
   请避免泄露 `remix_userkey`。
10. **已知环境问题（非本库逻辑）**：本机 Windows + Cangjie 1.2.0 stdx 实测
   登录 POST 偶发进程直接崩溃（exit -1，事件日志 `0xc0000374` = ntdll 堆损坏，
    约 2/10 次；同机另一个用 LinderHttp 的项目也复现）。判断为底层 TLS/网络库的
    原生内存问题，库无法在 Cangjie 层捕获。建议：进程级重试、升级 SDK/网络库，
    或换网络环境验证；集成测试可用 `ZLIB_TEST_STAGE=login` 单独复现。

---

## 附：文档索引

| 文档 | 内容 |
| --- | --- |
| [`README.md`](README.md) | 简介、安装、5 分钟快速开始、项目结构 |
| [`doc/eapi-endpoints.md`](doc/eapi-endpoints.md) | 端点清单（方法/路径/参数/鉴权/返回字段）与资料来源 |
| [`doc/feature_api.md`](doc/feature_api.md) | 旧版 API → 新版 API 迁移指南 |
| [`Agent.md`](Agent.md) | 开发者指南：硬约束、设计约定、新增接口流程、排错表 |
| [`MEMORY.md`](MEMORY.md) | 踩坑与决策证据链 |
| [`doccheck/`](doccheck) | 本文示例的编译校验工程（`cd doccheck && cjpm build`） |
| [`integration/`](integration) | 真实网络集成测试（`cd integration && cjpm run`） |
