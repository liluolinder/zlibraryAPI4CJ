package zlibraryAPI4CJ.common

import linderHttp.*
import linderHttp.utils.*

public var zlibBaseUrl: String = "https://zh.834101.ru"
public var zlibEAPI: String = "${zlibBaseUrl}/eapi"
public var httpClient: LinderHttp = LinderHttp(readTimeout: Duration.minute, writeTimeout: Duration.minute)
