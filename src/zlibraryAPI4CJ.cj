/**
 * zlibraryAPI4CJ —— Z-Library EAPI 的仓颉静态库。
 *
 * 本文件是模块根包，只做一件事：把 `zlibraryAPI4CJ.core` 与
 * `zlibraryAPI4CJ.model` 的公开入口在根包再导出。使用方写一条
 * `import zlibraryAPI4CJ.*` 就能拿到客户端、凭证、错误类型与全部数据模型，
 * 需要具体业务接口时再按需 `import zlibraryAPI4CJ.book.*` 等。
 *
 * 子包划分（按功能分层，依赖方向单一，不存在循环依赖）：
 *
 * | 子包 | 职责 |
 * | --- | --- |
 * | `zlibraryAPI4CJ.core`   | 客户端、凭证、站点池（自定义站 + 种子站换站）、响应信封、错误、URL/表单编码、容错 JSON 读取 |
 * | `zlibraryAPI4CJ.model`  | 跨子包共享的数据模型：图书、用户、下载信息、分页 |
 * | `zlibraryAPI4CJ.login`  | 邮箱密码登录、remix 凭证登录、注册/找回密码/第三方 token 登录 |
 * | `zlibraryAPI4CJ.book`   | 图书详情、相似图书、下载信息、保存/取消保存/删除、发送到 Kindle/邮箱、下载 |
 * | `zlibraryAPI4CJ.search` | 图书搜索、最热门、最近上传 |
 * | `zlibraryAPI4CJ.user`   | 个人资料、收藏列表、下载历史、个性化推荐、资料更新 |
 * | `zlibraryAPI4CJ.info`   | 站点信息（语言/扩展名/域名/套餐），返回原始 JSON |
 * | `zlibraryAPI4CJ.booklist` | 书单（papi：列表 / 我的书单 / 书单内图书）；eapi 没有书单接口 |
 *
 * 依赖方向：`core ← model ← 业务子包`。业务子包之间**互不 import**，
 * 所有共享类型都下沉到 `model`，这样既避免循环依赖，也让每个子包能独立测试。
 *
 * 典型用法：
 * ```cangjie
 * import zlibraryAPI4CJ.*
 * import zlibraryAPI4CJ.search.*
 *
 * let client = ZlibClient.create(baseUrl: "https://your-zlib-domain")
 * try {
 *     let page = SearchApi.search(client, message: "Rust")
 *     println("共 ${page.pagination.totalItems} 条，本页 ${page.size()} 本")
 * } finally {
 *     client.close()
 * }
 * ```
 */
package zlibraryAPI4CJ

public import zlibraryAPI4CJ.core.*
public import zlibraryAPI4CJ.model.*
