# 旧版（v1）→ 新版（v2）API 迁移指南

> 本文件面向**从 v1 迁移过来的调用方**，也用于记录「v2 为什么长成这样」。
> v2（commit `f8bcfd4` 起）是按 bbapi 模式**推翻重写**：静态 API + 不可变客户端 +
> 模型下沉 + 容错解码。v1 的类结构、方法名、返回类型都变了，
> **不是**换包名就能编译的兼容升级。
>
> v1 代码仍在 git 历史里，可随时取回对照：
>
> ```powershell
> cd C:\Project\Cangjie\zlibraryAPI4CJ
> git show af70e1e:src/client.cj
> git show af70e1e:src/dataModel/bookInfo.cj
> git show af70e1e:src/common/commons.cj
> ```
>
> 各接口的参数表与示例见 [`API_USAGE.md`](../API_USAGE.md)；
> 端点事实与资料可信度见 [`eapi-endpoints.md`](eapi-endpoints.md)。

---

## 1. 一句话总结变化

| 维度 | v1 | v2 |
| --- | --- | --- |
| 调用形态 | `client.search(...)`、`book.getDownloadInfo(cookie: c)`——方法散落在各个类上 | 全部 `public static func`，**第一个参数永远是 `ZlibClient`** |
| 身份传递 | 每个方法多一个 `cookie: String` 参数 | 凭证挂在客户端上，用 `withCredential` 派生 |
| 站点地址 | 全局可变变量 `zlibBaseUrl` / `zlibEAPI` + `changeUrl()` | `ZlibHost` 值对象 + `client.withBaseUrl()` / `resolveZlibHost()` |
| 失败表示 | 每个响应带 `success: UInt8`，调用方自己判断 | 统一**抛 `ZlibError`**（2.2.0 起传输/IO 异常也包装进来，原始异常在 `cause`） |
| 模型 | 各 `dataModel/*.cj` 里的类，**模型自己发 HTTP** | `model` 子包只做解码与派生，**不发请求** |
| 解码 | `Serializable.deserialize(DataModel)` + `strOr/u64Or` 兜底 | `stdx.encoding.json` + `readString/readInt/...` 宽松读取 |
| 数值类型 | `UInt64` | `Int64`（与服务端 JSON 数值语义一致，便于算差值） |
| 分页 | 调用方自己读 `pagination` | `BookPage` 封装 `hasMore()` / `nextPage()` |
| 全局状态 | `public var` 配置 | 无全局可变状态（客户端实例即配置） |

---

## 2. 类型对照表

| v1 类型 | v2 类型 | 说明 |
| --- | --- | --- |
| `ZlibClient`（实例方法集合） | `ZlibClient`（静态入口 `create` / `fromHttpClient`）+ 各 `XxxApi` | v2 的客户端只管连接/身份/信封/下载，业务在子包里 |
| `GetUserInfoOrLoginRes` | `ZlibUser`（直接返回） | 不再包 `success`；失败是异常 |
| `ZlibUserInfo` | `ZlibUser` | 字段名 `todayDownloadNum`→`downloadsToday`、`downloadLimit`→`downloadsLimit`；`cookie` 属性由 `ZlibCredential.toCookieHeader()` 取代 |
| `GetBookRes` | `ArrayList<BookInfoBrief>` | 列表接口直接返回数组 |
| `GetBookInfoRes` | `BookInfo` | 直接返回详情对象 |
| `GetDownloadInfoRes` | `DownloadInfo` | 直接返回下载信息 |
| `GetBookWithInfoAndPaginationRes` | `BookPage` | `books` + `pagination` 已封装，并带 `hasMore()` / `nextPage()` / `first()` |
| `Pagination`（字段 `UInt64`） | `Pagination`（字段 `Int64`） | 字段名不变；新增 `hasMore()` / `nextPage()` |
| `BookInfo`（带 HTTP 方法） | `BookInfo`（纯模型）+ `BookApi` | 旧 `saveBook` / `unSaveBook` / `getSimilarBook` / `getDownloadInfo` 全部移到 `BookApi` |
| `BookInfoBrief`（带 HTTP 方法） | `BookInfoBrief`（纯模型）+ `BookApi` | 同上 |
| `DownloadInfo`（含 `download()`） | `DownloadInfo`（纯模型）+ `BookApi.download` / `client.download` | `fileName` 属性 → `fileName()` 方法 |
| `common.zlibBaseUrl` / `zlibEAPI` / `changeUrl` | `ZlibHost` / `ZlibClient.baseUrl` / `withBaseUrl` / `ZlibSites` | 不再有全局变量；2.1.0 起「失败自动换站」由 `ZlibSites`（自定义站 + 种子站）管理 |
| `common.canAccessZlib` / `checkAccess` | 同名顶层函数（签名变化） | 探测逻辑保留；自动换站用 `resolveZlibHost` 或 `ZlibClient.create(..., seeds: ...)` |
| （无） | `ZlibCredential` | v1 用裸 cookie 字符串，v2 有了类型 |
| （无） | `ZlibError` / `ZlibErrorKind` | v1 只有 `Exception` / `success=0` |
| （无） | `ZlibEnvelope` | v1 每个接口一个 `XxxRes`，v2 统一信封 |

> v1 的 `Serializable<...>` / `serialize()` / `deserialize()` 全部删除：
> v2 不再用 `DataModel` 序列化框架，模型只保留 `fromJsonObject(obj)` 与
> `fromJson(text)` 两个解码入口。

---

## 3. 方法对照表

### 3.1 登录 / 用户

| v1 | v2 | v2 所在子包 |
| --- | --- | --- |
| `client.login(email: String, password: String)` | `LoginApi.login(client, email, password, siteLanguage: ...)` | `login` |
| `client.login(userID: UInt64, userKey: String)` | `LoginApi.loginWithToken(client, userId: Int64, userKey, siteLanguage: ...)` | `login` |
| `userInfo.getPersonalInfo()` | `UserApi.profile(client)` | `user` |
| `userInfo.getSaved(page: UInt64)` | `UserApi.saved(client, order: ..., page: ..., limit: ...)` | `user` |
| `userInfo.getRecommendBook()`（`/user/book/recommended`） | `UserApi.recommended(client)` | `user` |
| （无） | `UserApi.downloaded(client, ...)`（`/user/book/downloaded`） | `user` |
| （无） | `UserApi.update` / `hideBanner` / `donations` | `user` |
| （无） | `LoginApi.register` / `requestPasswordRecovery` / `resendConfirmation` / `tokenSignIn` | `login` |

### 3.2 图书

| v1 | v2 |
| --- | --- |
| `bookInfoBrief.getBookInfo(cookie: ...)` | `BookApi.info(client, id, hash, switchLanguage: ...)` 或 `BookApi.infoOf(client, brief)` |
| `bookInfo.getSimilarBook()` / `brief.getSimilarBook()` | `BookApi.similar(client, id, hash)` / `BookApi.similarOf(client, book)` |
| `bookInfo.getDownloadInfo(cookie: ...)` | `BookApi.file(client, id, hash)` / `BookApi.fileOf(client, book)` |
| `bookInfo.saveBook(cookie: ...)` → `Bool` | `BookApi.save(client, id)` / `BookApi.saveBrief(client, brief)` → `Unit`（失败抛异常） |
| `bookInfo.unSaveBook(cookie: ...)` → `Bool` | `BookApi.unsave(client, id)` / `BookApi.unsaveBrief(client, brief)` |
| （无） | `BookApi.remove(client, id)`（`/user/book/{id}/delete`） |
| （无） | `BookApi.formats(client, id, hash): ArrayList<BookFormat>` |
| （无） | `BookApi.sendTo(client, id, hash, target)` |
| `downloadInfo.download(path: Path, overwrite: Bool)` | `BookApi.download(client, info, dir, overwrite: ...)` / `BookApi.downloadBook(client, id, hash, dir, ...)` |

### 3.3 搜索 / 列表

| v1 | v2 |
| --- | --- |
| `client.search(message, yearFrom: ?UInt16, yearTo: ?UInt16, page: UInt16, limit: UInt16)` | `SearchApi.search(client, message, yearFrom: ?Int64, yearTo: ?Int64, languages: Array<String>, extensions: Array<String>, order: ?String, page: Int64, limit: Int64)` |
| `client.getRecommendBook()`（`/book/most-popular`） | `SearchApi.mostPopular(client, switchLanguage: ...)` |
| （无） | `SearchApi.recently(client)`（`/book/recently`） |

> ⚠ v1 有两个同名意义的「推荐」：
> `ZlibClient.getRecommendBook()` 打的是**全站最热门**（`/book/most-popular`），
> `ZlibUserInfo.getRecommendBook()` 打的是**个性化推荐**（`/user/book/recommended`）。
> v2 把它们拆成 `SearchApi.mostPopular` 与 `UserApi.recommended`，别再混用。

### 3.4 站点

| v1 | v2 |
| --- | --- |
| `common.zlibBaseUrl`（可变全局） | `ZlibClient.create(baseUrl: ...)`；当前值读 `client.baseUrl` |
| `common.zlibEAPI` | `client.eapiUrl`；路径拼接用 `client.apiUrl(path)` |
| `common.changeUrl(url)` | `client.withBaseUrl(url)`（返回新客户端，共享连接池） |
| `common.canAccessZlib(autoRedirect!)` | `canAccessZlib(baseUrl: ..., autoRedirect: ...)`（**不再修改全局地址**） |
| `common.checkAccess(url)` | `checkAccess(url)`（顶层函数，签名兼容） |
| （无） | `probeSite(url)` → `ZlibProbe`（带 `status` / `location` / `reachable`） |
| （无） | `resolveZlibHost(candidates: ...)` → `?ZlibHost`（按候选列表探测） |

---

## 4. 迁移示例

> v1 片段摘自旧版源码（`git show af70e1e:...`），仅作对照，
> **不要**试图在新工程里编译它们——依赖与 API 都已不存在。
> v2 片段是可直接使用的写法（承接上一个片段的变量，按顺序阅读）。

### 4.1 登录 + 登录态客户端

**v1**

```cangjie
import zlibraryAPI4CJ.*

let client = ZlibClient()
let res = client.login(email: "a@b.com", password: "pw")
if (res.success == 1) {
    let userInfo = res.userInfo.getOrThrow()
    // 后续每个调用都要带 cookie
    let saved = userInfo.getSaved(page: 1)
}
```

**v2**

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.login.*
import zlibraryAPI4CJ.user.*

let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
try {
    let login = LoginApi.login(client, "a@b.com", "pw")
    println("登录成功：${login.user.name}")

    // 派生登录态客户端；后续请求自动带 remix 凭证，不用再传 cookie
    let authed = login.withClient(client)

    let saved = UserApi.saved(authed, page: 1)
    for (book in saved.books) {
        println(book.title)
    }
} finally {
    client.close()
}
```

要点：
- `LoginApi.login` 返回 `LoginResult`，`LoginResult.withClient(client)` 已经把
  `credential` 绑到新客户端上；
- 不要试图原地改 `client.credential`（不可变），也不要把 `cookie` 存成字符串
  再逐方法透传。

### 4.2 图书详情 + 下载

**v1**

```cangjie
let detailRes = book.getBookInfo(cookie: userInfo.cookie)
let downloadRes = detailRes.book.getDownloadInfo(cookie: userInfo.cookie)
if (downloadRes.success == 1) {
    let file = downloadRes.file
    if (file.allowDownload) {
        file.download(path: Path("D:/downloads"))
    }
}
```

**v2**

```cangjie
import std.fs.*            // Path
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.book.*

// 承接 4.1：login 是 LoginResult，client 是游客客户端
let authed = login.withClient(client)

// 1) 详情
let book = BookApi.info(authed, 123456, "abcdef123456")
println("${book.title} / ${book.sizeText()}")

// 2) 换签名下载链接（带时效，不要缓存）
let info = BookApi.fileOf(authed, book)

// 3) 落盘（目录不存在会自动递归创建；同名默认自动改名，不覆盖）
if (info.available()) {
    let bytes = BookApi.download(authed, info, Path("D:/downloads"))
    println("已保存 ${info.fileName()}（${bytes} 字节）")
}
```

要点：
- v2 是**两步**：`file()` 换链接 → `download()` 落盘。想一步到位用
  `BookApi.downloadBook(client, id, hash, dir)`；
- `DownloadInfo.fileName` 是 v1 的**属性**，v2 是**方法** `fileName()`；
- v1 的 `ConflictMethod` / `conflictMethod` 参数在 v2 中变成 `overwrite: Bool`
  （默认 `false` = 自动改名，不覆盖）。

### 4.3 搜索

**v1**

```cangjie
let res = client.search(message: "Rust", yearFrom: 2020, page: 1, limit: 10)
for (book in res.books) {
    println(book.title)   // 这里是 BookInfo（带很多字段）
}
```

**v2**

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.search.*

var page = SearchApi.search(client, "Rust", yearFrom: 2020, limit: 10)
println("共 ${page.pagination.totalItems} 条，本页 ${page.size()} 本")
for (book in page.books) {
    println("${book.title} / ${book.authorText()}")
}
while (page.hasMore()) {
    page = SearchApi.search(client, "Rust", page: page.nextPage(), limit: 10)
    if (page.isEmpty()) {
        break
    }
}
```

要点：
- v2 的 `SearchApi.search` 返回 `BookPage`，`page.books` 是
  `ArrayList<BookInfo>`（与 v1 的 `GetBookWithInfoAndPaginationRes.books` 一致，
  都是完整 `BookInfo`，不是 `BookInfoBrief`）；
- `page` / `limit` 从 `UInt16` 变成 `Int64`；
- 新增 `languages[]` / `extensions[]` / `order` 三个可选过滤维度。

### 4.4 换域名重试

**v1**

```cangjie
if (!canAccessZlib(autoRedirect: true)) {
    // 全局地址已被 changeUrl 改掉，其它请求会跟着漂移
}
```

**v2**

```cangjie
import zlibraryAPI4CJ.*
import zlibraryAPI4CJ.search.*

// 探测只返回结果，不改全局状态
match (resolveZlibHost()) {
    case Some(host) =>
        let newClient = client.withBaseUrl(host.url)   // 共享连接池
        let page = SearchApi.search(newClient, "Rust")
        // ...
        ()
    case None => println("没有可用镜像")
}
```

---

## 5. 行为差异（会改变调用方代码的地方）

1. **`success` 字段没了。** v1 里 `if (res.success == 1)` 这类判断全部删除；
   失败现在是异常。要区分「没找到」与「真失败」，catch `ZlibError` 看 `kind`
   （`NotFound` / `NotLoggedIn` / `ApiFailure` / `BadResponse` / `Transport` / `Forbidden` / `Closed`）。
2. **错误信息变结构化。** `ZlibError` 带 `kind`、`path`、`serverMessage`、`status`、`detail`；
   v1 只有 `errorInfo: ?String`。
3. **`cookie` 参数全部删除。** 凭证在客户端里；要换身份就派生客户端。
4. **数值类型 `UInt64` → `Int64`。** `id`、`page`、`limit`、`filesize` 等全部改；
   `ZlibCredential.of(userId: Int64, ...)` 接收 `Int64`（内部转字符串）。
5. **全局可变配置删除。** `zlibBaseUrl` / `zlibEAPI` / `changeUrl` 不再存在。
   `canAccessZlib` 保留了名字，但**不再自动改地址**，真实地址用
   `resolveZlibHost()` 取。
6. **模型不再发请求。** `BookInfo.saveBook(...)` 之类的方法全部删除；
   所有网络动作走 `BookApi` / `UserApi` / `SearchApi` / `LoginApi` / `InfoApi`。
7. **模型不再实现 `Serializable`。** 没有 `serialize()` / `deserialize(DataModel)`；
   只有 `fromJsonObject(obj)` / `fromJson(text)`。
8. **`fileName` 属性 → `fileName()` 方法。**
9. **`download` 语义变化。** `DownloadInfo.download(path:, conflictMethod:)` 删除；
   改用 `BookApi.download(client, info, dir, overwrite: Bool)` 或
   `client.download(url, path, overwrite: Bool)`。
   v2 **不再**对下载 URL 做 `replace("%", "")`——那是对旧 stdx 百分号解码缺陷的
   workaround，现在由 LinderHttp 的 `compensateTargetDecoding` 处理（见 MEMORY）。
10. **列表接口返回类型变了。** `GetBookRes` → `ArrayList<BookInfoBrief>`；
    `GetBookWithInfoAndPaginationRes` → `BookPage`。
11. **UI 展示辅助方法新增。** `BookInfo.authorText()`、`sizeText()`、`webpage(baseUrl:)`、
    `DownloadInfo.fileName()`、`ZlibUser.downloadsLeft()`、`BookPage.first()` 等，
    v1 需要调用方自己拼的字符串现在有现成方法。

---

## 6. 迁移步骤（推荐顺序）

1. **换依赖**：消费工程 `cjpm.toml` 加 `zlibraryAPI4CJ` 与 `linderHttp` 的 `path` 依赖，
   并抄一份 `[target.x86_64-w64-mingw32]` 三段配置（`path` 依赖不传递 target 段）。
2. **替换客户端创建**：`ZlibClient()` → `ZlibClient.create(baseUrl: ...)`；
   删掉所有 `changeUrl` / 全局变量赋值。
3. **替换登录**：`client.login(...)` → `LoginApi.login(...)` +
   `login.withClient(client)`；把保存 cookie 字符串的代码删掉。
4. **删 cookie 参数**：把 `xxx(cookie: userInfo.cookie)` 全部改成静态 API 调用，
   客户端换成登录态派生的那个。
5. **改模型字段访问**：`UInt64` 变量改 `Int64`；`dataSaved` → `dateSaved`；
   `todayDownloadNum` → `downloadsToday`；`downloadLimit` → `downloadsLimit`；
   `fileName` → `fileName()`。
6. **改错误处理**：删 `if (success == 1)`，改成 `try/catch (ZlibError)`，
   必要时看 `err.cause`（2.2.0 起不再抛 `HttpError`）。
7. **改下载**：拆成 `BookApi.file` + `BookApi.download` 两（或一步 `downloadBook`）。
8. **跑编译**：`cjpm build`；对文档示例再跑 `cd doccheck && cjpm build`。

---

## 7. 常见迁移错误对照

| 报错 / 症状 | 原因 | 改法 |
| --- | --- | --- |
| `undefined symbol: ZlibClient()` | v2 的构造函数是 `private`，只能用 `create` / `fromHttpClient` | 改 `ZlibClient.create(...)` |
| `no member named 'success'` | `success` 字段已删除 | 用 `try/catch (ZlibError)` 或 `ZlibEnvelope.success` |
| `no member named 'login'` | 登录在 `LoginApi` | `import zlibraryAPI4CJ.login.*` 后 `LoginApi.login(...)` |
| `no member named 'getDownloadInfo'` | 图书接口都在 `BookApi` | `BookApi.file(...)` / `BookApi.fileOf(...)` |
| `cannot convert UInt64 to Int64` | v2 数值统一 `Int64` | 显式转换或用 `Int64(...)` |
| `getSaved(page: 1)` 报参数错误 | v2 的 `page` 是具名参数且多了 `order` / `limit` | `UserApi.saved(client, page: 1)` |
| `fileName` 不能调用 | v2 是方法 | `info.fileName()` |
| `allowDownload` 判断后仍下载失败 | 链接可能已过期 | 重新 `BookApi.file(...)` 换链接再下载 |

---

## 8. 回看 v1 代码

```powershell
cd C:\Project\Cangjie\zlibraryAPI4CJ

# v1 的客户端（login / search / getRecommendBook）
git show af70e1e:src/client.cj

# v1 的图书模型（含 saveBook / getDownloadInfo 等直连 HTTP 方法）
git show af70e1e:src/dataModel/bookInfo.cj
git show af70e1e:src/dataModel/bookInfoBrief.cj
git show af70e1e:src/dataModel/downloadInfo.cj

# v1 的用户模型与收藏分页模型
git show af70e1e:src/dataModel/userInfo.cj
git show af70e1e:src/dataModel/userSavedBook.cj

# v1 的全局配置与站点探测
git show af70e1e:src/common/commons.cj

# v1 的旧文档（示例已全部失效，只用于对照方法名）
git show af70e1e:doc/feature_api.md
```

> 想把 v1 整个目录导出到临时位置逐文件对照：
> `git archive af70e1e | tar -x -C <目标目录>`。
