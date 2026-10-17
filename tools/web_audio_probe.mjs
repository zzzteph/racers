// SPEC 139: does the web build ever get a RUNNING AudioContext?
//
// "There is no sound in the web version." The project's own audio code is the same on every platform,
// so the interesting question is not what Godot renders -- it is whether the browser ever lets the
// AudioContext out of `suspended`. Browsers start one suspended until the page has a user ACTIVATION,
// and this game is steered by MOVING the pointer, which is not an activation.
//
// This drives a real Chrome over the DevTools protocol, wraps `AudioContext` before the page loads,
// and records every state change and resume() call. Then it clicks the canvas and looks again, which
// separates "never resumes" from "resumes on the first click, as designed".
//
//   node tools/web_audio_probe.mjs [url] [seconds]

const URL_ = process.argv[2] || "http://127.0.0.1:8099/index.html";
const WAIT = Number(process.argv[3] || 40);
const PORT = 9333;

const HOOK = `
(() => {
  window.__audioLog = [];
  const log = (m) => { window.__audioLog.push(performance.now().toFixed(0) + "ms " + m); };
  for (const name of ["AudioContext", "webkitAudioContext"]) {
    const Real = window[name];
    if (!Real) continue;
    const Wrapped = function (...args) {
      const ctx = new Real(...args);
      window.__ctx = ctx;
      log("created state=" + ctx.state + " rate=" + ctx.sampleRate +
          " opts=" + JSON.stringify(args[0] || {}));
      ctx.addEventListener("statechange", () => log("statechange -> " + ctx.state));
      const resume = ctx.resume.bind(ctx);
      ctx.resume = () => { log("resume() called, state=" + ctx.state); return resume(); };
      return ctx;
    };
    Wrapped.prototype = Real.prototype;
    window[name] = Wrapped;
  }
  window.addEventListener("error", (e) => log("PAGE ERROR " + e.message));
})();
`;

async function cdp() {
  const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  const page = list.find((t) => t.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  const waiting = new Map();
  let id = 0;
  await new Promise((r) => (ws.onopen = r));
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m.result); waiting.delete(m.id); }
  };
  const send = (method, params = {}) =>
    new Promise((res) => { const n = ++id; waiting.set(n, res); ws.send(JSON.stringify({ id: n, method, params })); });
  return { send, ws };
}

const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));

const main = async () => {
  const { send, ws } = await cdp();
  await send("Runtime.enable");
  await send("Page.enable");
  await send("Page.addScriptToEvaluateOnNewDocument", { source: HOOK });
  await send("Page.navigate", { url: URL_ });
  console.log(`loading ${URL_} ... (${WAIT}s; the wasm is ~39 MB)`);

  const read = async (label) => {
    const r = await send("Runtime.evaluate", {
      expression: `JSON.stringify({log: window.__audioLog || [], state: window.__ctx ? window.__ctx.state : "no context", coi: window.crossOriginIsolated === true, secure: window.isSecureContext === true})`,
      returnByValue: true,
    });
    let v;
    try { v = JSON.parse(r.result.value); } catch { v = { log: [], state: "unreadable" }; }
    console.log(`\n=== ${label} ===`);
    console.log(`crossOriginIsolated=${v.coi}  isSecureContext=${v.secure}  AudioContext.state=${v.state}`);
    for (const line of v.log) console.log("  " + line);
    return v;
  };

  await sleep(WAIT);
  const before = await read("after load, no interaction");

  // A real click on the canvas: the user activation the browser is waiting for.
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: 640, y: 360, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: 640, y: 360, button: "left", clickCount: 1 });
  await sleep(3);
  const after = await read("after one click on the canvas");

  // And pointer movement only, which is how this game is actually driven.
  for (let i = 0; i < 20; i++) {
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: 500 + i * 8, y: 300 + i * 4 });
  }
  await sleep(2);
  await read("after pointer movement");

  console.log("\nVERDICT:");
  if (before.state === "running") console.log("  Context was RUNNING before any interaction -- autoplay was allowed here.");
  else if (after.state === "running") console.log("  Context was suspended until a CLICK, then ran. The click path works.");
  else console.log("  Context NEVER reached running. That is silence regardless of what the game renders.");
  ws.close();
  process.exit(0);
};

main().catch((e) => { console.error("probe failed:", e.message); process.exit(1); });
