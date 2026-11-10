/**
 * `zlibraryAPI4CJ.info` —— 站点信息类 eapi 接口。
 *
 * 覆盖的端点（均挂在 `<站点>/eapi` 下）：
 *
 * | 方法 | 路径 | 说明 |
 * | --- | --- | --- |
 * | GET | `/info` | 站点总览（域名、公告、语言、分类等） |
 * | GET | `/info/languages` | 站点支持的语言列表 |
 * | GET | `/info/extensions` | 站点支持的图书扩展名 |
 * | GET | `/info/domains` | 当前可用域名列表 |
 * | GET | `/info/plans` | 会员/套餐信息 |
 *
 * 为什么这些接口返回**原始 `JsonObject`** 而不是强类型模型：
 *
 * - 它们是「站点元数据」，字段随站点版本、镜像、账号状态整体变化
 *   （同一个 key 有时是对象、有时是数组，甚至同一站点不同时间是不同形状）；
 * - 每次变化都跟着改模型，会让一个只用来「看一眼站点支持哪些语言」的接口
 *   变得极易因为一个字段类型漂移而整体解码失败；
 * - 调用方通常只是取其中一两个字段，直接读原始对象更透明。
 *
 * 所以约定：**`InfoApi` 全部方法返回 `client.getEnvelope(...).unwrap()` 的根对象**，
 * 失败（`success = 0`）仍由 `unwrap` 抛 `ZlibError`；成功时调用方用
 * `objectFieldOf` / `arrayFieldOf` / `readString` 等 `core` 工具按需读取。
 *
 * 文件划分：
 *
 * | 文件 | 内容 |
 * | --- | --- |
 * | `info_pkg.cj`  | 包文档与 `package` 声明 |
 * | `info.cj`      | `InfoApi`：站点信息五个只读端点 |
 * | `info_test.cj` | 单元测试（离线固定样本） |
 */
package zlibraryAPI4CJ.info
