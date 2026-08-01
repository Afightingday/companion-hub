#!/usr/bin/env node
/* B12 音效 + 纸纹生成器（零依赖，确定性输出）。
   调性口径（docs/08 B12 + 2026-08-01 祐祐试听改向）：
   - 人物弹跳/落地 → 「duang」弹性质感（音高快滑落 + 弹簧颤音，非打击噪声）
   - 纸张翻页族   → 轻柔舒缓治愈（汉宁软包络膨胀 + 极低暖音垫，无任何噪尖）
   - 全局仍忌电子感：重低通、软饱和、不放裸高频
   第一版「破响」病根已除：crackle 高频噪尖删除、thump 逐采样噪声幅调删除、
   带通由单极差分升级为二阶级联（高频裙边 12dB/oct，噪声不再发毛）。
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

/** 带通 = 二阶级联低通差分：裙边 12dB/oct，白噪过完不发毛 */
function bandpass(centerHz, width = 0.6) {
  const lo1 = lowpass(centerHz), lo2 = lowpass(centerHz);
  const hi1 = lowpass(centerHz), hi2 = lowpass(centerHz);
  return (x, hz = centerHz) => {
    const up = hz * (1 + width), dn = hz * (1 - width);
    return lo2(lo1(x, up), up) - hi2(hi1(x, dn), dn);
  };
}

/** 指数衰减包络 */
const decay = (t, tau) => Math.exp(-t / tau);
/** 汉宁窗片段：t∈[t0,t0+T] 内 sin² 起落，外面为 0——软膨胀专用 */
const hann = (t, t0, T) => (t < t0 || t > t0 + T ? 0 : Math.sin((Math.PI * (t - t0)) / T) ** 2);

/** 阻尼低频「实体感」：音高滑落的暗正弦 + 一点二次谐波，无噪声成分 */
function thump(n, { f0, f1, tau, lpHz = 700, h2 = 0.18 }) {
  const out = new Float64Array(n);
  const lp = lowpass(lpHz);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const f = f0 + (f1 - f0) * Math.min(1, t / 0.08);
    phase += (2 * Math.PI * f) / SR;
    const s = Math.sin(phase) + h2 * Math.sin(2 * phase) * decay(t, tau * 0.6);
    out[i] = lp(s) * decay(t, tau) * Math.min(1, t / 0.01);
  }
  return out;
}

/** duang：Q 弹落地——音高快速滑落到基频 + 弹簧频率颤音（衰减的 wobble），
    重低通压亮度，听感是软软的果冻/弹簧，不是鼓点 */
function boing(n, { f0, f1, tau, glideT = 0.035, wobHz = 13, wob = 0.05, wobTau = 0.15, lpHz = 850, h2 = 0.22 }) {
  const out = new Float64Array(n);
  const lp = lowpass(lpHz);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const glide = f1 + (f0 - f1) * Math.exp(-t / glideT);
    const spring = 1 + wob * Math.sin(2 * Math.PI * wobHz * t) * Math.exp(-t / wobTau);
    phase += (2 * Math.PI * glide * spring) / SR;
    const s = Math.sin(phase) + h2 * Math.sin(2 * phase) * decay(t, tau * 0.55);
    out[i] = lp(s) * decay(t, tau) * Math.min(1, t / 0.006);
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

/** 软触点：重低通短噪（指腹碰到纸/桌的那一下），替代已删除的高频噪尖 */
function tap(rand, n, t0, { ms = 16, lpHz = 900, amp = 1 } = {}) {
  const out = new Float64Array(n);
  const lp = lowpass(lpHz);
  const s0 = sec(t0), len = sec(ms / 1000);
  for (let i = 0; i < len && s0 + i < n; i++) {
    const t = i / SR;
    out[s0 + i] = lp(rand() * 2 - 1) * hann(t, 0, ms / 1000) * amp;
  }
  return out;
}

/** 暖音垫：极低幅的暗正弦，给「治愈」一点温度（藏在噪声下面，听不出音高） */
function tone(n, { hz, t0, T, amp, lpHz = 600 }) {
  const out = new Float64Array(n);
  const lp = lowpass(lpHz);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    phase += (2 * Math.PI * hz) / SR;
    out[i] = lp(Math.sin(phase) + 0.25 * Math.sin(2 * phase)) * hann(t, t0, T) * amp;
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

/* ── 十枚音效（文件名与 SoundPlayer.Effect 一一对应，勿改名） ── */
const sounds = {};

/* 底栏切页：一记闷闷的「嗒」，几乎只有质感没有音高 */
{
  const rand = mulberry32(101);
  const n = sec(0.07);
  sounds['tab-tick'] = master(mix(n,
    thump(n, { f0: 240, f1: 190, tau: 0.02, lpHz: 500, h2: 0.15 }),
    paper(rand, n, { hzAt: () => 1100, width: 0.5, env: (t) => hann(t, 0, 0.04) }).map((v) => v * 0.3),
  ), 0.3);
}

/* 拖拽拎起：纸片轻轻离面，一小口软气流 */
{
  const rand = mulberry32(102);
  const n = sec(0.12);
  sounds['paper-lift'] = master(
    paper(rand, n, { hzAt: (t) => 600 + 350 * Math.min(1, t / 0.1), width: 0.5, env: (t) => hann(t, 0, 0.11) }),
    0.32);
}

/* 拖拽落定：深一点的 duang（从手里放下来，比跳跳沉） */
{
  const rand = mulberry32(103);
  const n = sec(0.36);
  sounds['paper-drop'] = master(mix(n,
    boing(n, { f0: 235, f1: 112, tau: 0.11, glideT: 0.04, wobHz: 11.5, wob: 0.05, wobTau: 0.18, lpHz: 780, h2: 0.25 }),
    tap(rand, n, 0.002, { ms: 16, lpHz: 800, amp: 0.3 }),
    paper(rand, n, { hzAt: () => 700, width: 0.5, env: (t) => hann(t, 0, 0.05) }).map((v) => v * 0.15),
  ), 0.46);
}

/* pet 跳跳落地：小 duang——更高更快更轻，三连跳听感 duang-duang-duang */
{
  const rand = mulberry32(104);
  const n = sec(0.3);
  sounds['hop-land'] = master(mix(n,
    boing(n, { f0: 285, f1: 150, tau: 0.085, glideT: 0.03, wobHz: 13.5, wob: 0.06, wobTau: 0.15, lpHz: 900, h2: 0.22 }),
    tap(rand, n, 0.001, { ms: 12, lpHz: 900, amp: 0.22 }),
  ), 0.42);
}

/* 开卡：拍立得轻轻递到面前——软膨胀上行 + 收尾抚平 + 暖垫 */
{
  const rand = mulberry32(105);
  const n = sec(0.4);
  const settle = new Float64Array(n);
  settle.set(thump(sec(0.06), { f0: 190, f1: 150, tau: 0.025, lpHz: 550 }).map((v) => v * 0.22), sec(0.28));
  sounds['card-open'] = master(mix(n,
    paper(rand, n, { hzAt: (t) => 520 + 520 * Math.min(1, t / 0.18), width: 0.5, env: (t) => hann(t, 0, 0.22) }),
    paper(rand, n, { hzAt: (t) => 900 - 380 * Math.min(1, Math.max(0, t - 0.16) / 0.2), width: 0.5, env: (t) => hann(t, 0.16, 0.2) }).map((v) => v * 0.55),
    tone(n, { hz: 170, t0: 0.02, T: 0.28, amp: 0.1 }),
    settle,
  ), 0.42);
}

/* 收卡：一口软气流放下去，更轻更暗 */
{
  const rand = mulberry32(106);
  const n = sec(0.26);
  sounds['card-close'] = master(
    paper(rand, n, { hzAt: (t) => 950 - 450 * (t / 0.26), width: 0.5, env: (t) => hann(t, 0, 0.24) }),
    0.3);
}

/* 掀膜起手：指腹搭上膜面的一口气，若有若无 */
{
  const rand = mulberry32(107);
  const n = sec(0.24);
  sounds['film-curl'] = master(mix(n,
    paper(rand, n, { hzAt: (t) => 480 + 280 * Math.min(1, t / 0.2), width: 0.45, env: (t) => hann(t, 0, 0.22) }),
    tone(n, { hz: 240, t0: 0, T: 0.18, amp: 0.06 }),
  ), 0.3);
}

/* 掀膜翻走：治愈系翻页——抬起软膨胀、放走软收束、远处极轻落定，无扑翼颤 */
{
  const rand = mulberry32(108);
  const n = sec(0.5);
  const lift = paper(rand, n, { hzAt: (t) => 430 + 420 * Math.min(1, t / 0.18), width: 0.55, env: (t) => hann(t, 0, 0.18) });
  const release = paper(rand, n, { hzAt: (t) => 880 - 480 * Math.min(1, Math.max(0, t - 0.15) / 0.3), width: 0.6, env: (t) => hann(t, 0.15, 0.3) }).map((v) => v * 0.9);
  const warm = tone(n, { hz: 205, t0: 0.06, T: 0.3, amp: 0.11 });
  const far = new Float64Array(n);
  far.set(thump(sec(0.08), { f0: 165, f1: 125, tau: 0.03, lpHz: 380 }).map((v) => v * 0.2), sec(0.36));
  sounds['film-fly'] = master(mix(n, lift, release, warm, far), 0.44);
}

/* 滴墨：水滴的哑光版——软触点 + 上行小啁啾，重低通，很轻 */
{
  const rand = mulberry32(109);
  const n = sec(0.18);
  const chirp = new Float64Array(n);
  const lp = lowpass(1500);
  let phase = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    if (t < 0.012) continue;
    const u = Math.min(1, (t - 0.012) / 0.05);
    phase += (2 * Math.PI * (500 + 430 * u * u)) / SR;
    chirp[i] = lp(Math.sin(phase)) * decay(t - 0.012, 0.05) * Math.min(1, (t - 0.012) / 0.004);
  }
  sounds['ink-drop'] = master(mix(n,
    tap(rand, n, 0.002, { ms: 8, lpHz: 1200, amp: 0.5 }),
    chirp.map((v) => v * 0.75),
    paper(rand, n, { hzAt: () => 2000, width: 0.5, env: (t) => hann(t, 0.06, 0.08) }).map((v) => v * 0.08),
  ), 0.32);
}

/* 进入对话：展笺——两段软膨胀慢慢展开 + 暖垫 + 收尾轻定 */
{
  const rand = mulberry32(110);
  const n = sec(0.5);
  const a = paper(rand, n, { hzAt: (t) => 480 + 500 * Math.min(1, t / 0.18), width: 0.5, env: (t) => hann(t, 0, 0.22) });
  const b = paper(rand, n, { hzAt: (t) => 820 - 370 * Math.min(1, Math.max(0, t - 0.18) / 0.26), width: 0.55, env: (t) => hann(t, 0.18, 0.26) }).map((v) => v * 0.7);
  const warm = tone(n, { hz: 195, t0: 0.05, T: 0.34, amp: 0.12 });
  const settle = new Float64Array(n);
  settle.set(thump(sec(0.07), { f0: 175, f1: 135, tau: 0.028, lpHz: 500 }).map((v) => v * 0.25), sec(0.34));
  sounds['enter-chat'] = master(mix(n, a, b, warm, settle), 0.42);
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
