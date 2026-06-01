
#!/usr/bin/env python3
import json
import base64
import paramiko
import getpass
import sys
import os

ROUTER_IP = "192.168.50.1"
ROUTER_USER = "root"
SING_BOX_CONFIG = "/etc/sing-box/config.json"

# Colors
R  = "\033[0m"
B  = "\033[1m"
DIM= "\033[2m"
CY = "\033[96m"
GR = "\033[92m"
YL = "\033[93m"
RD = "\033[91m"
MG = "\033[95m"
BL = "\033[94m"

def clear():
    os.system("cls" if os.name == "nt" else "clear")

def divider(char="─", color=DIM):
    print(f"{color}{char * 52}{R}")

def header(title=""):
    clear()
    print(f"{CY}{B}")
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║        ⬡  SING-BOX NODE MANAGER  ⬡          ║")
    print("  ╚══════════════════════════════════════════════╝")
    print(R)
    if title:
        print(f"  {MG}{B}▶  {title}{R}")
        divider()

def success(msg): print(f"\n  {GR}✔  {msg}{R}")
def error(msg):   print(f"\n  {RD}✘  {msg}{R}")
def info(msg):    print(f"\n  {BL}ℹ  {msg}{R}")
def warn(msg):    print(f"\n  {YL}⚠  {msg}{R}")

def prompt(label, default=""):
    hint = f"{DIM}[{default}]{R} " if default else ""
    return input(f"  {CY}❯{R} {label} {hint}: ").strip() or default

def pause():
    input(f"\n  {DIM}Press Enter to continue...{R}")

# ── SSH ──────────────────────────────────────────────────────────────────────

def ssh_connect(ip, user, password):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(ip, username=user, password=password, timeout=10)
    return client

def ssh_run(client, cmd):
    _, stdout, stderr = client.exec_command(cmd)
    return stdout.read().decode().strip(), stderr.read().decode().strip()

def get_config(client):
    out, err = ssh_run(client, f"cat {SING_BOX_CONFIG}")
    if err and not out:
        error(f"Error reading config: {err}")
        sys.exit(1)
    return json.loads(out)

def put_config(client, config):
    data = json.dumps(config, indent=2, ensure_ascii=False).replace("'", "'\\''")
    ssh_run(client, f"echo '{data}' > {SING_BOX_CONFIG}")
    ssh_run(client, "/etc/init.d/sing-box restart")
    success("Config saved and sing-box restarted.")

# ── vmess parsing ────────────────────────────────────────────────────────────

def parse_vmess(link):
    b64 = link[len("vmess://"):]
    b64 += "=" * (-len(b64) % 4)
    d = json.loads(base64.b64decode(b64).decode())
    node = {
        "type": "vmess",
        "tag": d.get("ps", d.get("add", "unnamed")),
        "server": d["add"],
        "server_port": int(d["port"]),
        "uuid": d["id"],
        "security": "auto",
        "alter_id": int(d.get("aid", 0)),
    }
    net = d.get("net", "tcp")
    if net == "ws":
        t = {"type": "ws"}
        if d.get("path"): t["path"] = d["path"]
        if d.get("host"): t["headers"] = {"Host": d["host"]}
        node["transport"] = t
    elif net == "grpc":
        node["transport"] = {"type": "grpc", "service_name": d.get("path", "")}
    if d.get("tls") == "tls":
        node["tls"] = {"enabled": True, "server_name": d.get("host") or d["add"]}
    return node

# ── helpers ──────────────────────────────────────────────────────────────────

def get_vmess(config):
    return [o for o in config.get("outbounds", []) if o.get("type") == "vmess"]

def find_selector(config):
    for o in config.get("outbounds", []):
        if o.get("type") == "selector":
            return o
    return None

# ── actions ──────────────────────────────────────────────────────────────────

def list_nodes(config, interactive=True):
    if interactive:
        header("Node List")
    nodes = get_vmess(config)
    selector = find_selector(config)
    default_tag = selector.get("default") if selector else None
    if not nodes:
        warn("No vmess nodes configured.")
        return
    print(f"  {DIM}{'#':<4} {'Tag':<28} {'Server':<20} {'Port'}{R}")
    divider()
    for i, n in enumerate(nodes, 1):
        is_def = n["tag"] == default_tag
        idx_col = f"{YL}{B}{i:<4}{R}" if is_def else f"{DIM}{i:<4}{R}"
        tag_col = f"{GR}{B}{n['tag']:<28}{R}" if is_def else f"{CY}{n['tag']:<28}{R}"
        srv_col = f"{n['server']:<20}"
        star    = f"  {YL}★ default{R}" if is_def else ""
        print(f"  {idx_col}{tag_col}{DIM}{srv_col}{n['server_port']}{R}{star}")
    divider()
    print(f"  {DIM}Total: {len(nodes)} node(s){R}")

def do_add(client):
    header("Add Node")
    link = prompt("Paste vmess:// link")
    if not link.startswith("vmess://"):
        error("Not a valid vmess:// link.")
        pause(); return
    config = get_config(client)
    node = parse_vmess(link)
    config.setdefault("outbounds", []).append(node)
    sel = find_selector(config)
    if sel is not None:
        sel.setdefault("outbounds", []).append(node["tag"])
    info(f"Adding  {CY}{node['tag']}{R}  →  {node['server']}:{node['server_port']}")
    put_config(client, config)
    pause()

def do_delete(client):
    header("Delete Node")
    config = get_config(client)
    list_nodes(config, interactive=False)
    nodes = get_vmess(config)
    if not nodes: pause(); return
    try:
        idx = int(prompt("Node # to delete"))
    except ValueError:
        error("Invalid input."); pause(); return
    if idx < 1 or idx > len(nodes):
        error("Index out of range."); pause(); return
    tag = nodes[idx - 1]["tag"]
    config["outbounds"] = [o for o in config["outbounds"]
                           if not (o.get("type") == "vmess" and o["tag"] == tag)]
    sel = find_selector(config)
    if sel:
        sel["outbounds"] = [t for t in sel.get("outbounds", []) if t != tag]
        if sel.get("default") == tag:
            del sel["default"]
    info(f"Deleting  {RD}{tag}{R}")
    put_config(client, config)
    pause()

def do_set_default(client):
    header("Set Default Node")
    config = get_config(client)
    list_nodes(config, interactive=False)
    nodes = get_vmess(config)
    if not nodes: pause(); return
    sel = find_selector(config)
    if sel is None:
        error("No selector outbound found in config."); pause(); return
    try:
        idx = int(prompt("Node # to set as default"))
    except ValueError:
        error("Invalid input."); pause(); return
    if idx < 1 or idx > len(nodes):
        error("Index out of range."); pause(); return
    tag = nodes[idx - 1]["tag"]
    sel["default"] = tag
    info(f"Default  →  {GR}{tag}{R}")
    put_config(client, config)
    pause()

# ── main menu ────────────────────────────────────────────────────────────────

MENU = [
    ("List nodes",        lambda c: (list_nodes(get_config(c)), pause())),
    ("Add node",do_add),
    ("Delete node",       do_delete),
    ("Set default node",  do_set_default),
    ("Exit",              None),
]

def main():
    header("Connect to Router")
    ip       = prompt("Router IP",  ROUTER_IP)
    user     = prompt("SSH user",   ROUTER_USER)
    password = getpass.getpass(f"  {CY}❯{R} Password: ")

    info("Connecting…")
    try:
        client = ssh_connect(ip, user, password)
    except Exception as e:
        error(f"Connection failed: {e}")
        sys.exit(1)
    success(f"Connected to {ip}")
    pause()

    while True:
        header("Main Menu")
        for i, (label, _) in enumerate(MENU, 1):
            color = RD if label == "Exit" else BL
            print(f"  {color}{B}[{i}]{R}  {label}")
        divider()
        choice = prompt("Select option")
        if not choice.isdigit() or not (1 <= int(choice) <= len(MENU)):
            error("Invalid choice."); pause(); continue
        idx = int(choice) - 1
        label, fn = MENU[idx]
        if fn is None:
            break
        fn(client)

    client.close()
    clear()
    print(f"\n  {GR}{B}Disconnected. Goodbye!{R}\n")

if __name__ == "__main__":
    main()
