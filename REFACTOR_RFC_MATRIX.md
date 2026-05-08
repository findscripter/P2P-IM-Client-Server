# Matrix 联邦化重建实施 RFC

> **决策**:用 Matrix 协议全量重建 P2P-IM,每个 Portal = 一台轻量 Matrix homeserver。
>
> **作者**:明杰
> **日期**:2026-05-08
> **状态**:决策已定,Day 1 启动 PoC/MVP;第一周不做生产切换

---

## 0. 摘要

| 维度             | 现状                          | 重构后                                                                                                |
| ---------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------- |
| 后端             | FastAPI + 自研协议 + SQLite   | **[continuwuity](https://github.com/continuwuity/continuwuity)**(Rust, 单二进制 + RocksDB;Conduit 社区分叉) |
| 信令保序         | HTTP 跨 Portal 直发,race 频发 | Matrix[federation v1.16](https://spec.matrix.org/v1.16/server-server-api/)                               |
| 1v1 RTC + 群通话 | 自研踩 ICE/DTLS/TURN 坑       | [Matrix VoIP 1.16](https://spec.matrix.org/v1.16/client-server-api/#voice-over-ip) + MatrixRTC(SDK 封装) |
| E2EE             | 没有                          | [Vodozemac](https://github.com/matrix-org/vodozemac)(MVP 支持,默认开启放到验收后决定)                    |
| App              | Provider + Dio + 自研 ws      | **全新 Flutter App** + [matrix_dart_sdk](https://pub.dev/packages/matrix) + Riverpod + freezed + go_router |
| 客户端形态       | Android APK + 裸 Web 两套代码 | **Flutter 一套代码 → Android / iOS / Web 三端**                                                |
| Web              | 裸 HTML/JS                    | Flutter Web build(同 codebase 副产物,主用于开发期 debug)                                              |
| TURN             | coturn(已部署)                | **保留不动**(Matrix VoIP 仍依赖 TURN 穿 NAT)                                                    |
| 测试             | 几乎为零                      | docker-compose + pytest + 真机回归(详见第 6 节)                                                       |

**项目定位**:这是一次 **rebuild / replatform**,不是兼容式 refactor。旧系统只作为功能参照和数据来源,新系统不保留旧 FastAPI API、自研 WebSocket 协议、SQLite 表结构、App Provider 状态机。

**时间预算**:3 人 + Claude Code 第一周冲出可演示 MVP/技术 PoC(详见第 7 节)。生产替换另设灰度迁移阶段,以验收门槛决定切换时间。

**去中心化等级**:Level 2 联邦化(每用户一台 server,server 间平等互通),与旧设计同档。Matrix 不引入"中央服务器"——`matrix.org` 只是基金会运营的一台公共 homeserver,本项目两台 VPS 跑 continuwuity 互相联邦,不依赖任何外部 server。

### 0.1 重建边界

本 RFC 的目标是 **功能体验等价**,不是代码/API/数据结构兼容:

- 不复用旧后端业务代码;旧 Portal 服务在迁移完成前并行运行。
- 不复用旧 App 的 Provider/Dio/WebSocket 业务层;可以参考 UI 和交互,但业务模型以 Matrix room/event/client sync 为核心重写。
- 旧数据库不作为新系统在线依赖;历史数据迁移是独立阶段,第一周只做脚本干跑和样本验证。
- 第一周验收标准是"能证明 Matrix 路线跑通",不是"替换生产"。
- 生产切换必须经过真机通话、E2EE、push、历史迁移、回滚预案验收。

---

## 1. 架构图

```
┌────────────────────────┐              ┌────────────────────────┐
│ 施歌 (Android/iOS/Web) │              │ Alice (Android/iOS/Web)│
│ Flutter + matrix sdk   │              │ Flutter + matrix sdk   │
└────────────┬───────────┘              └────────────┬───────────┘
             │ Client-Server API v1.16               │
             ↓                                       ↓
┌──────────────────────┐ ←── federation ──→ ┌──────────────────────┐
│ continuwuity Server B│   (Server-Server   │ continuwuity Server A│
│   liyananp2p.com     │    API v1.16)      │  185-115-...nip.io   │
└──────────┬───────────┘                    └──────────┬───────────┘
         │ ICE                                       │ ICE
         ↓                                           ↓
   ┌──────────┐                              ┌──────────┐
   │ coturn B │                              │ coturn A │
   └──────────┘                              └──────────┘
```

**概念映射**:

- "Portal" → continuwuity homeserver
- 用户 ID `id=1` → MXID `@owner:domain`(对外只暴露域名)
- 联系人 → DM Room
- 群组 → Public/Invite Room
- AI Agent → [Application Service](https://spec.matrix.org/v1.16/application-service-api/)

---

## 2. 选型理由

### 2.1 后端 continuwuity(2026-05 Matrix server 选型现状)

| 候选 | 语言 | 内存 | 状态(2026-05) | 适合本项目 |
|---|---|---|---|---|
| **continuwuity** | Rust | 50-150 MB | ✅ 活跃,每 1-2 周发版,v0.5.8;社区从 conduwuit 接手维护 | ✅ **首选** |
| tuwunel | Rust | 50-150 MB | ⚠️ 商业资助 + 全职开发,但**被 Matrix Foundation 封禁**,社区争议大 | ⚠️ 风险 |
| Conduit(原版) | Rust | 50-150 MB | ⚠️ Famedly 主力撤离,Ginger 接手维护节奏慢,功能落后于 fork | ⚠️ 备选 |
| conduwuit | Rust | — | ❌ **2026-01-19 已归档**(原作者封了仓库) | ❌ 不要用 |
| Dendrite | Go | 200-500 MB | ⚠️ Element 已转维护模式,只做安全修复 | ⚠️ fallback |
| Synapse | Python | 1-3 GB | ✅ 活跃但太重,需 Postgres | ❌ 一人 VPS 跑不动 |

**为什么 continuwuity**:
- 继承 conduwuit 全部功能(邮箱验证、注册令牌、反 spam 等),比 Conduit 原版功能多
- 社区活跃度最高,主分支常绿
- 单二进制 + 内置 RocksDB,腾讯云 1.9 GB 轻量也能跑
- 协议层与 Conduit 数据兼容,真踩雷可平滑切回 Conduit / Dendrite
- 不选 tuwunel:被 Matrix Foundation 封禁是个红旗,可能未来 federation 兼容性受影响

**已知风险**:志愿者驱动,关键贡献者退出有断档风险——但 2026-05 时间点社区健康。

### 2.2 客户端 matrix_dart_sdk

FluffyChat 在用,生产验证过。自带 sync token、e2ee、media、CallSession、room state——你直接调 `client.voip.inviteToCall()` 一行发起视频通话,不写一行 PeerConnection 代码,今天踩的 Bug 1/3/4 这些坑接触不到。

### 2.3 功能映射(打消"业务怎么办"的疑虑)

| 旧功能                | Matrix 实现                                                      |
| --------------------- | ---------------------------------------------------------------- |
| 用户注册              | Matrix 注册接口                                                  |
| Portal URL = 用户身份 | MXID 的 domain 部分                                              |
| 联系人申请            | invite + accept                                                  |
| 1v1 聊天 / 群组       | DM Room / Room                                                   |
| 已读回执 / 在线状态   | `m.receipt` / `m.presence`                                   |
| 文件、图片            | mxc:// +`m.image`/`m.file`                                   |
| 1v1 通话 / 群通话     | `m.call.*` / MatrixRTC                                         |
| 消息撤回 / 回复       | `m.room.redaction` / `m.in_reply_to`                         |
| 推送通知              | [Push Gateway API](https://spec.matrix.org/v1.16/push-gateway-api/) |
| **AI Agent**    | **MCP Server + Matrix Bot**(见第 9 节;App 被动接收,无需改动) |

---

## 3. 部署/运维变化

### 服务清单

| 服务                                                 | 现状        | 重构后                      |
| ---------------------------------------------------- | ----------- | --------------------------- |
| portal.service / portal2.service / agent-p2p.service | 跑着        | **第一周保留并行;生产切换窗口再停服** |
| continuwuity.service                                 | —          | **新增**              |
| nginx                                                | 反代 portal | 反代 continuwuity `/_matrix/*` |
| coturn.service                                       | 已部署      | **保留不动**          |
| postgres / redis                                     | 无          | 仍不需要                    |

### continuwuity systemd unit

```ini
[Unit]
Description=continuwuity Matrix Server
After=network.target

[Service]
User=continuwuity
ExecStart=/usr/local/bin/continuwuity
Environment="CONDUWUIT_CONFIG=/etc/continuwuity/continuwuity.toml"
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

> 二进制名沿用 conduwuit 习惯也叫 `conduwuit`,可改名为 `continuwuity`;环境变量名当前仍是 `CONDUWUIT_CONFIG`(继承自 conduwuit),按实际 release 文档为准。

### nginx 配置(关键 location,以 liyananp2p.com 为例)

```nginx
location /_matrix/ {
    proxy_pass http://127.0.0.1:6167;
    proxy_set_header Host $host;
    proxy_buffering off;
    client_max_body_size 100M;
}

location = /.well-known/matrix/server {
    return 200 '{"m.server": "liyananp2p.com:443"}';
    default_type application/json;
}

location = /.well-known/matrix/client {
    return 200 '{"m.homeserver": {"base_url": "https://liyananp2p.com"}}';
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
}

location = /.well-known/portal/owner.json {
    return 200 '{"matrix_user_id":"@owner:liyananp2p.com","display_name":"施歌"}';
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
}
```

**域名复用**:不新建 `matrix-*` 子域,`185-115-207-219.nip.io` 和 `liyananp2p.com` 直接配 `/_matrix/*` 反代,federation 走 443。

---

## 4. 数据迁移

### 4.1 迁移原则

数据迁移不是第一周上线前置项。第一周只做 **样本迁移验证**:

- 验证旧 SQLite 能读出用户、联系人、群、消息、文件。
- 验证联系人/群能映射到 Matrix room。
- 验证少量历史消息能通过 Application Service 写入并保留时间。
- 验证文件能重新上传为 `mxc://` 并在 App 显示。

生产迁移放在 MVP 稳定后单独排期,至少包含备份、干跑、校验报告、失败回滚、旧系统只读窗口。

### 4.2 用户映射 — 域名即身份

每个 Portal 一个 owner,所以"域名 = 用户":

| 旧                                             | 新(MXID 内部)                     | 对外                    |
| ---------------------------------------------- | --------------------------------- | ----------------------- |
| `https://liyananp2p.com` / `施歌`          | `@owner:liyananp2p.com`         | 域名 `liyananp2p.com` |
| `https://185-115-207-219.nip.io` / `Alice` | `@owner:185-115-207-219.nip.io` | 域名                    |

MXID 的 localpart **统一用 `owner`**(任何 Portal 都不需要为 username 取名),`display_name` 保留中文,**用户永远看不到 `@owner:` 前缀**。

### 4.3 加好友 UX — 域名即邀请符

```
┌─── 添加联系人 ───┐
│ 输入对方的域名:    │
│ ┌───────────────┐│
│ │liyananp2p.com ││
│ └───────────────┘│
│       [发送邀请] │
└──────────────────┘
```

App 内部流程:

1. 用户输入 `liyananp2p.com`(自动补 https + trim)
2. App 请求 `GET https://liyananp2p.com/.well-known/portal/owner.json`
3. 拿到 `{"matrix_user_id": "@owner:liyananp2p.com", ...}`
4. `client.startDirectChat("@owner:liyananp2p.com")`
5. fallback:若 well-known 不存在,直接尝试 `@owner:<domain>`,失败提示"对方域名无法识别"

### 4.4 其他实体映射

| 旧                 | 新                              | 备注                                                           |
| ------------------ | ------------------------------- | -------------------------------------------------------------- |
| `contacts` 表    | DM Room (m.direct)              | 双向 invite                                                    |
| `groups` 表      | Matrix Room(初期 invite-only)   | group_id ↔ room_id 映射保留在脚本里                           |
| 历史 `messages`  | event with `origin_server_ts` | **必须用 Application Service**(普通 client 不能伪造时间) |
| `/uploads/` 文件 | mxc://                          | 重新上传到 continuwuity `/_matrix/media/`                         |

迁移脚本伪代码(第二阶段完善):

```python
for old_msg in old_db.messages:
    if old_msg.file_url:
        new_mxc = upload_to_continuwuity(read_file(old_msg.file_url))
        new_content = replace_url(old_msg.content, old_msg.file_url, new_mxc)
    else:
        new_content = old_msg.content
    as_send(room_id, sender_mxid, new_content, origin_ts=old_msg.created_at)
```

### 4.5 迁移验收门槛

- 样本联系人映射准确率 100%。
- 样本群成员映射准确率 100%。
- 样本消息数量、发送方、时间、消息类型校验通过。
- 图片/文件 `mxc://` 可打开,失败文件有清单。
- 迁移脚本可重复干跑,不会污染生产 homeserver。
- 旧系统 DB 和上传目录已有离线备份。

---

## 5. 风险清单

| 风险                                                              | 影响               | 缓解                                                       |
| ----------------------------------------------------------------- | ------------------ | ---------------------------------------------------------- |
| continuwuity 仍在 0.x(v0.5.x),社区志愿者维护 | 关键 maintainer 退出可能影响活跃度 | 数据格式与 Conduit 兼容,真断档可平滑迁 Conduit / Dendrite / tuwunel |
| Federation 调试比 HTTP 复杂                                       | 学习成本 1-2 周    | federation tester + continuwuity 详细日志                       |
| 推送通知需要重写                                                  | App 关闭收不到消息 | Matrix push gateway + FCM(Week 2+)                         |
| 用户 ID 改变                                                      | 老用户要重新登录   | 引导 + 旧 portal_url 输入自动跳新                          |
| Vodozemac e2ee 在 iOS 较新                                        | 加密失败可能       | FluffyChat 已生产用,问题可控                               |
| **Flutter Web + flutter_webrtc 通话稳定性 = known unknown** | Web 端打不通通话   | Day 5 探针验证;失败则 Web 通话作 fallback,APK 不受影响     |
| Flutter Web 首屏 3-8s 白屏                                        | 首次打开等待感强   | splash screen + deferred-loading;IM 应用首屏速度非主要 KPI |

---

## 6. 测试矩阵

| 层级                    | 工具                                 | 跑在哪         | 验证什么                            | 频率        |
| ----------------------- | ------------------------------------ | -------------- | ----------------------------------- | ----------- |
| 单元                    | flutter_test + dart test             | 本机 / CI      | 业务逻辑、状态机                    | 每次 commit |
| 集成(mock)              | Riverpod override + FakeMatrixClient | CI             | App 内部跨层逻辑                    | 每次 commit |
| Federation 集成         | pytest + docker-compose              | CI             | server-server 协议                  | 每次 PR     |
| **App↔App 真机** | maestro / patrol + 物理设备          | 手动 / nightly | **真实 NAT 通话**、push、E2EE | 每个里程碑  |
| App↔Flutter Web        | 真机 + 浏览器                        | 手动           | Flutter Web 平台兼容性              | Day 5+      |
| WebRTC 极端网络         | docker network + iptables MASQUERADE | 半手动         | TURN 兜底、DTLS 重传                | 回归时      |

**关键认知**(本次 App→Web 卡 DTLS 调试得出):

- **Web 端 ≠ App 端**:Chrome 与 flutter_webrtc 的 ICE 行为/网络栈不同
- **WebRTC 通话在 Android emulator 不能可靠模拟真机**,必须真机回归
- **Flutter Web 上 flutter_webrtc 也不能平替原生 App**:同一套 Dart 代码,但 runtime 是浏览器原生 WebRTC

---

## 7. 三人 + Claude Code 第一周 MVP/PoC 执行表

> **节奏**:7 天。前 5 天三人并行,Day 6 真机回归 + 修 bug,Day 7 做 MVP 决策评审。
> **目标**:证明 Matrix 路线能承接核心体验,产出可演示新 App。第一周不下线旧系统、不迁生产数据、不强制用户更新。
> **角色分工**(可轮换):
>
> - **A:Server / 运维** — continuwuity、nginx、TURN、样本迁移、监控
> - **B:App 主线** — Flutter 框架、登录、聊天、通话
> - **C:App 业务** — 联系人、群组、文件、E2EE、域名加好友

### Day 1 — 双 server 联通 + Flutter 起步

| 角色 | 任务                                                                                                       |
| ---- | ---------------------------------------------------------------------------------------------------------- |
| A    | continuwuity 部署到 Server A & B(并行 portal.service);nginx 加 `/_matrix/` location;配 well-known             |
| B    | `flutter create portal_app_v2`;装齐 RFC 列出依赖;Riverpod + go_router + freezed 跑通                     |
| C    | 学 matrix_dart_sdk + FluffyChat `lib/pages/chat/`;写 `docker-compose.dev.yml`(本地两 continuwuity + coturn) |

**Day 1 验收**:Element Web 公网版能连本项目两台 server 注册账号、互发消息;federationtester 全绿;Flutter 项目 dart analyze 干净。

### Day 2 — 登录 + 联系人骨架

| 角色 | 任务                                                                                                                                      |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| A    | 注册 `@owner:185-115-207-219.nip.io` 和 `@owner:liyananp2p.com`;配 `/.well-known/portal/owner.json`;GitHub Actions(APK + Web build) |
| B    | LoginScreen(域名 + 密码);MatrixClient Riverpod provider;token 存 flutter_secure_storage                                                   |
| C    | 联系人列表(读 `client.directChats`);添加联系人(域名 → fetch well-known → `startDirectChat`)                                         |

**Day 2 验收**:APK 装手机,A 上输 `liyananp2p.com` 加好友,B 上能收到 invite。

### Day 3 — 聊天 + 群组 + Web 部署

| 角色 | 任务                                                                                      |
| ---- | ----------------------------------------------------------------------------------------- |
| A    | TURN credentials 注入 continuwuity;Flutter Web build CI 部署到 `185-115-207-219.nip.io/app/` |
| B    | ChatScreen(消息列表 + 发送 + 已读);消息状态 UI                                            |
| C    | 群组创建/邀请/退群;群消息                                                                 |

**Day 3 验收**:跨 server 文字消息(1v1 + 群)全通;Web build 浏览器能登录看消息。

### Day 4 — 通话 + 文件

| 角色 | 任务                                                                                                 |
| ---- | ---------------------------------------------------------------------------------------------------- |
| A    | nginx 调优(WS Upgrade、超时、X-Forwarded-For);监控基础(continuwuity `/metrics` + 简单 Grafana)          |
| B    | CallScreen(remote/local video + 控制按钮);来电界面 + 铃声;`client.voip.inviteToCall/answer/hangup` |
| C    | 文件/图片上传(mxc:// + sendImageEvent);缩略图 + cached_network_image                                 |

**Day 4 验收**:跨 server 1v1 视频通话能接通(可能不稳,Day 6 调);文件传输 OK。

### Day 5 — E2EE 探针 + 样本迁移 + Web 通话探针

| 角色 | 任务                                                                                       |
| ---- | ------------------------------------------------------------------------------------------ |
| A    | 写 `migrate_to_matrix.py` 样本版(旧 SQLite → Matrix);验证 AS token、时间戳、文件上传 |
| B    | E2EE 探针;Key verification / Recovery Key 流程调研并做最小 UI                              |
| C    | **Flutter Web 通话探针**:Web build 跟真机 App 1v1 视频对打,记录是否通;推送通知 stub  |

**Day 5 验收**:E2EE 能在样本房间跑通;迁移脚本能干跑 10-50 条样本消息;Flutter Web 通话有结论(通/不通)。

### Day 6 — 真机回归 + 修 bug

> **全员**:每人手机 + 至少一个 Web 浏览器,完整跑业务流程。

回归用例:

1. 登录(填域名 + 密码)
2. 加好友(输域名 → invite → accept)
3. 1v1 文字消息(在线 + 离线后上线)
4. 群组(创建 + 邀请 + 发言)
5. 文件传输(图片 + 大文件)
6. 1v1 视频通话(同网 + 跨 NAT 4G/WiFi)
7. E2EE(key verification + 跨设备登录)

**Day 6 验收**:7 个用例 ≥ 5 个通过;失败项必须能判断是 SDK/服务端/网络/产品未完成中的哪一类,每条有 owner。

### Day 7 — MVP 决策评审

| 时间 | 任务                                       |
| ---- | ------------------------------------------ |
| 上午 | 整理 PoC 验收结果:server federation、App、通话、E2EE、样本迁移 |
| 下午 | 补关键 bug;冻结第一版 MVP scope            |
| 傍晚 | 架构评审:继续 continuwuity / 切 Conduit / 切 Dendrite / 调整 VoIP 路线 |
| 晚   | 输出 Week 2 任务单和生产切换前置清单       |

**Day 7 验收**:得到一个可演示 MVP,旧系统继续服务;明确是否进入第二阶段产品化开发。

### Claude Code 协作建议

- 每人独立 git worktree;PR 到共享 dev 分支,每天合一次 main
- 大段功能(如 ChatScreen)直接让 Claude 写整文件,人 review
- 跨文件 refactor 用 `/agent` + plan mode
- 真机调试(尤其通话)Claude 帮不上,靠人 + chrome://webrtc-internals
- **Claude 写不动的**:真机 NAT 调试、iOS 签名、产品 UI 决策、推送 sandbox

### 第二阶段:产品化开发(预计 2-3 周)

- 推送通知(FCM + APNs / Matrix Push Gateway)。
- AI Agent(Application Service)。
- E2EE 默认开启策略、密钥恢复、跨设备登录体验。
- 通话稳定性持续调优,必要时 Android/iOS 优先,Web 通话降级。
- 群组、文件、搜索、撤回、回复、已读、通知免打扰等体验补齐。
- 监控、日志、备份、升级脚本完善。

### 第三阶段:灰度迁移与生产切换(预计 1 周+)

| 阶段 | 任务 |
| ---- | ---- |
| T-3 天 | 旧系统 DB + uploads 备份;样本迁移报告通过 |
| T-2 天 | 在测试 homeserver 全量干跑;校验消息/文件/群/联系人数量 |
| T-1 天 | 新 App 灰度给内部用户;旧系统保持可回退 |
| T 日 | 短暂停写旧系统;执行正式迁移;发布新 App |
| T+1 天 | 监控、用户反馈、修复迁移漏项;旧系统保留只读回滚窗口 |

**生产切换门槛**:真机通话稳定,E2EE 策略明确,push 可用,历史迁移报告通过,旧系统回滚预案可执行。

---

## 8. 二开指南(业务扩展 Cookbook)

> 在本架构上做二次开发,**99% 的需求都能在不碰 Matrix 协议、不改 continuwuity 源码的前提下实现**。
>
> 核心判断:**先问"能不能用自定义 event / SDK API / Application Service 实现?"——大概率能。**

### 8.1 三层二开边界

| 层级                             | 二开方便度  | 怎么做                                                              |
| -------------------------------- | ----------- | ------------------------------------------------------------------- |
| **业务层**(差异化功能)     | ✅ 非常方便 | 改 Flutter UI / 自定义 event / Application Service / 接 LLM         |
| **客户端层**(改 App 行为)  | ✅ 方便     | matrix_dart_sdk 是开源 Dart 包,fork 一份按需改                      |
| **协议层**(改 Matrix spec) | ❌ 不要碰   | 改了失去联邦兼容,你的客户端无法和 Element 等互通                    |
| **服务端源码**(改 continuwuity) | ⚠️ 不推荐 | Rust 学习曲线 + 跟不上 upstream 安全更新;90% 改动用 AS 在外层做就行 |

### 8.2 四个常见二开场景

#### 场景 1:加新业务规则(零协议改动)

```dart
// 例:"已读不回 24 小时提醒"——纯客户端逻辑
final unreadOver24h = room.timeline
  .where((e) => e.senderId != myMxid)
  .where((e) => !e.isRead)
  .where((e) => DateTime.now().difference(e.originServerTs) > Duration(hours: 24));

if (unreadOver24h.isNotEmpty) showReminder();
```

#### 场景 2:加自定义消息类型(用自定义 event,联邦兼容)

```dart
// 发送方
await room.sendEvent('com.yourproject.voice_msg', {
  'mxc_uri': mxcUri,
  'duration_ms': 3500,
  'waveform': [0.1, 0.3, 0.5, ...],
});

// 接收方
room.timeline
  .where((e) => e.type == 'com.yourproject.voice_msg')
  .forEach((e) => renderVoiceBubble(e));
```

**约定**:`com.yourproject.*` 前缀的 event 其他 Matrix 客户端会忽略(看不到也不报错),你的 App 完整识别。零破坏性。

#### 场景 3:AI Agent 接入(Application Service)

```python
# Application Service 注册到 continuwuity(registration.yaml)
id: agent-portal
url: http://localhost:9000
as_token: <secret>
hs_token: <secret>
namespaces:
  users:
    - exclusive: true
      regex: "@bot_.*:liyananp2p\\.com"

# AS 服务端代码(matrix-nio)
async def on_message(room, event):
    if '@agent' in event.body:
        response = await call_llm(event.body)
        await client.room_send(room.room_id, 'm.room.message',
            {'msgtype': 'm.text', 'body': response})
```

代码量 ~200 行 Python,**任意 LLM 都能接入**(OpenAI / Claude / 自部署模型)。Bot 用户在 federation 下行为和真人一样。

#### 场景 4:UI 完全重做

matrix_dart_sdk 只给你协议接口——**长什么样、交互怎么设计 100% 自由**。FluffyChat 和 Element 用同一个 SDK,UI 风格完全不一样。

### 8.3 不能扩展的边界(协议级硬限制)

如果你的需求落在下面任何一项,**说明 Matrix 不适合,要重谈架构**:

| 想做的事                    | 为什么 Matrix 做不到                                                         |
| --------------------------- | ---------------------------------------------------------------------------- |
| 消息真删除(物理删除)        | 协议设计只能 redact(标记删除);GDPR 场景要单独处理                            |
| 百万人级大群                | State resolution 在大房间复杂度爆炸,选错协议了——这种规模该用 Telegram 路线 |
| 完全无 server 通信          | Matrix 是 Level 2 联邦,不是 Level 3 P2P;真要无 server 走 Briar/libp2p        |
| 强制中央化(关闭 federation) | 那为什么用 Matrix?用专有协议反而更省事                                       |

### 8.4 二开决策树

```
有新需求 → 能用 Flutter 客户端逻辑做吗?
            ├ 能 → 改 App 代码,1 小时
            └ 不能 → 能用自定义 event 吗?
                      ├ 能 → 加 event type,半天
                      └ 不能 → 需要服务端逻辑吗?
                                ├ 是 → 写 Application Service,1-3 天
                                └ 否 → 真的需要改 continuwuity 吗?
                                       ├ 是 → 重新审视设计(99% 没必要)
                                       └ 否 → 落在 8.3 协议硬限制了,重谈架构
```

### 8.5 跟随 Matrix 生态的福利

二开方便不只是"自己能改",还包括"白嫖生态":

- 现成 [bridge](https://matrix.org/ecosystem/bridges/) 几十个:Discord/Slack/Telegram/QQ/IRC 互通,不用自己写
- 现成 client:Element / FluffyChat / Cinny 等都能连你的 server,用户多渠道选择
- 现成 bot 框架:[matrix-nio](https://matrix-nio.readthedocs.io/) / [mautrix](https://github.com/mautrix) 写 AI Agent 的脚手架
- Matrix Spec 演进时,SDK 跟随 → 你免费拿到新功能(Spaces、Threads、轻量推送等)

---

## 9. Agent 接入设计(MCP + Matrix Bot)

> **核心判断**:Agent 不直接操控 App——App 是**被动接收者**。Agent 通过 MCP 调 Matrix API,消息到了 continuwuity,App 的 sync 长连接自动把消息推到界面。
>
> 这意味着:**App 代码不需要为 Agent 做任何改动**,Agent 发的消息和人发的消息对 App 完全一样。

### 9.1 完整数据流

```
用户 → Agent (Hermes/Claude Desktop/Cursor/...)
           │
           │  MCP tool call (JSON-RPC over stdio/HTTP)
           │  例: send_message({ to: "施歌", body: "帮我订会议室" })
           ▼
      MCP Server (你写的,跑在服务器上)
           │
           │  Matrix REST API   PUT /_matrix/client/v3/rooms/{roomId}/send/m.room.message
           ▼
      continuwuity (Matrix homeserver)
           │  存储事件,推给目标 homeserver(federation)
           ▼
      Flutter App (via /sync long-poll)
           │  被动收到 m.room.message 事件
           ▼
      聊天界面自动更新,消息出现
```

**三段协议**:
- Agent ↔ MCP Server:MCP 协议(JSON-RPC,2024 Anthropic 标准)
- MCP Server ↔ continuwuity:Matrix Client-Server API v1.16(标准 HTTP REST)
- continuwuity ↔ App:Matrix /sync WebSocket(App 本来就有的长连接)

### 9.2 主流 Agent 兼容性

| Agent / 框架 | 协议支持 | 能接入本项目 MCP Server? | 备注 |
|---|---|---|---|
| **Hermes Agent** (Nous Research, 60k+ ⭐) | MCP-first + **原生 Matrix** | ✅ 双通道:MCP 工具 + 直接连 homeserver | Matrix 协议在 Hermes 是一等公民;可直接注册为 Matrix 用户 |
| **Claude Desktop** | MCP (stdio/HTTP) | ✅ 配 `mcpServers` 即可 | Anthropic 官方;本地配置指向你的 MCP Server |
| **Cursor / Windsurf** | MCP (HTTP) | ✅ | IDE 内 AI 直接能发消息/查聊天记录 |
| **OpenHands** | MCP | ✅ | 代码 Agent,可以通过 MCP 把任务进度发到 IM |
| **OpenClaw /ws/agent** | 自研 WebSocket | ⚠️ **需适配层** | 协议不兼容 MCP,需写 adapter 桥接(约 200 行);OpenClaw 每 2 天一更新,adapter 可能需同步维护 |
| **LangChain / LangGraph** | 自定义 tool | ✅ 实现 Matrix API tool | 把 MCP Server 的工具函数包装成 LangChain tool,约半天 |
| **AutoGen** | function calling | ✅ | 同上 |
| **Dify / Coze** | HTTP plugin | ✅ 把 MCP Server 包一层 REST | 低代码平台,写个 HTTP action 指向 MCP Server |

**关键结论**:MCP 是当前事实标准,几乎所有 2025+ Agent 框架都支持。自建 MCP Server 一次,所有 MCP 兼容 Agent 免配置即用。OpenClaw 需额外维护适配层,且随 OpenClaw 版本迭代有维护负担。

### 9.3 MCP Server 设计

MCP Server 是一个独立小服务(~300 行 Python),对外暴露 Matrix 操作能力。

#### 工具列表

```python
# mcp_server.py —— 用 FastMCP 框架(Anthropic 官方)

@mcp.tool()
async def send_message(contact_domain: str, body: str) -> str:
    """向联系人发一条文字消息。contact_domain 例如 liyananp2p.com"""
    room_id = await get_dm_room(contact_domain)
    await matrix_send(room_id, body)
    return f"已发送给 {contact_domain}"

@mcp.tool()
async def list_chats(limit: int = 20) -> list[dict]:
    """列出最近的聊天,含联系人域名和最后一条消息"""
    return await matrix_list_rooms(limit)

@mcp.tool()
async def get_messages(contact_domain: str, count: int = 50) -> list[dict]:
    """读取与某联系人的最近 N 条消息"""
    room_id = await get_dm_room(contact_domain)
    return await matrix_timeline(room_id, count)

@mcp.tool()
async def send_file(contact_domain: str, file_path: str) -> str:
    """上传文件并发送给联系人"""
    mxc = await matrix_upload(file_path)
    room_id = await get_dm_room(contact_domain)
    await matrix_send_file(room_id, mxc, file_path)
    return f"文件已发送"

@mcp.tool()
async def add_contact(domain: str) -> str:
    """向对方 Portal 域名发送加好友请求(Matrix invite)"""
    target_mxid = await resolve_owner(domain)  # 查 .well-known/portal/owner.json
    await matrix_client.invite(target_mxid)
    return f"邀请已发送给 {domain}"

@mcp.tool()
async def search_messages(query: str, limit: int = 20) -> list[dict]:
    """全文搜索历史消息"""
    return await matrix_search(query, limit)
```

#### 部署方式

```bash
# 与 continuwuity 同机部署,使用 service account
# @agent_bot:liyananp2p.com 用机器人账号操作

# 1. 安装
pip install fastmcp matrix-nio

# 2. 配置
export MATRIX_HOMESERVER=https://liyananp2p.com
export MATRIX_BOT_TOKEN=<service_account_access_token>

# 3. 启动(stdio 模式给 Claude Desktop 用)
python mcp_server.py

# 3b. HTTP 模式给远程 Agent 用
uvicorn mcp_server:app --port 9100
```

#### Claude Desktop 配置(用户侧)

```json
// ~/.config/claude/claude_desktop_config.json
{
  "mcpServers": {
    "portal-im": {
      "command": "python",
      "args": ["/path/to/mcp_server.py"],
      "env": {
        "MATRIX_HOMESERVER": "https://liyananp2p.com",
        "MATRIX_BOT_TOKEN": "syt_..."
      }
    }
  }
}
```

配置完成后,在 Claude Desktop 直接说"帮我给施歌发消息说明天会议改到下午 3 点",Claude 自动调用 `send_message` tool,不需要打开 App。

### 9.4 Hermes Agent 特殊集成

Hermes 原生支持 Matrix,可以**跳过 MCP Server 直接作为 Matrix 用户**:

```yaml
# hermes_config.yaml
integrations:
  matrix:
    homeserver: https://liyananp2p.com
    user_id: "@hermes_agent:liyananp2p.com"
    access_token: "syt_..."
    # Hermes 会自动订阅所有 room 事件
    # @mention 触发 AI 回复
    trigger: "@hermes_agent"
```

接入效果:在任何聊天室 @hermes_agent,Hermes 直接收到 Matrix event,调用本地 LLM 生成回复,再以 Matrix 消息回复——全程不需要 MCP Server 这一层。两种方式可以并存:

| 场景 | 推荐方案 |
|---|---|
| 用户在 Agent UI 里控制 IM | MCP Server(Claude Desktop / Cursor 等调用) |
| IM 群里 @AI 获得回复 | Hermes/Application Service Matrix Bot |
| 两者都要 | 并存,互不干扰 |

### 9.5 App 侧无需任何改动

再次强调这一点,防止开发时走弯路:

```
❌ 错误理解:Agent 需要通过某种接口"控制" App,App 要为 Agent 开 API
✅ 正确理解:Agent → Matrix API → continuwuity → App /sync(App 已有)
```

Agent 发的消息和人发的消息在 App 眼中完全相同——都是 `m.room.message` 事件,都走 /sync 推送,都渲染成聊天气泡。唯一区别是发送方 MXID 是 `@agent_bot:domain` 而非 `@owner:domain`,App 可以选择显示或隐藏这个标识。

---
