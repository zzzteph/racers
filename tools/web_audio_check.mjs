// SPEC 139: one command that answers "does the web build make any sound?"
//
// Loads a web export in a real Chrome over the DevTools protocol, taps everything that connects to the
// AudioContext destination with an AnalyserNode, waits for the page to become interactive, supplies the
// user activation the browser requires, and reports the peak level over time. It finishes with a KNOWN
// TONE through the same analyser, which is the control: without it, a flat reading could just as easily
// mean the probe is broken as that the game is silent -- and on the first run of this it did.
//
//   node tools/web_audio_check.mjs <url> [loadSeconds] [cdpPort]

const URL_ = process.argv[2] || "http://127.0.0.1:8099/index.html";
const LOAD = Number(process.argv[3] || 75);
const PORT = Number(process.argv[4] || 9334);

const HOOK = `
(() => {
  window.__lvl = {peak: 0, taps: 0, last: 0, tapped: []};
  const Real = window.AudioContext;
  if (!Real) return;
  window.AudioContext = function (...a) {
    const ctx = new Real(...a);
    window.__ctx = ctx;
    const an = ctx.createAnalyser();
    an.fftSize = 2048;
    window.__an = an;
    const buf = new Float32Array(an.fftSize);
    const rc = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (d, ...r) {
      const x = rc.call(this, d, ...r);
      if (d === ctx.destination) {
        try { rc.call(this, an); window.__lvl.taps++;
              window.__lvl.tapped.push(this.constructor && this.constructor.name); } catch (e) {}
      }
      return x;
    };
    setInterval(() => {
      if (ctx.state !== "running") return;
      an.getFloatTimeDomainData(buf);
      let p = 0;
      for (let i = 0; i < buf.length; i++) { const v = Math.abs(buf[i]); if (v > p) p = v; }
      if (p > window.__lvl.peak) window.__lvl.peak = p;
      window.__lvl.last = p;
    }, 50);
    return ctx;
  };
  window.AudioContext.prototype = Real.prototype;
})();`;

const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
const page = list.find((t) => t.type === "page");
if (!page) { console.error("no page target on port " + PORT); process.exit(1); }
const ws = new WebSocket(page.webSocketDebuggerUrl);
const waiting = new Map();
let id = 0;
await new Promise((r) => (ws.onopen = r));
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m.result); waiting.delete(m.id); }
};
const send = (m, p = {}) => new Promise((res) => { const n = ++id; waiting.set(n, res); ws.send(JSON.stringify({ id: n, method: m, params: p })); });
const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));
const evalIn = async (expr) => {
  const r = await send("Runtime.evaluate", { expression: expr, returnByValue: true });
  return r && r.result ? r.result.value : undefined;
};

await send("Runtime.enable");
await send("Page.enable");
await send("Page.addScriptToEvaluateOnNewDocument", { source: HOOK });
await send("Page.navigate", { url: URL_ });
console.log(`loading ${URL_}  (up to ${LOAD}s)`);

// Wait until the engine has actually created a context rather than trusting a fixed sleep.
let waited = 0;
while (waited < LOAD) {
  await sleep(5);
  waited += 5;
  const st = await evalIn(`window.__ctx ? window.__ctx.state : "none"`);
  if (st && st !== "none") { console.log(`  context exists after ~${waited}s (state=${st})`); break; }
}
// Wait for the game itself, not just the context: the AudioContext is created early in start-up, and
// a click that lands while the pck is still downloading is not forwarded to Godot at all, so it never
// resumes. SETTLE is generous on purpose -- the wasm is ~39 MB and the threaded build is slower still.
const SETTLE = Number(process.argv[5] || 70);
console.log(`  settling ${SETTLE}s before the activation click`);
await sleep(SETTLE);

// The activation gesture, repeated: the first click can land before the canvas is listening.
for (let k = 0; k < 4; k++) {
  await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: 640, y: 300 });
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x: 640, y: 300, button: "left", clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: 640, y: 300, button: "left", clickCount: 1 });
  await sleep(2);
  const st = await evalIn(`window.__ctx ? window.__ctx.state : "none"`);
  if (st === "running") { console.log(`  context RUNNING after ${k + 1} click(s)`); break; }
}

for (const t of [10, 20, 30]) {
  await sleep(10);
  const v = JSON.parse(await evalIn(`JSON.stringify({p: window.__lvl.peak, s: window.__ctx ? window.__ctx.state : "none", t: window.__lvl.taps, n: window.__lvl.tapped})`));
  console.log(`  t+${t}s  state=${v.s}  taps=${v.t} ${JSON.stringify(v.n)}  peak=${v.p.toFixed(5)}`);
}

const game = Number(await evalIn(`window.__lvl.peak`)) || 0;
const control = Number(await evalIn(`(() => {
  const c = window.__ctx; if (!c || c.state !== "running") return -1;
  const g = c.createGain(), o = c.createOscillator();
  g.gain.value = 0.2; o.connect(g); g.connect(window.__an); g.connect(c.destination); o.start();
  return 1;
})()`));
await sleep(2);
const ctrlPeak = control < 0 ? -1 : Number(await evalIn(`(() => { const b = new Float32Array(window.__an.fftSize);
  window.__an.getFloatTimeDomainData(b); let p = 0; for (const v of b) p = Math.max(p, Math.abs(v)); return p; })()`));
await evalIn(`window.__ctx && window.__ctx.suspend && 0`);

console.log("");
console.log(`GAME peak    = ${game.toFixed(5)}`);
console.log(`CONTROL tone = ${ctrlPeak < 0 ? "not run (context not running)" : ctrlPeak.toFixed(5)}`);
console.log("");
if (ctrlPeak <= 0) console.log("INCONCLUSIVE: the control tone was not measurable, so a flat game reading proves nothing.");
else if (game <= 1e-5) console.log("SILENT: the control is audible through the same graph, the game is not.");
else console.log("SOUND PRESENT: the web build is producing audio.");
ws.close();
process.exit(0);
