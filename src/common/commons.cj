package zlibraryAPI4CJ.common

import linderHttp.*
import stdx.encoding.url.*

public var zlibBaseUrl: String = "https://tw.jiaoyuan.ru"
public var zlibEAPI: String = "${zlibBaseUrl}/eapi"

public func changeUrl(url: String) {
    zlibBaseUrl = url
    zlibEAPI = URL.parse(zlibBaseUrl).replace(path:'/eapi').toString()
}

/*
 * 这两个探测必须关掉自动重定向：它们正是要靠 3xx 的 Location 去反查可用地址，
 * 跟随重定向就看不到 Location 了。所以各自单独建一个客户端，不复用全局共享客户端。
 */
private func newProbeClient(): HttpClient {
    HttpClientBuilder()
        .readTimeout(Duration.minute)
        .writeTimeout(Duration.minute)
        .followRedirects(false)
        .build()
}

public func canAccessZlib(autoRedirect!: Bool = false): Bool {
    let httpClient = newProbeClient()
    try {
        let res = httpClient.request(Method.Head, zlibBaseUrl).send()
        let reachable = if (autoRedirect && let Some(location) <- res.location) {
            changeUrl(location)
            true
        } else if (res.status == 503 || res.status == 200) {
            true
        } else {
            false
        }
        httpClient.close()
        reachable
    } catch (err: Exception) {
        httpClient.close()
        false
    }
}

public func checkAccess(url: String): Bool {
    let httpClient = newProbeClient()
    try {
        let res = httpClient.request(Method.Head, url).send()
        let reachable = res.status == 503 || res.status == 200
        httpClient.close()
        reachable
    } catch (err: Exception) {
        httpClient.close()
        false
    }
}
