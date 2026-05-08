"""
Portal IM — MCP Server
让 Claude Desktop / Hermes / Cursor 等 AI Agent 通过 MCP 操作 Matrix IM。

用法:
  stdio 模式 (Claude Desktop):   python mcp_server.py
  HTTP 模式 (远程 Agent):        uvicorn mcp_server:app --port 9100

环境变量 (.env):
  MATRIX_HOMESERVER=https://liyananp2p.com
  MATRIX_BOT_TOKEN=syt_...
  MATRIX_BOT_USER_ID=@owner:liyananp2p.com
"""

import asyncio
import json
import os
import aiohttp
from dotenv import load_dotenv
from fastmcp import FastMCP

load_dotenv()

HOMESERVER = os.getenv("MATRIX_HOMESERVER", "https://liyananp2p.com")
TOKEN = os.getenv("MATRIX_BOT_TOKEN", "")
BOT_USER = os.getenv("MATRIX_BOT_USER_ID", "")

mcp = FastMCP("portal-im", version="1.0.0")


# ── helpers ──────────────────────────────────────────────────────────────────

async def _matrix_get(path: str) -> dict:
    url = f"{HOMESERVER}/_matrix/client/v3{path}"
    async with aiohttp.ClientSession() as s:
        async with s.get(url, headers={"Authorization": f"Bearer {TOKEN}"}) as r:
            r.raise_for_status()
            return await r.json()


async def _matrix_post(path: str, body: dict) -> dict:
    url = f"{HOMESERVER}/_matrix/client/v3{path}"
    async with aiohttp.ClientSession() as s:
        async with s.post(url, json=body, headers={"Authorization": f"Bearer {TOKEN}"}) as r:
            r.raise_for_status()
            return await r.json()


async def _matrix_put(path: str, body: dict) -> dict:
    url = f"{HOMESERVER}/_matrix/client/v3{path}"
    async with aiohttp.ClientSession() as s:
        async with s.put(url, json=body, headers={"Authorization": f"Bearer {TOKEN}"}) as r:
            r.raise_for_status()
            return await r.json()


async def _resolve_dm_room(contact_domain: str) -> str | None:
    """通过域名找到与该联系人的 DM room id。"""
    target_mxid = f"@owner:{contact_domain}"
    resp = await _matrix_get(f"/joined_rooms")
    for room_id in resp.get("joined_rooms", []):
        state = await _matrix_get(f"/rooms/{room_id}/state/m.room.member/{target_mxid}")
        if state.get("membership") == "join":
            return room_id
    return None


async def _resolve_owner_mxid(domain: str) -> str:
    """查 .well-known/portal/owner.json，fallback 到 @owner:domain。"""
    try:
        async with aiohttp.ClientSession() as s:
            async with s.get(f"https://{domain}/.well-known/portal/owner.json", timeout=aiohttp.ClientTimeout(total=5)) as r:
                if r.status == 200:
                    data = await r.json()
                    return data.get("matrix_user_id", f"@owner:{domain}")
    except Exception:
        pass
    return f"@owner:{domain}"


# ── MCP tools ────────────────────────────────────────────────────────────────

@mcp.tool()
async def list_chats(limit: int = 20) -> list[dict]:
    """列出最近的聊天会话，含联系人域名和最后一条消息。"""
    resp = await _matrix_get("/joined_rooms")
    rooms = []
    for room_id in resp.get("joined_rooms", [])[:limit]:
        try:
            msgs = await _matrix_get(f"/rooms/{room_id}/messages?dir=b&limit=1")
            last = msgs.get("chunk", [{}])[0]
            rooms.append({
                "room_id": room_id,
                "last_message": last.get("content", {}).get("body", ""),
                "sender": last.get("sender", ""),
                "timestamp": last.get("origin_server_ts", 0),
            })
        except Exception:
            pass
    rooms.sort(key=lambda x: x["timestamp"], reverse=True)
    return rooms


@mcp.tool()
async def get_messages(contact_domain: str, count: int = 50) -> list[dict]:
    """读取与某联系人的最近 N 条消息。contact_domain 例如 liyananp2p.com"""
    room_id = await _resolve_dm_room(contact_domain)
    if not room_id:
        return [{"error": f"未找到与 {contact_domain} 的会话"}]
    resp = await _matrix_get(f"/rooms/{room_id}/messages?dir=b&limit={count}")
    return [
        {
            "sender": e.get("sender", ""),
            "body": e.get("content", {}).get("body", ""),
            "timestamp": e.get("origin_server_ts", 0),
            "event_id": e.get("event_id", ""),
        }
        for e in resp.get("chunk", [])
        if e.get("type") == "m.room.message"
    ]


@mcp.tool()
async def send_message(contact_domain: str, body: str) -> str:
    """向联系人发一条文字消息。contact_domain 例如 liyananp2p.com"""
    room_id = await _resolve_dm_room(contact_domain)
    if not room_id:
        return f"错误：未找到与 {contact_domain} 的会话，请先添加联系人"
    import time
    txn_id = str(int(time.time() * 1000))
    await _matrix_put(
        f"/rooms/{room_id}/send/m.room.message/{txn_id}",
        {"msgtype": "m.text", "body": body},
    )
    return f"已发送给 {contact_domain}：{body}"


@mcp.tool()
async def add_contact(domain: str) -> str:
    """向对方 Portal 域名发送加好友请求（Matrix DM invite）。"""
    target_mxid = await _resolve_owner_mxid(domain)
    resp = await _matrix_post("/createRoom", {
        "is_direct": True,
        "invite": [target_mxid],
        "preset": "trusted_private_chat",
    })
    return f"已向 {domain} ({target_mxid}) 发送好友邀请，room_id: {resp.get('room_id')}"


@mcp.tool()
async def list_pending_invites() -> list[dict]:
    """列出待处理的好友申请和群邀请。"""
    resp = await _matrix_get("/sync?filter=%7B%22room%22%3A%7B%22include_leave%22%3Afalse%7D%7D&timeout=0")
    invite_rooms = resp.get("rooms", {}).get("invite", {})
    results = []
    for room_id, data in invite_rooms.items():
        results.append({"room_id": room_id, "invite_state": data.get("invite_state", {})})
    return results


@mcp.tool()
async def search_messages(query: str, limit: int = 20) -> list[dict]:
    """全文搜索消息。"""
    resp = await _matrix_post("/search", {
        "search_categories": {
            "room_events": {
                "search_term": query,
                "order_by": "recent",
                "limit": limit,
            }
        }
    })
    results = resp.get("search_categories", {}).get("room_events", {}).get("results", [])
    return [
        {
            "room_id": r.get("result", {}).get("room_id", ""),
            "body": r.get("result", {}).get("content", {}).get("body", ""),
            "sender": r.get("result", {}).get("sender", ""),
            "timestamp": r.get("result", {}).get("origin_server_ts", 0),
        }
        for r in results
    ]


# ── entrypoint ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    mcp.run()  # stdio 模式，供 Claude Desktop 使用
