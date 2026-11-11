package zlibraryAPI4CJ.model

import std.collection.*
import stdx.encoding.json.*
import zlibraryAPI4CJ.core.*

/**
 * 评论作者。
 *
 * papi 评论接口把用户信息内嵌在每条评论的 `user` 字段里（不单独给用户表）。
 */
public class CommentUser <: ToString {
    public var name: String = ""
    public var avatar: String = ""
    public var cover: String = ""
    /** 用户主页 hash（拼 `/profile/{id}/{hash}` 用）。 */
    public var hash: String = ""
    public var isPremium: Bool = false
    public var isCurrentUser: Bool = false
    public var isAdmin: Bool = false

    public static func fromJsonObject(obj: JsonObject): CommentUser {
        let user = CommentUser()
        user.name = readString(obj, "name")
        user.avatar = readString(obj, "avatar")
        user.cover = readString(obj, "cover")
        user.hash = readString(obj, "hash")
        user.isPremium = readBoolOr(obj, "isPremium", false)
        user.isCurrentUser = readBoolOr(obj, "isCurrentUser", false)
        user.isAdmin = readBoolOr(obj, "isAdmin", false)
        user
    }

    public func toString(): String {
        "CommentUser(${name})"
    }
}

/**
 * 一条书籍/书单评论。
 *
 * `parentId == 0` 表示顶层评论，否则是对某条评论的回复；接口**不保证**
 * 父评论一定在同一页里（父评论可能更早、已被 offset 跳过），所以展示时
 * 既可以按 `parentId` 分组，也可以平铺并标记「回复」。
 */
public class BookComment <: ToString {
    public var id: Int64 = 0
    /** 评论对象类型：`book` / `booklist`。 */
    public var objectType: String = ""
    /** 被评论对象的 id（书 id / 书单 id）。 */
    public var objectId: Int64 = 0
    /** 父评论 id；`0` 表示顶层评论。 */
    public var parentId: Int64 = 0
    public var userId: Int64 = 0
    public var text: String = ""
    /** 绝对时间（`2023-11-03 16:41:00`，站点本地时区）。 */
    public var date: String = ""
    /** 相对时间（`3年前`）。 */
    public var dateRelative: String = ""
    public var user: CommentUser = CommentUser()
    /** 点赞数（来自 `reactionsInfo`，可能为 0）。 */
    public var likes: Int64 = 0
    /** 当前账号是否点过赞。 */
    public var liked: Bool = false

    public static func fromJsonObject(obj: JsonObject): BookComment {
        let comment = BookComment()
        comment.id = readInt(obj, "id")
        comment.objectType = readString(obj, "object")
        comment.objectId = readInt(obj, "object_id")
        comment.parentId = readIntOr(obj, "parent_id", 0)
        comment.userId = readInt(obj, "user_id")
        comment.text = readString(obj, "text")
        comment.date = readString(obj, "date")
        comment.dateRelative = readString(obj, "dateRelative")
        match (objectFieldOf(obj, "user")) {
            case Some(userObject) => comment.user = CommentUser.fromJsonObject(userObject)
            case None => ()
        }
        comment
    }

    public func toString(): String {
        "BookComment(${id}, ${user.name}, ${date})"
    }
}

/** 单条评论的点赞信息（来自响应的 `reactionsInfo.reactions`）。 */
public class CommentReaction <: ToString {
    public var itemId: Int64 = 0
    /** 当前用户对它的操作状态（0 未操作 / 1 已赞）。 */
    public var status: Int64 = 0
    public var count: Int64 = 0
    public var users: ArrayList<Int64> = ArrayList<Int64>()

    public static func fromJsonObject(obj: JsonObject): CommentReaction {
        let reaction = CommentReaction()
        reaction.itemId = readInt(obj, "item_id")
        reaction.status = readInt(obj, "status")
        reaction.count = readInt(obj, "count")
        for (item in arrayFieldOf(obj, "users")) {
            match (item.kind()) {
                case JsInt => reaction.users.add(item.asInt().getValue())
                case _ => ()
            }
        }
        reaction
    }

    public func toString(): String {
        "CommentReaction(${itemId}, ${count})"
    }
}

/**
 * 一页评论。
 *
 * 接口：`GET /papi/comments/{object}/{objectId}/{offset}?limit=…`
 *
 * ⚠ 服务端**忽略 `limit`**（实测 `limit=5/20/50/500` 都返回最多 100 条），
 * 分页只能靠路径里的 `offset` 递增；`nextOffset(offset)` 给下一段起点。
 */
public class BookCommentsPage <: ToString {
    public var comments: ArrayList<BookComment> = ArrayList<BookComment>()
    /** 该书是否关闭了评论。 */
    public var commentsDisabled: Bool = false
    /** 本条评论的点赞信息（key 是评论 id 字符串）。 */
    public var reactions: HashMap<String, CommentReaction> = HashMap<String, CommentReaction>()

    /** 本页条数。 */
    public func size(): Int64 {
        Int64(comments.size)
    }

    /** 下一页的 offset（本页为空时返回 0）。 */
    public func nextOffset(currentOffset: Int64): Int64 {
        if (comments.isEmpty()) {
            return 0
        }
        currentOffset + Int64(comments.size)
    }

    public static func fromRoot(root: JsonObject): BookCommentsPage {
        let page = BookCommentsPage()
        page.comments = decodeEach(arrayFieldOf(root, "comments"),
            {obj => BookComment.fromJsonObject(obj)})
        page.commentsDisabled = readBoolOr(root, "commentsDisabled", false)
        match (objectFieldOf(root, "reactionsInfo")) {
            case Some(reactionsInfo) =>
                for (item in arrayFieldOf(reactionsInfo, "reactions")) {
                    match (item.kind()) {
                        case JsObject =>
                            let reaction = CommentReaction.fromJsonObject(item.asObject())
                            page.reactions["${reaction.itemId}"] = reaction
                        case _ => ()
                    }
                }
            case None => ()
        }
        // 把点赞数/是否已赞合并到评论上，调用方不必再查 reactions
        for (comment in page.comments) {
            match (page.reactions.get("${comment.id}")) {
                case Some(reaction) =>
                    comment.likes = reaction.count
                    comment.liked = reaction.status != 0
                case None => ()
            }
        }
        page
    }

    public func toString(): String {
        "BookCommentsPage(${comments.size})"
    }
}
