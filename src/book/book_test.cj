package zlibraryAPI4CJ.book

import std.fs.*
import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * book 子包单元测试。
 *
 * 接口函数本身都要发网络请求，单元测试只覆盖「不联网就能证明」的部分：
 * 查询参数构造、下载前置校验、与客户端的路径拼接。
 * 真实网络验证放在集成测试/调用方工程里，不放进 `cjpm test`（否则 CI 会被网络拖垮）。
 */
@Test
class SwitchLanguageQueryTest {
    @TestCase
    func testNone(): Unit {
        @Expect(switchLanguageQuery(None).size, 0)
    }

    @TestCase
    func testSome(): Unit {
        let query = switchLanguageQuery(Some("en"))
        @Expect(query.size, 1)
        @Expect(query[0][0], "switch-language")
        @Expect(query[0][1], "en")
    }
}

@Test
class BookApiGuardTest {
    @TestCase
    func testDownloadRejectsEmptyLink(): Unit {
        let client = ZlibClient.create(baseUrl: "https://example.com")
        var caught = false
        try {
            BookApi.download(client, DownloadInfo(), Path("target\\tmp_download_guard"))
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.BadResponse
        }
        @Expect(caught, true)
        client.close()
    }

    @TestCase
    func testDownloadRejectsNotAllowed(): Unit {
        let client = ZlibClient.create(baseUrl: "https://example.com")
        let info = DownloadInfo()
        info.downloadLink = "https://dl.example.com/f/1"
        info.allowDownload = false
        var caught = false
        try {
            BookApi.download(client, info, Path("target\\tmp_download_guard"))
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.ApiFailure
        }
        @Expect(caught, true)
        client.close()
    }

    @TestCase
    func testSendToRejectsEmptyTarget(): Unit {
        let client = ZlibClient.create(baseUrl: "https://example.com")
        var caught = false
        try {
            BookApi.sendTo(client, 1, "hash", "  ")
        } catch (err: ZlibError) {
            caught = err.kind == ZlibErrorKind.BadResponse
        }
        @Expect(caught, true)
        client.close()
    }

    @TestCase
    func testApiUrlShape(): Unit {
        // 路径拼接是纯逻辑，可以在不发请求的前提下断言
        let client = ZlibClient.create(baseUrl: "https://example.com")
        @Expect(client.apiUrl("/book/1/x"), "https://example.com/eapi/book/1/x")
        @Expect(client.apiUrl("/user/book/1/save"),
            "https://example.com/eapi/user/book/1/save")
        client.close()
    }
}

@Test
class DirectoryHelperTest {
    @TestCase
    func testEnsureDirectoryIsIdempotent(): Unit {
        // 实测：Directory.create(dir, recursive: true) 在目录已存在时会抛
        // FSException，因此 ensureDirectory 必须可重复调用（下载到已有目录是常见用法）
        let dir = Path("target\\test_book_dirs\\nested")
        removeIfExists(dir, recursive: true)
        @Expect(exists(dir), false)
        ensureDirectory(dir)
        @Expect(exists(dir), true)
        ensureDirectory(dir) // 第二次不应该抛异常
        @Expect(exists(dir), true)
        removeIfExists(dir, recursive: true)
        @Expect(exists(dir), false)
    }
}
