/**
 * `zlibraryAPI4CJ.book` —— 图书相关的 eapi 接口。
 *
 * 覆盖的端点（均挂在 `<站点>/eapi` 下）：
 *
 * | 方法 | 路径 | 说明 |
 * | --- | --- | --- |
 * | GET | `/book/{id}/{hash}` | 图书详情（`book` 字段） |
 * | GET | `/book/{id}/{hash}/similar` | 相似图书（`books` 数组） |
 * | GET | `/book/{id}/{hash}/file` | 下载信息（`file` 字段，含签名下载链接） |
 * | GET | `/book/{id}/{hash}/formats` | 可用格式（原始 JSON，形状不稳定） |
 * | GET | `/book/{id}/{hash}/send-to-{type}` | 发送到 Kindle / 邮箱 |
 * | GET | `/user/book/{id}/save` | 收藏 |
 * | GET | `/user/book/{id}/unsave` | 取消收藏 |
 * | GET | `/user/book/{id}/delete` | 从「收藏/已下载」列表里删除 |
 *
 * 要点：
 *
 * - `id` + `hash` 是几乎所有图书接口的必需定位符，二者缺一不可；
 * - **收藏/取消收藏/删除只需要 `id`**（旧版接口路径就只带 id）；
 * - 下载分两步：先 `file()` 拿到签名链接，再 `download()` 落盘。
 *   官方文档明确说明：现代 Z-Library 的下载链接指向「个人域名」，
 *   换账号/换域名后旧链接会失效，必须重新换取；
 * - 这些接口大多需要登录态（游客调用会得到 `success=0`），
 *   本库把服务端含 login 字样的错误映射成 `ZlibErrorKind.NotLoggedIn`。
 *
 * 文件划分：
 *
 * | 文件 | 内容 |
 * | --- | --- |
 * | `book.cj`      | `BookApi`：详情/相似/下载/收藏/发送/落盘 |
 * | `book_test.cj` | 单元测试（离线固定样本） |
 */
package zlibraryAPI4CJ.book
