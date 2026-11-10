package zlibraryAPI4CJ.core

import std.collection.*
import std.convert.*
import stdx.encoding.json.*

/**
 * Z-Library eapi 的响应信封。
 *
 * eapi 的响应形态比 B 站那种 `{code,message,data}` 更松散，但有两个稳定锚点：
 *
 * - 成功：`{"success": 1, ...}`，业务数据直接平铺在根上
 *   （`user` / `book` / `books` / `file` / `pagination` …）；
 * - 失败：`{"success": 0, "error": "..."}`（部分老接口用 `msg`）。
 *
 * 所以本类只做三件事：解析根对象、判定 `success`、按字段取子对象/数组。
 * 业务数据的具体形状交给各子包解码——信封不假设字段名，避免不同接口
 * 各写一套信封类。
 */
public class ZlibEnvelope {
    /** 原始 JSON 根对象，保留给需要读信封外字段的场景。 */
    public let root: JsonObject

    private init(root: JsonObject) {
        this.root = root
    }

    /**
     * 从响应体文本解析信封。
     *
     * 对非 JSON 响应单独给出可诊断的错误：Z-Library 域名失效或触发风控时，
     * 前面一层会直接回一段 HTML/登录页；若原样丢给 JSON 解析器，
     * 调用方只能看到 `JsonException`，不知道真正发生了什么。
     */
    public static func parse(body: String, path!: String = ""): ZlibEnvelope {
        let trimmed = body.trimAscii()
        if (trimmed.isEmpty() || !trimmed.startsWith("{")) {
            throw ZlibError.badResponse(path, body)
        }
        let root = try {
            JsonValue.fromStr(trimmed).asObject()
        } catch (_: Exception) {
            throw ZlibError.badResponse(path, body)
        }
        ZlibEnvelope(root)
    }

    /** 是否成功（`success` 兼容 `1` / `true` / `"1"`；缺失视为失败）。 */
    public prop success: Bool {
        get() {
            readBool(root, "success")
        }
    }

    /** 服务端错误文案：优先 `error`，其次 `msg`；都没有时为空串。 */
    public prop errorText: String {
        get() {
            let error = readString(root, "error")
            if (!error.isEmpty()) {
                return error
            }
            readString(root, "msg")
        }
    }

    /** 是否成功。 */
    public prop ok: Bool {
        get() {
            success
        }
    }

    /**
     * 成功则返回根对象，失败抛 `ZlibError`。
     *
     * 这是子包的默认入口：`envelope.unwrap(path: "/book/{id}/{hash}")`。
     * 若调用方想自己处理失败（例如把 `success=0` 当成「没找到」而不是异常），
     * 直接用 `success` / `errorText` 判断即可。
     */
    public func unwrap(path!: String = ""): JsonObject {
        if (!success) {
            let message = errorText
            let lower = message.toAsciiLower()
            // 服务端未登录文案：英文（旧版实测）与中文（zh 站点实测 2026-11-10：
            // "登录到您的账户"）都要覆盖，否则调用方只能看到笼统的 ApiFailure。
            if (lower.contains("login") || lower.contains("log in") ||
                lower.contains("sign in") || message.contains("登录")) {
                throw ZlibError(ZlibErrorKind.NotLoggedIn, message, path: path,
                    serverMessage: message)
            }
            if (lower.contains("not found") || lower.contains("nothing has been found")) {
                throw ZlibError(ZlibErrorKind.NotFound, message, path: path,
                    serverMessage: message)
            }
            throw ZlibError.apiFailure(path, message)
        }
        root
    }

    /** 取根上的对象字段；缺失或类型不符返回 `None`。 */
    public func objectField(name: String): ?JsonObject {
        objectFieldOf(root, name)
    }

    /** 取根上的数组字段；缺失或类型不符返回空数组。 */
    public func arrayField(name: String): ArrayList<JsonValue> {
        arrayFieldOf(root, name)
    }

    /** 用于日志/调试的一行摘要。 */
    public func toString(): String {
        "ZlibEnvelope(success=${success}, error=${errorText})"
    }
}

// ---------------------------------------------------------------------------
// 宽松 JSON 读取工具
//
// Z-Library 的字段类型并不稳定（实测同一字段在不同接口/不同时间可能是
// 数字或字符串，可选字段会整条缺失）。如果模型解码直接用 `asInt()`，
// 一个脏字段就会让整页结果作废。所以所有模型解码统一走这里的读函数：
// 读不到就回退默认值，宁可少一个字段也不要整条失败。
// ---------------------------------------------------------------------------

/** 读取字符串字段；数字/布尔会转成文本，缺失返回空串。 */
public func readString(obj: JsonObject, key: String): String {
    if (let Some(value) <- obj.get(key)) {
        return jsonToString(value)
    }
    ""
}

/** 读取字符串字段；缺失或为空时返回 `fallback`。 */
public func readStringOr(obj: JsonObject, key: String, fallback: String): String {
    let value = readString(obj, key)
    if (value.isEmpty()) {
        fallback
    } else {
        value
    }
}

/** 读取可选字符串字段；缺失/`null` 返回 `None`，空串也视为 `None`。 */
public func readOptionalString(obj: JsonObject, key: String): ?String {
    if (let Some(value) <- obj.get(key)) {
        let text = jsonToString(value)
        if (!text.isEmpty()) {
            return Some(text)
        }
    }
    None
}

/** 读取整数字段；兼容整数、浮点、数字字符串与布尔。 */
public func readInt(obj: JsonObject, key: String): Int64 {
    if (let Some(value) <- obj.get(key)) {
        return jsonToInt(value)
    }
    0
}

/** 读取整数字段；缺失时返回 `fallback`。 */
public func readIntOr(obj: JsonObject, key: String, fallback: Int64): Int64 {
    if (let Some(value) <- obj.get(key)) {
        return jsonToInt(value)
    }
    fallback
}

/** 读取浮点字段；兼容整数与数字字符串。 */
public func readFloat(obj: JsonObject, key: String): Float64 {
    if (let Some(value) <- obj.get(key)) {
        return jsonToFloat(value)
    }
    0.0
}

/** 读取布尔字段；兼容 `0/1` 与 `"true"/"false"`。 */
public func readBool(obj: JsonObject, key: String): Bool {
    if (let Some(value) <- obj.get(key)) {
        return jsonToBool(value)
    }
    false
}

/** 读取布尔字段；缺失时返回 `fallback`。 */
public func readBoolOr(obj: JsonObject, key: String, fallback: Bool): Bool {
    if (let Some(value) <- obj.get(key)) {
        return jsonToBool(value)
    }
    fallback
}

/** 取对象字段；缺失或类型不符返回 `None`。 */
public func objectFieldOf(obj: JsonObject, key: String): ?JsonObject {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsObject => return Some(value.asObject())
                case _ => return None
            }
        case None => return None
    }
}

/** 取数组字段；缺失或类型不符返回空数组。 */
public func arrayFieldOf(obj: JsonObject, key: String): ArrayList<JsonValue> {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsArray => return value.asArray().getItems()
                case _ => return ArrayList<JsonValue>()
            }
        case None => return ArrayList<JsonValue>()
    }
}

/**
 * 从数组里逐项解码，跳过解码失败的项。
 *
 * 单条脏数据（上游字段类型漂移、条目被删除）不应该让整页列表失败，
 * 所以这里吞掉单条异常；需要严格失败语义时用 `decodeEachOrThrow`。
 */
public func decodeEach<T>(items: ArrayList<JsonValue>, decoder: (JsonObject) -> T): ArrayList<T> {
    let result = ArrayList<T>()
    for (item in items) {
        try {
            match (item.kind()) {
                case JsObject => result.add(decoder(item.asObject()))
                case _ => ()
            }
        } catch (_: Exception) {
            () // 单条脏数据不应让整页失败
        }
    }
    result
}

/** 从数组里逐项解码，任一条失败即整体抛错。 */
public func decodeEachOrThrow<T>(items: ArrayList<JsonValue>,
    decoder: (JsonObject) -> T): ArrayList<T> {
    let result = ArrayList<T>()
    for (item in items) {
        result.add(decoder(item.asObject()))
    }
    result
}

/** 从 JSON 文本直接解析出对象；失败抛 `ZlibError`（BadResponse）。 */
public func parseJsonObject(text: String, path!: String = ""): JsonObject {
    let trimmed = text.trimAscii()
    if (trimmed.isEmpty() || !trimmed.startsWith("{")) {
        throw ZlibError.badResponse(path, text)
    }
    try {
        JsonValue.fromStr(trimmed).asObject()
    } catch (_: Exception) {
        throw ZlibError.badResponse(path, text)
    }
}

// ---------------------------- 单值宽松转换 ----------------------------

/** `JsonValue` → `Int64`：整数、浮点（`1.0`）、数字字符串、布尔都接受。 */
internal func jsonToInt(value: JsonValue): Int64 {
    match (value.kind()) {
        case JsInt => return value.asInt().getValue()
        case JsFloat => return Int64(value.asFloat().getValue())
        case JsString =>
            let text = value.asString().getValue().trimAscii()
            let parsed = try {
                Int64.parse(text)
            } catch (_: Exception) {
                0
            }
            return parsed
        case JsBool =>
            if (value.asBool().getValue()) {
                return 1
            }
            return 0
        case _ => return 0
    }
}

/** `JsonValue` → `Float64`：整数、浮点、数字字符串都接受。 */
internal func jsonToFloat(value: JsonValue): Float64 {
    match (value.kind()) {
        case JsFloat => return value.asFloat().getValue()
        case JsInt => return Float64(value.asInt().getValue())
        case JsString =>
            let text = value.asString().getValue().trimAscii()
            let parsed = try {
                Float64.parse(text)
            } catch (_: Exception) {
                0.0
            }
            return parsed
        case _ => return 0.0
    }
}

/** `JsonValue` → `String`：数字与布尔也转成字符串，不丢信息。 */
internal func jsonToString(value: JsonValue): String {
    match (value.kind()) {
        case JsString => return value.asString().getValue()
        case JsInt => return "${value.asInt().getValue()}"
        case JsFloat => return "${value.asFloat().getValue()}"
        case JsBool =>
            if (value.asBool().getValue()) {
                return "true"
            }
            return "false"
        case JsNull => return ""
        case _ => return value.toString()
    }
}

/** `JsonValue` → `Bool`：兼容 `0/1` 与 `"true"/"false"` 字符串。 */
internal func jsonToBool(value: JsonValue): Bool {
    match (value.kind()) {
        case JsBool => return value.asBool().getValue()
        case JsInt => return value.asInt().getValue() != 0
        case JsFloat => return value.asFloat().getValue() != 0.0
        case JsString =>
            let text = value.asString().getValue().trimAscii().toAsciiLower()
            return text == "true" || text == "1" || text == "yes"
        case _ => return false
    }
}
