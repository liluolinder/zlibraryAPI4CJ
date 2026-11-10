package zlibraryAPI4CJ.core

import std.collection.*

/**
 * URL 查询参数构造工具。
 *
 * eapi 的 GET 接口几乎全靠 query 传参（`switch-language`、`page`、`limit`、
 * `order`…）。这里不直接用 `stdx.encoding.url` 的 Form/URL 实现，原因有二：
 *
 * 1. **同名参数允许重复**：`languages[]=german&languages[]=french` 是数组参数，
 *    不能被「同名覆盖」的语义合并掉（合并后服务端只会看到最后一个）；
 * 2. **编码口径要可控**：服务端按 RFC 3986 未保留字符判断，编码大小写无所谓，
 *    但空格必须是 `%20` 而不是 `+`。
 */
public class Query {
    private let pairs: ArrayList<(String, String)> = ArrayList<(String, String)>()

    public init() {}

    /** 以初始参数构造。 */
    public static func of(items: Array<(String, String)>): Query {
        let query = Query()
        for (pair in items) {
            query.add(pair[0], pair[1])
        }
        query
    }

    /** 追加一个参数；同名参数**不会**被覆盖（数组参数需要重复 key）。 */
    public func add(name: String, value: String): Query {
        pairs.add((name, value))
        this
    }

    /** 追加一组同名参数，例如 `addAll("languages[]", ["german", "english"])`。 */
    public func addAll(name: String, values: Array<String>): Query {
        for (value in values) {
            pairs.add((name, value))
        }
        this
    }

    /** 设置参数；同名已存在则先删除再追加（普通标量参数用这个）。 */
    public func set(name: String, value: String): Query {
        var index: Int64 = 0
        while (index < pairs.size) {
            if (pairs[index][0] == name) {
                pairs.remove(index..(index + 1))
                continue
            }
            index++
        }
        pairs.add((name, value))
        this
    }

    /** 设置参数；值为 `Option`，`None` 时跳过，方便可选参数链式拼接。 */
    public func setIfSome(name: String, value: ?String): Query {
        match (value) {
            case Some(actual) => set(name, actual)
            case None => ()
        }
        this
    }

    /** 设置整型参数。 */
    public func setInt(name: String, value: Int64): Query {
        set(name, "${value}")
    }

    /** 合并另一组参数（覆盖语义）。 */
    public func merge(items: Array<(String, String)>): Query {
        for (pair in items) {
            set(pair[0], pair[1])
        }
        this
    }

    /** 转成参数数组。 */
    public func toArray(): Array<(String, String)> {
        pairs.toArray()
    }

    /** 参数个数。 */
    public prop size: Int64 {
        get() {
            pairs.size
        }
    }

    /** 拼成查询串（不含前导 `?`），值做百分号编码。 */
    public func encode(): String {
        formEncode(pairs.toArray())
    }

    public func toString(): String {
        "Query(${encode()})"
    }
}

/**
 * 把参数数组编码成 `a=1&b=2` 形式（表单体与查询串共用同一套编码）。
 *
 * 与 `Query` 的区别：这里**保留全部同名参数**，所以数组参数（`xxx[]`）安全。
 */
public func formEncode(fields: Array<(String, String)>): String {
    let parts = ArrayList<String>()
    for (pair in fields) {
        parts.add("${percentEncode(pair[0])}=${percentEncode(pair[1])}")
    }
    String.join(parts.toArray(), delimiter: "&")
}

/**
 * 把参数拼到 url 上。
 *
 * 已有 `?` 时用 `&` 续接，否则用 `?` 起头；参数为空时原样返回。
 */
public func withQuery(url: String, params: Array<(String, String)>): String {
    if (params.size == 0) {
        return url
    }
    let encoded = formEncode(params)
    if (url.contains("?")) {
        "${url}&${encoded}"
    } else {
        "${url}?${encoded}"
    }
}

/** 追加一个参数对，返回新数组（保持不可变语义）。 */
public func appendPair(items: Array<(String, String)>,
    pair: (String, String)): Array<(String, String)> {
    let result = ArrayList<(String, String)>()
    for (item in items) {
        result.add(item)
    }
    result.add(pair)
    result.toArray()
}

/**
 * RFC 3986 百分号编码（小写十六进制，空格编 `%20`）。
 *
 * 未保留字符（ALPHA / DIGIT / `-` / `.` / `_` / `~`）原样保留，
 * 其余字节逐个编码；多字节 UTF-8 字符会按字节展开，这是服务端期望的形式。
 */
public func percentEncode(value: String): String {
    let bytes = value.toArray()
    var result = ""
    for (byte in bytes) {
        if (isUriUnreservedByte(byte)) {
            result += String.fromUtf8([byte])
        } else {
            result += "%"
            result += lowerHexDigit(byte >> 4)
            result += lowerHexDigit(byte & 0x0F)
        }
    }
    result
}

private func isUriUnreservedByte(byte: UInt8): Bool {
    (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) ||
        byte == 45 || byte == 46 || byte == 95 || byte == 126
}

private func lowerHexDigit(value: UInt8): String {
    let digits = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"
    ]
    digits[Int64(value & 0x0F)]
}
