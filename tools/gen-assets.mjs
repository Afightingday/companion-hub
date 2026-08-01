#!/usr/bin/env node
/* B12 音效 + 纸纹生成器（零依赖，确定性输出）。
   调性口径（docs/08 B12）：纸声、笔触、轻物落桌，忌电子音效感——
   因此全部用滤波噪声/阻尼低频/短促瞬态合成，不放裸正弦长音。
   跑法：node tools/gen-assets.mjs   （在 apps/ios 下）
   产物：App/Resources/sounds/*.wav（44.1kHz 16bit 单声道）
        App/Resources/assets/grain.png（256² 两倍频程值噪声，soft-light 用） */

import { writeFileSync, mkdirSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SR = 44100;

/* ── 确定性随机（mulberry32）：同一种子每次生成逐字节相同 ── */
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* ── 基础件 ────────────────────────────────────────── */
const sec = (s) => Math.round(s * SR);

/** 单极低通（连续调用，保内部状态） */
function lowpass(cutHz) {
  let y = 0;
  return (x, hz = cutHz) => {
    const a = 1 - Math.exp((-2 * Math.PI * hz) / SR);
    y += a * (x - y);
    return y;
  };
}

/** 带通 = 两级低通差分（宽 Q，够纸声用） */
function bandpass(centerHz, width = 0.6) {
  const lo = lowpass(centerHz * (1 + width));
  const hi = lowpass(centerHz * (1 - width));
  return (x, hz = centerHz) => lo(x, hz * (1 + width)) - hi(x, hz * (1 - width));
}

/** 指数衰减包络 */
const decay = (t, tau) => Math.exp(-t / tau);
/** 起音包络（0→1） */
const attack = (t, tau) => 1 - Math.exp(-t / tau);

/** 阻尼低频「实体感」：正弦掉音高 + 噪声幅调，听感是软物而不是电子音 */
function thump(rand, n, { f0, f1, tau, noiseAmt = 0.18, lpHz = 700 }) {
  const out = new Float64Array(n);
  const lp = lowpass(lpHz);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const k = Math.min(1, t / 0.012);
    const f = f0 + (f1 - f0) * Math.min(1, t / 0.08);
    phase += (2 * Math.PI * f) / SR;
    const wob = 1 + noiseAmt * (rand() * 2 - 1);
    out[i] = lp(Math.sin(phase) * wob) * decay(t, tau) * k;
  }
  return out;
}

/** 纸噪声：带通白噪，中心频率随时间走 sweep 曲线 */
function paper(rand, n, { hzAt, width = 0.55, env }) {
  const out = new Float64Array(n);
  const bp = bandpass(1000, width);
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    out[i] = bp(rand() * 2 - 1, hzAt(t)) * env(t);
  }
  return out;
}

/** 微瞬态（纸的细碎「咔」）：几毫秒的高通噪尖 */
function crackle(rand, n, at, amp = 1) {
  const out = new Float64Array(n);
  for (const [t0, a] of at) {
    const s0 = sec(t0);
    const len = sec(0.004 + rand() * 0.004);
    for (let i = 0; i < len && s0 + i < n; i++) {
      out[s0 + i] += (rand() * 2 - 1) * decay(i / SR, 0.0016) * a * amp;
    }
  }
  return out;
}

const mix = (n, ...parts) => {
  const out = new Float64Array(n);
  for (const p of parts) for (let i = 0; i < Math.min(n, p.length); i++) out[i] += p[i];
  return out;
};

/** 归一到目标峰值 + 首尾 3ms 消 click + 软饱和 */
function master(buf, peak = 0.5) {
  let m = 1e-9;
  for (const v of buf) m = Math.max(m, Math.abs(v));
  const g = peak / m;
  const fade = sec(0.003);
  return buf.map((v, i) => {
    let x = v * g;
    x = Math.tanh(x * 1.2) / Math.tanh(1.2); // 软饱和去数字棱角
    if (i < fade) x *= i / fade;
    if (i > buf.length - fade) x *= (buf.length - i) / fade;
    return x;
  });
}

function wav(buf) {
  const n = buf.length;
  const b = Buffer.alloc(44 + n * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, buf[i])) * 32767), 44 + i * 2);
  return b;
}

/* ── 十枚音效 ──────────────────────────────────────── */
const sounds = {};

/* 底栏切页：一记很轻的笔触点，几乎只有质感没有音高 */
{
  const rand = mulberry32(101);
  const n = sec(0.06);
  sounds['tab-tick'] = master(mix(n,
    paper(rand, n, { hzAt: () => 2100, env: (t) => attack(t, 0.002) * decay(t, 0.012) }),
    thump(rand, n, { f0: 220, f1: 170, tau: 0.014, lpHz: 500 }).map((v) => v * 0.25),
  ), 0.32);
}

/* 拖拽拎起：纸片离面，噪声轻扫上行 */
{
  const rand = mulberry32(102);
  const n = sec(0.1);
  sounds['paper-lift'] = master(
    paper(rand, n, { hzAt: (t) => 900 + 900 * (t / 0.1), env: (t) => attack(t, 0.012) * decay(t, 0.045) }),
    0.34);
}

/* 拖拽落定：轻物落桌——软木面沉一下 + 极短纸擦 */
{
  const rand = mulberry32(103);
  const n = sec(0.16);
  sounds['paper-drop'] = master(mix(n,
    thump(rand, n, { f0: 185, f1: 120, tau: 0.05, lpHz: 620 }),
    paper(rand, n, { hzAt: () => 1500, env: (t) => decay(t, 0.012) }).map((v) => v * 0.4),
    crackle(rand, n, [[0.001, 1]], 0.35),
  ), 0.46);
}

/* pet 跳跳落地：比落桌更软更圆（毯感），跳三次各配一记 */
{
  const rand = mulberry32(104);
  const n = sec(0.09);
  sounds['hop-land'] = master(mix(n,
    thump(rand, n, { f0: 150, f1: 105, tau: 0.036, lpHz: 420, noiseAmt: 0.24 }),
    paper(rand, n, { hzAt: () => 900, env: (t) => decay(t, 0.008) }).map((v) => v * 0.22),
  ), 0.4);
}

/* 开卡：拍立得抽出来——纸滑上行长扫 + 到位小顿 */
{
  const rand = mulberry32(105);
  const n = sec(0.2);
  const slide = paper(rand, n, {
    hzAt: (t) => 800 + 1700 * Math.min(1, t / 0.13),
    env: (t) => attack(t, 0.02) * decay(t, 0.075),
  });
  const settle = new Float64Array(n);
  settle.set(thump(rand, sec(0.06), { f0: 200, f1: 150, tau: 0.02, lpHz: 700 }).map((v) => v * 0.5), sec(0.135));
  sounds['card-open'] = master(mix(n, slide, settle, crackle(rand, n, [[0.004, 0.8], [0.02, 0.5]], 0.3)), 0.44);
}

/* 收卡：反向短扫，更轻 */
{
  const rand = mulberry32(106);
  const n = sec(0.14);
  sounds['card-close'] = master(
    paper(rand, n, { hzAt: (t) => 2100 - 1300 * (t / 0.14), env: (t) => attack(t, 0.008) * decay(t, 0.05) }),
    0.32);
}

/* 掀膜起手：膜面受力微弯，细碎纸脆 + 低幅弯折噪 */
{
  const rand = mulberry32(107);
  const n = sec(0.15);
  sounds['film-curl'] = master(mix(n,
    paper(rand, n, { hzAt: (t) => 1400 + 500 * Math.sin(t * 34), env: (t) => attack(t, 0.01) * decay(t, 0.055) }),
    crackle(rand, n, [[0.008, 1], [0.03, 0.7], [0.062, 0.5], [0.1, 0.35]], 0.5),
  ), 0.34);
}

/* 掀膜翻走：整页掀离的鼓风 + 尾段扑翼颤 + 远处极轻落点 */
{
  const rand = mulberry32(108);
  const n = sec(0.3);
  const whoosh = paper(rand, n, {
    hzAt: (t) => (t < 0.12 ? 700 + 2400 * (t / 0.12) : 3100 - 2100 * ((t - 0.12) / 0.18)),
    width: 0.7,
    env: (t) => attack(t, 0.03) * decay(Math.max(0, t - 0.05), 0.1),
  }).map((v, i) => {
    const t = i / SR; // 尾段 28Hz 扑翼幅调
    return v * (t > 0.16 ? 0.6 + 0.4 * Math.sin(2 * Math.PI * 28 * t) : 1);
  });
  const far = new Float64Array(n);
  far.set(thump(rand, sec(0.05), { f0: 170, f1: 130, tau: 0.018, lpHz: 450 }).map((v) => v * 0.22), sec(0.24));
  sounds['film-fly'] = master(mix(n, whoosh, far), 0.46);
}

/* 滴墨：水滴「叮咚」的哑光版——短击 + 上行小啁啾，重低通压掉电子感 */
{
  const rand = mulberry32(109);
  const n = sec(0.17);
  const chirp = new Float64Array(n);
  const lp = lowpass(1900);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    if (t < 0.012) continue; // 先有一粒击水点
    const u = Math.min(1, (t - 0.012) / 0.05);
    phase += (2 * Math.PI * (520 + 470 * u * u)) / SR;
    chirp[i] = lp(Math.sin(phase)) * decay(t - 0.012, 0.045) * attack(t - 0.012, 0.004);
  }
  sounds['ink-drop'] = master(mix(n,
    crackle(rand, n, [[0.002, 1]], 0.5),
    chirp.map((v) => v * 0.8),
    paper(rand, n, { hzAt: () => 2600, env: (t) => (t > 0.05 ? decay(t - 0.05, 0.03) * 0.1 : 0) }),
  ), 0.36);
}

/* 进入对话：展笺——两段纸滑（展开、抚平），收尾轻定 */
{
  const rand = mulberry32(110);
  const n = sec(0.3);
  const a = paper(rand, n, { hzAt: (t) => 700 + 1200 * Math.min(1, t / 0.09), env: (t) => attack(t, 0.015) * decay(t, 0.05) });
  const b = new Float64Array(n);
  b.set(paper(rand, sec(0.16), { hzAt: (t) => 1200 + 1400 * Math.min(1, t / 0.08), env: (t) => attack(t, 0.012) * decay(t, 0.055) }).map((v) => v * 0.8), sec(0.12));
  const settle = new Float64Array(n);
  settle.set(thump(rand, sec(0.06), { f0: 190, f1: 140, tau: 0.02, lpHz: 600 }).map((v) => v * 0.35), sec(0.23));
  sounds['enter-chat'] = master(mix(n, a, b, settle), 0.42);
}

/* ── 写盘 ──────────────────────────────────────────── */
const sndDir = join(ROOT, 'App/Resources/sounds');
mkdirSync(sndDir, { recursive: true });
for (const [name, buf] of Object.entries(sounds)) {
  writeFileSync(join(sndDir, `${name}.wav`), wav(buf));
  console.log(`sounds/${name}.wav  ${(buf.length / SR).toFixed(2)}s`);
}

/* ── 纸纹 grain.png：256² 值噪声两倍频程，中灰基底 ──
   iOS 侧以 soft-light + 5% 不透明度平铺（对位 Demo .grain） */
{
  const rand = mulberry32(201);
  const N = 256;
  const base = Array.from({ length: 64 * 64 }, () => rand());
  const val = (x, y) => {
    // 双线性采样 64 网格 → 平滑低频
    const gx = (x / N) * 64, gy = (y / N) * 64;
    const x0 = Math.floor(gx) % 64, y0 = Math.floor(gy) % 64;
    const x1 = (x0 + 1) % 64, y1 = (y0 + 1) % 64;
    const fx = gx - Math.floor(gx), fy = gy - Math.floor(gy);
    const a = base[y0 * 64 + x0] * (1 - fx) + base[y0 * 64 + x1] * fx;
    const b = base[y1 * 64 + x0] * (1 - fx) + base[y1 * 64 + x1] * fx;
    return a * (1 - fy) + b * fy;
  };
  const rows = [];
  for (let y = 0; y < N; y++) {
    const row = Buffer.alloc(1 + N * 4);
    for (let x = 0; x < N; x++) {
      const v = 0.6 * rand() + 0.4 * val(x, y); // 高频白噪 + 低频起伏
      const g = Math.round(96 + v * 64); // 中灰域，soft-light 下明暗对称
      row[1 + x * 4] = g; row[2 + x * 4] = g; row[3 + x * 4] = g; row[4 + x * 4] = 255;
    }
    rows.push(row);
  }
  const raw = Buffer.concat(rows);
  const crcTable = Array.from({ length: 256 }, (_, k) => {
    let c = k;
    for (let i = 0; i < 8; i++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const b = Buffer.alloc(12 + data.length);
    b.writeUInt32BE(data.length, 0); b.write(type, 4); data.copy(b, 8);
    b.writeUInt32BE(crc(b.subarray(4, 8 + data.length)), 8 + data.length);
    return b;
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(N, 0); ihdr.writeUInt32BE(N, 4);
  ihdr[8] = 8; ihdr[9] = 6; // 8bit RGBA
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  writeFileSync(join(ROOT, 'App/Resources/assets/grain.png'), png);
  console.log(`assets/grain.png  ${N}x${N}`);
}
