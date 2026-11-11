package zlibraryAPI4CJ.comment

import zlibraryAPI4CJ.core.*
import zlibraryAPI4CJ.model.*

/**
 * 评论模型单元测试。
 *
 * 样本取自 2026-11-11 真实 papi 响应（截断到两条：一条顶层、一条回复），
 * 只验证离线可验证的 JSON 解码与「点赞合并」语义。
 */
@Test
class CommentDecodeTest {
    private let SAMPLE = """
{
  "success": 1,
  "commentsDisabled": false,
  "comments": [
    {
      "id": 417359,
      "object": "book",
      "object_id": 24126585,
      "parent_id": null,
      "user_id": 35076277,
      "text": "学习批判继承",
      "date": "2023-11-03 16:41:00",
      "dateRelative": "3年前",
      "user": {
        "name": "xzwh", "avatar": "", "cover": "/img/profile/cover-0.png",
        "hash": "11b921", "isPremium": false, "isCurrentUser": false,
        "isAdmin": false
      }
    },
    {
      "id": 776685,
      "object": "book",
      "object_id": 24126585,
      "parent_id": 709973,
      "user_id": 41352629,
      "text": "第六第七是文革时期的",
      "date": "2025-01-10 13:26:13",
      "dateRelative": "1年前",
      "user": {
        "name": "随便", "avatar": "", "cover": "/img/profile/cover-0.png",
        "hash": "df703c", "isPremium": false, "isCurrentUser": false,
        "isAdmin": false
      }
    }
  ],
  "reactionsInfo": {
    "reactions": [
      {"item_id": 417359, "status": 1, "count": 17, "users": [1, 2, 3]},
      {"item_id": 776685, "status": 0, "count": 2, "users": []}
    ],
    "isLiked": []
  },
  "currentUser": {"name": "reader", "isAdmin": false}
}
"""

    @TestCase
    func testCommentDecode(): Unit {
        let page = BookCommentsPage.fromRoot(parseJsonObject(SAMPLE))
        @Expect(page.comments.size, 2)
        @Expect(page.commentsDisabled, false)
        let top = page.comments[0]
        @Expect(top.id, 417359)
        @Expect(top.objectType, "book")
        @Expect(top.objectId, 24126585)
        @Expect(top.parentId, 0)
        @Expect(top.user.name, "xzwh")
        @Expect(top.date, "2023-11-03 16:41:00")
        @Expect(top.dateRelative, "3年前")
    }

    @TestCase
    func testReplyParentAndLikes(): Unit {
        let page = BookCommentsPage.fromRoot(parseJsonObject(SAMPLE))
        let reply = page.comments[1]
        @Expect(reply.parentId, 709973)
        @Expect(reply.user.name, "随便")
        // reactionsInfo 已合并进评论
        @Expect(page.comments[0].likes, 17)
        @Expect(page.comments[0].liked, true)
        @Expect(reply.likes, 2)
        @Expect(reply.liked, false)
        @Expect(page.reactions.size, 2)
    }

    @TestCase
    func testNextOffset(): Unit {
        let page = BookCommentsPage.fromRoot(parseJsonObject(SAMPLE))
        @Expect(page.nextOffset(0), 2)
        @Expect(page.nextOffset(100), 102)
        let empty = BookCommentsPage.fromRoot(parseJsonObject(
            "{\"success\":1,\"comments\":[],\"commentsDisabled\":true}"))
        @Expect(empty.comments.size, 0)
        @Expect(empty.commentsDisabled, true)
        @Expect(empty.nextOffset(0), 0)
    }
}
