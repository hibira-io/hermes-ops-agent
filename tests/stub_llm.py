# Scripted OpenAI-compatible model for the smoke test: asks for one tool call
# (a terminal STUB_COMMAND, or STUB_TOOL with STUB_ARGS), then reports the
# tool result verbatim.
import json, os, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
CMD = os.environ.get("STUB_COMMAND", "rm -rf /opt/data/workspace/old-logs")
TOOL = os.environ.get("STUB_TOOL", "terminal")
ARGS = os.environ.get("STUB_ARGS") or json.dumps({"command": CMD})
LOG = open(os.environ.get("STUB_LOG", "/dev/null"), "a")

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        body = json.dumps({"data": [{"id": "stub", "object": "model"}]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        msgs = req.get("messages", [])
        tool_msgs = [m for m in msgs if m.get("role") == "tool"]
        LOG.write(json.dumps({"n": len(msgs), "tools": [t.get("function", {}).get("name") for t in req.get("tools") or []], "last": msgs[-1] if msgs else None})[:6000] + "\n"); LOG.flush()
        if not tool_msgs:
            msg = {"role": "assistant", "content": None, "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": TOOL, "arguments": ARGS}}]}
            finish = "tool_calls"
        else:
            c = tool_msgs[-1].get("content")
            if isinstance(c, list): c = " ".join(p.get("text", "") for p in c)
            msg = {"role": "assistant", "content": "TOOL RESULT: " + str(c)[:1500]}
            finish = "stop"
        if req.get("stream"):
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
            delta = dict(msg)
            if "tool_calls" in delta:
                delta["tool_calls"] = [dict(delta["tool_calls"][0], index=0)]
            for d, f in ((delta, None), ({}, finish)):
                chunk = {"id": "x", "object": "chat.completion.chunk", "created": int(time.time()), "model": "stub", "choices": [{"index": 0, "delta": d, "finish_reason": f}]}
                self.wfile.write(b"data: " + json.dumps(chunk).encode() + b"\n\n"); self.wfile.flush()
            usage = {"id": "x", "object": "chat.completion.chunk", "created": int(time.time()), "model": "stub", "choices": [], "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}
            self.wfile.write(b"data: " + json.dumps(usage).encode() + b"\n\ndata: [DONE]\n\n"); self.wfile.flush()
        else:
            body = json.dumps({"id": "x", "object": "chat.completion", "created": int(time.time()), "model": "stub", "choices": [{"index": 0, "message": msg, "finish_reason": finish}], "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)

ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
