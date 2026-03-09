package zlibraryAPI4CJ.common

import linderHttp.*


public var zlibBaseUrl: String = "https://zh.101isfj.ru"
public var zlibEAPI: String = "${zlibBaseUrl}/eapi"

public func changeUrl(url:String){
    zlibBaseUrl = url
    zlibEAPI = "${zlibBaseUrl}/eapi"
}

public func canAccessZlib(autoRedirect!:Bool = false):Bool{
    var httpClient = LinderHttp(readTimeout: Duration.minute, writeTimeout: Duration.minute,autoRedirect:false)

    let res =  httpClient.setUrl(zlibBaseUrl).send()
    
    if(autoRedirect && let Some(location)<-res.location){
        changeUrl(location[0])
        true
    }else if(res.status != 302 ){
        true
    }else{
        false
    }
}

