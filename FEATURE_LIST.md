# Portal IM — 功能清单（旧系统参照 → 新系统实现对照）

> 从旧 FastAPI + 自研协议代码提取，作为新 Matrix 版本的功能验收基准。
> 标记 ✅ 代表新系统已有原生支持；🔨 代表需要定制实现；⏳ 代表延后阶段。

---

## 1. 账号与身份

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 1.1 | Portal 初始化（首次建账号） | `POST /api/auth/init` | Matrix `/_matrix/client/v3/register` | ✅ |
| 1.2 | 登录（密码 → JWT） | `POST /api/auth/login` | Matrix `/_matrix/client/v3/login` | ✅ |
| 1.3 | 获取当前用户信息 | `GET /api/auth/me` | `/_matrix/client/v3/profile/{userId}` | ✅ |
| 1.4 | 修改密码 | `POST /api/auth/change-password` | `/_matrix/client/v3/account/password` | ✅ |
| 1.5 | 域名即身份（Portal URL = 用户标识） | `portal_url` 字段 | MXID `@owner:domain`，域名即身份 | ✅ |
| 1.6 | FCM 推送 Token 注册 | `POST /api/auth/fcm/register` | Matrix Push Rules + Push Gateway | ⏳ Week 2 |

---

## 2. 联系人

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 2.1 | 联系人列表 | `GET /api/contacts` | `client.directChats` map | ✅ |
| 2.2 | 通过域名加好友（发出申请） | `POST /api/contact-requests/apply` → 跨 Portal HTTP | `client.startDirectChat("@owner:domain")` 发 invite | ✅ |
| 2.3 | 收到好友申请列表 | `GET /api/contact-requests/received` | Matrix room invite list | ✅ |
| 2.4 | 同意好友申请 | `POST /api/contact-requests/{id}/approve` | `client.joinRoom(roomId)` | ✅ |
| 2.5 | 拒绝好友申请 | `POST /api/contact-requests/{id}/reject` | `client.leaveRoom(roomId)` | ✅ |
| 2.6 | 已发出申请列表 | `GET /api/contact-requests/sent` | 监听 invite state 在自己发出的 room | ✅ |
| 2.7 | 联系人备注名 | `PUT /api/contacts/{id}` | Matrix room name（DM room 本地 alias） | 🔨 |
| 2.8 | 删除联系人 | `DELETE /api/contacts/{id}` | leave + forget room | ✅ |
| 2.9 | 联系人在线状态 | WebSocket presence | `m.presence` event | ✅ |
| 2.10 | 域名解析（`/.well-known/portal/owner.json`） | 无（旧系统直接存 portal_url） | `GET /.well-known/portal/owner.json` 查 MXID | 🔨 nginx 静态 |

---

## 3. 1v1 消息

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 3.1 | 发送文字消息 | `POST /api/messages` → 跨 Portal HTTP 转发 | `room.sendTextEvent(body)` | ✅ |
| 3.2 | 接收消息（实时） | WebSocket `type=message` | Matrix /sync timeline event | ✅ |
| 3.3 | 历史消息加载 | `GET /api/messages/contact/{id}` | `client.getRoomTimeline(roomId, limit)` | ✅ |
| 3.4 | 未读消息数 | `GET /api/messages/unread` | `room.notificationCount` | ✅ |
| 3.5 | 标记已读 | `POST /api/messages/{id}/read` | `room.setReadMarker(eventId)` | ✅ |
| 3.6 | 最近会话列表（消息列表首屏） | `GET /api/messages/latest` | `client.rooms` sorted by lastEvent | ✅ |
| 3.7 | 消息搜索 | `GET /api/messages/search` | `client.searchMessagesInRoom()` | ✅ |
| 3.8 | 消息撤回 | `POST /api/messages/{id}/recall` + webhook | `room.redactEvent(eventId)` | ✅ |
| 3.9 | 回复消息（带引用） | `reply_to_message_id` 字段 | `m.in_reply_to` relation | ✅ |
| 3.10 | 转发消息 | App 内转发逻辑 | 读 event 内容重发 | 🔨 App 层 |
| 3.11 | 删除本地消息记录 | `DELETE /api/messages/{id}` | 本地缓存清除（Matrix event 不物理删，仅 redact） | 🔨 |
| 3.12 | 输入中状态 | WebSocket `type=typing` | `room.setTyping(true/false)` | ✅ |

---

## 4. 群组

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 4.1 | 创建群组 | `POST /api/groups` | `client.createRoom(preset: publicChat / private)` | ✅ |
| 4.2 | 群列表 | `GET /api/groups` | `client.rooms.where((r) => !r.isDirectChat)` | ✅ |
| 4.3 | 群详情 | `GET /api/groups/{id}` | `client.getRoomById(roomId)` | ✅ |
| 4.4 | 邀请成员（跨 Portal） | `POST /api/groups/invite` → 跨 Portal webhook | `room.invite("@owner:domain")` | ✅ Federation 原生支持 |
| 4.5 | 收到群邀请 | `GET /api/groups/invites` | Matrix room invite list（过滤非 DM room） | ✅ |
| 4.6 | 接受群邀请 | `POST /api/groups/invites/{id}/accept` | `client.joinRoom(roomId)` | ✅ |
| 4.7 | 拒绝群邀请 | `POST /api/groups/invites/{id}/reject` | `client.leaveRoom(roomId)` | ✅ |
| 4.8 | 发送群消息 | `POST /api/messages/group` → P2P 转发每个成员 | `room.sendTextEvent(body)` | ✅ 简单多了 |
| 4.9 | 群历史消息 | `GET /api/messages/group/{id}` | `room.timeline` | ✅ |
| 4.10 | 踢出成员（群主） | `DELETE /api/groups/{id}/members/{contactId}` | `room.kick(userId)` | ✅ |
| 4.11 | 退群 | `POST /api/groups/by-uuid/{uuid}/leave` | `client.leaveRoom(roomId)` | ✅ |
| 4.12 | 解散群（群主） | `POST /api/groups/{id}/dissolve` | `room.kick` all + leave | 🔨 |
| 4.13 | 修改群名/头像 | `PUT /api/groups/{id}` | `room.setName()` / `room.setAvatar()` | ✅ |
| 4.14 | 群公告 | `PUT /api/groups/{id}/announcement` | `room.setTopic()` | ✅ |
| 4.15 | 群成员列表 | `GET /api/groups/{id}/members` | `room.getParticipants()` | ✅ |

---

## 5. 文件与媒体

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 5.1 | 图片发送 | `POST /api/files/upload` → `m.image` 自研 | `room.sendImageEvent(bytes)` → `mxc://` | ✅ |
| 5.2 | 文件发送（任意类型） | 同上 | `room.sendFileEvent(bytes, fileName)` | ✅ |
| 5.3 | 视频发送 | 同上 | `room.sendVideoEvent(bytes)` | ✅ |
| 5.4 | 语音消息 | 同上（audio） | `room.sendAudioEvent(bytes)` | ✅ |
| 5.5 | 图片预览/缩略图 | Portal 自生成 | continuwuity 自动生成 thumbnail | ✅ |
| 5.6 | 文件下载 | `GET /api/files/download/{path}` | `client.downloadMxcUri(mxcUri)` | ✅ |
| 5.7 | 文件类型图标 | `file_icon_helper.dart` | 同逻辑保留（纯 UI，无需改） | ✅ |

---

## 6. 实时通话（VoIP）

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 6.1 | 1v1 视频通话发起 | WebSocket `call_invite` + 自研 ICE | `client.voip.inviteToCall(roomId, CallType.kVideo)` | ✅ |
| 6.2 | 接听来电 | `call_accept` | `callSession.answer()` | ✅ |
| 6.3 | 拒绝/挂断 | `call_reject` / `call_hangup` | `callSession.reject()` / `.hangup()` | ✅ |
| 6.4 | ICE candidate 交换 | `call_ice` WebSocket | `m.call.candidates` Matrix event | ✅ |
| 6.5 | TURN 服务器 | coturn A + B（已部署） | 保留 coturn，continuwuity TURN config 注入 | ✅ |
| 6.6 | 1v1 语音通话 | 同上 | `CallType.kVoice` | ✅ |
| 6.7 | 群组通话 | 未实现 | MatrixRTC（后续阶段） | ⏳ |

---

## 7. AI Agent 接入

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 7.1 | Agent 接收消息 | WebSocket `/ws/agent` + OpenClaw 协议 | MCP Server → Matrix API | 🔨 Week 2 |
| 7.2 | Agent 发送消息到用户 | `agent_response` WebSocket event | MCP `send_message` tool → Matrix event | 🔨 |
| 7.3 | @mention 触发 Agent | App 内特殊 UI | Matrix Bot（AS）监听 `@agent` mention | 🔨 |
| 7.4 | 主流 Agent 接入（Claude/Hermes/Cursor） | 只支持 OpenClaw | 标准 MCP，任意 MCP 兼容框架开箱即用 | ✅ 架构升级 |

---

## 8. 通知与推送

| # | 功能 | 旧实现 | 新实现 | 状态 |
|---|------|--------|--------|------|
| 8.1 | App 内实时推送（前台） | WebSocket 长连接 | Matrix /sync long-poll | ✅ |
| 8.2 | App 离线推送（FCM） | 未完成 | Matrix Push Gateway + FCM | ⏳ Week 2 |
| 8.3 | 消息角标数 | 自实现 | `room.notificationCount` | ✅ |

---

## 9. 用户界面（App Screens）

来自旧 App 的 screens，全部在新 Flutter App 中重写：

| Screen | 对应功能域 |
|--------|-----------|
| `home_screen` | 会话列表（chats tab） |
| `chat_detail_screen` | 1v1 聊天窗口 |
| `group_chat_screen` | 群组聊天窗口 |
| `contacts_screen` | 联系人列表 |
| `contacts_book_screen` | 通讯录视图 |
| `add_contact_screen` | 加好友（输入域名） |
| `contact_detail_screen` | 联系人资料 |
| `requests_screen` | 待处理的好友/群邀请 |
| `groups_screen` | 群组列表 |
| `group_members_screen` | 群成员列表 |
| `group_profile_screen` | 群资料/公告 |
| `invite_member_screen` | 邀请进群 |
| `call_screen` | 通话界面（video + 控制按钮） |
| `agent_chat_screen` | AI Agent 对话（Week 2） |
| `search_screen` | 全局搜索 |
| `in_chat_search_screen` | 会话内搜索 |
| `forward_screen` | 转发消息 |
| `me_screen` | 个人资料 |
| `settings_screen` | 设置 |
| `login_screen` | 登录（域名 + 密码） |
| `init_screen` | 首次初始化（创建账号） |
| `explore_screen` | 发现（后续扩展） |

---

## 10. 旧系统特有痛点（新系统不需要解决，已消除）

- 跨 Portal HTTP 转发竞态（信令乱序）→ Matrix federation 天然有序
- ICE candidate pendingIce 竞态 Bug → matrix_dart_sdk CallSession 封装
- 自研 WebSocket 协议版本碎片化 → Matrix 标准 spec
- 群消息 P2P 广播（每条消息发给每个成员）→ Matrix room 服务端广播
- SQLite 迁移脚本维护 → RocksDB + continuwuity 自管理
- 两套代码（App + Web）→ Flutter 一套代码三端

---

**最后更新**: 2026-05-08  
**版本**: v1.0（基于旧系统代码提取，新系统开发参照）
