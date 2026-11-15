# zlibraryAPI4CJ

**Z-Library EAPI 的仓颉（Cangjie）静态库** —— 按功能划分子包，类型安全、可复用，
覆盖登录、图书、搜索、用户、站点信息等 eapi 接口。

- 语言：[仓颉](https://cangjie-lang.cn/) 1.2.0（`cjc` / `cjpm`）
- 输出：**静态库**（`output-type = "static"`）
- HTTP：[LinderHttp](https://gitcode.com/LiquidStudio/LinderHttp) 2.0（连接池 + 重试 + Cookie）
- JSON：`stdx.encoding.json`（容错解码，无宏、无反射）

> 本库不是 Z-Library 官方项目。接口路径与字段来自社区逆向文档，
> 域名与字段随时可能变化；使用前请阅读文末的[免责声明](#免责声明)。
> 2026-11-10 已在 `https://zh.eva101.ru` 做过真实站点联调（`integration/` 36/36 通过；
> 登录后链路 16/16 通过，含真实下载落盘）。

---

## 特性

- **按功能划分的子包**：`core` / `model` / `login` / `book` / `search` / `user` / `info`，
  依赖方向严格单向（`core ← model ← 业务子包`，业务子包互不 import）。
- **连接复用**：一个 `ZlibClient` 只持有一个 `HttpClient`，连接池、Cookie、超时全共享；
  客户端不可变，`withCredential` / `withBaseUrl` 派生新客户端时共享连接池。
- **站点自动恢复（2.1.0）**：调用方传入「当前自定义站 + 单个种子站」两个**单值**；
  自定义站失败时自动向种子站查询最新域名、**覆盖自定义站**并用新地址重试请求。
  官方域名列表**不由本库定义**（各前端自己维护）；手动探测入口保留 `probeSite` / `checkAccess` / `canAccessZlib`。
- **身份双通道**：同时发送 `remix-userid` / `remix-userkey` 请求头与
  `remix_userid` / `remix_userkey` Cookie，兼容不同版本服务端。
- **统一异常（对齐 bbapi）**：对外只抛 `ZlibError`——业务失败保留业务 `kind`；
  网络（`HttpError`）、文件系统、stdx 等**底层异常统一归 `Cangjie`**，
  原始异常在 `cause`，调用方一个 catch 管全部。- **启动即登录（2.2.1）**：`create(credential:)` / `fromHttpClient(credential:)` 会把凭证
  预置进底层 Cookie 存储，服务端下发 `Set-Cookie` 后凭证也不会丢（bbapi 曾出现
  「传了凭证，但第二个请求起变游客」的同类问题）。
- **容错解码**：字段缺失、数字写字符串、布尔给 0/1 都不会让整页结果作废；
  单条脏数据自动跳过。
- **分页封装**：列表接口返回 `BookPage`（`hasMore()` / `nextPage()` / `first()`），
  不用调用方自己推分页逻辑。
- **书单（2.5.0）**：eapi 没有书单接口，本库通过网站前端的 **papi** 抓取——
  `BooklistApi.list` / `BooklistApi.my` / `BooklistApi.books`，返回书单列表、
  作者、预览封面与书单内的完整 `BookInfo` 列表。
- **评论（2.6.0）**：同样走 papi：`CommentApi.book` / `CommentApi.booklist`，
  返回评论正文、作者、相对时间、回复关系与点赞（`reactionsInfo` 已合并进 `BookComment.likes`），
  按 offset 分页（服务端忽略 limit，每页最多 100 条）。
- **文档示例可编译**：`doccheck/` 工程把 `API_USAGE.md` 的示例全部编译一遍。

---

## 环境要求

| 项 | 要求 |
| --- | --- |
| 仓颉工具链 | 1.2.0（`cjc` / `cjpm`） |
| stdx | 需要 `stdx.encoding.json` 等，`CANGJIE_STDX_PATH` 指向 SDK 的 stdx 目录 |
| 平台 | 已在 `x86_64-w64-mingw32`（Windows 桌面）验证；`cjpm.toml` 保留了鸿蒙/Android/iOS 交叉编译 target 段 |
| HTTP 依赖 | 本地 `path` 依赖 `C:/Project/Cangjie/LinderHttp`（2.0） |

---

## 安装

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
> 1. `linderHttp` 的**依赖名大小写**必须与对方 `cjpm.toml` 的 `name` 完全一致；
> 2. `[target.x86_64-w64-mingw32]` 的三段配置**必须自己抄一遍**（`path` 依赖不会传递 target 段），
>    否则链接期会报 `undefined reference`；
> 3. `-lcrypt32` 是 Windows 上 TLS 证书校验所需，stdx 的 `path-option` 是 JSON 解析所需。

---

## 5 分钟快速开始

```cangjie
import zlibraryAPI4CJ.*        // ZlibClient / ZlibCredential / ZlibError / 全部数据模型
import zlibraryAPI4CJ.book.*   // BookApi

main(): Int64 {
    // 1. 建客户端：自定义站优先；配置种子站后，自定义站失败会自动换站并重试
    let client = ZlibClient.create(baseUrl: "https://your-zlib-domain",
        seed: "https://seed1.example")
    try {
        // 2. 取图书详情（id + hash 是几乎所有图书接口的定位符）
        let book = BookApi.info(client, 123456, "abcdef123456")
        println("${book.title} / ${book.authorText()} / ${book.sizeText()}")

        // 3. 收藏（只需要 id）与取消收藏
        BookApi.save(client, book.id)
        BookApi.unsave(client, book.id)

        // 4. 换下载链接并落盘
        let info = BookApi.file(client, book.id, book.hash)
        if (info.available()) {
            let bytes = BookApi.download(client, info, Path("./downloads"))
            println("已写入 ${bytes} 字节：${info.fileName()}")
        }
    } finally {
        client.close()
    }
    0
}
```

`Path` 来自 `std.fs`，示例省略了 `import std.fs.*`。

### 探测站点

本库不再内置「官方域名候选列表」：官方地址由调用方（前端）自己维护。
下面是单站点探测入口：

```cangjie
import zlibraryAPI4CJ.*

main(): Int64 {
    // 单点探测：200 / 503（维护页）/ 3xx 都算「连得上」
    let probe = probeSite("https://your-zlib-domain")
    println("status=${probe.status} redirect=${probe.isRedirect} reachable=${probe.reachable}")

    // 3xx 的 Location 可以提升为真实站点地址
    if (probe.isRedirect && !probe.location.isEmpty()) {
        println("跳转到：${probe.location}")
    }
    0
}
```

### 站点自动换站与重试（2.1.0）

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.search.*

main(): Int64 {
    // 自定义站优先；自定义站失败 -> 向种子站要新地址 -> 覆盖自定义站 -> 重试
    let client = ZlibClient.create(
        baseUrl: "https://your-zlib-domain",
        seed: "https://seed1.example")   // 单个引导站；空串表示不换站
    try {
        // 任何接口失败都会自动走「换站 + 重试」（默认最多 3 次，30 秒冷却窗口）
        let page = SearchApi.search(client, "Rust")
        println("当前站点：${client.currentSiteUrl()}")
        println("命中 ${page.pagination.totalItems} 条")
    } finally {
        // 换站后的当前地址可持久化，下次启动直接作为 baseUrl
        println(client.sites.snapshot())
        client.close()
    }
    0
}
```

- 换站规则：只对「域名类错误」（连不上 / 非 JSON 风控页 / 403）换站重试；
  未登录、书不存在等业务错误**不会**重试。
- 关闭重试：`ZlibClientConfig.autoRetry = false`；调整次数：`maxAttempts`。
- 手动急救：`client.refreshSite(force: true)`；手动切站：`client.setCustomSite(url)`。
- 详细机制见 [`API_USAGE.md`](API_USAGE.md) 第 5 章。

### 如何决定「是否官方镜像」

> 结论先说：**本库不判断、也不需要判断**哪个域名是官方镜像；它只认两个单值——
> **当前自定义站**（`baseUrl`）与**种子站**（`seed`）。「官方/自定义」是**前端自己的分类**，
> 前端把分类结果翻译成 `seed` 是否为空传进来。

#### 为什么把判定留在前端

- **官方域名列表会变，且各产品可能不同**：Z-Library 官方域会被封、镜像会轮换，
  「官方」是一种产品约定（例如 seline_read 内置 3 个官方地址），不该由底层的 API 库固化；
- **后端只需要一种能力**：`Seed` 有值 ⇒ 失败时允许换站；`seed` 为空 ⇒ 只做同址重试、失败就报错。
  「是不是官方」在行为上恰好等价于「该不该带种子站」，所以一个空串就能表达完整语义；
- **避免策略矩阵**：如果库里加 `isOfficial` 开关，就要维护「官方 × 自定义 × 各种回退开关」
  的组合；现在只有「有无 seed」这一维，实现和排查都简单。

#### 判定规则（前端侧，供消费方参考）

```
规范化(url) = trim → 补 https:// → 去尾部 / → 去误加的 /eapi
是官方镜像 ⇔ 规范化(url) ∈ 官方地址列表（精确匹配，不猜、不做后缀匹配）
```

判定结果只影响一件事：**建客户端时 `seed` 传什么**。

| 前端选择 | 传给本库 | 本库行为 |
| --- | --- | --- |
| 官方地址（A/B/C） | `baseUrl = A`，`seed = ""` | 请求失败只做同址重试，最终抛 `ZlibError`（前端展示「网络链接失败」），**不会**自动换站 |
| 自定义地址（D/E/F） | `baseUrl = F`，`seed = G`（种子站） | 失败时 `refreshSite()` 依次探测：F 自身 3xx → G 的 3xx → G 本身；探到新域名 Z 后 `adopt(Z)` 覆盖 F，重试请求 |

对应代码路径（本库）：

- `ZlibSites(customUrl: String, seed: String)`：两个参数都是**单值**，没有数组；
- `ZlibClient.refreshSite()`：`if (!sitesValue.hasSeed()) { return false }` —— 没有种子站就不换站；
- `planSiteRefresh(currentUrl, seed, probe, fallbackToSeed)`：`seed` 为空直接返回 `None`（本轮不换站）；
- 换站成功后 `sites.adopt(host)` 覆盖自定义站；调用方（前端）再把 `currentSiteUrl()` 写回自己的配置。

```cangjie
// 前端伪代码：官方 → 不带种子站；自定义 → 带种子站
let official = normalized in myOfficialList          // 前端自己维护的 3 个官方地址
let seed = if (official) { "" } else { mySeedSite }  // 空串 = 禁止自动换站
let client = ZlibClient.create(baseUrl: normalized, seed: seed)
```

> 消费方若把「官方地址」当自定义站传（比如 `seed` 也给了种子站），本库会照常执行换站——
> **回退与否完全由调用方通过 `seed` 决定**，本库不做「这是官方所以不许回退」的二次判断。
### 登录

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*
import zlibraryAPI4CJ.user.*

main(): Int64 {
    let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
    try {
        // 邮箱密码登录；凭证与客户端都不可变，不要让 guest 变成登录态
        let result = LoginApi.login(guest, "you@example.org", "your-password")
        let mine = result.withClient(guest) // 派生登录态客户端（共享连接池）
        println("${result.user.name}，今日剩余 ${result.user.downloadsLeft()} 次")

        // 需要登录态的接口都用 mine
        let saved = UserApi.saved(mine)
        println("收藏 ${saved.pagination.totalItems} 本")

        // 只想要登录态客户端时，用便捷方法省一步
        let alsoMine = LoginApi.loginClient(guest, "you@example.org", "your-password")
        println(alsoMine.credential.isLoggedIn) // true
    } finally {
        guest.close()
    }
    0
}
```

### 用已有登录凭证（不重新登录）

```cangjie
import zlibraryAPI4CJ.*

// 方式一：从浏览器 Cookie 串解析（键名大小写不敏感，同时接受 siteLanguage / siteLanguageV2）
let credential = ZlibCredential.fromCookieString(
    "remix_userid=123456; remix_userkey=xxxxxxxx; siteLanguageV2=zh")
let client = ZlibClient.create(baseUrl: "https://your-zlib-domain", credential: credential)

// 方式二：逐字段构造（userId 是字符串，避免服务端偶发返回字符串时丢信息）
let credential2 = ZlibCredential(userId: "123456", userKey: "xxxxxxxx", siteLanguage: "zh")

// 方式三：从数值 id 构造
let credential3 = ZlibCredential.of(123456, "xxxxxxxx")
```

登录接口见 [`API_USAGE.md`](API_USAGE.md) 的 login 章节；
登录成功后用 `LoginResult.withClient(client)` 派生登录态客户端
（内部走 `withCredential`，共享连接池；不要试图原地改凭证）。

### 错误处理

```cangjie
import zlibraryAPI4CJ.*

try {
    let book = BookApi.info(client, 1, "hash")
    println(book.title)
} catch (err: ZlibError) {
    // 一个 catch 管所有错误：网络层也已被包装成 ZlibError
    match (err.kind) {
        case ZlibErrorKind.NotLoggedIn => println("需要登录")
        case ZlibErrorKind.NotFound => println("书不存在：${err.serverMessage}")
        case ZlibErrorKind.Cangjie => println("底层异常（网络/文件）：${err.detail}")
        case _ => println(err.detail)
    }
    // 排查底层网络/TLS 时才看 cause（原始 HttpError）
    if (let Some(cause) <- err.cause) {
        println("底层异常：${cause}")
    }
}
```

---

## 子包一览

| 子包 | 主要入口 | 覆盖能力 |
| --- | --- | --- |
| `zlibraryAPI4CJ.core` | `ZlibClient` `ZlibCredential` `ZlibHost` `ZlibEnvelope` `ZlibError` `Query` | 客户端、凭证、站点探测、信封、错误、URL/表单编码、UTF-8 安全截断 |
| `zlibraryAPI4CJ.model` | `BookInfo` `BookInfoBrief` `ZlibUser` `DownloadInfo` `Pagination` `BookPage` | 跨子包共享的数据模型与容错解码 |
| `zlibraryAPI4CJ.login` | `LoginApi` `LoginResult` | 邮箱密码登录、remix 凭证登录、注册、找回密码、第三方 token 登录 |
| `zlibraryAPI4CJ.book` | `BookApi` | 图书详情、相似图书、下载信息、可用格式、收藏/取消/删除、发送到 Kindle/邮箱、落盘 |
| `zlibraryAPI4CJ.search` | `SearchApi` | 图书搜索（年份/语言/扩展名/排序）、最热门、最近上传 |
| `zlibraryAPI4CJ.user` | `UserApi` | 个人资料、收藏列表、下载历史、个性化推荐、资料更新、隐藏横幅、捐赠信息 |
| `zlibraryAPI4CJ.info` | `InfoApi` | 站点信息：语言、扩展名、域名、套餐（形状不稳定，返回原始 JSON） |
| `zlibraryAPI4CJ.booklist` | `BooklistApi` | 书单：公开/我的书单列表（papi `get-page`）、书单内图书（papi `get-books`）；eapi 无此接口 |
| `zlibraryAPI4CJ.comment` | `CommentApi` | 评论：书/书单的评论列表（papi `comments/{object}/{id}/{offset}`，含点赞与回复关系） |

根包已 `public import` 了 `core.*` 与 `model.*`，所以 `import zlibraryAPI4CJ.*`
就能拿到客户端、凭证、错误类型与全部模型；业务接口再按需 import 对应子包。

---

## 项目结构

```
zlibraryAPI4CJ/
├── cjpm.toml                  # 静态库配置：static + linderHttp path 依赖 + 平台 target 段
├── README.md                  # 本文件：简介 / 安装 / 快速开始
├── API_USAGE.md               # 面向调用方的完整手册（逐接口参数表 + 示例）
├── Agent.md                   # 面向开发者：硬约束、API 约定、验证流程
├── MEMORY.md                  # 踩坑与决策证据链
├── doc/
│   ├── feature_api.md         # 旧版（v1）API → 新版（v2）API 迁移指南
│   └── eapi-endpoints.md      # 本库覆盖的 eapi 端点清单（含资料来源与可信度标注）
├── doccheck/                  # 文档示例编译校验工程（executable，path 依赖主工程）
│   ├── cjpm.toml
│   └── src/main.cj
├── integration/               # 真实网络集成测试（executable，需联网；实测镜像见 src/main.cj）
│   ├── cjpm.toml
│   └── src/main.cj
└── src/
    ├── zlibraryAPI4CJ.cj      # 根包：只做 public import core.* / model.*
    ├── core/                  # 客户端、凭证、站点池、探测、信封、错误、编码、截断
    │   ├── core_pkg.cj  client.cj  credential.cj  host.cj
    │   ├── site.cj      envelope.cj  error.cj    query.cj  text.cj
    │   └── core_test.cj
    ├── model/                 # 共享数据模型
    │   ├── model_pkg.cj  book.cj  user.cj  download.cj  page.cj
    │   ├── booklist.cj        # 书单 / 作者 / 预览书籍 / 书单书籍页
    │   ├── comment.cj         # 评论 / 评论作者 / 点赞 / 评论页
    │   └── model_test.cj
    ├── login/                 # LoginApi / LoginResult
    ├── book/                  # BookApi
    ├── search/                # SearchApi
    ├── user/                  # UserApi
    ├── info/                  # InfoApi
    ├── booklist/              # BooklistApi（papi）
    └── comment/               # CommentApi（papi）
```

---

## 构建与测试

```powershell
cd C:\Project\Cangjie\zlibraryAPI4CJ

cjpm build                       # 构建静态库
cjpm test --no-progress          # 单元测试（143 个，全部离线，不联网）

cd doccheck
cjpm build                       # 文档示例编译校验（API_USAGE.md 的全部示例）

cd ../integration
cjpm run                         # 真实网络集成测试（2026-11-10 在 zh.eva101.ru 实测 36/36 通过）

# 可选：登录后链路（profile / 收藏 / 推荐 / 下载历史 / 换下载链接 / 真实下载）
# 账号密码只放环境变量，不要写进仓库；真实下载会消耗 1 次每日配额
$env:ZLIB_TEST_EMAIL="you@example.org"
$env:ZLIB_TEST_PASSWORD="***"
$env:ZLIB_TEST_DOWNLOAD="1"      # 不要真下载就省略
cjpm run
```

单元测试只覆盖「不联网就能证明」的部分（纯函数、固定 JSON 样本解码、参数构造）。
真实接口可用性需要在有可用域名的网络环境里手工验证——
本机对 Z-Library 候选镜像基本不可达（503 / 超时），原因见 `MEMORY.md`。
文档示例由 `doccheck/` 编译校验：改了 public 签名却没同步文档，这里会直接编译失败。

---

## 文档索引

| 文档 | 读者 | 内容 |
| --- | --- | --- |
| [`API_USAGE.md`](API_USAGE.md) | 调用方 | 完整使用手册：客户端、凭证、站点探测、错误处理、逐接口参数表与示例 |
| [`doc/eapi-endpoints.md`](doc/eapi-endpoints.md) | 调用方 / 维护者 | 本库覆盖的端点清单：方法、路径、参数、鉴权、返回字段、资料可信度 |
| [`doc/feature_api.md`](doc/feature_api.md) | 从 v1 迁移的开发者 | 旧 API → 新 API 对照表、迁移步骤、注意事项 |
| [`Agent.md`](Agent.md) | 接手本库的开发者 | 硬约束、子包依赖方向、API 设计约定、新增接口流程、排错表 |
| [`MEMORY.md`](MEMORY.md) | 接手本库的开发者 | 旧版为何编译不过、域名/百分号/字段漂移等踩坑证据 |
| [`integration/`](integration) | 维护者 / CI | 真实网络集成测试：接口可用性、错误映射、自动换站、登录后链路与下载（`cjpm run`） |

---

## 免责声明

- 本库**仅供学习与研究**。Z-Library 的可用性、合法性以及使用条款由其运营方与
  用户所在司法辖区的法律决定，与本库无关；请自行确认使用场景合法合规。
- 本库不提供、不内置、不缓存任何书籍内容，只封装公开可访问的接口。
- 接口路径、字段、鉴权方式均来自社区逆向文档（来源见 `doc/eapi-endpoints.md`），
  可能随时失效；本库对由此造成的任何损失不承担责任。
- 请勿把 `remix_userkey` 等账号凭证写进日志、仓库或公开渠道。
- 本仓库当前**未附带 LICENSE 文件**；如需使用请先与仓库维护者确认授权。
