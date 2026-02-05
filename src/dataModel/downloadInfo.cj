package zlibraryAPI4CJ.dataModel

public struct GetDownloadInfoRes <: Serializable<GetDownloadInfoRes> {
    public var success: UInt8 = 0
    public var file: DownloadInfo = DownloadInfo()

    public func serialize(): DataModel {
        return DataModelStruct().add(field<UInt8>("success", success)).add(field<DownloadInfo>("file", file))
    }
    public static func deserialize(dm: DataModel): GetDownloadInfoRes {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = GetDownloadInfoRes()
        result.success = UInt8.deserialize(dms.get("success"))
        result.file = DownloadInfo.deserialize(dms.get("file"))
        return result
    }
}

public struct DownloadInfo <: Serializable<DownloadInfo> {
    public var downloadLink: String = ''
    public var description: String = ''
    public var author: String = ''
    public var extension: String = ''
    public var allowDownload: Bool = true

    public prop fileName: String {
        get() {
            URL.parse(downloadLink).queryForm.get("filename") ?? ""
        }
    }

    public func download(path!: Path, conflictMethod!: ConflictMethod = ConflictMethod.HARMONY) {
        let savePath = path.join(fileName)
        let response = LinderHttp(
            url: RequestUrl.from(downloadLink.replace("%", "")),
            writeTimeout: Duration.Max,
            readTimeout: Duration.Max,
            intercept: Intercept(
                requestL: {
                    req: LinderHttp => req.url |> println //输出请求域名
                },
                requestErrorL: {
                    err: Exception => '小笨蛋，请求出错了哦，错误信息为${err.message}' |> println
                },
                responseL: {
                    res: LinderHttpResponse => res.status |> println //输出响应状态
                },
                responseErrorL: {
                    err: Exception => '小笨蛋，请求出错了哦，错误信息为${err.message}' |> println
                },
                onStartReadL: {
                    totalSize: Int64 => '文件总大小为${totalSize}' |> println
                },
                onReadProgressUpdateL: {
                    singleReadSize: Int64, hasReadSize: Int64, totalSize: Int64 => '总进度${Float64(hasReadSize) / Float64(totalSize) * 100.0}%，本次读取文件大小为${singleReadSize}, 已经读取了${hasReadSize}, 总大小为${totalSize}' |>
                        println
                },
                onReadEndL: {
                    path: ?Path => '保存完成,保存地址为${path}' |> println
                }
            )
        ).send()
        response.status |> println
        response.getBodyFile(filePath: savePath, conflictMethod: conflictMethod)
    }

    public func serialize(): DataModel {
        return DataModelStruct()
            .add(field<String>("downloadLink", downloadLink))
            .add(field<String>("description", description))
            .add(field<String>("author", author))
            .add(field<String>("extension", extension))
            .add(field<Bool>("allowDownload", allowDownload))
    }
    public static func deserialize(dm: DataModel): DownloadInfo {
        var dms = match (dm) {
            case data: DataModelStruct => data
            case _ => throw Exception("this data is not DataModelStruct")
        }
        var result = DownloadInfo()
        result.downloadLink = String.deserialize(dms.get("downloadLink"))
        result.description = String.deserialize(dms.get("description"))
        result.author = String.deserialize(dms.get("author"))
        result.extension = String.deserialize(dms.get("extension"))
        result.allowDownload = Bool.deserialize(dms.get("allowDownload"))
        return result
    }
}
