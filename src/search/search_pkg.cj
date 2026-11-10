/**
 * `zlibraryAPI4CJ.search` —— 搜索相关的 eapi 接口。
 *
 * 覆盖的端点（均挂在 `<站点>/eapi` 下）：
 *
 * | 方法 | 路径 | 说明 |
 * | --- | --- | --- |
 * | POST | `/book/search` | 图书搜索（表单参数，响应含 `books` + `pagination`） |
 * | GET | `/book/most-popular` | 最热门图书（`books` 数组） |
 * | GET | `/book/recently` | 最近上传的图书（`books` 数组） |
 *
 * 要点：
 *
 * - 搜索用 **POST + urlencoded 表单**，不是 query：筛选条件多、`message`
 *   可能很长，服务端按表单解析；
 * - `languages[]` / `extensions[]` 是**数组参数**，每个元素一个同名 key
 *   （`languages[]=german&languages[]=french`）。同名 key 必须全部保留，
 *   不能被「同名覆盖」的 map 语义合并（合并后服务端只会看到最后一个值），
 *   所以表单是按 `Array<(String, String)>` 顺序构造的，见 `searchForm`；
 * - `order` 原样透传：社区已知值有 `year` / `popular` 等，枚举由服务端定义，
 *   本库不做本地校验，写死枚举反而会在服务端新增排序方式时过期；
 * - 列表响应统一用 `BookPage`（`books` + `pagination`）承载，
 *   调用方靠 `hasMore()` / `nextPage()` 翻页；
 * - `most-popular` / `recently` 返回的是列表项 `BookInfoBrief`
 *   （只有 id/title/author/cover/hash，要详情需 `BookApi.infoOf`）。
 *
 * 文件划分：
 *
 * | 文件 | 内容 |
 * | --- | --- |
 * | `search_pkg.cj`  | 包文档与 `package` 声明 |
 * | `search.cj`      | `SearchApi`：搜索、最热门、最近上传，以及表单构造 |
 * | `search_test.cj` | 单元测试（离线固定样本） |
 */
package zlibraryAPI4CJ.search
