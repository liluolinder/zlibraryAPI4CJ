/**
 * 评论子包。
 *
 * Z-Library 的评论接口**不在 eapi 里**（`/eapi/book/{id}/{hash}/reviews`
 * 等实测 404），而在网站前端的 papi：
 *
 * ```text
 * GET /papi/comments/{object}/{objectId}/{offset}?limit=500
 * ```
 *
 * - `object` = `book` / `booklist`；
 * - `objectId` = 书 id（不是 hash）/ 书单 id；
 * - 路径最后一段是 **offset**（实测 `0` 从第一条开始，`1` 跳过第一条返回 99 条）；
 * - `limit` 服务端**忽略**（5/20/50/500 都返回最多 100 条），分页只能靠 offset；
 * - 匿名可读；登录后还会返回 `currentUser` 与「是否已赞」。
 *
 * 响应字段：
 * - `comments`：评论数组，每条含 `id` / `text` / `date` / `dateRelative` /
 *   `parent_id`（回复关系）/ 内嵌 `user`；
 * - `commentsDisabled`：该书是否关闭评论；
 * - `reactionsInfo.reactions`：每条评论的点赞数（`item_id` / `count` / `status`）。
 *
 * 本子包把 `reactionsInfo` 合并进 `BookComment.likes` / `liked`，调用方不需要
 * 自己关联两张表。
 */
package zlibraryAPI4CJ.comment
