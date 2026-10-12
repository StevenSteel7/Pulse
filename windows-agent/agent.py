"""
SIXDX Stats Agent
------------------
Lightweight, read-only HTTP agent exposing live system stats (CPU, RAM, GPU,
disk, uptime) for consumption by the Pulse macOS widget over the LAN.

Endpoint:
    GET /stats   -> JSON stats, requires header  X-API-Key: <shared secret>
    GET /health  -> {"ok": true}, no auth (cheap liveness probe)

Run directly:
    python agent.py

Configuration is read from config.json next to this file (or the path in the
SIXDX_AGENT_CONFIG env var). See config.example.json for the schema. Values
can also be overridden with environment variables (SIXDX_AGENT_HOST,
SIXDX_AGENT_PORT, SIXDX_AGENT_API_KEY) which take priority over the file.

By default this process binds to a single LAN interface (not 0.0.0.0) so it
is not reachable from outside the home network, and never touches any of the
other local services / ports already running on this machine. Setting "host"
to "0.0.0.0" (config.json or SIXDX_AGENT_HOST) opts into binding all
interfaces, which is only safe to do together with a router port-forward
you've deliberately set up — see the "Remote access over the internet"
section in README.md for the tradeoffs (plain HTTP, no TLS) before doing
this.
"""

from __future__ import annotations

import json
import os
import platform
import secrets
import socket
import subprocess
import time
from pathlib import Path
from typing import Optional

import psutil
import uvicorn
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse

CONFIG_PATH = Path(os.environ.get("SIXDX_AGENT_CONFIG", Path(__file__).with_name("config.json")))

DEFAULT_CONFIG = {
    "host": "192.168.1.54",
    "port": 8801,
    "api_key": "CHANGE-ME-TO-A-LONG-RANDOM-SECRET",
    "disk_path": "C:\\",
}


def load_config() -> dict:
    config = dict(DEFAULT_CONFIG)
    if CONFIG_PATH.exists():
        try:
            file_config = json.loads(CONFIG_PATH.read_text())
            config.update({k: v for k, v in file_config.items() if v is not None})
        except (json.JSONDecodeError, OSError) as exc:
            print(f"[sixdx-agent] WARNING: could not read {CONFIG_PATH}: {exc}")

    # Environment variables win over the file, useful for the Task Scheduler setup.
    if os.environ.get("SIXDX_AGENT_HOST"):
        config["host"] = os.environ["SIXDX_AGENT_HOST"]
    if os.environ.get("SIXDX_AGENT_PORT"):
        config["port"] = int(os.environ["SIXDX_AGENT_PORT"])
    if os.environ.get("SIXDX_AGENT_API_KEY"):
        config["api_key"] = os.environ["SIXDX_AGENT_API_KEY"]

    return config


CONFIG = load_config()

app = FastAPI(title="SIXDX Stats Agent", docs_url=None, redoc_url=None, openapi_url=None)


def _require_api_key(x_api_key: Optional[str]) -> None:
    expected = CONFIG.get("api_key", "")
    if not expected or expected == DEFAULT_CONFIG["api_key"]:
        raise HTTPException(status_code=500, detail="Agent has no api_key configured. Edit config.json.")
    if not x_api_key or not secrets.compare_digest(x_api_key, expected):
        raise HTTPException(status_code=401, detail="Missing or invalid X-API-Key.")


def _gpu_stats() -> dict:
    """Query the first NVIDIA GPU via nvidia-smi. Returns a dict with a
    'available' flag so the client can render an honest "no GPU data" state
    instead of guessing at zeros."""
    query = "utilization.gpu,memory.used,memory.total,temperature.gpu,name"
    try:
        result = subprocess.run(
            ["nvidia-smi", f"--query-gpu={query}", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            timeout=3,
            check=True,
        )
        line = result.stdout.strip().splitlines()[0]
        util, mem_used, mem_total, temp, name = [p.strip() for p in line.split(",")]
        return {
            "available": True,
            "name": name,
            "utilization_percent": float(util),
            "vram_used_mb": float(mem_used),
            "vram_total_mb": float(mem_total),
            "temperature_c": float(temp),
        }
    except (subprocess.SubprocessError, FileNotFoundError, OSError, IndexError, ValueError) as exc:
        return {"available": False, "error": str(exc)}


def _disk_stats() -> dict:
    path = CONFIG.get("disk_path", "C:\\")
    usage = psutil.disk_usage(path)
    return {
        "path": path,
        "used_gb": round(usage.used / (1024 ** 3), 2),
        "total_gb": round(usage.total / (1024 ** 3), 2),
        "percent": usage.percent,
    }


def _memory_stats() -> dict:
    vm = psutil.virtual_memory()
    return {
        "used_gb": round((vm.total - vm.available) / (1024 ** 3), 2),
        "total_gb": round(vm.total / (1024 ** 3), 2),
        "percent": vm.percent,
    }


def _cpu_stats() -> dict:
    # interval=0.3 blocks briefly to get a real (non-zero) sample rather than
    # the misleading "since last call" value psutil returns with interval=None.
    percent = psutil.cpu_percent(interval=0.3)
    return {
        "percent": percent,
        "logical_cores": psutil.cpu_count(logical=True),
        "physical_cores": psutil.cpu_count(logical=False),
    }


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/stats")
def stats(x_api_key: Optional[str] = Header(default=None)):
    _require_api_key(x_api_key)
    return JSONResponse(
        {
            "hostname": socket.gethostname() or platform.node(),
            "os": f"{platform.system()} {platform.release()}",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "uptime_seconds": int(time.time() - psutil.boot_time()),
            "cpu": _cpu_stats(),
            "memory": _memory_stats(),
            "gpu": _gpu_stats(),
            "disk": _disk_stats(),
        }
    )


if __name__ == "__main__":
    scope = "ALL INTERFACES - reachable from the internet if port-forwarded" if CONFIG["host"] == "0.0.0.0" else "LAN-only"
    print(f"[sixdx-agent] binding to http://{CONFIG['host']}:{CONFIG['port']} ({scope})")
    if CONFIG.get("api_key") == DEFAULT_CONFIG["api_key"]:
        print("[sixdx-agent] WARNING: using the placeholder API key. Edit config.json before exposing this on the network.")
    uvicorn.run(app, host=CONFIG["host"], port=int(CONFIG["port"]), log_level="info")
