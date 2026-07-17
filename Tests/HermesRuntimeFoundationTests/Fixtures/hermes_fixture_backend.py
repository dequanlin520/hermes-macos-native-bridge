#!/usr/bin/env python3
import argparse
import asyncio
import base64
import hashlib
import json
import signal
import struct
import sys
from urllib.parse import parse_qs, urlparse


def status_body():
    return json.dumps(
        {
            "version": "0.18.2",
            "auth_required": True,
            "auth_mode": "loopback_token",
            "desktop_contract": 3,
            "gateway_running": True,
            "gateway_state": "running",
        }
    ).encode()


async def read_http_request(reader):
    data = await reader.readuntil(b"\r\n\r\n")
    head = data.decode("ascii", errors="replace")
    lines = head.split("\r\n")
    method, target, _ = lines[0].split(" ", 2)
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.lower()] = value.strip()
    return method, target, headers


async def write_http(writer, status, body=b"", content_type="text/plain"):
    reason = {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"}.get(
        status, "Error"
    )
    writer.write(
        f"HTTP/1.1 {status} {reason}\r\n"
        f"Content-Length: {len(body)}\r\n"
        f"Content-Type: {content_type}\r\n"
        "Connection: close\r\n\r\n".encode()
        + body
    )
    await writer.drain()
    writer.close()
    await writer.wait_closed()


async def read_ws_frame(reader):
    first = await reader.readexactly(2)
    opcode = first[0] & 0x0F
    masked = first[1] & 0x80
    length = first[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", await reader.readexactly(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", await reader.readexactly(8))[0]
    mask = await reader.readexactly(4) if masked else b"\x00\x00\x00\x00"
    payload = await reader.readexactly(length)
    if masked:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    if opcode == 8:
        return None
    return payload.decode()


async def write_ws_text(writer, text):
    payload = text.encode()
    header = bytearray([0x81])
    if len(payload) < 126:
        header.append(len(payload))
    elif len(payload) <= 65535:
        header.append(126)
        header.extend(struct.pack("!H", len(payload)))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", len(payload)))
    writer.write(bytes(header) + payload)
    await writer.drain()


async def websocket_handler(reader, writer, target, headers, expected_token, mode):
    query = parse_qs(urlparse(target).query)
    if query.get("token", [""])[0] != expected_token:
        await write_http(writer, 403, b"forbidden")
        return

    key = headers.get("sec-websocket-key")
    if not key:
        await write_http(writer, 400, b"missing websocket key")
        return

    accept = base64.b64encode(
        hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
    ).decode()
    writer.write(
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept}\r\n\r\n".encode()
    )
    await writer.drain()

    if mode != "no-ready":
        await write_ws_text(
            writer, json.dumps({"jsonrpc": "2.0", "method": "event", "params": {"type": "gateway.ready"}})
        )

    pending_out_of_order = []
    while True:
        try:
            message = await read_ws_frame(reader)
        except Exception:
            break
        if message is None:
            break
        request = json.loads(message)
        method = request.get("method")
        request_id = request.get("id")
        params = request.get("params") or {}

        if method == "session.create":
            response = {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": {
                    "session_id": "session-1",
                    "stored_session_id": "stored-1",
                    "message_count": 0,
                    "info": {"desktop_contract": 3},
                },
            }
        elif method == "prompt.submit":
            if params.get("text") == "timeout":
                continue
            if params.get("text") == "close-pending":
                writer.close()
                await writer.wait_closed()
                return
            if params.get("text") == "rpc-error":
                response = {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {"code": -32602, "message": "fixture invalid params"},
                }
            elif params.get("text") == "out-of-order-a":
                pending_out_of_order.append(
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "result": {"status": "streaming-a"},
                    }
                )
                continue
            elif params.get("text") == "out-of-order-b":
                await write_ws_text(
                    writer,
                    json.dumps(
                        {"jsonrpc": "2.0", "id": request_id, "result": {"status": "streaming-b"}}
                    ),
                )
                for pending in pending_out_of_order:
                    await write_ws_text(writer, json.dumps(pending))
                pending_out_of_order.clear()
                continue
            else:
                response = {"jsonrpc": "2.0", "id": request_id, "result": {"status": "streaming"}}
        elif method == "session.status":
            response = {"jsonrpc": "2.0", "id": request_id, "result": {"output": "idle"}}
        elif method == "session.interrupt":
            response = {"jsonrpc": "2.0", "id": request_id, "result": {"status": "interrupted"}}
        elif method == "approval.respond":
            response = {"jsonrpc": "2.0", "id": request_id, "result": {"resolved": True}}
        elif method == "fixture.emitApproval":
            response = {"jsonrpc": "2.0", "id": request_id, "result": {"ok": True}}
        else:
            response = {
                "jsonrpc": "2.0",
                "id": request_id,
                "error": {"code": -32601, "message": "unknown fixture method"},
            }

        await write_ws_text(writer, json.dumps(response))
        if method == "session.create" and mode == "approval-after-create":
            await write_ws_text(
                writer,
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "method": "event",
                        "params": {
                            "type": "approval.request",
                            "session_id": "session-1",
                            "approval_id": "approval-1",
                            "prompt": "Allow fixture action?",
                            "extra": "bounded",
                        },
                    }
                ),
            )

    writer.close()
    await writer.wait_closed()


async def handle_client(reader, writer, expected_token, mode):
    try:
        method, target, headers = await read_http_request(reader)
        parsed = urlparse(target)
        if method == "GET" and parsed.path == "/api/status":
            if mode == "malformed-status":
                await write_http(writer, 200, b"{", "application/json")
            else:
                await write_http(writer, 200, status_body(), "application/json")
        elif method == "GET" and parsed.path == "/api/ws":
            await websocket_handler(reader, writer, target, headers, expected_token, mode)
        else:
            await write_http(writer, 404, b"not found")
    except Exception:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True)
    parser.add_argument("--mode", default="normal")
    args = parser.parse_args()

    server = await asyncio.start_server(
        lambda reader, writer: handle_client(reader, writer, args.token, args.mode),
        "127.0.0.1",
        0,
    )
    port = server.sockets[0].getsockname()[1]
    print(f"READY port={port}", flush=True)

    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    loop.add_signal_handler(signal.SIGTERM, stop.set)
    async with server:
        await stop.wait()


if __name__ == "__main__":
    asyncio.run(main())
