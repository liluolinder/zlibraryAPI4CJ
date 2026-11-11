/**
 * 书单（readlist）子包。
 *
 * Z-Library 官方 eapi **没有**书单接口（实测 404），书单是网站前端用
 * `papi` 内部 JSON 接口提供的。本子包因此走 papi：
 *
 * | 能力 | 方法 |
 * | --- | --- |
 * | 公开书单列表 | `BooklistApi.list(...)` |
 * | 我的书单（需登录） | `BooklistApi.my(...)` |
 * | 书单里的书 | `BooklistApi.books(...)` |
 *
 * 协议要点（2026-11-11 实测）：
 *
 * 1. 列表：`GET /papi/booklist/get-page/{page}?order=popular&searchQuery=&color=all&access=public`
 *    返回 `readlists` / `readlistsOwners` / `booksGrouped`（书单 id → 前几本书）/ `nextPage`。
 * 2. 书籍：`POST /papi/booklist/{id}/get-books/{page}` 表单 `page=…`，
 *    返回 `books`（每项 `{"book": {...}}`）与 `pagination`。
 * 3. `access` 取 `public` / `private`；`private` 需要登录态（`remix_userid/remix_userkey`
 *    Cookie 或请求头，客户端已统一携带）。
 * 4. papi 与 eapi 共用连接池、凭证、换站与重试策略，只是路径前缀不同，
 *    由 `ZlibClient.getPapiJson` / `postPapiFormJson` 负责。
 */
package zlibraryAPI4CJ.booklist
