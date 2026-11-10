# MEMORY.md — zlibraryAPI4CJ 开发记忆

> 记录**实际踩过的坑、实测结论、以及当时做的决策与理由**。
> 与 `Agent.md` 的分工：`Agent.md` 是「怎么做」的规范，本文件是
> 「为什么是这样」的证据链。每条尽量注明**验证方式**，方便下一个人复核。
>
> 本库 v2（commit `f8bcfd4`）是**推翻重写**，不是增量重构。旧版代码保留在
> git 历史里，可用 `git show af70e1e:<路径>` 取回，例如：
>
> ```powershell
> git show af70e1e:src/client.cj
> git show af70e1e:src/dataModel/bookInfo.cj
> git show af70e1e:src/common/commons.cj
> ```

---

## 1. 环境与工具链

### 1.1 版本与路径

| 项 | 值 | 验证方式 |
| --- | --- | --- |
| `cjpm --version` | `Cangjie Project Manager: 1.2.0` | `cjpm --version` |
| `cjc --version` | `Cangjie Compiler: 1.2.0 (cjnative)`，Target `x86_64-w64-mingw32` | `cjc --version` |
| `CANGJIE_HOME` | `C:\Program\SDK\Cangjie` | `$env:CANGJIE_HOME` |
| `CANGJIE_STDX_PATH` | `C:\Program\SDK\Cangjie_Stdx` | `$env:CANGJIE_STDX_PATH` |
| stdx 静态库 | `${CANGJIE_STDX_PATH}/windows_x86_64_cjnative/static/stdx` | `cjpm.toml` 的 `bin-dependencies.path-option` |
| HTTP 依赖 | `linderHttp 2.0`，`path = "C:/Project/Cangjie/LinderHttp"` | `C:\Project\Cangjie\LinderHttp\cjpm.toml` |

### 1.2 Windows 平台必须有的两行链接配置

```toml
[target.x86_64-w64-mingw32]
compile-option = "--cfg \"ohos=false\""
link-option = "-lcrypt32"
[target.x86_64-w64-mingw32.bin-dependencies]
path-option = ["${CANGJIE_STDX_PATH}/windows_x86_64_cjnative/static/stdx"]
```

- `-lcrypt32`：Windows 上 TLS 证书链校验要用系统 crypto API；
  少了它会在链接期报 `undefined reference`，或在运行期握手失败。
- stdx 的 `path-option`：`stdx.encoding.json`、`stdx.net.http` 等都在 stdx 里，
  不指路径就链接不到。
- `--cfg "ohos=false"`：同一份 `cjpm.toml` 里还留着鸿蒙 target 段，
  这个宏让代码里 `@When[ohos]` 之类的分支在 Windows 上走桌面路径。

**给消费工程的提醒**：`path` 依赖不会把 target 段传染给你。
消费工程（包括本仓库的 `doccheck/`）**必须自己复制一遍**上面这三段，
否则一样链接失败。`doccheck/cjpm.toml` 就是为此逐字复制的。

### 1.3 编译选项 `-Woff unused`

主工程 `compile-option = "-Woff unused"` 是有意关掉 unused 警告：
并行开发期间常常先写常量/参数后接线，开 unused 会刷屏。
**不要**顺手加 `-Werror`，那会把他人的临时未用变量变成构建失败。

---

## 2. 旧版（v1）为什么编译不过

证据全部来自 git 历史（`af70e1e` 及其之前）。逐条列出，因为「旧代码抄过来就能用」
是接手时最容易犯的错。

### 2.1 `LinderHttp.client()` 在 2.0 里已经是属性，不是函数

旧 `src/client.cj`、旧 `src/dataModel/*.cj` 里到处是：

```cangjie
var httpClient = LinderHttp.client()          // ❌ 2.0 里是属性
let response = LinderHttp.get(url)            // ✅ 这个还能用
```

LinderHttp 2.0（`src/http/facade.cj`）声明的是：

```cangjie
public static prop client: HttpClient { get() { SharedClients.shared() } }
```

把属性当函数调用（`client()`）直接编译失败。
v2 的写法是**自己建 `HttpClient`**（`HttpClientBuilder().build()`），
把生命周期交给 `ZlibClient`——这样连接池、代理、超时都可控，
也不会因为全局单例而与别人的配置互相污染。

> 另一处相关变化：2.0 的 `LinderHttp.get(...)` 返回 `Response`，
> 要取结构体数据得 `.dataModel()`，而旧代码把「发请求」写在了模型类里（见 2.2）。

### 2.2 旧版把 HTTP 调用写在数据模型里

旧 `dataModel/bookInfo.cj` 的 `BookInfo` 类里直接有：

```cangjie
public func saveBook(cookie!: String): Bool {
    var httpClient = LinderHttp.client()
    let response = httpClient.request(Method.Get, "${zlibEAPI}/user/book/${id}/save")
        .headers(Headers().set("cookie", cookie))
        ...
}
```

`bookInfoBrief.cj`、`userInfo.cj`、`downloadInfo.cj` 同样如此。
后果：

1. **模型与传输强耦合**：模型无法脱离网络单测，只能拿真实响应验；
2. **凭证靠参数逐个透传**：每个方法都多一个 `cookie: String`，
   一漏就变游客态，且没有任何类型检查；
3. **`downloadInfo.download(path:)` 里直接下载**，模型承担了落盘职责；
4. 模型里用了 `LinderHttp` / `Headers` / `Path`，却**没有对应 import**（见 2.3）。

v2 的分层是硬性的：**`model` 只做解码与派生，`core` 负责传输，
业务子包只做「拼路径 + 选字段 + 调 client」**。

### 2.3 旧版大量缺 import（而且「集中 import」救不了）

旧 `dataModel/bookInfo.cj` 文件开头**一个 import 都没有**，却用了：

- `${zlibEAPI}`（来自 `zlibraryAPI4CJ.common`）；
- `LinderHttp` / `Headers` / `Method` / `Timeouts` / `Path`；
- `DataModel` / `DataModelStruct` / `Serializable` 等序列化类型。

旧 `bookInfoBrief.cj` 同样没有 import 却用了 `LinderHttp`、`Headers`。

旧版似乎想用 `src/dataModel/importFile.cj` 集中 import 给整个包用：

```cangjie
internal import zlibraryAPI4CJ.common.*
internal import stdx.serialization.serialization.*
internal import linderHttp.*
internal import stdx.encoding.url.*
internal import std.fs.*
```

**这在仓颉里不成立：import 是按文件生效的，不是按包。**
那个文件除了 import 之外什么都没有，等于没写。

v2 的做法：每个文件自己写需要的 import（`client.cj` 里就有
`std.collection.* / std.fs.* / stdx.encoding.json.* / linderHttp.*`），
`*_pkg.cj` 只放包声明与包文档，不放 import 供他人共享。

### 2.4 单引号是 Rune，不是字符串

旧代码把字段名写成单引号：

```cangjie
.add(field<?String>('date_saved', dataSaved))
body.add('message', message)
```

仓颉里单引号是 **`Rune`（字符）**，不是字符串。`field(...)` 要 `String`、
`Form.add` 也要 `String`，这种写法是类型错误。
v2 统一用双引号字符串字面量。

### 2.5 旧版全局可变配置

旧 `src/common/commons.cj`：

```cangjie
public var zlibBaseUrl: String = "https://tw.jiaoyuan.ru"
public var zlibEAPI: String = "${zlibBaseUrl}/eapi"

public func changeUrl(url: String) {
    zlibBaseUrl = url
    zlibEAPI = URL.parse(zlibBaseUrl).replace(path:'/eapi').toString()
}
```

问题不在「能不能用」，而在**语义**：任何一次 `changeUrl` 都会影响进程内
所有调用方；两个线程分别用不同镜像时必然互相踩。
而且 `zlibEAPI` 与 `zlibBaseUrl` 是两份状态，可能出现不一致的中间态。

v2 把站点收敛成 `ZlibHost` 值对象，挂在不可变的 `ZlibClient` 上：
`client.withBaseUrl(url)` 派生新客户端（共享连接池），
`resolveZlibHost()` 只返回探测结果、**不修改任何全局状态**。

### 2.6 旧文档与旧 API 已经对不上

旧 `doc/feature_api.md` 里的示例是 `client.search(...)`、`client.login(...)`、
`downloadInfo.fileName` 属性、`ConflictMethod.HARMONY` 等，
这些 API 在 v2 里**全部不存在**（v2 是静态 API + 方法式 `fileName()`、
`overwrite: Bool`）。旧 README 的示例同理。

**教训**：文档不是代码的注释，是会腐烂的独立产物。所以 v2 建了
`doccheck/` 编译校验工程（见 13 节），把「文档示例能否编译」变成可执行的检查。

---

## 3. 站点域名不稳定，下载还要求「个人域名」

### 3.1 域名是长期问题，不是临时故障

- 旧版默认域名 `https://tw.jiaoyuan.ru`（旧 `commons.cj`），
  旧 README 又写 `https://zh.101run.ru`——同一仓库里两处默认值就不一致；
- LinderHttp/社区客户端常用 `1lib.sk`（bipinkrish/Zlibrary-API 的默认值）；
- 官方 eapi 文档（baroxyton/zlibrary-eapi-documentation）说可用域包括
  `1lib.fr`、`singlelogin.me`，以及一个 onion 地址；
- 该文档还明确写了：**下载必须使用 personal zlibrary domains**
  （每个账号有专属域名）。

所以 v2 的结论是：**站点地址是一等配置，不是常量**。

- `ZlibHost.DEFAULT_URL` 只是「老项目的第三方镜像」，注释里写明了随时可能失效；
- `ZlibHost.MIRRORS` 是**候选列表**，不保证每个都通；
- 真正用法是 `resolveZlibHost()` 探测，或调用方自己传 `baseUrl`。

### 3.2 本机实测：候选镜像基本不可达（2026-11-10）

```powershell
Invoke-WebRequest -Uri https://tw.jiaoyuan.ru -Method Head -TimeoutSec 8
# -> 503 Service Unavailable
Invoke-WebRequest -Uri https://z-library.sk  -Method Head -TimeoutSec 8
# -> 请求超时
Invoke-WebRequest -Uri https://1lib.sk       -Method Head -TimeoutSec 8
# -> 请求超时
```

`tw.jiaoyuan.ru` 回 503 时 `ZlibProbe.reachable` 仍判为「连得上」
（503 是站点维护页，说明 DNS/TLS 通了，换镜像可能没用但对域名本身是活证据）。
**这就是本库所有单元测试都不联网的直接原因**（见第 10 节）。

### 3.3 下载链接的域名与站点域名不同

`DownloadInfo.downloadLink` 是**签名过的绝对地址**，主机名常常是
CDN 或个人域名。所以：

- 下载时**不能**沿用 API 请求头（不要带 `remix-userid/remix-userkey`，
  跨域还可能触发校验）——`ZlibClient` 内部有独立的 `fileHeaders()`；
- 链接有签名与时效，**不要缓存**；403/404 就重调 `BookApi.file()` 换新链接；
- 官方文档明确要求下载走个人域名，游客态或旧域名拿到的链接大概率失效。

---

## 4. 百分号解码缺陷与 `replace("%", "")` 这个 workaround

旧 `dataModel/downloadInfo.cj` 的下载实现：

```cangjie
LinderHttp.get(downloadLink.getOrThrow().replace("%", ""),
    timeouts: Timeouts(read: Duration.Max, write: Duration.Max))
    .saveTo(savePath, overwrite: overwrite)
```

`replace("%", "")` 把所有 `%` 删掉——这**不是**业务需要，而是当年
stdx 传输层对「请求目标」做百分号解码的 workaround：
请求 URI 里的 `%XX` 被底层解一次，导致签名 URL 里的 `%` 语义被破坏，
当时的粗暴修法是干脆把 `%` 全删掉（副作用是合法编码也一起毁掉）。

仓颉 1.2.0 + LinderHttp 2.0 已经有正经修法。LinderHttp 的
`ClientConfig.compensateTargetDecoding`（`src/http/options.cj`）注释写得很清楚：

> 实测仓颉 1.2.0 的 stdx：把 `?q=a%20b` 交出去，线路上写的是 `?q=a b`（服务端 505），
> `%2F` 会变 `/`、`%26` 会变 `&`，语义直接被破坏。开启本项后本库会把路径/查询里
> 已有的 `%` 再转义一次，底层解码一次后线路上恰好是正确的 `%xx`。
> 如果将来工具链修好了这个问题，把它置为 false 即可。

**v2 的结论**：不在业务代码里做任何 `%` 替换。
`ZlibClient.download(url, path)` 原样把 URL 交给 LinderHttp，
由 `compensateTargetDecoding` 统一处理。
若将来工具链修好、该补偿反而添乱（例如走代理时），
在消费方构建 `HttpClient` 时把这一项关掉即可——但**不要**回到字符串替换。

---

## 5. Z-Library 字段类型不稳定 / 字段会缺

这是本库**所有解码都必须走宽松读取**的根本原因（不是防御性编程洁癖）。

### 5.1 实测/社区样本里出现过的形态

固定 JSON 样本（`src/model/model_test.cj` 的 `testLenientDecode`）刻意覆盖了：

```json
{
  "id": "777",            // 数字字段给字符串
  "author": null,          // 可选字段给 null
  "year": "2020",          // 数字字段给数字字符串
  "filesize": 2048.0,      // 整数给浮点
  "kindleAvailable": "1"   // 布尔给字符串
}
```

以及「整条缺字段」的情况（`dl`、`pagination`、`isUserSavedBook`）。

旧代码对此已有注释，可交叉验证：

```cangjie
// 全部走容错反序列化：Z-Library 会偶尔省略字段（实测 `dl` 就有书缺），
// 直接 String.deserialize 会抛 DataModelException 让整次搜索/详情失败
```

### 5.2 处理策略

1. 模型字段一律 `public var` + 默认值，**缺字段不抛异常**；
2. 所有读取走 `readString/readInt/readFloat/readBool/readOptionalString`；
3. 列表用 `decodeEach`，**跳过单条脏数据**——一条书目的字段漂移不该让整页搜索作废；
4. 同一字段有两种 key 的（如 `_isUserSavedBook` / `isUserSavedBook`），
   两种都读（`BookInfo.fromJsonObject` 里的 `optionalBoolOf`）；
5. 服务端偶尔「字段有、但类型对不上对象/数组」→
   `objectFieldOf` 回 `None`、`arrayFieldOf` 回空数组，不做强制转换。

### 5.3 不要为「稳定形状」造假设

- `pagination` 可能整个缺失 → `BookPage.pagination` 回落到全 0 的 `Pagination()`，
  `hasMore()` 因而是 `false`。调用方要分得清「没有下一页」和「服务端没给分页」。
- `formats`、`user/donations`、`info/*` 的响应形状不稳定，所以 v2 直接返回
  **原始 `JsonObject`**，不硬造模型。少一层模型，少一层会腐烂的假设。

---

## 6. 为什么不用 CJson（bbapi 用了，本库刻意不用）

bbapi 用 `CJson` 的 `@JsonSerializable` 宏，本库没有，理由是**约束不同**：

| 维度 | bbapi + CJson | zlibraryAPI4CJ |
| --- | --- | --- |
| 类型稳定性 | B 站字段类型固定，文档可实测 | Z-Library 同字段会数字/字符串漂移 |
| 解码失败代价 | 单个接口失败 | 一条坏数据会让整页搜索/收藏列表作废 |
| 信封形态 | 统一 `{code,message,data}`，宏只解 `data` | 数据平铺在根上，字段名因接口而异 |
| 依赖 | 需要额外 git 依赖 | stdx 已在用，JSON 免费 |
| 缺字段行为 | 宏对非 Option 字段要求键必须存在 | 缺字段必须静默回退默认值 |

CJson 的宏对 `Int64` 字段调 `asInt()`，遇 `String` 直接抛 `JsonException`
（这一条来自 bbapi 的实测记录，见其 MEMORY 6.2），
且宏也没法表达「先试 `_isUserSavedBook` 再试 `isUserSavedBook`」这种逻辑。
所以 v2 用 `stdx.encoding.json` + 手写 `fromJsonObject`：
代码量略多，但**解码行为完全可控**，且没有宏依赖。

> 附带的收益：不引入 CJson 就不会踩 bbapi MEMORY 里那串宏坑
> （`@JsonName` 不剥离反引号、关键字字段、宏包不能 re-export 等）。

---

## 7. 为什么模型下沉到 `model` 子包

bbapi 把模型放在各业务子包里（`video/model/*.cj`），本库**不能**照抄：

- `BookInfo` 同时是 `book`（详情）、`search`（搜索结果）、`user`（收藏/历史）的返回值；
- `ZlibUser` 同时被 `login` 与 `user` 使用；
- `BookPage`（books + pagination）被 `book`/`search`/`user` 三处使用。

若各包各定义一份 → 重复代码 + 类型不通用（调用方拿到的是 `search.BookInfo`，
传给 `BookApi` 要求 `book.BookInfo` 编译不过）；
若各包互相 import → 依赖图变网状，`search` 依赖 `book`、`book` 又依赖 `user`……

**最终约定（`src/model/model_pkg.cj` 里也写了）：**

```
依赖方向：core ← model ← 业务子包，业务子包之间互不 import
```

共享类型一律下沉 `model`，这样每个子包可独立测试、独立演进，
也让「业务子包互不依赖」这条硬约束能一直守住。

---

## 8. 站点探测为什么必须 `followRedirects(false)`

旧 `commons.cj` 的注释已经把原因写清楚了，v2 原样继承：

> 这两个探测必须关掉自动重定向：它们正是要靠 3xx 的 `Location` 去反查可用地址，
> 跟随重定向就看不到 Location 了。

`probeSite` 的实现就是按这个语义写的：

```cangjie
let client = HttpClientBuilder()
    .readTimeout(Duration.second * 10)
    .totalTimeout(Duration.second * 15)
    .followRedirects(false)   // 关键：不跟随，才能读到 Location
    .cookies(false)           // 探测不需要 Cookie，避免污染 Cookie 存储
    .build()
```

`resolveZlibHost` 的判定顺序也据此而来：

1. 有 3xx 且 `Location` 非空 → 直接用 `Location`（补全成绝对地址）作为站点；
2. 否则 `200` / `503`（维护页也算通）→ 用候选地址；
3. 全失败 → 返回 `None`。**不要**在这里抛异常：找不到镜像和接口报错是两种故障，
   调用方需要不同的处理（换网络 vs 换账号），混成一个异常就没法区分。

`ZlibProbe.reachable` 把「3xx / 200 / 503」都算可达，
`checkAccess` 则更严格（只认 200/503），
`canAccessZlib(autoRedirect: true)` 兼容旧版「3xx 也算可用」的习惯。

---

## 9. 闭包扫描器 CJ044 的误报与规避

写新文件前要跑 `check_cangjie_closure.py`（见 `Agent.md` 7.3）。
它有个**已确认的误报**：

```cangjie
func pick(value: Int64): String {
    match (value) {
        case 1 => "one"      // ← 三个分支全被误报 CJ044
        case 2 => "two"
        case _ => "many"
    }
}
```

复现（2026-11-10，脚本 `check_cangjie_closure.py`）：

```
probe.cj:5:9: CJ044 [error] A match case must contain at least one expression
after =>; use () for an explicit Unit branch.
```

原因：脚本先把注释与**字面量**遮成空格（保留偏移），
再在 `=>` 后找「下一个非空白字符」。分支体是纯字面量时，
字面量已被遮掉，扫描器看到的下一个非空 token 是下一个 `case` 或 `}`，
于是判定为空分支。

**规避写法**（都实测通过 `exit 0`）：

```cangjie
// ✅ 用 return（推荐，语义也最清晰）
case 1 => return "one"

// ✅ 分支体不是纯字面量（拼接 / 插值 / 函数调用）
case 2 => return "t" + "wo"

// ❌ 不要用花括号块来「避开」：case 1 => { "one" } 会触发 CJ028
```

团队约定：**match 分支体不要只写一个裸字符串/数字字面量**；
要写就 `return` 出去，或把字面量赋给变量再返回。
这样既绕开误报，也避免「分支到底返回还是丢弃」的阅读歧义。

---

## 10. 本机连不上 z-lib，所以测试全部离线

- 实测：候选镜像 503 / 超时（第 3.2 节的 PowerShell 记录）；
- 即使偶尔能连上，Z-Library 对自动化请求有风控（Cloudflare 类页面），
  单元测试拿它当依赖会变成随机红灯；
- eapi 的写操作（登录、收藏）会改动真实账号状态。

**结论：`cjpm test` 一律不联网。** 测试只覆盖「不联网就能证明」的部分：

| 层 | 测什么 |
| --- | --- |
| `core` | 站点规范化、Location 解析、凭证 Cookie/头、Query 编码、信封解析与错误映射、宽松读取、客户端 URL 拼接 / 派生 / 关闭后抛错 |
| `model` | 固定 JSON 样本 → 字段、容错形态（缺失/类型漂移）、派生（`fileName`/`sizeText`/`webpage`/`hasMore`） |
| 业务子包 | 查询参数构造、落盘前置校验、路径拼接；**网络调用不测** |

真实接口可用性只能靠独立消费工程手工验证；如果没有可用域名，
就以 `doc/eapi-endpoints.md` 的社区文档为准，并在改动处注明「推断」。

---

## 11. 客户端不可变派生 + 共享连接池

设计动机（`client.cj` 注释）：

- 一个 `ZlibClient` 内部只持有一个 LinderHttp `HttpClient`，
  连接池与 Cookie 存储共享 → **进程内复用一个实例**，别每次请求新建（每次都要 TLS 握手）；
- `credential` / `host` / `config` 都不可原地改，
  派生用 `withCredential` / `withBaseUrl` / `withHost`（**共享同一个 `HttpClient`**）；
- 场景：同进程里既有游客请求又有登录请求，前者不该带 remix 凭证
  （会影响推荐/搜索结果个性化）——派生两个客户端即可干净隔离。

两个容易忽略的点：

1. **派生客户端不独立**：`close()` 关的是同一个底层 `HttpClient`，
   所以「关闭某个派生客户端」等于关闭整组。要独立生命周期就
   `ZlibClient.create(...)` 另建一个。
2. **登录成功后凭证不会自动更新**：`Set-Cookie` 被 `HttpClient` 的 Cookie 存储收下，
   但客户端持有的 `credential` 是不可变值。所以登录后应显式
   `client.withCredential(loginResult.credential)`；
   若只拿到了 Cookie（例如别的库代登录），用 `client.credentialFromCookies()`
   从 Cookie 存储里捞 `remix_userid` / `remix_userkey` / `siteLanguage(V2)`。
   否则会出现「登录成功但后续仍游客态」。

---

## 12. 凭证与配置分开

`ZlibCredential`（我是谁）与 `ZlibClientConfig`（怎么连）刻意是两个类型：

- 敏感度不同：`ZlibCredential.toRequestHeaders()` 里含 `remix_userkey`（等价密码），
  所以 `toString()` 刻意**不打印** userKey 原文；
- 生命周期不同：凭证会随登录变化，配置基本是进程级常量；
- 传参风险不同：把 UA/超时和密钥塞进同一个「配置对象」，
  很容易在日志或异常里把密钥一起打出来。

`ZlibCredential` 同时写 Cookie 与请求头，不是冗余：官方 eapi 文档说
「provide a `remix-userid` header as well as a `remix-userkey` header.
In some cases, it may also be necessary to provide the login as the cookies…」，
两种都发兼容性最好；语言 Cookie 也同时写 `siteLanguage`（旧）与
`siteLanguageV2`（新），避免「登录了却拿到英文/未登录页面」。

---

## 13. 文档示例必须过编译器（`doccheck/`）

**动机**：旧 `doc/feature_api.md` 的示例全部基于 v1 API，
v2 重写后一条都编译不过——但没人发现，因为文档不参与构建。
bbapi 的经验（其 MEMORY 6.7）也是同一个事故：手写示例里有一批
「位置参数写成具名」「模型没实现 ToString 却拿去插值」之类的错误。

**做法**：`doccheck/` 是独立 executable 工程：

- `doccheck/cjpm.toml`：`path` 依赖 `..` 与 `C:/Project/Cangjie/LinderHttp`，
  **逐字复制**主工程 `[target.x86_64-w64-mingw32]` 的三段配置
  （`compile-option` / `link-option` / `bin-dependencies.path-option`）；
- `doccheck/src/main.cj`：把 `API_USAGE.md` 的每段示例落成一个函数，
  函数体可以不做真实联网动作，但必须**类型正确**；
- 验收命令：`cd doccheck && cjpm build`。

这不只是 CI 检查，写文档时它也是「签名是否记错」的最快反馈。
**改 public 签名 → 必须同步改 `API_USAGE.md` + `doccheck`。**

**实际结果（v2 收尾时）**：

```powershell
cd C:\Project\Cangjie\zlibraryAPI4CJ\doccheck
cjpm build
# cjpm build success
.\target\release\bin\main.exe
# zlibraryAPI4CJ doccheck: 所有文档示例已通过编译检查
```

`doccheck/src/main.cj` 约 1060 行，按 `API_USAGE.md` 的章节号命名函数
（`doc3_6`、`doc9_14` …），覆盖全部子包示例与工具函数示例。
第一次构建就通过，说明「写文档时逐条对着 `src` 核对签名」这一步是有效的；
但**不能因此省掉**——示例与源码不同步时，这份工程才会暴露问题。

> 注意：`doccheck` 的 `main()` **不执行**任何联网示例，只靠「函数被编译」
> 触发类型检查。所有示例函数都保持「参数已给出、不真正调用」的形态。

---

## 14. 已知限制与未覆盖项

1. **未联网验证**：v2 的所有接口路径/参数来自社区文档与旧代码，
   没有在真实站点上逐条回归（本机网络不可达，见第 3.2、10 节）。
   `doc/eapi-endpoints.md` 里对「实测 / 推断」做了标注。
2. **`/user/donations`、`/book/{id}/{hash}/formats`、`/info/*`**
   返回原始 `JsonObject`：形状不稳定，本库不承诺字段。
3. **注册验证码流程未覆盖**：`/papi/user/verification/send-code`、
   `/rpc.php`（社区客户端用过）不在本库范围内，只覆盖
   `user/registration` 这一条无验证码路径。
4. **没有限流/重试策略**：重试交给 LinderHttp 的 `RetryPolicy` 默认值；
   Z-Library 每日下载次数限制由服务端控制（`ZlibUser.downloadsLeft()` 只是展示）。
5. **静态库无法独立运行**：验证必须通过消费工程（`doccheck/` 或调用方项目）。
6. **域名硬编码风险**：`ZlibHost.DEFAULT_URL` 与 `MIRRORS` 必然过期，
   生产环境请显式传 `baseUrl` 或先 `resolveZlibHost()`。

---

## 15. 验证方式汇总（可复现）

```powershell
# 1) 版本
cjpm --version; cjc --version

# 2) 构建
cd C:\Project\Cangjie\zlibraryAPI4CJ; cjpm build

# 3) 单测（离线；当前基线 TOTAL 93 / PASSED 93 / FAILED 0）
cjpm test --no-progress

# 4) 预检（每个新文件）
python C:\Users\liluo\.agents\skills\cangjie-lang-features\scripts\check_cangjie_closure.py src\core\client.cj

# 5) 文档示例编译校验
cd doccheck; cjpm build

# 6) 回看旧版代码（迁移时对照）
cd C:\Project\Cangjie\zlibraryAPI4CJ
git show af70e1e:src/client.cj
git show af70e1e:src/dataModel/bookInfo.cj
git show af70e1e:src/common/commons.cj
```

### 15.1 v2 收尾时的实际结果

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 静态库构建 | `cjpm build` | success |
| 离线单测 | `cjpm test --no-progress` | TOTAL 93 / PASSED 93 / FAILED 0 |
| 文档示例编译 | `cd doccheck && cjpm build` | success（并可直接运行 `target\release\bin\main.exe`） |
| 新 `.cj` 文件预检 | `check_cangjie_closure.py` | `doccheck/src/main.cj` ok, exit 0 |

> 单测数字是**基线**而非硬指标：新增接口应当带来新测试，这个数字只会变大；
> 若某次提交后数字下降，先确认是不是删了测试。
