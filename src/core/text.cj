package zlibraryAPI4CJ.core

/**
 * 按「字符（Rune）」安全截断字符串。
 *
 * 直接用 `text[0..n]` 是在**字节**上切：一个 3 字节的汉字被切掉一半
 * 就会产生非法 UTF-8 序列，后续输出/日志会抛 `Invalid utf8 byte sequence`。
 * 错误消息预览这类场景必须先按 Rune 边界切。
 *
 * @param text 原始字符串
 * @param maxRunes 最多保留的字符数
 * @param suffix 截断后追加的后缀（如 `...`）；传空串表示不加
 */
public func truncateRunes(text: String, maxRunes: Int64, suffix!: String = "..."): String {
    if (maxRunes <= 0) {
        return ""
    }
    let runes = text.toRuneArray()
    if (Int64(runes.size) <= maxRunes) {
        return text
    }
    var result = ""
    var count: Int64 = 0
    for (rune in runes) {
        if (count >= maxRunes) {
            break
        }
        result += String.fromUtf8(rune.toString().toArray())
        count++
    }
    result + suffix
}

/**
 * 按「字节」截断字符串，但保证不切碎 UTF-8 字符。
 *
 * 用于「最多 n 字节」的场景（例如把 HTML 预览塞进异常消息）：
 * 从上限位置往前回退，跳过 UTF-8 续字节（`0b10xxxxxx`）再切。
 */
public func truncateBytesSafe(text: String, maxBytes: Int64, suffix!: String = "..."): String {
    if (maxBytes <= 0) {
        return suffix
    }
    let bytes = text.toArray()
    if (Int64(bytes.size) <= maxBytes) {
        return text
    }
    var end = maxBytes
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
        end--
    }
    String.fromUtf8(bytes[0..end]) + suffix
}
