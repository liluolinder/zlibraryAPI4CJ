package zlibraryAPI4CJ.login

import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

// eapi 路径常量集中在这里：登录相关接口全部挂在 `/user/**` 下，
// 写成常量避免各处拼错，也让新增接口时能一眼看到已覆盖的端点。
private let LOGIN_PATH: String = "/user/login"
private let PROFILE_PATH: String = "/user/profile"
private let REGISTRATION_PATH: String = "/user/registration"
private let PASSWORD_RECOVERY_PATH: String = "/user/password-recovery"
private let RESEND_CONFIRMATION_PATH: String = "/user/email/confirmation/resend"
private let TOKEN_SIGN_IN_PATH: String = "/user/token-sign-in"

/**
 * 一次成功登录的结果。
 *
 * 为什么要把「用户资料」和「凭证」一起返回，而不是只返回凭证：
 *
 * - `ZlibUser` 里的 `downloadsToday` / `downloadsLimit` 是调用方最想马上展示的
 *   配额信息，登录时服务端已经一并给出，再查一次 `/user/profile` 纯属浪费配额；
 * - `credential` 是**派生客户端**的唯一入口（`withClient`），单独返回它会让
 *   调用方到处拼 `client.withCredential(...)`。
 *
 * 该类是不可变值：`user` / `credential` 都是 `let`，登录结果可以安全地跨线程共享。
 */
public class LoginResult <: ToString {
    /** 服务端返回的用户资料（含 id / 邮箱 / 配额）。 */
    public let user: ZlibUser

    /**
     * 由 `user` 派生出的登录凭证（`remix_userid` + `remix_userkey`）。
     *
     * `ZlibUser.toCredential()` 只取 id 与 key，不依赖 Cookie；
     * 因此调用方可以把这个凭证落盘，下次直接用 `ZlibClient.create(credential: ...)`
     * 恢复登录态，不必反复用邮箱密码登录。
     */
    public let credential: ZlibCredential

    public init(user: ZlibUser, credential: ZlibCredential) {
        this.user = user
        this.credential = credential
    }

    /**
     * 把本次登录的凭证绑定到一个新客户端上。
     *
     * 底层是 `client.withCredential(...)`：新客户端共享原客户端的连接池与
     * Cookie 存储，所以派生是廉价的；原客户端的凭证保持不变（不可变语义），
     * 这也是「同一进程内游客请求与登录请求并存」不会互相污染的原因。
     *
     * @param client 任意 `ZlibClient`（通常是登录时用的那个）
     * @return 带登录态的新客户端
     */
    public func withClient(client: ZlibClient): ZlibClient {
        client.withCredential(credential)
    }

    public func toString(): String {
        // 不打印 remix_userkey：凭证等价于密码
        "LoginResult(user=${user.id}, login=${credential.isLoggedIn})"
    }
}

/**
 * 登录相关静态接口。
 *
 * 所有方法的第一个参数都是 `ZlibClient`，接口函数本身无状态，
 * 因此可以并发调用、也可以在不同站点/凭证的客户端上复用。
 */
public class LoginApi {
    /**
     * 邮箱 + 密码登录。
     *
     * 接口：`POST /eapi/user/login`，表单字段 `email` / `password`。
     *
     * 成功响应的根对象里有 `user`：
     * `{ "success": 1, "user": { "id": ..., "remix_userkey": ..., "email": ... } }`。
     * 同时服务端会下发 `remix_userid` / `remix_userkey` 两个 Cookie，但客户端持有的
     * 凭证是**不可变值**、不会自动更新，所以本方法显式从 `user` 派生凭证并放进
     * `LoginResult`，避免「登录成功但后续仍游客态」。
     *
     * @param client 客户端（游客态即可，登录请求本身不需要凭证）
     * @param email 注册邮箱
     * @param password 密码
     * @param siteLanguage 站点语言覆盖值（如 `"en"`）；`None` 表示沿用默认语言
     * @return 登录结果（用户资料 + 可绑定到客户端的凭证）
     * @throws ZlibError 服务端 `success = 0`（密码错误、账号未确认等）或响应不是 JSON
     */
    public static func login(client: ZlibClient, email: String, password: String,
        siteLanguage!: ?String = None): LoginResult {
        let form: Array<(String, String)> = [("email", email), ("password", password)]
        let user = client.postFormObject(LOGIN_PATH, "user", form) { obj =>
            ZlibUser.fromJsonObject(obj)
        }
        LoginResult(user, credentialOf(user, siteLanguage))
    }

    /**
     * 用已有的 remix 凭证登录（「token 登录」）。
     *
     * 接口：`GET /eapi/user/profile`。Z-Library 没有 OAuth token，所谓 token 就是
     * `remix_userid` + `remix_userkey` 这一对值：先用它们派生一个临时客户端，
     * 再用它请求 `/user/profile`，能拿到 `user` 就说明凭证有效。
     *
     * 这样做而不是本地假定凭证有效，是因为服务端会在改密码/风控后让旧 key 立即失效，
     * 只有真的打一次接口才知道。
     *
     * @param client 客户端（站点地址取自它）
     * @param userId 用户 id（`remix_userid`，登录响应 `user.id`）
     * @param userKey 账号密钥（`remix_userkey`）
     * @param siteLanguage 站点语言覆盖值；`None` 表示沿用默认语言
     * @return 登录结果（用户资料 + 凭证）
     * @throws ZlibError 凭证失效（服务端提示需要登录）或响应不是 JSON
     */
    public static func loginWithToken(client: ZlibClient, userId: Int64, userKey: String,
        siteLanguage!: ?String = None): LoginResult {
        let seed = tokenCredential(userId, userKey, siteLanguage)
        let user = client.withCredential(seed).getObject(PROFILE_PATH, "user") { obj =>
            ZlibUser.fromJsonObject(obj)
        }
        LoginResult(user, credentialFor(user, seed))
    }

    /**
     * 邮箱 + 密码登录，并直接返回已绑定凭证的客户端。
     *
     * 等价于 `LoginApi.login(...).withClient(client)`，只是省掉一步；
     * 需要用户资料（配额、昵称）时用 `login`，只想要登录态时用本方法。
     */
    public static func loginClient(client: ZlibClient, email: String, password: String,
        siteLanguage!: ?String = None): ZlibClient {
        login(client, email, password, siteLanguage: siteLanguage).withClient(client)
    }

    /**
     * 用已有 remix 凭证登录，并直接返回登录态客户端。
     *
     * 等价于 `LoginApi.loginWithToken(...).withClient(client)`。
     */
    public static func loginTokenClient(client: ZlibClient, userId: Int64, userKey: String,
        siteLanguage!: ?String = None): ZlibClient {
        loginWithToken(client, userId, userKey, siteLanguage: siteLanguage).withClient(client)
    }

    /**
     * 注册新账号。
     *
     * 接口：`POST /eapi/user/registration`，表单字段 `email` / `password` / `name`。
     *
     * 注册成功后服务端通常还会发一封确认邮件；未确认账号登录会失败，
     * 此时可用 `resendConfirmation` 重发。
     *
     * @return `Unit`：本接口只关心成功与否，业务数据没有后续用途
     * @throws ZlibError 邮箱已注册、密码强度不足等服务端拒绝
     */
    public static func register(client: ZlibClient, email: String, password: String,
        name: String): Unit {
        let form: Array<(String, String)> = [("email", email), ("password", password),
            ("name", name)]
        client.postFormEnvelope(REGISTRATION_PATH, form).unwrap(path: REGISTRATION_PATH)
        ()
    }

    /**
     * 发送找回密码邮件。
     *
     * 接口：`POST /eapi/user/password-recovery`，表单字段 `email`。
     *
     * 出于防枚举考虑，服务端对「邮箱不存在」也可能返回 `success = 1`，
     * 所以不要用本方法的成功与否判断邮箱是否注册过。
     */
    public static func requestPasswordRecovery(client: ZlibClient, email: String): Unit {
        let form: Array<(String, String)> = [("email", email)]
        client.postFormEnvelope(PASSWORD_RECOVERY_PATH, form)
            .unwrap(path: PASSWORD_RECOVERY_PATH)
        ()
    }

    /**
     * 重发注册确认邮件。
     *
     * 接口：`POST /eapi/user/email/confirmation/resend`，无表单字段。
     *
     * 需要登录态（服务端要知道给哪个账号发信），所以调用前先用
     * `LoginApi.loginClient` / `withCredential` 派生登录客户端。
     */
    public static func resendConfirmation(client: ZlibClient): Unit {
        client.postFormEnvelope(RESEND_CONFIRMATION_PATH, Array<(String, String)>())
            .unwrap(path: RESEND_CONFIRMATION_PATH)
        ()
    }

    /**
     * 第三方（Google / Apple）id_token 登录。
     *
     * 接口：`POST /eapi/user/token-sign-in`，表单字段 `name` / `id_token`。
     *
     * `name` 是身份提供方名（社区客户端传 `"google"` / `"apple"`），`idToken` 是
     * OIDC 的 id_token 原文。成功响应与邮箱登录相同，根对象里有 `user`。
     *
     * 该接口没有语言参数（服务端按账号存储的语言返回），所以凭证语言用默认值。
     *
     * @return 登录结果（用户资料 + 凭证）
     * @throws ZlibError id_token 无效或账号未确认
     */
    public static func tokenSignIn(client: ZlibClient, name: String,
        idToken: String): LoginResult {
        let form: Array<(String, String)> = [("name", name), ("id_token", idToken)]
        let user = client.postFormObject(TOKEN_SIGN_IN_PATH, "user", form) { obj =>
            ZlibUser.fromJsonObject(obj)
        }
        LoginResult(user, user.toCredential())
    }
}

/**
 * 由用户资料派生凭证，`siteLanguage` 为 `Some` 时覆盖默认语言。
 *
 * 用 `??` 而不是 `match`：这里只是「取默认值」，两种写法语义相同，
 * 但 `??` 更短且不引入分支。
 */
private func credentialOf(user: ZlibUser, siteLanguage: ?String): ZlibCredential {
    user.toCredential(siteLanguage: siteLanguage ?? ZLIB_DEFAULT_SITE_LANGUAGE)
}

/** 用 `id` + `userKey` 构造凭证，语言参数为空时回退默认语言。 */
private func tokenCredential(userId: Int64, userKey: String,
    siteLanguage: ?String): ZlibCredential {
    ZlibCredential.of(userId, userKey,
        siteLanguage: siteLanguage ?? ZLIB_DEFAULT_SITE_LANGUAGE)
}

/**
 * 优先用服务端刚返回的 `remix_userkey` 组装凭证，缺失时退回调用方给的那份。
 *
 * `/user/profile` 正常会回带 `remix_userkey`，但历史上该字段偶发缺失；
 * 直接 `user.toCredential()` 会得到空 key（`isLoggedIn == false`），
 * 让「凭证明明有效」的登录变成静默的游客态。这里显式兜底。
 */
private func credentialFor(user: ZlibUser, fallback: ZlibCredential): ZlibCredential {
    if (user.remixUserKey.isEmpty()) {
        return fallback
    }
    user.toCredential(siteLanguage: fallback.siteLanguage)
}
