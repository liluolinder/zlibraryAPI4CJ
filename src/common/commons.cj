package zlibraryAPI4CJ.common

import linderHttp.*

public var zlibBaseUrl: String = "https://zh.znanjing.ru"
public var zlibEAPI: String = "${zlibBaseUrl}/eapi"

public var commonIntercept = Intercept(
    requestErrorL: {
                err  => throw  Exception('请求发生错误:${err.message}')
            }
            ,
    responseErrorL: {
                err => throw Exception('响应体发送错误:${err.message}')
            })

public func changeUrl(url: String) {
    zlibBaseUrl = url
    zlibEAPI = "${zlibBaseUrl}/eapi"
}

public func canAccessZlib(autoRedirect!: Bool = false): Bool {
     var httpClient = LinderHttp(readTimeout: Duration.minute, writeTimeout: Duration.minute, intercept:commonIntercept)

    let res = httpClient.setUrl(zlibBaseUrl).send()

    if (autoRedirect && let Some(location) <- res.location) {
        changeUrl(location[0])
        true
    } else if (res.status != 302) {
        true
    } else {
        false
    }
}

