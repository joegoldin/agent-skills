#!/usr/bin/env python3
"""figr — read-only Figma CLI (spec / json / png / meta / find / comments / me).

Auth resolution order:
  1. --token-file PATH          (explicit flag; agenix-friendly)
  2. $FIGMA_TOKEN_FILE          (path to a file containing the token)
  3. $FIGMA_TOKEN               (raw token value)
  4. /run/agenix/figma_token    (agenix on NixOS / nix-darwin)
  5. $XDG_CONFIG_HOME/figma/token   (default: ~/.config/figma/token)

Strictly read-only: every request is an HTTP GET against api.figma.com.
"""

import argparse
import json
import os
import re
import signal
import sys
import urllib.error
import urllib.parse
import urllib.request

# Behave like a normal Unix tool when piped into `head` etc.: die silently on
# SIGPIPE instead of spraying BrokenPipeError tracebacks at interpreter exit.
signal.signal(signal.SIGPIPE, signal.SIG_DFL)

API = "https://api.figma.com/v1"


def die(msg, code=1):
    print(f"figr: {msg}", file=sys.stderr)
    sys.exit(code)


def resolve_token(token_file=None):
    candidates = []
    if token_file:
        candidates.append(token_file)
    if os.environ.get("FIGMA_TOKEN_FILE"):
        candidates.append(os.environ["FIGMA_TOKEN_FILE"])
    for path in candidates:
        try:
            with open(path) as f:
                token = f.read().strip()
            if token:
                return token
            die(f"token file {path} is empty")
        except OSError as e:
            die(f"cannot read token file {path}: {e.strerror}")
    if os.environ.get("FIGMA_TOKEN"):
        return os.environ["FIGMA_TOKEN"].strip()
    xdg = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    for path in ["/run/agenix/figma_token", os.path.join(xdg, "figma", "token")]:
        try:
            with open(path) as f:
                token = f.read().strip()
            if token:
                return token
        except OSError:
            continue
    die(
        "no Figma token found. Provide one via --token-file, $FIGMA_TOKEN_FILE, "
        "$FIGMA_TOKEN, /run/agenix/figma_token, or ~/.config/figma/token"
    )


def get(token, path, params=None, raw=False):
    url = f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"X-Figma-Token": token})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = json.loads(e.read()).get("err") or ""
        except Exception:
            pass
        hint = ""
        if e.code == 403:
            hint = " (token invalid, or it lacks the file_read scope)"
        elif e.code == 404:
            hint = " (bad file key, or the token's account cannot view this file)"
        elif e.code == 429:
            hint = " (rate limited — wait and retry)"
        die(f"HTTP {e.code} on {path}{hint}{': ' + detail if detail else ''}")
    except urllib.error.URLError as e:
        die(f"network error on {path}: {e.reason}")
    return body if raw else json.loads(body)


# ── target parsing ──────────────────────────────────────────────────────────
# Every command accepts either a full figma.com URL or "FILE_KEY [NODE_ID]".

URL_RE = re.compile(
    r"figma\.com/(?:design|file|board|slides|proto)/(?P<key>[A-Za-z0-9]+)"
    r"(?:/branch/(?P<branch>[A-Za-z0-9]+))?"
)


def parse_target(args_list):
    """Return (file_key, node_id_or_None) from a URL or positional args."""
    if not args_list:
        die("missing target: pass a figma.com URL, or FILE_KEY [NODE_ID]")
    first = args_list[0]
    if "figma.com/" in first:
        m = URL_RE.search(first)
        if not m:
            die(f"cannot parse figma URL: {first}")
        key = m.group("branch") or m.group("key")
        node = None
        q = urllib.parse.parse_qs(urllib.parse.urlparse(first).query)
        if q.get("node-id"):
            node = q["node-id"][0].replace("-", ":")
        if len(args_list) > 1:
            node = norm_node(args_list[1])
        return key, node
    key = first
    node = norm_node(args_list[1]) if len(args_list) > 1 else None
    return key, node


def norm_node(node):
    return node.replace("-", ":")


def require_node(node):
    if not node:
        die("this command needs a node: use a URL with ?node-id=… or pass FILE_KEY NODE_ID")
    return node


# ── spec dump ───────────────────────────────────────────────────────────────


def _rgba(c, opacity=None):
    a = c.get("a", 1) if opacity is None else opacity
    hexpart = f"#{int(c['r'] * 255):02x}{int(c['g'] * 255):02x}{int(c['b'] * 255):02x}"
    return hexpart + (f"/{a:.2f}" if a < 1 else "")


def _paints(node, kind):
    out = []
    for p in node.get(kind, []):
        if p.get("visible", True) is False:
            continue
        if p.get("type") == "SOLID":
            out.append(_rgba(p["color"], p.get("opacity")))
        else:
            out.append(p.get("type", "?"))
    return out


def spec_line(node):
    bits = []
    fills = _paints(node, "fills")
    strokes = _paints(node, "strokes")
    if fills:
        bits.append("fill=" + ",".join(fills))
    if strokes:
        w = node.get("strokeWeight", 0)
        bits.append("stroke=" + ",".join(strokes) + (f" w={w:g}" if w else ""))
    if node.get("cornerRadius") is not None:
        bits.append(f"r={node['cornerRadius']:g}")
    if node.get("rectangleCornerRadii"):
        bits.append(f"r={[round(x, 1) for x in node['rectangleCornerRadii']]}")
    pads = {k: node[k] for k in ("paddingLeft", "paddingRight", "paddingTop", "paddingBottom") if node.get(k)}
    if pads:
        vals = [pads.get(k, 0) for k in ("paddingTop", "paddingRight", "paddingBottom", "paddingLeft")]
        if len(set(vals)) == 1:
            bits.append(f"pad={vals[0]:g}")
        else:
            bits.append("pad=" + "/".join(f"{v:g}" for v in vals) + " (t/r/b/l)")
    if node.get("itemSpacing"):
        bits.append(f"gap={node['itemSpacing']:g}")
    if node.get("layoutMode"):
        bits.append(node["layoutMode"][:3])
    if node.get("opacity") is not None and node["opacity"] < 1:
        bits.append(f"opacity={node['opacity']:.2f}")
    style = node.get("style") or {}
    if node.get("type") == "TEXT":
        bits.append(
            f"font={style.get('fontFamily', '?')} w{style.get('fontWeight', '?')} "
            f"{style.get('fontSize', 0):g}px lh={style.get('lineHeightPx', 0):.0f}"
        )
        text = (node.get("characters") or "")[:70].replace("\n", "⏎")
        bits.append(f"“{text}”")
        if node.get("characterStyleOverrides"):
            marks = set()
            for ov in (node.get("styleOverrideTable") or {}).values():
                if ov.get("fontWeight", 400) >= 600:
                    marks.add("bold-span")
                if ov.get("textDecoration") == "UNDERLINE":
                    marks.add("underline-span")
                if ov.get("fills"):
                    marks.add("color-span")
                if ov.get("hyperlink"):
                    marks.add("link-span")
            bits.append("overrides=" + (",".join(sorted(marks)) or "yes"))
    return bits


def cmd_spec(token, args):
    key, node = parse_target(args.target)
    node = require_node(node)
    data = get(token, f"/files/{key}/nodes", {"ids": node})
    doc = data["nodes"].get(node, {}).get("document")
    if not doc:
        die(f"node {node} not found in file {key}")

    def walk(n, depth=0):
        if args.depth is not None and depth > args.depth:
            return
        bb = n.get("absoluteBoundingBox") or {}
        size = f"{bb.get('width', 0):.0f}x{bb.get('height', 0):.0f}"
        line = (
            "  " * depth
            + f"[{n['id']}] {n['type'][:4]} {n.get('name', '')[:36]:<38} {size} "
            + " ".join(map(str, spec_line(n)))
        )
        print(line.rstrip())
        for c in n.get("children", []):
            walk(c, depth + 1)

    walk(doc)


def cmd_json(token, args):
    key, node = parse_target(args.target)
    params = {}
    if args.depth is not None:
        params["depth"] = args.depth
    if node:
        params["ids"] = node
        data = get(token, f"/files/{key}/nodes", params)
    else:
        data = get(token, f"/files/{key}", params or None)
    out = json.dumps(data, indent=2)
    if args.output:
        with open(args.output, "w") as f:
            f.write(out)
        print(f"wrote {len(out)} bytes to {args.output}")
    else:
        print(out)


def cmd_png(token, args):
    key, node = parse_target(args.target)
    node = require_node(node)
    params = {"ids": node, "format": args.format, "scale": args.scale}
    data = get(token, f"/images/{key}", params)
    url = (data.get("images") or {}).get(node)
    if not url:
        die(f"Figma returned no render for node {node} (err={data.get('err')})")
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=120) as resp:
        blob = resp.read()
    out = args.output or f"figma-{node.replace(':', '-')}.{args.format}"
    with open(out, "wb") as f:
        f.write(blob)
    print(f"wrote {len(blob)} bytes to {out}")


def cmd_meta(token, args):
    key, _ = parse_target(args.target)
    data = get(token, f"/files/{key}", {"depth": 1})
    print(f"name:         {data.get('name')}")
    print(f"lastModified: {data.get('lastModified')}")
    print(f"version:      {data.get('version')}")
    print(f"editorType:   {data.get('editorType')}")
    print("pages:")
    for page in data.get("document", {}).get("children", []):
        print(f"  [{page['id']}] {page.get('name')}")


def cmd_find(token, args):
    key, node = parse_target(args.target)
    if node:
        data = get(token, f"/files/{key}/nodes", {"ids": node})
        roots = [d["document"] for d in data["nodes"].values() if d.get("document")]
    else:
        data = get(token, f"/files/{key}")
        roots = [data["document"]]
    pat = args.pattern.lower()
    hits = 0

    def walk(n, path):
        nonlocal hits
        name = n.get("name", "")
        here = path + [name]
        if pat in name.lower():
            hits += 1
            print(f"[{n['id']}] {n['type']:<10} {' > '.join(here)}")
        for c in n.get("children", []):
            walk(c, here)

    for r in roots:
        walk(r, [])
    if not hits:
        print(f"no layers matching {args.pattern!r}", file=sys.stderr)


def cmd_comments(token, args):
    # Comments are file-wide in the API; a node id in the target is ignored.
    key, _ = parse_target(args.target)
    data = get(token, f"/files/{key}/comments")
    comments = data.get("comments", [])
    if not comments:
        print("no comments")
        return

    def fmt(c, indent=""):
        who = (c.get("user") or {}).get("handle", "?")
        when = (c.get("created_at") or "")[:16]
        resolved = " [resolved]" if c.get("resolved_at") else ""
        msg = " ".join((c.get("message") or "").split())
        print(f"{indent}{when} {who}{resolved}: {msg}")

    roots = sorted(
        (c for c in comments if not c.get("parent_id")),
        key=lambda c: c.get("created_at") or "",
        reverse=True,
    )
    replies = {}
    for c in comments:
        if c.get("parent_id"):
            replies.setdefault(c["parent_id"], []).append(c)
    for root in roots:
        fmt(root)
        for child in sorted(replies.get(root.get("id"), []), key=lambda c: c.get("created_at") or ""):
            fmt(child, indent="  ↳ ")


def cmd_me(token, args):
    data = get(token, "/me")
    print(f"handle: {data.get('handle')}")
    print(f"email:  {data.get('email')}")


def main():
    parser = argparse.ArgumentParser(
        prog="figr",
        description="Read-only Figma CLI. Targets are a figma.com URL or FILE_KEY [NODE_ID].",
    )
    parser.add_argument("--token-file", help="path to a file containing the Figma token")
    sub = parser.add_subparsers(dest="cmd", required=True)

    def add(name, fn, help_text, node_target=True):
        p = sub.add_parser(name, help=help_text)
        p.set_defaults(fn=fn)
        p.add_argument("target", nargs="+" if node_target else 1, metavar="TARGET")
        return p

    p = add("spec", cmd_spec, "human-readable layout/style tree for a node (colors, spacing, fonts)")
    p.add_argument("--depth", type=int, help="limit tree depth")

    p = add("json", cmd_json, "raw API JSON for a file or node")
    p.add_argument("--depth", type=int, help="limit tree depth (API-side)")
    p.add_argument("-o", "--output", help="write to file instead of stdout")

    p = add("png", cmd_png, "render a node to an image file")
    p.add_argument("-o", "--output", help="output path (default figma-<node>.<fmt>)")
    p.add_argument("--scale", type=float, default=1, help="render scale 0.01-4 (default 1)")
    p.add_argument("--format", default="png", choices=["png", "svg", "jpg", "pdf"])

    add("meta", cmd_meta, "file name, last-modified, and page list")

    p = sub.add_parser("find", help="search layer names; prints node ids and paths")
    p.set_defaults(fn=cmd_find)
    p.add_argument("pattern", help="case-insensitive substring to match layer names")
    p.add_argument("target", nargs="+", metavar="TARGET")

    add("comments", cmd_comments, "list file comments")

    p = sub.add_parser("me", help="verify the token (prints account handle/email)")
    p.set_defaults(fn=cmd_me)

    args = parser.parse_args()
    token = resolve_token(args.token_file)
    args.fn(token, args)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
