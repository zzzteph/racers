// SPEC 139: click through the running web build and report the audio level at each step.
//
// Used with `web_audio_level.mjs` already attached to the page (it installs the analyser tap). Takes a
// list of "x,y" clicks and a dwell time, screenshots after each, and prints the peak level measured in
// between -- so "which screen is silent" is answered with a picture and a number rather than a guess.
//
//   node tools/web_drive.mjs 177,589 3 200,250 4 ...
//   (pairs of "x,y" and seconds-to-listen; a bare number with no preceding click just listens)

const PORT = 9333;
const args = process.argv.slice(2);

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
const send = (m, p = {}) => new Promise((res) => { const n = ++id; waiting.set(n, res); ws.send(JSON.stringify({ id: n, method: m, params: p })); });
const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));
await send("Page.enable");
await send("Runtime.enable");

const fs = await import("node:fs");
let step = 0;

const reset = () => send("Runtime.evaluate", { expression: "if(window.__lvl){window.__lvl.peak=0}" });
const peak = async () => {
  const r = await send("Runtime.evaluate", {
    expression: `JSON.stringify({p: (window.__lvl&&window.__lvl.peak)||0, s: window.__ctx?window.__ctx.state:"none"})`,
    returnByValue: true });
  return JSON.parse(r.result.value);
};
const shot = async (label) => {
  const r = await send("Page.captureScreenshot", { format: "png" });
  const path = `build/web-step${step}.png`;
  fs.writeFileSync(path, Buffer.from(r.data, "base64"));
  const v = await peak();
  console.log(`step ${step} ${label.padEnd(20)} state=${v.s} peak=${v.p.toFixed(5)}  -> ${path}`);
  step++;
};

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a.includes(",")) {
    const [x, y] = a.split(",").map(Number);
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", clickCount: 1 });
    const secs = Number(args[i + 1]) || 3;
    i++;
    await reset();
    await sleep(secs);
    await shot(`click ${x},${y}`);
  } else {
    await reset();
    await sleep(Number(a) || 3);
    await shot("listen");
  }
}
ws.close();
process.exit(0);
