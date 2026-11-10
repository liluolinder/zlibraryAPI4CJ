# Agent.md — zlibraryAPI4CJ 开发指南

> 本文件面向「后续接手本库的 AI Agent 或人类开发者」，记录**必读的上下文、
> 硬约束、API 约定与验证方式**。读完它应当能直接开始改动，而不需要重新
> 逆向一遍现有代码。
>
> 运行期踩坑与决策证据见 [`MEMORY.md`](MEMORY.md)；
> 调用方手册见 [`API_USAGE.md`](API_USAGE.md)；
> 旧版（v1）到新版（v2）的迁移对照见 [`doc/feature_api.md`](doc/feature_api.md)；
> eapi 端点事实清单见 [`doc/eapi-endpoints.md`](doc/eapi-endpoints.md)。

---

## 1. 项目定位

`zlibraryAPI4CJ` 是 **Z-Library EAPI 的仓颉（Cangjie）静态库**，按功能划分子包，
把社区逆向出来的 eapi 接口（登录、图书、搜索、用户、站点信息）做成
类型安全、可复用、符合仓颉语言习惯的库。

- 模块名 / 根包：`zlibraryAPI4CJ`
- 输出类型：**static**（`cjpm.toml` 中 `output-type = "static"`）
- 语言 / 编译器：仓颉 **1.2.0**（`cjc` / `cjpm`），宿主平台 `x86_64-w64-mingw32`
- HTTP：[LinderHttp](https://gitcode.com/LiquidStudio/LinderHttp) 2.0（本地 `path` 依赖）
- JSON：`stdx.encoding.json`（**手动容错解码，不用宏**）
- 版本：`2.4.0`（`2.0.0` = 按 bbapi 模式重写的第二版；`2.1.0` 增加站点池 /
  种子站换站 / 请求自动重试；`2.2.0` 统一异常类型——对外只抛 `ZlibError`；
  `2.2.1` 修复启动凭证丢失；`2.2.2` 底层 `detail` 改用 `HttpError.describe()`；
  `2.3.1` 明确 `message`/`detail` 分工；`2.4.0` 对齐 bbapi——底层异常统一
  归 `Cangjie`，移除 `Transport`/`Io` 两个类别）

**静态库不能有 `main`**。可运行验证放在独立消费工程里
（本仓库内的 `doccheck/` 就是这样的消费工程，见第 11 节）。

> 本库**不是** Z-Library 官方库，接口路径与字段来自社区逆向文档
> （来源见 `doc/eapi-endpoints.md`）。Z-Library 的域名、字段、鉴权方式
> 都可能随时变化，所以代码里所有「不稳定」的假设都写成了容错逻辑。
> 使用前请阅读 README 末尾的免责声明。

---

## 2. 硬约束（改动前必看）

| 约束 | 说明 |
| --- | --- |
| `output-type = "static"` | 不要改成 executable；不要往 `src/` 加 `main()` |
| `cjc-version = "1.2.0"` | 与工具链一致；不要降级到 1.1.0（旧版写法依赖已移除的 API，见 MEMORY） |
| HTTP 依赖 | `linderHttp = { path = "C:/Project/Cangjie/LinderHttp" }`，依赖名大小写必须与对方 `cjpm.toml` 的 `name` 完全一致 |
| JSON 依赖 | 只用 `stdx.encoding.json`；**不要**引入 CJson（原因见 MEMORY，「为什么不用 CJson」） |
| 平台配置 | `[target.x86_64-w64-mingw32]` 段必须保留 `compile-option = "--cfg \"ohos=false\""`、`link-option = "-lcrypt32"` 与 stdx 的 `bin-dependencies.path-option` |
| 编译选项 | 主工程 `compile-option = "-Woff unused"`；不要随手加 `-Werror`（会把他人的 `unused` 变成构建失败） |
| 写作用域 | 文档类改动只碰 `*.md`、`doc/**`、`doccheck/**`；**不要**为了改文档去改动 `src/**` 与 `cjpm.toml` |
| 提交 | 本仓库由 Lead/维护者统一提交；子任务禁止自行 `git commit` |

`cjpm.toml` 里除 Windows 外的 target 段（ohos / android / ios）是给
鸿蒙/移动端交叉编译预留的，改 Windows 相关字段时**不要**动它们。

---

## 3. 子包结构与依赖方向

```
zlibraryAPI4CJ (root: 只做 public import core.* 与 model.*)
├── core    客户端 / 凭证 / 站点探测 / 信封 / 错误 / 查询串 / 文本截断
├── model   跨子包共享的数据模型（图书 / 用户 / 下载信息 / 分页）
├── login   邮箱密码登录、remix 凭证登录、注册 / 找回密码 / 第三方 token 登录
├── book    图书详情、相似图书、下载信息、收藏 / 取消收藏 / 删除、发送到 Kindle/邮箱、落盘
├── search  图书搜索、最热门、最近上传
├── user    个人资料、收藏列表、下载历史、个性化推荐、资料更新
└── info    站点信息（语言 / 扩展名 / 域名 / 套餐），返回原始 JSON
```

**依赖方向严格单向：`core ← model ← 业务子包`，业务子包之间互不 import。**

原因：Z-Library 的 `BookInfo` 同时出现在 `book` / `search` / `user` 的返回值里，
`ZlibUser` 同时被 `login` 与 `user` 使用。若每个业务子包各定义一份模型，
要么重复代码，要么让子包互相 import、把依赖图变成网。所以共享模型统一下沉到
`model`——这也是本库与 bbapi（模型放业务子包内）**唯一的架构差异**。

### 3.1 各子包文件与职责

| 子包 | 文件 | 职责 |
| --- | --- | --- |
| `core` | `core_pkg.cj` | 包文档、常量 `ZLIB_API_PREFIX` / `ZLIB_DEFAULT_SITE_LANGUAGE` |
| | `client.cj` | `ZlibClient`（请求 / 信封解包 / 自动重试 / 派生 / 下载）、`ZlibClientConfig` |
| | `site.cj` | `ZlibSites`（自定义站 + 种子站换站）、`ZlibSiteSnapshot`、`planSiteRefresh` / `fetchSeedDomains` / `extractDomainList` / `normalizeDomain` |
| | `credential.cj` | `ZlibCredential`：`remix_userid` / `remix_userkey` / `siteLanguage` |
| | `host.cj` | `ZlibHost`、`ZlibProbe`、`probeSite` / `checkAccess` / `canAccessZlib` / `resolveZlibHost` |
| | `envelope.cj` | `ZlibEnvelope` + 宽松 JSON 读取（`readString` / `readInt` / `decodeEach` …） |
| | `error.cj` | `ZlibErrorKind`、`ZlibError` |
| | `query.cj` | `Query`、`formEncode`、`withQuery`、`appendPair`、`percentEncode` |
| | `text.cj` | `truncateRunes` / `truncateBytesSafe`（UTF-8 安全截断） |
| | `core_test.cj` | 离线单测（站点规范化、凭证、查询串、信封、错误、客户端生命周期） |
| `model` | `book.cj` | `BookInfo`（详情）、`BookInfoBrief`（列表项） |
| | `user.cj` | `ZlibUser` |
| | `download.cj` | `DownloadInfo`（签名下载链接 + 文件名生成） |
| | `page.cj` | `Pagination`、`BookPage` |
| | `model_test.cj` | 固定 JSON 样本的解码 / 派生测试 |
| `book` | `book.cj` | `BookApi`：`info` / `infoOf` / `similar` / `similarOf` / `file` / `fileOf` / `formats` / `save` / `saveBrief` / `unsave` / `unsaveBrief` / `remove` / `sendTo` / `download` / `downloadBook` |
| | `book_pkg.cj` | 包文档（覆盖的端点表） |
| | `book_test.cj` | 离线单测（查询参数、落盘前置校验、URL 拼接） |
| `login` | `login.cj` | `LoginApi` / `LoginResult`（`login` / `loginWithToken` / `loginClient` / `loginTokenClient` / `register` / `requestPasswordRecovery` / `resendConfirmation` / `tokenSignIn`） |
| | `login_pkg.cj` | 包文档 |
| | `login_test.cj` | 离线单测（凭证派生、表单构造、LoginResult 不可变） |
| `search` | `search.cj` | `SearchApi`：`search` / `mostPopular` / `recently` |
| | `search_pkg.cj` | 包文档 |
| | `search_test.cj` | 离线单测（表单编码、数组参数保留重复 key、固定 JSON 解码） |
| `user` | `user.cj` | `UserApi`：`profile` / `saved` / `downloaded` / `recommended` / `update` / `hideBanner` / `donations` |
| | `user_pkg.cj` | 包文档 |
| | `user_test.cj` | 离线单测（分页 query、update 只发非 None 字段） |
| `info` | `info.cj` | `InfoApi`：`site` / `languages` / `extensions` / `domains` / `plans`（均返回 `JsonObject`） |
| | `info_pkg.cj` | 包文档 |
| | `info_test.cj` | 离线单测（信封解析、原始 JSON 读取） |

每个子包一个 `*_pkg.cj`，只放 `package` 声明、必要的 import 和**包级文档注释**
（说明这个包覆盖哪些端点、有哪些坑）。根包 `src/zlibraryAPI4CJ.cj` 只做
`public import zlibraryAPI4CJ.core.*` 与 `public import zlibraryAPI4CJ.model.*`。

### 3.2 命名与可见性

- 包名：`zlibraryAPI4CJ.core` / `.model` / `.login` / `.book` / `.search` / `.user` / `.info`。
- 根包导出后，调用方写 `import zlibraryAPI4CJ.*` 拿客户端与模型，
  再按需 `import zlibraryAPI4CJ.book.*` 等。
- 纯内部实现（如 `resolveLocation`、`originOf`、`jsonToInt`）一律 `internal func` 或
  `private func`，**不要**为了测试方便改成 `public`；测试放在同包内即可访问 `internal`。

---

## 4. API 设计约定（改代码时请保持）

1. **接口函数都是 `public static func`，第一个参数是 `ZlibClient`。**
   仓颉没有包级扩展函数，把 client 显式传参比让 API 类持有状态更清晰；
   接口函数本身无状态，同一个客户端可以并发复用。

2. **`None` 语义优先于异常。**
   - 「本来可能没有数据」→ 返回 `?T` 或空集合（`BookPage.first()`、`readOptionalString`）；
   - 「业务失败」→ 抛 `ZlibError`（`success=0`、未登录、书不存在）；
   - 「传输失败」→ 在本层（`execute`）参与重试；退出 `execute` 前统一包装成
     `ZlibError`（原始 `HttpError` 在 `cause`），**对外只暴露 `ZlibError`**。
    调用方只需要一个 `catch (err: ZlibError)`。

3. **列表分页封装成 `BookPage` 而不是裸数组。**
   `BookPage` 带 `pagination`、`hasMore()`、`nextPage()`、`first()`；
   只给数组会迫使每个调用方自己重新推一遍分页逻辑。

4. **客户端不可变，站点状态受控可变。** 凭证 / 配置 / 显式站点不能原地改，
   派生用 `withCredential` / `withBaseUrl` / `withHost` / `withSites`
   （共享同一个底层 `HttpClient` 与连接池）。
   例外是 `ZlibSites`：它用 `Mutex` 保护「当前自定义站 + 种子站列表」，
   自动换站会 `adopt` 新地址（2.1.0 需求：失败后覆盖自定义站并自动重试）。
   `withCredential` 派生的客户端**共享**同一份 `ZlibSites`，`withBaseUrl` 则派生独立副本。
   同一进程里同时需要游客态与登录态时，派生两个客户端即可干净隔离。

5. **能复用就复用。**
   - 取「根上的某个对象字段」→ `client.getObject(path, field, decoder)`；
   - 取「根上的某个数组字段」→ `client.getObjects(path, field, decoder)`；
   - 取原始信封 → `client.getEnvelope(path, query: ...).unwrap(path: path)`；
   - 解码 JSON → 模型类的 `fromJsonObject`；
   - 截断字符串 → `truncateRunes` / `truncateBytesSafe`
     （**绝对不要写 `text[0..n]`**，`String` 下标是字节下标，见 MEMORY）；
   - 编码 query / 表单 → `Query` / `formEncode`（同名参数不能去重）。

6. **解码器用闭包传参，不要试图做泛型静态接口分派。**
   `client.getObject<T>(path, field, decoder: (JsonObject) -> T)` 的设计原因：
   仓颉当前不支持「对泛型形参做静态接口成员分派」，
   `{ obj => BookInfo.fromJsonObject(obj) }` 既类型安全又零反射。

7. **文档注释写「为什么」而不只是「是什么」。**
   尤其是与外部文档不一致、或踩过坑的地方（字段类型漂移、域名限制、
   百分号编码、个人域名下载），必须写明实测结论，否则下一个人会照文档再踩一次。

---

## 5. 响应信封与容错解码

eapi 的两个稳定锚点：

- 成功：`{"success": 1, ...}`，业务数据直接平铺在根上（`user` / `book` /
  `books` / `file` / `pagination` …）；
- 失败：`{"success": 0, "error": "..."}`（部分老接口用 `msg`；`success` 也可能是
  `true` 或 `"1"`）。

`ZlibEnvelope` 只做三件事：解析根对象、判定 `success`、按字段取子对象/数组。
**不要**给不同接口各写一个信封类，也不要在信封层假设业务字段名。

业务子包的标准写法：

```cangjie
// 取根上的对象字段（book / user / file）
client.getObject("/book/${id}/${hash}", "book", { obj => BookInfo.fromJsonObject(obj) },
    query: switchLanguageQuery(switchLanguage))

// 取根上的数组字段（books）
client.getObjects("/book/${id}/${hash}/similar", "books",
    { obj => BookInfoBrief.fromJsonObject(obj) })

// 形状不稳定的接口：直接返回原始根对象
let path = "/book/${id}/${hash}/formats"
client.getEnvelope(path).unwrap(path: path)
```

### 5.1 宽松读取是硬约定，不是可选优化

Z-Library 的字段类型会漂移（同一字段可能是数字或字符串、布尔可能是 `0/1`、
可选字段会整条缺失）。所以模型解码**一律**走 `core` 的读函数：

| 函数 | 语义 |
| --- | --- |
| `readString(obj, key)` | 字符串；数字/布尔转文本；缺失返回 `""` |
| `readStringOr(obj, key, fallback)` | 同上，空串时用 `fallback` |
| `readOptionalString(obj, key)` | 缺失 / `null` / 空串 → `None` |
| `readInt(obj, key)` / `readIntOr` | 兼容整数、浮点、数字字符串、布尔 |
| `readFloat(obj, key)` | 兼容整数与数字字符串 |
| `readBool(obj, key)` / `readBoolOr` | 兼容 `0/1`、`"true"/"false"` |
| `objectFieldOf(obj, key)` | 对象字段，否则 `None` |
| `arrayFieldOf(obj, key)` | 数组字段，否则空数组 |
| `decodeEach(items, decoder)` | 逐条解码，**跳过单条失败**（列表接口默认用它） |
| `decodeEachOrThrow(items, decoder)` | 逐条解码，任一条失败即抛错（需要严格语义时用） |

判断标准：**单条脏数据不能拖垮整页结果**。需要严格语义的场合才用
`decodeEachOrThrow`，并在文档注释里写明为什么。

### 5.2 错误映射

`ZlibEnvelope.unwrap()` 会把服务端文案做一次粗分类：

| 服务端文案包含 | 映射到 |
| --- | --- |
| `login` / `log in` | `ZlibErrorKind.NotLoggedIn` |
| `not found` / `nothing has been found` | `ZlibErrorKind.NotFound` |
| 其它 `success=0` | `ZlibErrorKind.ApiFailure`（保留 `serverMessage` 原文） |

非 JSON 响应（风控页、登录页、空响应）→ `ZlibErrorKind.BadResponse`，
错误消息里只放**截断后的**响应片段（`truncateBytesSafe`），不要把整页 HTML 塞进异常。
HTTP 层失败（DNS / TLS / 超时 / 池满）在 `execute` 里参与重试，
最终由 `ZlibError.wrapUnhandled` 统一包装成 `ZlibError(Cangjie)`（原始 `HttpError` 在 `cause`），
不要在这里另造异常类型。

### 5.3 站点管理与自动重试（2.1.0）

请求链路：业务 API → `client.getObject/getEnvelope/getRaw/...` →
内部 `execute(operation)`（自动重试外壳）→ `sendGet/sendPostForm`。
`execute` 的规则必须保持：

| 情况 | 行为 |
| --- | --- |
| 底层 `HttpError` / 未包装异常 | 按 `config.maxAttempts` 重试；**同样会先换站再重试**（DNS 失败是最常见换站触发点）；对外统一包装成 `ZlibError(Cangjie)` |
| `ZlibError(BadResponse/Forbidden)` | 同上（`shouldSwitchSite` 判定） |
| `ZlibError(ApiFailure/NotLoggedIn/NotFound/Closed)` | **不重试**，原样抛出 |
| `download/fetchBytes` | 只重试传输异常，**不换站**（下载链接是个人域名，换站无意义） |

换站细节：

- 触发后调用 `refreshSite()`：用种子站列表依次 `GET /eapi/info/domains`
  拿候选域名（也兼容种子站 3xx `Location`；若种子站刚返回过域名、说明它本身可达，
  允许直接兜底到种子站，避免 HEAD 偶发超时白等）；
- 探测到第一个可用地址就 `sites.adopt(...)` **覆盖自定义站**，下一次尝试立即生效；
- **冷却窗口**：`ZlibSites.beginRefresh()` 默认 30 秒一次，避免失败风暴打爆种子站；
- 每次换站最多探测 `planSiteRefresh(maxCandidates: 4)` 个候选、每个 5 秒超时，
  避免一次换站把请求卡几分钟（实测一次换站约 20~55 秒，取决于被墙域名数量）；
- 全部失败**统一抛 `ZlibError`**（非 `ZlibError` 的底层异常由 `wrapUnhandled` 包装，原始异常在 `cause`）；
- 新增接口无需关心重试：只要走 `client.getXxx/postXxx` 就自动具备该能力。
- **未包装的底层异常也会重试**：实测 LinderHttp 偶尔把 stdx 的 TLS/读写异常
  直接漏到外层（不是 `HttpError`），`execute` 用兜底 `catch (err: Exception)`
  按传输失败处理，否则一次网络抖动就会让业务调用直接失败。
- **底层异常分类（2.4.0，对齐 bbapi）**：所有非业务异常统一归 `Cangjie`——
  LinderHttp `HttpError`、`std.fs.FSException`、stdx 异常都是 `Cangjie` 一类，
  来源看 `cause`（`HttpError` / `FSException`）；不再有 `Transport` / `Io` 类别。
  `Cangjie.isRetryable` 由 `cause` 决定（可重试的 `HttpError` → true）；
  `shouldSwitchSite(Cangjie) = false`（换站不解决底层问题，内部重试仍按异常类型走）。
- **下载单独超时**：`config.downloadTimeout`（默认 5 分钟）用于下载/取字节；
  API 的 30 秒读超时对文件太短。`ensureDirectory` 先判断再创建，可重复调用。
- **启动凭证（2.2.1）**：`create(credential:)` 会把凭证预置进底层 Cookie 存储。
  LinderHttp 在 Cookie 存储非空时会用存储内容覆盖手写的 `Cookie` 头，只靠手写头
  会在服务端下发 `Set-Cookie` 后的下一次请求丢凭证（bbapi 同类 bug）。
  换站后 `ensureCredentialCookies` 自动补种；不要绕过客户端自己拼 Cookie 头。
- **文案约定（2.3.1）**：`ZlibError.message` 是纯文案（不含类别前缀），
  `detail = "[kind] " + message` 才带前缀；日志用 `detail`，要服务端原文用 `message`。
- **底层 detail（2.2.2）**：包装 `HttpError` 时 `detail` 用 `HttpError.describe()`
  而不是 `message`，文本形如
  `[Cangjie] 底层请求失败：Protocol [https://x/eapi/...] attempts=3: Failed to resolve ...`；
  `StatusError` 还带状态码与响应体开头；排查时仍可从 `err.cause` 拿原始 `HttpError`。

> ⚠ **已知环境问题**：本机（Windows + Cangjie 1.2.0 stdx）实测登录 POST 偶发
> ~2/10 次进程直接崩溃（exit -1，事件日志 `0xc0000374` = ntdll 堆损坏），
> 同一机器上另一个用 LinderHttp 的项目也复现过，判断为底层 TLS/网络库的原生问题，
> 不是本库逻辑。集成测试请用进程级重试；排查时 `ZLIB_TEST_STAGE=login` 可单独复现。

---

## 6. 仓颉语言特性使用清单

新增代码应对齐下表（都是本库已经在用的写法）：

| 特性 | 用在哪 | 注意 |
| --- | --- | --- |
| `prop` 计算属性 | `ZlibCredential.isLoggedIn`、`ZlibErrorKind.code`、`ZlibClient.baseUrl`、`ZlibEnvelope.success` | 计算属性不落字段；**实现 `Resource` 时 `isClosed` 必须是方法而不是 `prop`** |
| `Resource` 接口 | `ZlibClient`、`ZlibClientConfig` 的 `close()` / `isClosed()` | `isClosed` 写成 `prop` 会与接口函数冲突，编译失败 |
| 无参枚举 + `Equatable` | `ZlibErrorKind` | 无参枚举默认不能用 `==`，需显式 `operator func ==` / `!=`（本库按 `code` 比较） |
| `match` 模式匹配 | 枚举映射、`JsonValue.kind()` 分派、`Option` 解包 | 优先 `if (let Some(x) <- v)` 或 `match`，不要 `getOrThrow()` 处理预期内的缺失 |
| `public import` | 根包 re-export `core.*` / `model.*` | 只允许在根包做 re-export；业务子包内部用普通 `import` |
| 闭包作为解码器 | `getObject(..., decoder)`、`decodeEach` | 见 4.6；不要试图用泛型静态接口分派 |
| 具名参数 | `client.getEnvelope(path, query: ...)`、`create(baseUrl: ...)` | **具名参数必须写在位置参数之后**；`= None` 的默认值不要重复传 |
| 字符串插值 | 所有日志与错误消息 | 插值目标必须实现 `ToString`；`ZlibEnvelope` 只写了 `toString()` 但**没有**声明 `<: ToString`，所以 `${envelope}` 编译不过 |
| 字符字面量 | —— | 单引号是 **Rune/Char**（`'a'`），不是字符串；旧代码 `field<?String>('date_saved', ...)` 是类型错误 |
| 块注释可嵌套 | 文档注释 `/** */` | 文档注释里**不能**出现 `/*`（会开启嵌套注释，吞掉后面的代码） |

> 仓颉的 `import` 是**按文件**生效的（不是按包）：每个用到 `JsonObject`、
> `ZlibError`、`BookInfo` 的文件都要自己写 import。旧版 `importFile.cj`
> 试图在一个文件里集中 import 供其它文件共享，是行不通的（见 MEMORY）。

---

## 7. 构建、测试与验证

### 7.1 构建

```powershell
cd C:\Project\Cangjie\zlibraryAPI4CJ
cjpm build
```

### 7.2 单元测试（全部离线）

```powershell
cd C:\Project\Cangjie\zlibraryAPI4CJ
cjpm test --no-progress                       # 全部子包（当前应为 TOTAL 143 / PASSED 143）
cjpm test --no-progress src\core src\model    # 只跑部分包（仍会先编译整个模块）
```

> ⚠ `cjpm test <子包>` 仍然要先把**整个模块**编译通过。只要有一个并行开发的
> 子包编译失败，单包测试也跑不起来——这时先等该包修好，或只用
> `cjpm build --target-dir` 隔离排查。

### 7.3 预检脚本（写新文件前）

```powershell
python C:\Users\liluo\.agents\skills\cangjie-lang-features\scripts\check_cangjie_closure.py <文件>
```

要求 **exit 0 且 0 warning**。它会拦一批仓颉语法/习惯错误
（空 `match` 分支 CJ044、数字类型后缀 CJ038、`== None` CJ040、
整数极值名 CJ026、`~` 取反 CJ039 等）。
已知误报：`case X => "字符串字面量"` 这种「分支表达式是纯字面量」的写法会被
CJ044 误判为空分支，规避写法见 MEMORY。

### 7.4 文档示例编译校验（`doccheck/`）

`doccheck/` 是一个 **executable** 消费工程，通过 `path` 依赖主工程，
把 `API_USAGE.md` 里的每段示例落成可编译函数。它是文档与代码一致性的
唯一自动化保障：

```powershell
cd C:\Project\Cangjie\zlibraryAPI4CJ\doccheck
cjpm build
```

**改了任何 public 签名，必须同步改 `API_USAGE.md` 与 `doccheck/src/main.cj`，
并让 `doccheck` 构建通过。** 文档示例编译不过，是本库最容易发生的事故。

### 7.5 联网集成测试（`integration/`）

`cjpm test` **不联网**（固定 JSON 样本）。验证「接口是否还能用」用独立消费工程
`integration/`（executable，path 依赖主工程）：

```powershell
cd C:\Project\Cangjie\zlibraryAPI4CJ\integration
cjpm run
```

- 2026-11-10 在 `https://zh.eva101.ru` 实测 **36/36 通过**（搜索 / 榜单 / 详情 /
  相似 / 格式 / 站点信息 / 错误映射 / 自动换站重试）；**登录后链路 16/16 通过**
  （登录 / token 登录 / profile / 收藏 / 推荐 / 历史 / 收藏取消 / 换链接 / 真实下载）；
- 账号密码只通过环境变量传入（`ZLIB_TEST_EMAIL` / `ZLIB_TEST_PASSWORD`），
  绝不写进仓库；`ZLIB_TEST_ONLY_AUTH=1` 只跑登录链路，
  `ZLIB_TEST_STAGE=login|token|read|write|file|cleanup` 可分段调试，
  `ZLIB_TEST_DOWNLOAD=1` 才真正下载（消耗每日配额）；
- 镜像会轮换：先看 `probeSite` 检查，失败就改 `integration/src/main.cj` 的 `DOMAIN`；
- 本机对 `z-library.sk` 等域名不可达（超时），但 `zh.eva101.ru` 可用；
  集成测试里故意用死域名 + 种子站来验证 2.1.0 的换站能力。

---

## 8. 新增一个接口的标准流程

1. **查事实**：在 `doc/eapi-endpoints.md` 与外部社区文档
   （baroxyton/zlibrary-eapi-documentation、bipinkrish/Zlibrary-API、
   sertraline/zlibrary）里确认路径、方法、参数、是否需要登录；
   文档没写的字段类型标成「推断」，不要伪装成实测。
2. **归属子包**：登录 → `login`；图书 → `book`；搜索 → `search`；
   账号/收藏/历史 → `user`；站点元信息 → `info`。
   **不要**新建跨子包依赖。
3. **建模型**（如果响应是强类型）：加到 `model` 对应文件，
   字段一律 `public var` + 默认值，解码函数 `fromJsonObject` 只走宽松读取。
   形状不稳定的接口干脆返回 `JsonObject`，不要硬造模型。
4. **写接口函数**：在业务子包加 `public static func`，第一参数 `client: ZlibClient`，
   用 `getObject` / `getObjects` / `getEnvelope` 之一取数据。
   需要在路径里拼 id/hash 的，写清「id 和 hash 必须来自同一本书」。
5. **补单元测试**：在对应 `*_test.cj` 加固定 JSON 样本 / 纯函数断言。
   **不联网**；网络部分不测。
6. **跑验证**：`check_cangjie_closure.py` → `cjpm build` → `cjpm test`。
7. **补文档**：`API_USAGE.md` 加章节（参数表 + 返回值 + 示例 + 注意事项），
   `doc/eapi-endpoints.md` 加端点行，`doccheck/src/main.cj` 加一个校验函数。
8. **补 MEMORY**：如果发现了新的字段漂移 / 域名行为 / 语言坑，记进 `MEMORY.md`。

---

## 9. 代码风格

- 注释与文档注释用**中文**；术语保留英文原词（endpoint、query、hash、remix_userkey）。
- 文档注释解释「为什么」，尤其是与官方/社区文档不一致、或违反直觉的地方。
- 每个子包一个 `xxx_pkg.cj`，只放包声明 + 包文档；不要在里面放业务代码。
- 数据模型集中在 `model`，接口函数集中在 `<功能>.cj`；
  单文件控制在 400 行上下，超了就按「模型 / 接口 / 测试」拆。
- 常量用 `public let`，不要用可变全局变量（旧版的 `public var zlibBaseUrl`
  是反面教材：改一个全局变量会影响所有客户端，见 MEMORY）。
- 每行代码宽度约 100 列；长参数列表按「一个参数一行、续行缩进」排版。
- 新增 public API 必须写文档注释，并同步 `API_USAGE.md` + `doccheck`。

---

## 10. 当前状态与后续建议

- 2.1.0 新增站点池与请求自动重试（`ZlibSites` / 种子站换站），
  2026-11-10 在 `zh.eva101.ru` 实测 `integration/` 36/36 通过；
- 2.2.0 统一异常类型：对外只抛 `ZlibError`，`HttpError`/stdx/文件系统异常包装进
  `cause`，调用方一个 catch 管全部（见 §5.3、`API_USAGE.md` 第 6 章）；
- 七个业务子包全部完成（`core` / `model` / `login` / `book` / `search` / `user` / `info`），
  每个包都有离线单测；`cjpm test --no-progress` 当前为 **TOTAL 143 / PASSED 143 / FAILED 0**。
- `doccheck/` 已建立，`cd doccheck && cjpm build` 通过；`API_USAGE.md`
  的每个示例在 `doccheck/src/main.cj` 里都有一个对应函数。
- 未覆盖的 eapi 能力：`/user/donations` 的形状不稳定（返回原始 JSON）；
  `/book/{id}/{hash}/formats` 已按实测形状返回强类型 `ArrayList<BookFormat>`；`/papi`、`/rpc.php`
  等注册验证码流程未覆盖；书单（booklist）未覆盖。
- 所有接口**未经真实站点回归**（开发机对候选镜像 503/超时），
  字段事实以 `doc/eapi-endpoints.md` 的社区文档标注为准。
- 若 Z-Library 恢复稳定的官方域名，可把 `ZlibHost.MIRRORS` 收敛，
  但**不要**删除 `baseUrl` 配置入口——域名轮换是这个项目的长期约束。

---

## 11. 快速排错表

| 现象 | 先查这里 |
| --- | --- |
| 构建报 `undefined reference` / TLS 相关链接错误 | `cjpm.toml` 的 `[target.x86_64-w64-mingw32]`：`-lcrypt32`、stdx `path-option` |
| 请求返回 `BadResponse`（非 JSON） | 域名失效 / 被风控页替换；先 `probeSite` / `resolveZlibHost` |
| 接口一直 `NotLoggedIn` | 登录后是否用 `withCredential` 派生了客户端；`remix_userkey` 是否为空 |
| 搜索/收藏分页拿不到第二页 | 看 `BookPage.pagination` 的 `current` / `total_pages` 是否为 0（服务端偶尔不给） |
| 下载链接 403 / 404 | 链接带签名且常常指向个人域名，过期就重调 `BookApi.file()` |
| 中文被截断成乱码 | 用了 `text[0..n]`，改用 `truncateRunes` / `truncateBytesSafe` |
| `cjpm test src\xxx` 报别的包的错 | 整模块编译；先修好那个包，或等它完成 |
| 文档示例编译报「找不到成员」 | `doccheck` 没跟着改；以源码签名为准修文档 |
| `doccheck` 报 target 段相关链接错误 | `doccheck/cjpm.toml` 少抄了主工程的 `[target.x86_64-w64-mingw32]` 三段配置 |
| 换站过于频繁 / 种子站被限流 | `ZlibSites.beginRefresh()` 冷却窗口（默认 30s）与 `refreshInterval`；确认没有每次都 `refreshSite(force: true)` |
| 换站后仍全部失败 | 种子站是否可达、`/eapi/info/domains` 是否返回域名；看 `client.sites.snapshot()` 的 `refreshCount` / `lastRefreshAtMillis` |
| 请求偶尔变慢（几十秒） | 自动换站会串行探测候选域名（每个 5s 超时、最多 4 个）；可调小 `maxCandidates` 或关掉 `autoRetry` |
| 集成测试全红 | 镜像失效；改 `integration/src/main.cj` 的 `DOMAIN`，先用 `probeSite`/`checkAccess` 确认域名可用 |
| 进程直接退出（exit -1，事件日志 `0xc0000374` ntdll 堆损坏） | 底层 stdx/LinderHttp 的 TLS 原生层问题（本机实测登录 POST 约 2/10 次，其它项目也复现）；进程级重试或升级 SDK；`ZLIB_TEST_STAGE=login` 可单独复现 |
| 下载报 `read data timeout` | 下载 CDN 慢；调大 `config.downloadTimeout`（默认 5 分钟），API 的 30 秒读超时对文件不够 |
| `Directory.create` 对已存在目录抛 `FSException` | 用 `ensureDirectory`（库内部已封装）；调用方自建目录前先 `exists()` |
| 报错 `ZlibError(Cangjie)` | Cangjie 运行时/标准库异常（非网络层）；看 `detail`/`cause`，多为环境或底层依赖问题 |
| 启动时带了凭证，第一次请求成功、之后变游客 | LinderHttp 用 Cookie 存储覆盖手写 Cookie 头；本库已用 `seedCredentialCookies` 预置、换站后补种。绕过客户端自拼请求时需自己维护 Cookie 存储 |
