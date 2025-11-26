package zlibraryAPI4CJ.zlibclinet.utils

import stdx.net.tls.*
import stdx.net.http.*
import zlibraryAPI4CJ.common.*

public func getTlsConfig(): TlsClientConfig {
    var tlsConfig = TlsClientConfig()

    tlsConfig.verifyMode = TrustAll
    tlsConfig.domain = zlibraryUrl.replace("https://", "")
    tlsConfig
}

public func setCommonHeader(reqBuilder: HttpRequestBuilder): HttpRequestBuilder {
    reqBuilder
        .header("Sec-ch-ua", #""Chromium";v="142", "Microsoft Edge";v="142", "Not_A Brand";v="99""#)
        .header("Sec-ch-ua-platform", #""Windows""#)
        .header("User-agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0")
}
