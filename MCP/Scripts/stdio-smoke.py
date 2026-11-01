"""Exercise the built Swift executable over real stdio; no Bluetooth access."""
import json
import plistlib
import selectors
import subprocess
import sys

binary = sys.argv[1]
# otool prints little-endian 32-bit words for native macOS 64-bit binaries.
section = subprocess.check_output(["otool", "-X", "-s", "__TEXT", "__info_plist", binary], text=True)
words = [word for line in section.splitlines() for word in line.split()[1:]]
metadata = b"".join(bytes.fromhex(word)[::-1] for word in words)
info = plistlib.loads(metadata.rstrip(b"\0"))
assert info["CFBundleIdentifier"] == "com.soundblaster.pyb00st-mcp", info
assert info["NSBluetoothAlwaysUsageDescription"], info
if "--disabled" in sys.argv[2:]:
    result = subprocess.run([binary], capture_output=True, text=True, timeout=10)
    assert result.returncode != 0, result
    assert result.stdout == "", result.stdout
    assert "MCP is disabled" in result.stderr, result.stderr
    print("Disabled trait: nonzero exit, diagnostic on stderr, no protocol/Bluetooth session.")
    sys.exit(0)

for version in ("2025-11-25", "2025-06-18"):
    process = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, bufsize=1)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    def send(message):
        process.stdin.write(json.dumps({"jsonrpc": "2.0", **message}) + "\n")
        process.stdin.flush()

    def request(number, method, params):
        send({"id": number, "method": method, "params": params})
        assert selector.select(timeout=10), f"Timeout for {method}"
        line = process.stdout.readline()
        assert line, f"EOF for {method}"
        response = json.loads(line)
        assert response["id"] == number, response
        return response

    try:
        initialized = request(1, "initialize", {
            "protocolVersion": version, "capabilities": {},
            "clientInfo": {"name": "pyb00st-stdio-smoke", "version": "1"},
        })
        assert initialized["result"]["serverInfo"]["name"] == "pyb00st-mcp", initialized
        send({"method": "notifications/initialized"})
        tools = request(2, "tools/list", {})["result"]["tools"]
        assert len(tools) == 8, tools
        assert all(t["inputSchema"]["additionalProperties"] is False for t in tools)
        state = request(3, "tools/call", {"name": "hub_state", "arguments": {}})["result"]
        assert state["structuredContent"]["connected"] is False, state
        assert state["structuredContent"]["ports"] == {}, state
        assert state["isError"] is False, state
        invalid = request(4, "tools/call", {"name": "hub_motor_run", "arguments": {
            "port": "A", "milliseconds": 2001, "dutyCycle": 30,
        }})
        assert invalid["error"]["code"] == -32602, invalid
        disconnected = request(5, "tools/call", {"name": "hub_led", "arguments": {"color": "green"}})
        assert disconnected["result"]["isError"] is True, disconnected
        process.stdin.close()
        assert process.wait(timeout=10) == 0
        assert process.stdout.read() == "", "Unexpected non-protocol stdout"
        print(f"Stdio {version}: initialize, 8 tools, cached state, validation, disconnected write, EOF passed.")
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        process.stdout.close()
        process.stderr.close()
        if not process.stdin.closed:
            process.stdin.close()
