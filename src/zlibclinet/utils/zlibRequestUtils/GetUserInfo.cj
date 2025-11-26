package zlibraryAPI4CJ.zlibclinet.utils.zlibRequestUtils

public func getUserInfoU(htmlString: String): JsonObject {
    var doc: Document = Html4cj.parse(htmlString)
    var ascriptAll: Elements = doc.select('z-account')

    var jsonMap = JsonObject()

    for (i in ascriptAll) {
        if (i.hasAttr('avatar')) {
            jsonMap.put("userAvatar", JsonString(i.attr('avatar').toString().replace("\\n", "").replace("\\\"", "")))
            break
        }
    }

    ascriptAll = doc.select('a')
    var index: Int64 = 0
    for (i in ascriptAll) {
        if (i.attr('href') == #"/profile"#) {
            if (index == 1) {
                jsonMap.put("userName", JsonString(i.html()))
            }
            index++
        }
    }

    ascriptAll = doc.select("div")
    index = 0

    for (i in ascriptAll) {
        if (i.attr("class") == #"caret-scroll__title"#) {
            index++
            match (index) {
                case 2 => jsonMap.put("downloadLimit", JsonString(i.html().toString().replace("\\n ", "")))
                case 4 => jsonMap.put("donation", JsonString(i.html().toString().replace("\\n ", "")))
                case _ => continue
            }
        }
    }

    jsonMap
}
