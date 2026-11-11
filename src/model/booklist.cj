package zlibraryAPI4CJ.model

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * 书单（readlist）作者/所有者。
 *
 * papi 的书单列表响应把作者信息放在根对象的 `readlistsOwners` 里（按 user id 索引），
 * 而不是每个书单内嵌一份 —— 同一作者的多份书单因此只传一次。
 */
public class ReadlistOwner <: ToString {
    /** 用户 id。 */
    public var id: Int64 = 0
    /** 昵称。 */
    public var name: String = ""
    /** 个人主页相对地址。 */
    public var link: String = ""
    /** 头像地址（可能为空）。 */
    public var avatar: String = ""

    public static func fromJsonObject(obj: JsonObject): ReadlistOwner {
        let owner = ReadlistOwner()
        owner.id = readInt(obj, "id")
        owner.name = readString(obj, "name")
        owner.link = readString(obj, "link")
        owner.avatar = readString(obj, "avatar")
        owner
    }

    public func toString(): String {
        "ReadlistOwner(${id}, ${name})"
    }
}

/**
 * 书单列表里用于预览的一本书。
 *
 * 与 `BookInfoBrief` 的区别：papi 这里给的是 `coverUrl`（绝对地址）而不是
 * `cover`（文件名），所以单独一个类型，不强行复用。
 */
public class ReadlistPreviewBook <: ToString {
    public var id: Int64 = 0
    public var title: String = ""
    public var author: String = ""
    public var cover: String = ""
    public var coverUrl: String = ""
    public var link: String = ""
    public var language: String = ""
    public var identifier: String = ""

    public static func fromJsonObject(obj: JsonObject): ReadlistPreviewBook {
        let book = ReadlistPreviewBook()
        book.id = readInt(obj, "id")
        book.title = readString(obj, "title")
        book.author = readString(obj, "author")
        book.cover = readString(obj, "cover")
        book.coverUrl = readString(obj, "coverUrl")
        book.link = readString(obj, "link")
        book.language = readString(obj, "language")
        book.identifier = readString(obj, "identifier")
        book
    }

    public func toString(): String {
        "ReadlistPreviewBook(${id}, ${title})"
    }
}

/**
 * 一份书单。
 *
 * 端点为网站前端的内部接口：
 * `GET /papi/booklist/get-page/{page}?order=…&searchQuery=…&color=…&access=…`
 */
public class Readlist <: ToString {
    /** 书单 id。 */
    public var id: Int64 = 0
    /** 创建者用户 id（对应 `BooklistPage.owners` 的 key）。 */
    public var userId: Int64 = 0
    public var title: String = ""
    public var description: String = ""
    /** 语言代码（可能为空）。 */
    public var languages: String = ""
    /** 是否公开。 */
    public var publicReadlist: Bool = true
    /** 是否成人内容。 */
    public var adult: Bool = false
    /** 是否是编辑精选。 */
    public var editorsChoice: Bool = false
    public var viewsCount: Int64 = 0
    public var booksCount: Int64 = 0
    public var favoritesCount: Int64 = 0
    public var commentsCount: Int64 = 0
    /** 书单配色编号（网站前端用）。 */
    public var color: Int64 = 0
    public var date: String = ""
    public var dateUpdated: String = ""
    /** 书单页相对地址（`/booklist/{id}/{hash}/{slug}.html`）。 */
    public var link: String = ""

    public static func fromJsonObject(obj: JsonObject): Readlist {
        let readlist = Readlist()
        readlist.id = readInt(obj, "id")
        readlist.userId = readInt(obj, "user_id")
        readlist.title = readString(obj, "title")
        readlist.description = readString(obj, "description")
        readlist.languages = readString(obj, "languages")
        readlist.publicReadlist = readBoolOr(obj, "public", true)
        readlist.adult = readBoolOr(obj, "adult", false)
        readlist.editorsChoice = readBoolOr(obj, "editors_choice", false)
        readlist.viewsCount = readInt(obj, "views_count")
        readlist.booksCount = readInt(obj, "books_count")
        readlist.favoritesCount = readInt(obj, "favorites_count")
        readlist.commentsCount = readInt(obj, "comments_count")
        readlist.color = readInt(obj, "color")
        readlist.date = readString(obj, "date")
        readlist.dateUpdated = readString(obj, "date_updated")
        readlist.link = readString(obj, "link")
        readlist
    }

    /** 作者昵称（需要 `BooklistPage.owners` 配合）。 */
    public func ownerName(page: BooklistPage): String {
        var name = ""
        if (let Some(owner) <- page.owners.get("${userId}")) {
            name = owner.name
        }
        name
    }

    public func toString(): String {
        "Readlist(${id}, ${title}, ${booksCount} books)"
    }
}

/**
 * 书单列表页。
 *
 * `papi` 的列表响应把三块数据放在根上：
 * - `readlists`：本页书单；
 * - `readlistsOwners`：作者信息（user id → owner）；
 * - `booksGrouped`：书单 id → 前几本书（用于卡片预览）；
 * - `nextPage`：下一页页码（0 表示没有更多）。
 */
public class BooklistPage <: ToString {
    public var readlists: ArrayList<Readlist> = ArrayList<Readlist>()
    /** 当前账号收藏的书单（未登录时为空）。 */
    public var favoriteReadlists: ArrayList<Readlist> = ArrayList<Readlist>()
    public var owners: HashMap<String, ReadlistOwner> = HashMap<String, ReadlistOwner>()
    public var previews: HashMap<String, ArrayList<ReadlistPreviewBook>> =
        HashMap<String, ArrayList<ReadlistPreviewBook>>()
    /** 下一页页码；0 表示没有更多。 */
    public var nextPage: Int64 = 0

    /** 某份书单的预览书籍（没有时为 None）。 */
    public func previewOf(readlistId: Int64): ?ArrayList<ReadlistPreviewBook> {
        previews.get("${readlistId}")
    }

    public static func fromRoot(root: JsonObject): BooklistPage {
        let page = BooklistPage()
        page.readlists = decodeEach(arrayFieldOf(root, "readlists"),
            {obj => Readlist.fromJsonObject(obj)})
        page.favoriteReadlists = decodeEach(arrayFieldOf(root, "favoriteReadlists"),
            {obj => Readlist.fromJsonObject(obj)})
        page.nextPage = readIntOr(root, "nextPage", 0)
        match (objectFieldOf(root, "readlistsOwners")) {
            case Some(ownersObject) =>
                for ((key, value) in ownersObject.getFields()) {
                    match (value.kind()) {
                        case JsObject => page.owners[key] = ReadlistOwner.fromJsonObject(value.asObject())
                        case _ => ()
                    }
                }
            case None => ()
        }
        match (objectFieldOf(root, "booksGrouped")) {
            case Some(grouped) =>
                for ((key, value) in grouped.getFields()) {
                    match (value.kind()) {
                        case JsArray =>
                            page.previews[key] = decodeEach(value.asArray().getItems(),
                                {obj => ReadlistPreviewBook.fromJsonObject(obj)})
                        case _ => ()
                    }
                }
            case None => ()
        }
        page
    }

    public func toString(): String {
        "BooklistPage(${readlists.size}/${nextPage})"
    }
}

/**
 * 书单里的书籍页。
 *
 * 端点为 `POST /papi/booklist/{id}/get-books/{page}`；每本书包在
 * `{"book": {...}}` 里，与 eapi 的 `BookInfo` 字段一致。
 * `pagination` 字段与 eapi 分页同名同义。
 */
public class BooklistBooksPage <: ToString {
    public var books: ArrayList<BookInfo> = ArrayList<BookInfo>()
    public var limit: Int64 = 20
    public var current: Int64 = 1
    public var totalItems: Int64 = 0
    public var totalPages: Int64 = 0
    /** 是否有上一页。 */
    public var before: Bool = false
    /** 是否有下一页。 */
    public var next: Bool = false

    /** 本页条数。 */
    public func size(): Int64 {
        Int64(books.size)
    }

    public static func fromRoot(root: JsonObject): BooklistBooksPage {
        let page = BooklistBooksPage()
        for (item in arrayFieldOf(root, "books")) {
            match (item.kind()) {
                case JsObject =>
                    match (objectFieldOf(item.asObject(), "book")) {
                        case Some(bookObject) =>
                            page.books.add(BookInfo.fromJsonObject(bookObject))
                        case None => ()
                    }
                case _ => ()
            }
        }
        match (objectFieldOf(root, "pagination")) {
            case Some(pagination) =>
                page.limit = readIntOr(pagination, "limit", 20)
                page.current = readIntOr(pagination, "current", 1)
                page.totalItems = readIntOr(pagination, "total_items", 0)
                page.totalPages = readIntOr(pagination, "total_pages", 0)
                page.before = readBoolOr(pagination, "before", false)
                page.next = readBoolOr(pagination, "next", false)
            case None => ()
        }
        page
    }

    public func toString(): String {
        "BooklistBooksPage(${current}/${totalPages}, ${books.size} books)"
    }
}
