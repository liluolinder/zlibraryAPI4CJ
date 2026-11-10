/**
 * `zlibraryAPI4CJ.model` —— 跨子包共享的数据模型。
 *
 * 为什么单独抽一层 `model`，而不是像 bbapi 那样把模型放在各业务子包里：
 * Z-Library 的 `BookInfo` 同时出现在 `book` / `search` / `user` 三个子包的
 * 返回值里，`ZlibUser` 同时被 `login` 与 `user` 使用。若每个子包各定义一份，
 * 要么重复代码，要么让子包互相 import（破坏「业务子包互不依赖」的约束）。
 * 所以约定：
 *
 * **依赖方向：`core ← model ← 业务子包`，业务子包之间互不 import。**
 *
 * 所有模型都是「可读的宽松容器」：
 *
 * - 字段一律 `public var` + 默认值，缺失字段不会让解码失败；
 * - 解码统一走 `core` 的 `readString/readInt/readBool` 容错读取
 *   （Z-Library 同一字段可能给数字或字符串）；
 * - `fromJsonObject` 是唯一解码入口，`fromJson` 只是便捷包装；
 * - 派生属性/方法（`webpage()` / `fileName()` / `hasMore()`）不落字段。
 *
 * 文件划分：
 *
 * | 文件 | 内容 |
 * | --- | --- |
 * | `book.cj`     | `BookInfo`（详情）、`BookInfoBrief`（列表项） |
 * | `user.cj`     | `ZlibUser` |
 * | `download.cj` | `DownloadInfo` |
 * | `page.cj`     | `Pagination`、`BookPage` |
 */
package zlibraryAPI4CJ.model
