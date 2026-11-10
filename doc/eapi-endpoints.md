# eapi 端点清单

> 本文件整理**本库覆盖的 Z-Library eapi 端点**：方法、路径、参数、鉴权、
> 返回字段，以及每个事实的资料来源与可信度。
>
> **为什么需要单独一份**：Z-Library 没有公开的官方 API 文档，所有信息都来自
> 社区逆向，且字段/域名会变。把「我们根据什么认为它是这样」写下来，
> 才能在接口失效时快速判断是「我们记错了」还是「服务端改了」。
>
> 迁移对照见 [`feature_api.md`](feature_api.md)；
> 参数与示例的调用方式见 [`API_USAGE.md`](../API_USAGE.md)。

---

## 1. 通用约定

### 1.1 地址

```
<站点根地址>/eapi + 端点路径
例： https://your-domain/eapi/book/search
```

- `eapi` 前缀是本库常量 `ZLIB_API_PREFIX = "/eapi"`；
  用户经常把整条 eapi 地址贴进来，`ZlibHost.of()` 会自动去掉多余的 `/eapi`
  与尾部 `/`，避免请求打到 `/eapi/eapi`。
- 站点根地址**没有长期稳定的值**：主域会被封、镜像会轮换、账号还有个人域名。
  本库不写死，见 `ZlibHost.DEFAULT_URL` / `ZlibHost.MIRRORS` /
  `resolveZlibHost()`。

### 1.2 鉴权

来自 baroxyton/zlibrary-eapi-documentation 的原文要点（转述）：

> 用账号发起请求时，需要提供 `remix-userid` 与 `remix-userkey` 两个请求头；
> 某些情况下还需要同时提供 `remix_userid` / `remix_userkey` 两个 Cookie。

本库两种都发（`ZlibCredential.toRequestHeaders()` + `toCookieHeader()`），
并额外写语言 Cookie：

| 名称 | 位置 | 来源 | 作用 |
| --- | --- | --- | --- |
| `remix-userid` | 请求头 | 登录响应 `user.id` | 账号 id |
| `remix-userkey` | 请求头 | 登录响应 `user.remix_userkey` | 账号密钥（等价密码） |
| `remix_userid` | Cookie | 同上 | 兼容只认 Cookie 的后端 |
| `remix_userkey` | Cookie | 同上 | 同上 |
| `siteLanguage` / `siteLanguageV2` | Cookie | 用户选择 | 影响返回文案语言 |

社区客户端（bipinkrish/Zlibrary-API）默认带
`User-Agent`（桌面 Chrome）与 `Content-Type: application/x-www-form-urlencoded`；
本库同样带桌面 UA，并按请求类型设置 `Accept` /
`Accept-Language` / `Referer` / `Origin`。

### 1.3 POST 请求

来自同一份社区文档：POST body 是 **urlencoded 表单**
（`param1=value1&param2=value2`），且需要
`Content-Type: application/x-www-form-urlencoded`；
数组参数用**方括号 + 重复 key**，如
`languages[]=german&languages[]=english&languages[]=french`。

本库的 `formEncode` / `Query` 正是为此实现：**同名 key 不去重**。

### 1.4 响应信封

- 成功：`{"success": 1, ...}`，业务数据平铺在根上；
- 失败：`{"success": 0, "error": "..."}`（部分老接口用 `msg`）。

本库 `ZlibEnvelope` 统一解析，`unwrap()` 失败时抛 `ZlibError`。
各端点「返回字段」一列只写**本库关心的字段**，不是完整响应。

### 1.5 下载与个人域名

社区文档明确写道（转述）：

> 由于近期变更，现在必须使用 **personal zlibrary domains**（每个用户的个人域名）
> 才能下载书籍。

实测含义（结合本库旧版经验）：

- `GET /book/{id}/{hash}/file` 返回的 `downloadLink` 是**签名过的绝对地址**；
- 其主机名可能是 CDN 或个人域名，**与站点域名不同**；
- 链接带时效，过期后 403/404，需要重新换取；
- 下载请求**不应**携带 remix 凭证（本库有独立的 `fileHeaders()`）。

### 1.6 可信度标注

本文件用五种标注：

| 标注 | 含义 |
| --- | --- |
| **社区文档** | 来自 baroxyton/zlibrary-eapi-documentation 的端点清单/说明 |
| **社区客户端** | 来自 bipinkrish/Zlibrary-API 的实现（参数名等细节） |
| **旧版实测** | 本库 v1 代码/注释里记录的实测结论（如字段缺失、`_isUserSavedBook` 下划线） |
| **v2 实测** | 2026-11-10 在 `https://zh.eva101.ru` 上跑 `integration/` 时直接观察到的行为（36/36 通过） |
| **推断** | 按端点命名/社区用法推断，**没有独立证据**；接口失效时优先怀疑这类 |

> 2026-11-10 起，本库用独立工程 `integration/` 做过一轮真实站点联调
> （`zh.eva101.ru`，36/36 通过）；未覆盖部分仍按社区文档标注。
> 实测细节见 `MEMORY.md` 第 16 节。

---

## 2. 端点总表

路径均相对于 `<站点>/eapi`。「鉴权」列：**需要** = 通常要求登录态；
**可选** = 游客也能拿到部分数据，登录后结果更完整。

### 2.1 登录 / 账号（`zlibraryAPI4CJ.login`）

| 方法 | 路径 | 参数 | 鉴权 | 返回字段 | 本库入口 | 可信度 |
| --- | --- | --- | --- | --- | --- | --- |
| POST | `/user/login` | 表单 `email`、`password` | 否 | `user`（对象：`id`、`email`、`name`、`kindle_email`、`remix_userkey`、`downloads_today`、`downloads_limit`…） | `LoginApi.login` | 社区文档 + 社区客户端 |
| GET | `/user/profile` | 无 | 需要 | `user`（同上） | `LoginApi.loginWithToken` / `UserApi.profile` | 社区文档 |
| POST | `/user/registration` | 表单 `email`、`password`、`name` | 否 | 信封（`success` / `error`） | `LoginApi.register` | 社区文档 + 社区客户端 |
| POST | `/user/password-recovery` | 表单 `email` | 否 | 信封 | `LoginApi.requestPasswordRecovery` | 社区文档 + 社区客户端 |
| POST | `/user/email/confirmation/resend` | 无 | 需要 | 信封 | `LoginApi.resendConfirmation` | 社区文档 |
| POST | `/user/token-sign-in` | 表单 `name`、`id_token` | 否 | `user`（对象） | `LoginApi.tokenSignIn` | 社区文档 + 社区客户端 |

补充：

- `/user/profile` 也是「用 remix 凭证验证身份」的标准做法：
  社区客户端 `loginWithToken` 就是拿 `remix_userid`/`remix_userkey`
  直接 GET 一次 profile，成功即视为登录（bipinkrish 的实现）。
- `id_token` 是第三方（如 Google）登录的 token，`name` 是提供方名称；
  具体取值集合**推断**，本库不做枚举约束（原样透传）。
- 注册验证码流程（`/papi/user/verification/send-code`、`/rpc.php`）
  **不在本库覆盖范围**。
- **实测补充（2026-11-10）**：未登录/凭证错误时 HTTP 状态码是 **400**，
  但响应体仍是 JSON（`{"success":0,"error":"登录到您的账户"}`）；
  本库不按 HTTP 状态码判错，而是解析 body 的 `success`，因此错误映射不受影响。

### 2.2 图书（`zlibraryAPI4CJ.book`）

| 方法 | 路径 | 参数 | 鉴权 | 返回字段 | 本库入口 | 可信度 |
| --- | --- | --- | --- | --- | --- | --- |
| GET | `/book/{id}/{hash}` | query `switch-language`（可选） | 可选 | `book`（对象，见 3.1） | `BookApi.info` / `BookApi.infoOf` | 社区文档 + **v2 实测** |
| GET | `/book/{id}/{hash}/similar` | 无 | 可选 | `books`（数组，元素为简要图书，见 6.2） | `BookApi.similar` / `BookApi.similarOf` | 社区文档 + **v2 实测** |
| GET | `/book/{id}/{hash}/file` | 无 | 需要 | `file`（对象：`downloadLink`、`description`、`author`、`extension`、`allowDownload`） | `BookApi.file` / `BookApi.fileOf` | 社区文档 + 社区客户端 |
| GET | `/book/{id}/{hash}/formats` | 无 | 可选（匿名实测可用） | `books` 数组：每项 `id`/`hash`/`extension`/`filesize`/`filesizeString` | `BookApi.formats`（返回 `ArrayList<BookFormat>`） | **v2 实测**（zh.eva101.ru, 2026-11-10） |
| GET | `/book/{id}/{hash}/send-to-{type}` | 路径里的 `{type}`（如 `kindle`、`email`） | 需要 | 信封 | `BookApi.sendTo` | 社区客户端（`type` 取值集合为**推断**） |
| GET | `/user/book/{id}/save` | 无 | 需要 | 信封 | `BookApi.save` / `BookApi.saveBrief` | 社区文档 |
| GET | `/user/book/{id}/unsave` | 无 | 需要 | 信封 | `BookApi.unsave` / `BookApi.unsaveBrief` | 社区文档 |
| GET | `/user/book/{id}/delete` | 无 | 需要 | 信封 | `BookApi.remove` | 社区文档 |

补充：

- **收藏/取消收藏/删除只需要 `id`**，不需要 `hash`；详情/相似/下载/发送需要
  `id` + `hash`，且必须来自**同一本书**。
- 本库把「收藏失败」做成异常而不是 `Bool`：未登录时返回 `success=0`，
  静默 `false` 会掩盖登录过期。
- `switch-language` 的 query key 用连字符：社区客户端
  （bipinkrish）对图书详情/最热门/信息类接口都传 `switch-language`。

### 2.3 搜索与榜单（`zlibraryAPI4CJ.search`）

| 方法 | 路径 | 参数 | 鉴权 | 返回字段 | 本库入口 | 可信度 |
| --- | --- | --- | --- | --- | --- | --- |
| POST | `/book/search` | 表单：`message`、`yearFrom`、`yearTo`、`languages[]`、`extensions[]`、`order`、`page`、`limit` | 可选 | `books` + `pagination`（额外含 `before`/`next`，本库忽略） | `SearchApi.search` | 社区文档 + 社区客户端 + **v2 实测** |
| GET | `/book/most-popular` | query `switch-language`（可选） | 可选 | `books`（数组，实测 100 条简要图书） | `SearchApi.mostPopular` | 社区文档 + 社区客户端 + **v2 实测** |
| GET | `/book/recently` | 无 | 可选 | `books`（数组）；**实测返回 `{"success":1}` 不含 books**（可能按账号/时间无数据） | `SearchApi.recently` | 社区文档 + **v2 实测**（返回空） |

补充（搜索参数）：

- `yearFrom` / `yearTo`：出版年份区间，数字字符串；`None` 时不发送。
- `languages[]` / `extensions[]`：**数组参数**，用重复同名 key 表达
  （社区文档的方括号约定）。社区客户端 bipinkrish 的实现里
  `extensions[]` 带方括号、`languages` 不带方括号——两者口径不完全一致，
  本库按「数组参数一律方括号重复 key」统一处理；若线上只认某一种，
  这是**第一个要排查的地方**。
- `order`：排序方式，**原样透传**。社区已知值包括 `year`、`popular` 等
  （bipinkrish 文档字符串写的是 `["year",...]`），完整取值集合由服务端定义、
  未公开，所以本库不做枚举校验。
- `page` / `limit`：页码（从 1 开始）与每页条数（常见 10/20/50）。
- baroxyton 的端点清单里搜索参数还列了一个 `e`（含义未说明，**推断**为内部参数）。
  本库不发送它。

### 2.4 用户资料 / 收藏 / 历史（`zlibraryAPI4CJ.user`）

| 方法 | 路径 | 参数 | 鉴权 | 返回字段 | 本库入口 | 可信度 |
| --- | --- | --- | --- | --- | --- | --- |
| GET | `/user/profile` | 无 | 需要 | `user`（对象） | `UserApi.profile` | 社区文档 |
| GET | `/user/book/saved` | query `order`、`page`、`limit` | 需要 | `books` + `pagination` | `UserApi.saved` | 社区文档 + 社区客户端 |
| GET | `/user/book/downloaded` | query `order`、`page`、`limit` | 需要 | `books` + `pagination` | `UserApi.downloaded` | 社区文档 + 社区客户端 |
| GET | `/user/book/recommended` | 无 | 需要 | `books`（数组） | `UserApi.recommended` | 社区文档 |
| POST | `/user/update` | 表单 `email`、`password`、`name`、`kindle_email`（只发非空项） | 需要 | 信封 | `UserApi.update` | 社区文档 + 社区客户端 |
| GET | `/user/hide-banner` | 无 | 需要 | 信封 | `UserApi.hideBanner` | 社区文档 + 社区客户端 |
| GET | `/user/donations` | 无 | 需要 | 形状不稳定（本库返回原始 `JsonObject`） | `UserApi.donations` | 社区文档（形状**推断**） |

补充：

- `saved` / `downloaded` 的 `order` 与搜索的 `order` 一样是**服务端定义的原样值**。
- `kindle_email` 是**下划线**形式（不是 `kindleEmail`），写错会静默不生效。
- `/user/update` 只发调用方显式给出的字段：漏发字段 = 不修改，
  发空串 = 改成空（可能触发校验失败）。本库用 `None` 表示「不修改」。
- `/user/donations` 社区文档只确认端点存在，返回体形状没有稳定文档，
  所以本库**不造模型**。

### 2.5 站点信息（`zlibraryAPI4CJ.info`）

| 方法 | 路径 | 参数 | 鉴权 | 返回字段 | 本库入口 | 可信度 |
| --- | --- | --- | --- | --- | --- | --- |
| GET | `/info` | query `switch-language`（可选） | 否 | 站点信息：`books`/`articles`/`plans`/`languages`/`extensions`/`banner`/`service` 等 | `InfoApi.site` | 社区文档 + **v2 实测** |
| GET | `/info/languages` | 无 | 否 | `languages`：**map** `{"english":"英语",...}`（实测 175 种） | `InfoApi.languages` | 社区文档 + **v2 实测** |
| GET | `/info/extensions` | 无 | 否 | `extensions`：字符串数组（实测 12 项） | `InfoApi.extensions` | 社区文档 + **v2 实测** |
| GET | `/info/domains` | 无 | 否 | `domains`：对象数组，每项 `domain`/`contentAvailable`/`isRedirector`；**种子站换站内部也用它**（`fetchSeedDomains` + `extractDomainList`） | `InfoApi.domains` | 社区文档 + **v2 实测** |
| GET | `/info/plans` | query `switch-language` / `switchLanguage`（**有分歧**） | 否 | 套餐信息（形状不稳定） | `InfoApi.plans` | 社区文档 + 社区客户端 |

补充：

- **query key 有分歧**：baroxyton 的清单写 `/info` 与 `/info/plans` 的 query 是
  `switchLanguage`（驼峰），bipinkrish 的实现用的是 `switch-language`（连字符，
  与图书接口一致）。本库统一按连字符发送（与多数接口一致），
  如果服务端不认，第一个要试的就是改成 `switchLanguage`。
- 这五个接口的响应都被本库当作**原始 `JsonObject`** 返回：
  社区没有稳定 schema，硬造模型只会制造会腐烂的假设。

---

## 3. 关键返回对象

### 3.1 `book`（图书详情）

字段名以服务端 JSON key 为准，本库模型字段做驼峰映射。
下列标注来自 v1 注释/测试与社区客户端，**不是**官方 schema：

| JSON key | 类型（本库） | 说明 | 可信度 |
| --- | --- | --- | --- |
| `id` | `Int64` | 图书 id | 社区客户端 |
| `content_type` | `String` | `book` / `article` … | 社区客户端 |
| `title` | `String` | 书名 | 社区客户端 |
| `author` | `?String` | 作者，部分书没有 | 旧版实测 |
| `year` | `Int64` | 出版年份（可能给字符串，本库容错） | 旧版实测 |
| `publisher` / `edition` / `identifier` | `?String` | 出版信息 | 社区客户端 |
| `language` | `String` | 语言 | 社区客户端 |
| `pages` | `Int64` | 页数 | 社区客户端 |
| `cover` | `String` | 封面 URL | 社区客户端 |
| `filesize` | `Int64` | 字节数（可能给浮点，本库容错） | 旧版实测 |
| `filesizeString` | `String` | 可读大小（`12.3 MB`）；本库 `sizeText()` 优先用它 | 社区客户端 |
| `extension` | `String` | 扩展名（不含点） | 社区客户端 |
| `md5` / `sha256` | `String` | 校验值 | 社区客户端 |
| `hash` | `String` | 图书 hash，下载/详情必需 | 社区客户端 |
| `href` | `String` | 图书页相对地址 | 社区客户端 |
| `dl` | `String` | 下载路径，**可能缺失**（只有在线阅读的书没有） | 旧版实测 |
| `readOnlineUrl` / `readOnlineAvailable` | `?String` / `Bool` | 在线阅读能力 | 社区客户端 |
| `kindleAvailable` / `sendToEmailAvailable` | `Bool` | 发送能力（可能给 `0/1` 或 `"1"`） | 旧版实测 |
| `_isUserSavedBook` | `?Bool` | 当前用户是否已收藏（仅登录态出现；社区抓包里也有无下划线写法，本库两种都读） | 旧版实测 |
| `date_saved` | `?String` | 收藏日期（仅登录态出现） | 旧版实测 |
| `interestScore` / `qualityScore` | `String` | 评分，服务端原样返回字符串 | 社区客户端 |
| `description` | `String` | 简介 | 社区客户端 |

> `dl` 为空 ≠ 不能下载：真正下载链接要用 `/book/{id}/{hash}/file` 换。

### 3.2 `books`（列表项）

搜索/相似/推荐/收藏/历史列表里的元素。本库 `BookInfoBrief` 只取 5 个字段：

| JSON key | 说明 |
| --- | --- |
| `id` | 图书 id（下载必需） |
| `hash` | 图书 hash（下载必需） |
| `title` / `author` / `cover` | 展示用 |

> 注意：同一份 `books` 数组在不同接口里的元素形状不同——
> `/book/search`、`/user/book/saved`、`/user/book/downloaded` 返回的是**完整**
> `BookInfo`；`/book/{id}/{hash}/similar`、`/book/most-popular`、
> `/book/recently`、`/user/book/recommended` 返回的是精简列表项。
> 本库按各自形状选了 `BookInfo` 或 `BookInfoBrief`，不要互相替换。

### 3.3 `pagination`

```json
"pagination": {
  "limit": 20,
  "current": 1,
  "total_items": 1234,
  "total_pages": 62
}
```

本库 `Pagination` 映射成 `limit` / `current` / `totalItems` / `totalPages`（`Int64`）。
**服务端偶尔不给这个对象**，本库回落到全 0 的分页信息，
所以 `hasMore()` 为 `false` 时也要能区分「到底了」和「服务端没给」。

### 3.4 `user`

| JSON key | 本库字段 | 说明 |
| --- | --- | --- |
| `id` | `id: Int64` | 账号 id |
| `email` | `email: String` | 注册邮箱 |
| `name` | `name: String` | 昵称 |
| `kindle_email` | `kindleEmail: ?String` | Kindle 推送邮箱 |
| `remix_userkey` | `remixUserKey: String` | 账号密钥（**等价密码，不要打日志**） |
| `downloads_today` | `downloadsToday: Int64` | 今日已下载 |
| `downloads_limit` | `downloadsLimit: Int64` | 每日上限 |
| `confirmed` | `confirmed: Bool` | 邮箱是否已确认（社区样本给 `1/0`，**推断**） |
| `isPremium` | `isPremium: Bool` | 是否付费会员（社区样本给 `1/0`，**推断**） |

### 3.5 `file`（下载信息）

| JSON key | 本库字段 | 说明 |
| --- | --- | --- |
| `downloadLink` | `downloadLink: String` | 签名绝对地址（有时效，别缓存） |
| `description` | `description: ?String` | 通常就是书名，用作文件名主体 |
| `author` | `author: ?String` | 拼进文件名 |
| `extension` | `extension: String` | 扩展名（不含点） |
| `allowDownload` | `allowDownload: Bool` | 是否允许下载；**老接口不给该字段**，本库缺省视为允许 |

本库文件名规则：`描述 (作者).扩展名`，缺哪段省略哪段；描述为空退化成
`book.扩展名`；路径分隔符与 Windows 非法字符替换成 `_`。

---

## 4. 本库**没有**覆盖的端点

| 端点 | 说明 |
| --- | --- |
| `/papi/user/verification/send-code` | 注册验证码发送（bipinkrish 用过），本库不覆盖 |
| `/rpc.php` | 验证码校验/注册的另一种实现（bipinkrish 用过），本库不覆盖 |
| 书籍列表（booklist）相关 | sertraline/zlibrary 的 HTML 客户端有公开/私有书单，eapi 侧未确认 |
| `/user/book/{id}/...` 其它子路径 | 只覆盖 save / unsave / delete |

> 需要这些能力时，可以先用 `client.getRaw` / `client.postFormRaw` /
> `client.getEnvelope` 直接打，确认形状后再考虑纳入子包（流程见 `Agent.md` 第 8 节）。

---

## 5. 资料来源

| 来源 | 用途 | 备注 |
| --- | --- | --- |
| [`baroxyton/zlibrary-eapi-documentation`](https://github.com/baroxyton/zlibrary-eapi-documentation) | 端点清单、鉴权方式、POST 表单格式、数组参数方括号写法、个人域名下载限制 | 本文件的主要事实来源；英文内容已转述为中文 |
| [`bipinkrish/Zlibrary-API`](https://github.com/bipinkrish/Zlibrary-API)（`Zlibrary.py`） | 参数名细节：`extensions[]`、`kindle_email`、`order` 已知值、`switch-language` 用法、默认域名 `1lib.sk` | 社区 Python 客户端 |
| [`sertraline/zlibrary`](https://github.com/sertraline/zlibrary) | 客户端形态与用法参考（HTML 解析路线，eapi 覆盖少） | 只作社区实践参考，未从中取端点事实 |
| 本库 v1 代码与注释（git `af70e1e`） | 字段漂移、`dl` 缺字段、`_isUserSavedBook` 下划线、百分号解码 workaround | 「旧版实测」标注的来源 |

> 上述外部仓库仅作**事实参考**，本文件没有照抄其英文原文；
> 端点的可用性以实际服务端行为为准。

---

## 6. v2 实测样本（2026-11-10，zh.eva101.ru）

> 只摘录与本库模型字段相关的部分；完整结果见 `integration/` 与 `MEMORY.md` 第 16 节。

### 6.1 列表项（`most-popular` / `similar`）

```json
{"id":24126585,"isbn":"","url":"/book/V9W3MOb89Y/...html","title":"毛泽东选集(1-7卷...)","author":"毛泽东","cover":"https://...jpg","coverData":" data-id=24126585 ...","hash":"217fd6"}
```

对应 `BookInfoBrief`（2.1.0 增加 `isbn` / `url` / `coverData`）。

### 6.2 搜索（`/book/search`）

```json
{"success":1,"books":[...完整 BookInfo...],"pagination":{"limit":5,"current":1,"before":0,"next":2,"total_items":500,"total_pages":100}}
```

`books` 元素是完整 `BookInfo`（含 `dl`、`readOnlineUrl`、`categories`、`_isUserSavedBook` 等）。

### 6.3 格式（`/book/{id}/{hash}/formats`）

```json
{"success":1,"books":[{"id":35851393,"hash":"b4c3ae","extension":"azw3","filesize":5285744,"filesizeString":"5.04 MB"}]}
```

部分书返回 `{"success":1,"books":[]}`（实测 17309781/625607）。

### 6.4 站点信息

- `/info/extensions`：`{"success":1,"extensions":["pdf","fb2","epub","lit","mobi","djvu","djv","txt","rtf","azw","azw3","cbz"]}`
- `/info/languages`：`{"success":1,"languages":{"english":"英语","russian":"俄语",...}}`（175 种）
- `/info/domains`：`{"success":1,"domains":[{"domain":"z-library.sk","contentAvailable":true,"isRedirector":false},...]}`

### 6.5 未登录错误（HTTP 400，但 body 是 JSON）

`/user/profile`、`/user/book/saved`、`/book/{id}/{hash}/file` 等：

```
HTTP/1.1 400
{"success":0,"error":"登录到您的账户"}
```

本库映射成 `ZlibErrorKind.NotLoggedIn`（`unwrap` 识别中英文 login 文案）。
错误密码登录是 `{"success":0,"error":"电子邮件或密码错误"}` → `ApiFailure`。
