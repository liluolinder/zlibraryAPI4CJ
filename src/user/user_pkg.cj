/**
 * `zlibraryAPI4CJ.user` —— 当前登录用户的资料、书单与账号设置。
 *
 * 本包全部是「需要登录态」的接口，集中在 `UserApi`：
 *
 * | 方法 | 端点 | 说明 |
 * | --- | --- | --- |
 * | `profile` | `GET /user/profile` | 用户资料（含下载配额） |
 * | `saved` | `GET /user/book/saved` | 收藏列表（分页，返回 `BookPage`） |
 * | `downloaded` | `GET /user/book/downloaded` | 下载历史（分页，返回 `BookPage`） |
 * | `recommended` | `GET /user/book/recommended` | 个性化推荐（`BookInfoBrief` 列表） |
 * | `update` | `POST /user/update` | 改邮箱/密码/昵称/Kindle 邮箱（只发非 `None` 字段） |
 * | `hideBanner` | `GET /user/hide-banner` | 关掉首页横幅 |
 * | `donations` | `GET /user/donations` | 捐赠信息（形状不稳定，返回原始 JSON） |
 *
 * 调用前必须先有登录态客户端（`LoginApi.loginClient` 或
 * `client.withCredential(...)`），否则服务端会返回 `success = 0` 并提示登录，
 * 客户端侧统一抛 `ZlibErrorKind.NotLoggedIn`。
 *
 * 列表接口用 `BookPage` 而不是裸数组：调用方需要 `hasMore()` / `nextPage()`
 * 才知道该不该继续翻页，只给数组会迫使每个调用方自己再推一遍分页逻辑。
 *
 * ```cangjie
 * import zlibraryAPI4CJ.*
 * import zlibraryAPI4CJ.login.*
 * import zlibraryAPI4CJ.user.*
 *
 * let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
 * try {
 *     let mine = LoginApi.loginClient(guest, "you@example.org", "password")
 *     var page = UserApi.saved(mine, order: "date", page: 1, limit: 20)
 *     while (page.hasMore()) {
 *         page = UserApi.saved(mine, order: "date", page: page.nextPage(), limit: 20)
 *     }
 * } finally {
 *     guest.close()
 * }
 * ```
 */
package zlibraryAPI4CJ.user
