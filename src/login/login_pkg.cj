/**
 * `zlibraryAPI4CJ.login` —— 登录、注册与账号凭据派生。
 *
 * 本包只覆盖 eapi 里与「拿到身份」相关的接口，全部集中在 `LoginApi`：
 *
 * | 方法 | 端点 | 说明 |
 * | --- | --- | --- |
 * | `login` | `POST /user/login` | 邮箱 + 密码登录，返回用户资料与凭证 |
 * | `loginWithToken` | `GET /user/profile` | 用已有 remix 凭证换取用户资料 |
 * | `loginClient` | — | `login` 的便捷版：直接返回已绑定凭证的客户端 |
 * | `loginTokenClient` | — | `loginWithToken` 的便捷版 |
 * | `register` | `POST /user/registration` | 注册（email / password / name） |
 * | `requestPasswordRecovery` | `POST /user/password-recovery` | 发送找回密码邮件 |
 * | `resendConfirmation` | `POST /user/email/confirmation/resend` | 重发邮箱确认信 |
 * | `tokenSignIn` | `POST /user/token-sign-in` | 第三方（Google/Apple）id_token 登录 |
 *
 * 关键设计：**登录的结果不是「客户端变成登录态」，而是一个 `LoginResult`。**
 * `ZlibClient` 与 `ZlibCredential` 都是不可变值，登录成功后必须用
 * `LoginResult.withClient(client)`（内部走 `client.withCredential`）派生一个
 * 新客户端。这样调用方可以同时持有游客客户端与登录客户端，两者共享同一个
 * 连接池，互不污染凭证。
 *
 * ```cangjie
 * import zlibraryAPI4CJ.*
 * import zlibraryAPI4CJ.login.*
 *
 * let guest = ZlibClient.create(baseUrl: "https://your-zlib-domain")
 * try {
 *     let result = LoginApi.login(guest, "you@example.org", "password")
 *     let mine = result.withClient(guest)
 *     println("hi, ${result.user.name}, 今日剩余 ${result.user.downloadsLeft()} 次")
 * } finally {
 *     guest.close()
 * }
 * ```
 *
 * 凭证是敏感信息：`ZlibCredential.toString()` 与 `ZlibUser.toString()` 都刻意
 * 不打印 `remix_userkey`，本包也不做任何日志输出。
 */
package zlibraryAPI4CJ.login
