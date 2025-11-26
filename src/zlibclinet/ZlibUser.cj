package zlibraryAPI4CJ.zlibclinet

public class ZlibUser {
    public var cookie: ?String = None
    public var account: String = ''
    public var password: String = ''

    public init() {}

    public init(_account: String, _password: String) {
        account = _account
        password = _password
        let loginRes = this.login()
        if (loginRes[0] == 1) {
            cookie = loginRes[1]
        }
    }

    public func refreashUrl(): (Int64, String) {
        try {
            let client = ClientBuilder().tlsConfig(getTlsConfig()).autoRedirect(false).build()

            var requestBuilder = HttpRequestBuilder().method("GET").url(zlibraryUrl)

            let response = (requestBuilder |> setCommonHeader).build() |> client.send
            let locations = response.headers.get('location')
            client.close()
            if (locations.isEmpty()) {
                (-1, '无需处理')
            } else {
                (1, locations.toArray()[0].removeSuffix('/'))
            }
        } catch (error: Exception) {
            (-1, error.toString())
        }
    }

    public func login(): (Int64, String) {
        try {
            if (account == '' || password == '') {
                throw Exception('账号或者密码为空')
            }
            //请求表单
            let form = Form()
            form.add("isModal", "true")
            form.add("email", account)
            form.add("password", password)
            form.add("site_mode", "books")
            form.add("action", "login")
            form.add("redirectUrl", zlibraryUrl)
            form.add("gg_json_mode", '1')

            let client = ClientBuilder().tlsConfig(getTlsConfig()).build()

            var requestBuilder = HttpRequestBuilder()
                .method("POST")
                .body(form.toEncodeString())
                .url("${zlibraryUrl}/rpc.php")
                .header("content-type", "application/x-www-form-urlencoded")

            let response = (requestBuilder |> setCommonHeader).build() |> client.send
            let res = StringReader(response.body).readToEnd()

            var resJson: JsonObject = JsonValue.fromStr(res).asObject()

            resJson = resJson.get('response').getOrThrow().asObject()

            client.close()

            if (!resJson.containsKey('message')) {
                let userId = resJson.get('user_id').getOrDefault({=> JsonInt(0)}).asInt().getValue()
                let userKey = resJson.get('user_key').getOrDefault({=> JsonString('')}).asString().getValue()
                let cookie = 'siteLanguage=zh; selectedSiteMode=books; remix_userkey=${userKey}; remix_userid=${userId}; redirects_count=%7B%22auth%22%3A1%2C%22hide-auth-params%22%3A1%7D'
                (1, cookie)
            } else {
                (-1, resJson.get('message').getOrDefault({=> JsonNull()}).toString())
            }
        } catch (error: Exception) {
            (-1, error.toString())
        }
    }

    public func getUserInfo() {
        try {
            let client = ClientBuilder().tlsConfig(getTlsConfig()).build()

            var requestBuilder = HttpRequestBuilder().method("GET").url("${zlibraryUrl}/?ts")

            if (!cookie.isNone()) {
                requestBuilder.header("Cookie", cookie.getOrDefault({=> ''}))
            }

            let response = (requestBuilder |> setCommonHeader).build() |> client.send

            let res = StringReader(response.body).readToEnd()

            client.close()
            (Int64(response.status), getUserInfoU(res).toJsonString())
        } catch (error: Exception) {
            (-1, error.toString())
        }
    }

    public func getRecommendBook(page!: Int64 = 1): (Int64, RecommendBookRes) {
        try {
            let client = ClientBuilder().tlsConfig(getTlsConfig()).build()

            var requestBuilder = HttpRequestBuilder()
                .method("GET")
                .url("${zlibraryAPIUrl}/book/mostpopular/mosaic/20/${page}")

            let response = (requestBuilder |> setCommonHeader).build() |> client.send

            let res = StringReader(response.body).readToEnd()

            let recommendbookRes = res |> JsonValue.fromStr |> DataModel.fromJson |> RecommendBookRes.deserialize

            client.close()

            (Int64(response.status), recommendbookRes)
        } catch (error: Exception) {
            (-1, RecommendBookRes())
        }
    }
}
