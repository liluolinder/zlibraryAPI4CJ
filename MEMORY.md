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

- `ZlibHost.DEFAULT_URL` 2.1.0 起设为 `https://zh.eva101.ru`（2026-11-10 实测 eapi 可用），
  但注释里仍写明镜像会轮换；
- `ZlibHost.MIRRORS` 是**候选列表**，不保证每个都通；
- 真正用法是配置 `seeds` 自动换站、`resolveZlibHost()` 探测，或调用方自己传 `baseUrl`。

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

**2026-11-10 补充（第二轮实测）**：用户提供了 `https://zh.eva101.ru`，该域名的
eapi **可用**（HEAD `/` 返回 503，但 `/eapi/book/search` 等全部 `success=1`），
于是有了 `integration/` 联网集成测试（36/36 通过，详见第 16 节）。
`z-library.sk` / `1lib.sk` / `article.sk` 等从本机仍然超时——
**这正好验证了「种子站返回的域名列表不一定对你可用」**，也是换站逻辑
在候选域名全部探测失败后要能回退到种子站本身的原因。

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

## 10. `cjpm test` 一律离线；联网验证放 `integration/`

- 实测：候选镜像大多 503 / 超时（第 3.2 节的 PowerShell 记录）；
  2026-11-10 找到可用的 `zh.eva101.ru` 后，联网验证改由独立工程
  `integration/` 承担（`cjpm run`），**仍然不放进 `cjpm test`**；
- 即使能连上，Z-Library 对自动化请求有风控（Cloudflare 类页面），
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

1. **已完成一轮真实站点联调**：2026-11-10 用 `zh.eva101.ru` 跑 `integration/`
   36/36 通过（搜索/榜单/详情/相似/格式/站点信息/错误映射/自动换站重试），
   详见第 16 节；但镜像与字段仍会变，`doc/eapi-endpoints.md` 用
   「社区文档 / v2 实测 / 推断」标注可信度。
2. **形状不稳定的接口**：`/user/donations`、`/info/*` 仍返回原始 `JsonObject`；
   `/book/{id}/{hash}/formats` 已在 2.1.0 按实测形状强类型化为 `ArrayList<BookFormat>`。
3. **注册验证码流程未覆盖**：`/papi/user/verification/send-code`、
   `/rpc.php`（社区客户端用过）不在本库范围内，只覆盖
   `user/registration` 这一条无验证码路径。
4. **重试与限流**：2.1.0 起有请求级自动重试（默认 3 次）与站点切换冷却（默认 30 秒），
   但**没有**全局限流/退避队列；Z-Library 每日下载次数限制由服务端控制
   （`ZlibUser.downloadsLeft()` 只是展示）。
5. **静态库无法独立运行**：验证必须通过消费工程（`doccheck/` 编译校验、
   `integration/` 联网验证，或调用方项目）。
6. **域名硬编码风险**：`ZlibHost.DEFAULT_URL` 与 `MIRRORS` 只是候选，
   生产环境请显式传 `baseUrl`、配置 `seeds` 自动换站，或先 `resolveZlibHost()`。

---

## 15. 验证方式汇总（可复现）

```powershell
# 1) 版本
cjpm --version; cjc --version

# 2) 构建
cd C:\Project\Cangjie\zlibraryAPI4CJ; cjpm build

# 3) 单测（离线；当前基线 TOTAL 141 / PASSED 141 / FAILED 0）
cjpm test --no-progress

# 4) 预检（每个新文件）
python C:\Users\liluo\.agents\skills\cangjie-lang-features\scripts\check_cangjie_closure.py src\core\client.cj

# 5) 文档示例编译校验
cd doccheck; cjpm build

# 6) 联网集成测试（需要可用镜像；镜像见 integration/src/main.cj 的 DOMAIN）
cd ../integration; cjpm run

# 7) 回看旧版代码（迁移时对照）
cd C:\Project\Cangjie\zlibraryAPI4CJ
git show af70e1e:src/client.cj
git show af70e1e:src/dataModel/bookInfo.cj
git show af70e1e:src/common/commons.cj
```

### 15.1 v2 收尾时的实际结果

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 静态库构建 | `cjpm build` | success |
| 离线单测 | `cjpm test --no-progress` | TOTAL 141 / PASSED 141 / FAILED 0 |
| 文档示例编译 | `cd doccheck && cjpm build` | success（并可直接运行 `target\release\bin\main.exe`） |
| 联网集成测试 | `cd integration && cjpm run` | 36 passed / 0 failed，exit 0（2026-11-10，zh.eva101.ru） |
| 新 `.cj` 文件预检 | `check_cangjie_closure.py` | `doccheck/src/main.cj` ok, exit 0 |

> 单测数字是**基线**而非硬指标：新增接口应当带来新测试，这个数字只会变大；
> 若某次提交后数字下降，先确认是不是删了测试。

---

## 16. 真实站点联调记录（2026-11-10，zh.eva101.ru）

### 16.1 结果

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 离线单测 | `cjpm test --no-progress` | 141 passed / 0 failed |
| 联网集成（基础） | `cd integration && cjpm run` | 36 passed / 0 failed，exit 0 |
| 联网集成（登录后链路） | `ZLIB_TEST_ONLY_AUTH=1` + `ZLIB_TEST_EMAIL/PASSWORD` | 16 passed / 0 failed（含真实下载 723637 字节） |
| 联网集成（完整一次） | 带账号密码跑全量 | 50 passed / 0 failed，exit 0 |

### 16.2 实测确认的事实（已写进模型/文档）

| 事实 | 证据 | 代码处理 |
| --- | --- | --- |
| `POST /eapi/book/search` 表单可用，返回 `books` + `pagination`（多 `before`/`next` 字段） | search rust：total=500、100 页 | `BookPage` 读 limit/current/total_items/total_pages，忽略额外字段 |
| `most-popular`/`similar` 列表项形状：`id,isbn,url,title,author,cover,coverData,hash` | 100/24 条样本 | `BookInfoBrief` 增加 `isbn`/`url`/`coverData`；`webpage()` 优先 `url` |
| `/formats` 返回 `{success,books:[{id,hash,extension,filesize,filesizeString}]}`，匿名可用；部分书为空数组 | 24126585 → 16 项；17309781 → `[]` | 新增 `BookFormat` 模型，`BookApi.formats()` 改返回 `ArrayList<BookFormat>` |
| 未登录接口返回 **HTTP 400** + `{"success":0,"error":"登录到您的账户"}` | `/user/profile`、`/book/{id}/{hash}/file`、`/user/book/saved` | `unwrap` 增加中文「登录」识别 → `NotLoggedIn` |
| 错误密码返回 `{"success":0,"error":"电子邮件或密码错误"}` | `/user/login` | 保持 `ApiFailure`，`serverMessage` 保留原文 |
| `/info/languages` 返回 map `{"english":"英语",...}`（175 种） | info-languages 样本 | 继续返回原始 `JsonObject`，文档给读取示例 |
| `/info/extensions` 返回 `{"success":1,"extensions":[12 项]}` | info-extensions 样本 | 文档给 `arrayFieldOf` 读取示例 |
| `/info/domains` 返回 `{"success":1,"domains":[{"domain":"...","contentAvailable":true,"isRedirector":false}]}` | 5 个候选域名 | `extractDomainList` 支持对象数组；换站以它为主数据源 |
| HEAD `/` 返回 503，但 eapi 正常 | `probeSite` / `checkAccess` | 503 视为可达（原设计正确） |
| 种子站列表里的域名从本机不可达（z-library.sk 等超时） | 换站实测 | 候选探测失败后回退种子站本身（`fallbackToSeed`） |
| HEAD 探测偶发超过 5 秒，导致换站误判失败 | 第一次 `refreshSite(force)` 返回 false | `planSiteRefresh` 增加「种子站刚返回过域名 ⇒ 直接兜底」的短路 |
| 一次换站耗时约 20~55 秒（最多 4 个候选 ×5s + 拉列表） | 集成测试计时 | 文档写明；`maxCandidates` 可调 |
| 登录成功返回 `user`（id/email/remix_userkey/downloads_today/limit）；`loginWithToken` 用 remix 凭证可直接复用 | 真实账号登录 | 现有 `LoginApi`/`ZlibCredential` 直接可用，无需改 |
| profile / 收藏 / 推荐 / 下载历史 / 收藏 / 取消收藏 全部可正常调用 | 真实账号 16/16 | 未改接口；写操作测试做成「原本未收藏才收藏、随后取消」 |
| `/book/{id}/{hash}/file` 返回签名链接，主机是 **dln1.ncdn.ec**（Cloudflare，与站点域名不同） | 实测 | 下载用独立 `fileHeaders`，不带 remix 头；真实下载 723637 字节成功 |
| 下载超过 30 秒读超时会 `read data timeout` | 首次下载失败 | 新增 `config.downloadTimeout`（默认 5 分钟），`download`/`fetchBytes` 使用它 |
| `Directory.create(dir, recursive: true)` 对**已存在目录**抛 `FSException` | 下载到已存在目录时复现 | 新增内部 `ensureDirectory`（先 `exists` 再建，幂等），`BookApi.download` 改用它；补单测 |
| LinderHttp 偶发把底层 stdx 异常直接漏到外层（如 `read response timeout and the connection is closed`） | 收藏请求偶发失败 | `execute` 增加兜底 `catch (Exception)`：按传输失败重试+换站；补单测 |
| 进程偶发直接崩溃：exit -1，事件日志 `0xc0000374`（ntdll 堆损坏） | 2026-11-10 登录 POST 约 2/10；2026-11-11 做 2.2.0 验证时升高到连续 3~4 次（任意请求阶段，加 `logStep` 后确认崩溃点随机，不是某一步/某段新代码）；同机另一项目也复现 | 判断为底层 stdx/TLS 原生问题，非本库逻辑；集成测试用进程级重试/分段复现 |

### 16.3 踩坑修复（本轮联调直接改出的代码）

1. **`ensureDirectory`**：`Directory.create` 对已存在目录抛异常，改为先 `exists` 再建；
   `BookApi.download`/`downloadBook` 都走它，单测覆盖「连续调用两次」。
2. **`execute` 兜底重试**：新增 `catch (err: Exception)` 分支，把未包装的底层网络异常
   视作瞬时故障重试（API 请求还会换站），避免一次抖动直接失败。
3. **`config.downloadTimeout`**：下载/取字节用 5 分钟读写超时，与 API 的 30 秒分开。
4. **集成测试安全**：账号密码只走环境变量；写操作先记录原状态（已收藏则跳过），
   测试后取消收藏还原；`ZLIB_TEST_STAGE=cleanup` 用于清理被中断测试留下的收藏。

### 16.4 仍未验证的部分

- 登录后的其它写操作：发送到 Kindle / 更新资料 / 隐藏 banner / 捐赠等会改账号状态的接口；
- 真实下载的「配额扣减」时序：实测下载前后 `downloadsLeft()` 都是 9（服务端可能延迟结算），
  只断言了「不增加」；
- 注册/找回密码/第三方 token 登录：会触发真实邮件/账号副作用，未测；
- `/user/donations`、`/info/plans` 等形状不稳定接口：只保证原始 JSON 透传。
---

## 17. 统一异常类型（2.2.0）

### 17.1 决策

旧行为：调用方要写两个（甚至三个）`catch`——`ZlibError`、`HttpError`、兜底 `Exception`。
bbapi 也是分开的（`BiliError` 与 `HttpError` 各管一层），但用户明确要求
「一个 catch 管理所有」，所以 2.2.0 改为：**公开 API 只抛 `ZlibError`**。

- `execute` 内部仍区分 `ZlibError` / `HttpError` / 未包装异常来做重试与换站决策；
- 退出 `execute` 前统一包装：
  - `FSException` → `ZlibError(Io)`
  - 其它非 `ZlibError`（`HttpError`、stdx TLS/读写异常）→ `ZlibError(Transport)`
  - 原始异常放进新增的 `ZlibError.cause`
- `ZlibClient.create*`（构造 HttpClient）与 `BookApi.download`（建目录/写盘）也在边界包装；
- 新增 `ZlibErrorKind.Io`（code=8，`isRetryable=false`）、`ZlibError.io(...)`、
  `ZlibError.wrapUnhandled(...)`；
- 破坏性变更：原来 `catch (err: HttpError)` 不再命中，改为 `catch (err: ZlibError)`，
  需要底层细节时看 `err.cause`。

### 17.2 实现要点（踩坑）

- 重试循环里**重试耗尽不能直接 `throw err`**：原实现对 `HttpError`/未包装异常在最后一次
  `throw err`，会绕过循环后的包装逻辑（单测第一次就抓到了）；
  改为 `break` 出循环，循环结束后统一包装；
- `ZlibErrorKind` 新增成员后，`site.cj` 的 `shouldSwitchSite` 是穷尽匹配，必须补 `Io`；
- 单测 `UnifiedErrorTest`：异常包装成 `Transport`、`HttpError` 包装、`Io` 工厂、
  `wrapUnhandled` 保留 path；
- 文档全部改为单 catch：README、`API_USAGE.md` 第 6 章、`Agent.md` §5.3、doccheck 示例。

### 17.3 兼容性

- 源码兼容：`catch (err: ZlibError)` 不受影响；`ZlibError` 构造器新增默认参数 `cause!`；
- 行为兼容：重试/换站规则不变，只是最终抛出的类型统一；
- 依赖方若之前读 `HttpError.kind/url/attempts`，改为读 `err.cause`（`?Exception`）。
---

## 18. 启动凭证丢失 bug（2.2.1）

### 18.1 现象（bbapi 同类 bug）

用户反馈：bbapi 里「启动时给客户端传了登录凭证，但请求实际没带」。在本库复现路径：

1. `ZlibClient.create(baseUrl, credential: 已登录凭证)`（全新 HttpClient、空 Cookie 存储）；
2. 第一次 `UserApi.profile()` → **成功**（手写的 `Cookie` 头生效）；
3. 普通请求（如 `SearchApi.search`）→ 服务端下发 `Set-Cookie: bsrv=...; path=/`；
4. 第二次 `UserApi.profile()` → **NotLoggedIn**（变回游客）。

### 18.2 根因

LinderHttp 的 `mergeHeaders` 在 **Cookie 存储非空**时，会用存储内容
**覆盖**调用方手写的 `Cookie` 头：

```cangjie
// LinderHttp/src/http/client.cj
match (cookieStore) {
    case Some(store) => match (store.headerFor(request.url)) {
        case Some(line) => merged.set("cookie", line)   // 覆盖手写 Cookie
        case None => ()
    }
    ...
}
```

新客户端存储为空 → 第一次请求用手写 Cookie，凭证有效；服务端一下发 Cookie，
存储变非空 → 之后每次请求的 Cookie 头都只剩存储内容（`bsrv` + 语言），
`remix_userid` / `remix_userkey` 丢失。`remix-userid` 请求头服务端不认，
所以直接变游客。

### 18.3 修复

客户端创建时把凭证**预置进 Cookie 存储**（`seedCredentialCookies`），
并在每次请求尝试前检查当前站点存储里是否还有 `remix_userid`，
换站导致域名变化时自动补种（`ensureCredentialCookies`）：

```cangjie
headers.add("remix_userid=${credentialValue.userId}; Path=/; Max-Age=31536000")
headers.add("remix_userkey=${credentialValue.userKey}; Path=/; Max-Age=31536000")
headers.add("siteLanguage=...; Path=/; Max-Age=31536000")
headers.add("siteLanguageV2=...; Path=/; Max-Age=31536000")
store.store(sitesValue.current().url, headers.toArray())
```

这样存储拼出的 Cookie 始终包含凭证，服务端下发的 `bsrv` 等只是叠加。

### 18.4 验证

- 集成测试新增 `ZLIB_TEST_STAGE=credential`：全新客户端 profile →
  普通请求 → profile → profile，三次都必须保持登录态；另外覆盖
  `createWithSites(credential:)`、`fromCookieString` 往返、游客对照；
- 实测 `zh.eva101.ru` 真实账号：**11/11 通过**（修复前「普通请求后仍生效」失败）；
- 离线单测新增 `StartupCredentialTest`（4 个 case），断言凭证被写进
  Cookie 存储（`http.cookies().headerFor(...)` 含 `remix_userid`）。
### 18.5 补充（2.2.2）：底层 `detail` 用 `HttpError.describe()`

`wrapUnhandled` 包装 `HttpError` 时，`detail` 的文本改用 `describe()`，
比 `message` 多出：错误类别、请求 URL、LinderHttp 实际重试次数；
`StatusError` 还带 HTTP 状态码与响应体开头。

实测（死域名请求 `/eapi/user/profile`）：

```
[Transport] 底层请求失败：Protocol [https://definitely-dead.invalid/eapi/user/profile] attempts=3: Failed to resolve address definitely-dead.invalid.
```

- 普通日志打 `err.detail` 就能看到足够信息，不必再取 `cause`；
- 需要原始 `HttpError` 的 `kind/url/attempts` 字段时，`err.cause` 仍在；
- 集成测试新增 `ZLIB_TEST_STAGE=httpdetail` 现场验证这段文本（4/4 通过）；
- 单测新增 `testWrappedHttpErrorDetailUsesDescribe` / `testWrappedStatusErrorDetailHasStatusAndBody`。