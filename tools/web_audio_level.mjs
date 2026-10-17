// SPEC 139: is the web build actually PUTTING SOUND into the audio graph?
//
// `web_audio_probe.mjs` answered the first half -- the AudioContext is created suspended and one click
// resumes it. That only proves the tap is open. This measures whether anything comes out of it: every
// node that connects to `ctx.destination` is also connected to an AnalyserNode, and the peak level is
// sampled over time. Silence with a RUNNING context is a different bug from a suspended context, and
// the two need telling apart before anything is "fixed".
//
//   node tools/web_audio_level.mjs [url] [load seconds]

const URL_ = process.argv[2] || "http://127.0.0.1:8099/index.html";
const LOAD = Number(process.argv[3] || 45);
const PORT = 9333;

const HOOK = `
(() => {
  window.__lvl = {peak: 0, samples: 0, taps: 0, log: []};
  const Real = window.AudioContext;
  window.AudioContext = function (...a) {
    const ctx = new Real(...a);
    window.__ctx = ctx;
    const an = ctx.createAnalyser();
    an.fftSize = 2048;
    window.__an = an;
    const buf = new Float32Array(an.fftSize);
    // Anything that reaches the speakers also reaches the analyser.
    const realConnect = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (dest, ...rest) {
      const r = realConnect.call(this, dest, ...rest);
      if (dest === ctx.destination) {
        try { realConnect.call(this, an); window.__lvl.taps++;
              window.__lvl.log.push("tapped " + (this.constructor && this.constructor.name)); } catch (e) {}
      }
      return r;
    };
    setInterval(() => {
      if (ctx.state !== "running") return;
      an.getFloatTimeDomainData(buf);
      let p = 0;
      for (let i = 0; i < buf.length; i++) { const v = Math.abs(buf[i]); if (v > p) p = v; }
      window.__lvl.samples++;
      if (p > window.__lvl.peak) window.__lvl.peak = p;
      window.__lvl.last = p;
    }, 50);
    return ctx;
  };
  window.AudioContext.prototype = Real.prototype;
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
  return {
    send: (method, params = {}) =>
      new Promise((res) => { const n = ++id; waiting.set(n, res); ws.send(JSON.stringify({ id: n, method, params })); }),
    ws,
  };
}

const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));

const main = async () => {
  const { send, ws } = await cdp();
  await send("Runtime.enable");
  await send("Page.enable");
  await send("Page.addScriptToEvaluateOnNewDocument", { source: HOOK });
  await send("Page.navigate", { url: URL_ });
  console.log(`loading ${URL_} ...`);
  await sleep(LOAD);

  const click = async (x, y) => {
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
  };
  const level = async (label) => {
    const r = await send("Runtime.evaluate", {
      expression: `JSON.stringify({s: window.__ctx ? window.__ctx.state : "none", ...window.__lvl})`,
      returnByValue: true,
    });
    const v = JSON.parse(r.result.value);
    console.log(`${label.padEnd(34)} state=${v.s} taps=${v.taps} peak=${(v.peak || 0).toFixed(5)} last=${(v.last || 0).toFixed(5)}`);
    return v;
  };

  await level("loaded, untouched");
  await click(640, 360);          // the activation gesture
  await sleep(4);
  await level("after activation click");
  // Reset the peak, then let the menu play on its own for a while.
  await send("Runtime.evaluate", { expression: "window.__lvl.peak=0;window.__lvl.samples=0" });
  await sleep(8);
  await level("menu, 8 s of listening");
  // Try to get into a race: the menu buttons are stacked centre-left in the 1280x720 layout.
  await click(200, 250);
  await sleep(3);
  await click(640, 620);
  await sleep(3);
  await send("Runtime.evaluate", { expression: "window.__lvl.peak=0" });
  await sleep(10);
  const end = await level("after menu clicks, 10 s");
  const tapped = await send("Runtime.evaluate", { expression: "JSON.stringify((window.__lvl.log||[]).slice(0,6))", returnByValue: true });
  console.log("taps:", tapped.result.value);
  console.log("\nVERDICT:");
  if ((end.taps || 0) === 0) console.log("  NOTHING ever connected to ctx.destination -- the engine never built an output graph.");
  else if ((end.peak || 0) < 1e-5) console.log("  Output graph exists and the context runs, but the signal is FLAT -- silence is produced, not blocked.");
  else console.log(`  Real signal present (peak ${end.peak.toFixed(4)}). The web build does make sound once activated.`);
  ws.close();
  process.exit(0);
};

main().catch((e) => { console.error("probe failed:", e.message); process.exit(1); });
