// Renders a GUI snapshot (from play.luau) to PNG, following Roblox's layout rules:
// UDim2 sizes/positions, AnchorPoint, UIPadding, UIListLayout, UIGridLayout,
// ScrollingFrame canvas, UIStroke (border mode), ZIndex (sibling), RichText <font color>.
// Fonts: Enum.Font.Arcade is Press Start 2P and Enum.Font.Code is Inconsolata in Roblox.
//
// Usage: node render.mjs <snapshot.json> <out.png> [width=1280] [height=720]

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const [, , input, output, W = '1280', H = '720'] = process.argv;
const VIEW = { w: Number(W), h: Number(H) };
const tree = JSON.parse(fs.readFileSync(input, 'utf8'));
// Lune encodes empty tables as {}.
(function normalize(node) {
  node.children = Array.isArray(node.children) ? node.children : Object.values(node.children || {});
  node.children.forEach(normalize);
})(tree);

const GUI = new Set(['Frame', 'TextLabel', 'TextButton', 'ScrollingFrame', 'ImageLabel', 'ImageButton', 'TextBox']);
const DEFAULT = {
  Size: { xs: 0, xo: 100, ys: 0, yo: 100 },
  Position: { xs: 0, xo: 0, ys: 0, yo: 0 },
  AnchorPoint: { x: 0, y: 0 },
  BackgroundColor3: 'a3a2a5',
  BackgroundTransparency: 0,
  BorderSizePixel: 1,
  BorderColor3: '1b2a35',
  Visible: true,
  ZIndex: 1,
  LayoutOrder: 0,
  TextSize: 14,
  TextColor3: '000000',
  TextXAlignment: 'Center',
  TextYAlignment: 'Center',
  ScrollBarThickness: 12,
};
const LABEL_SIZE = { xs: 0, xo: 200, ys: 0, yo: 50 };

function prop(node, key) {
  const v = node.props[key];
  if (v === undefined || v === null) {
    if (key === 'Size' && (node.class === 'TextLabel' || node.class === 'TextButton')) return LABEL_SIZE;
    return DEFAULT[key];
  }
  if (typeof v === 'object') {
    if (v.t === 'Color3') return v.hex;
    if (v.t === 'Enum') return v.name;
  }
  return v;
}

const findChild = (node, cls) => node.children.find((c) => c.class === cls);
const udim = (u, total) => (u ? u.s * total + u.o : 0);

function rgba(hex, transparency = 0) {
  const n = parseInt(hex, 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${1 - transparency})`;
}

function contentBox(node, rect) {
  const pad = findChild(node, 'UIPadding');
  if (!pad) return { ...rect };
  const l = udim(pad.props.PaddingLeft, rect.w), r = udim(pad.props.PaddingRight, rect.w);
  const t = udim(pad.props.PaddingTop, rect.h), b = udim(pad.props.PaddingBottom, rect.h);
  return { x: rect.x + l, y: rect.y + t, w: rect.w - l - r, h: rect.h - t - b };
}

function sizeIn(node, box) {
  const s = prop(node, 'Size');
  return { w: s.xs * box.w + s.xo, h: s.ys * box.h + s.yo };
}

// Absolute rects for the GUI children of `node`, laid out inside `box`.
function place(node, box) {
  const kids = node.children.filter((c) => GUI.has(c.class) && prop(c, 'Visible') !== false);
  const list = findChild(node, 'UIListLayout');
  const grid = findChild(node, 'UIGridLayout');
  const sorted = [...kids].sort((a, b) => prop(a, 'LayoutOrder') - prop(b, 'LayoutOrder') || a.order - b.order);
  const out = new Map();
  if (list) {
    const horizontal = prop(list, 'FillDirection') === 'Horizontal';
    const gap = udim(list.props.Padding, horizontal ? box.w : box.h);
    let cursor = horizontal ? box.x : box.y;
    for (const c of sorted) {
      const size = sizeIn(c, box);
      out.set(c, horizontal ? { x: cursor, y: box.y, ...size } : { x: box.x, y: cursor, ...size });
      cursor += (horizontal ? size.w : size.h) + gap;
    }
  } else if (grid) {
    const cs = grid.props.CellSize, cp = grid.props.CellPadding || { xs: 0, xo: 5, ys: 0, yo: 5 };
    const cw = cs.xs * box.w + cs.xo, ch = cs.ys * box.h + cs.yo;
    const px = cp.xs * box.w + cp.xo, py = cp.ys * box.h + cp.yo;
    let x = box.x, y = box.y;
    for (const c of sorted) {
      if (x > box.x && x + cw > box.x + box.w + 0.5) { x = box.x; y += ch + py; }
      out.set(c, { x, y, w: cw, h: ch });
      x += cw + px;
    }
  } else {
    for (const c of kids) {
      const size = sizeIn(c, box);
      const p = prop(c, 'Position'), a = prop(c, 'AnchorPoint');
      out.set(c, {
        x: box.x + p.xs * box.w + p.xo - a.x * size.w,
        y: box.y + p.ys * box.h + p.yo - a.y * size.h,
        ...size,
      });
    }
  }
  return { kids, rects: out };
}

const FONTS = { Arcade: "'P2P'", Code: "'Inconsolata'" };

function richText(text, rich) {
  const escaped = text.replace(/&/g, '&amp;');
  if (!rich) return escaped.replace(/</g, '&lt;');
  return escaped
    .replace(/<font color="(#[0-9a-fA-F]{6})">/g, '<span style="color:$1">')
    .replace(/<\/font>/g, '</span>');
}

function renderNode(node, rect, parentRect) {
  const style = [
    `left:${rect.x - parentRect.x}px`, `top:${rect.y - parentRect.y}px`,
    `width:${rect.w}px`, `height:${rect.h}px`, `z-index:${prop(node, 'ZIndex')}`,
  ];
  const bgT = prop(node, 'BackgroundTransparency');
  if (bgT < 1) style.push(`background:${rgba(prop(node, 'BackgroundColor3'), bgT)}`);
  const shadows = [];
  const stroke = findChild(node, 'UIStroke');
  if (stroke && stroke.props.Enabled !== false) {
    shadows.push(`0 0 0 ${stroke.props.Thickness ?? 1}px ${rgba(stroke.props.Color?.hex ?? '000000', stroke.props.Transparency ?? 0)}`);
  }
  const border = prop(node, 'BorderSizePixel');
  if (border > 0 && bgT < 1) shadows.push(`0 0 0 ${border}px ${rgba(prop(node, 'BorderColor3'), bgT)}`);
  if (shadows.length) style.push(`box-shadow:${shadows.join(',')}`);
  if (node.props.ClipsDescendants || node.class === 'ScrollingFrame') style.push('overflow:hidden');

  let inner = '';
  const box = contentBox(node, rect);

  if ((node.class === 'TextLabel' || node.class === 'TextButton') && node.props.Text) {
    const x = prop(node, 'TextXAlignment'), y = prop(node, 'TextYAlignment');
    const wrapped = !!node.props.TextWrapped;
    const textStyle = [
      `left:${box.x - rect.x}px`, `top:${box.y - rect.y}px`, `width:${box.w}px`, `height:${box.h}px`,
      'display:flex', `flex-direction:column`,
      `justify-content:${y === 'Top' ? 'flex-start' : y === 'Bottom' ? 'flex-end' : 'center'}`,
      `align-items:${x === 'Left' ? 'flex-start' : x === 'Right' ? 'flex-end' : 'center'}`,
      `text-align:${x === 'Left' ? 'left' : x === 'Right' ? 'right' : 'center'}`,
      `font-family:${FONTS[prop(node, 'Font')] ?? "'Inconsolata'"},'Noto Color Emoji'`,
      `font-size:${prop(node, 'TextSize')}px`, 'line-height:1.05',
      `color:${rgba(prop(node, 'TextColor3'), node.props.TextTransparency ?? 0)}`,
      `white-space:${wrapped ? 'pre-wrap' : 'pre'}`,
    ];
    inner += `<div class="t" style="${textStyle.join(';')}"><span style="flex-shrink:0;max-width:${wrapped ? box.w + 'px' : 'none'}">${richText(node.props.Text, node.props.RichText)}</span></div>`;
  }

  // Children (scrolling frames lay out on their canvas).
  let childBox = box;
  if (node.class === 'ScrollingFrame') {
    const cp = node.props.CanvasPosition || { x: 0, y: 0 };
    childBox = { ...box, x: box.x - cp.x, y: box.y - cp.y };
    const first = place(node, childBox);
    let bottom = 0;
    for (const r of first.rects.values()) bottom = Math.max(bottom, r.y + r.h - childBox.y);
    if (bottom > box.h) {
      const bar = prop(node, 'ScrollBarThickness');
      childBox = { ...childBox, w: childBox.w - bar };
      const barColor = node.props.ScrollBarImageColor3?.hex ?? '000000';
      const thumbH = Math.max(20, (box.h / bottom) * box.h);
      inner += `<div style="position:absolute;right:0;top:${(cp.y / bottom) * box.h}px;width:${bar}px;height:${thumbH}px;background:#${barColor};z-index:999"></div>`;
    }
  }
  inner += renderChildren(node, childBox, rect);
  return `<div class="g" data-name="${node.props.Name ?? ''}" style="${style.join(';')}">${inner}</div>`;
}

function renderChildren(node, box, ownRect) {
  const { kids, rects } = place(node, box);
  return kids.map((c) => renderNode(c, rects.get(c), ownRect)).join('');
}

const root = { x: 0, y: 0, w: VIEW.w, h: VIEW.h };
const body = renderChildren(tree, root, root);
const font = (pkg, file) => `file://${here}/node_modules/@fontsource/${pkg}/files/${file}`;
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:P2P;src:url(${font('press-start-2p', 'press-start-2p-latin-400-normal.woff2')})}
@font-face{font-family:Inconsolata;src:url(${font('inconsolata', 'inconsolata-latin-400-normal.woff2')})}
*{box-sizing:border-box;margin:0;padding:0}
body{width:${VIEW.w}px;height:${VIEW.h}px;position:relative;overflow:hidden;background:#000}
.g,.t{position:absolute}
</style></head><body>${body}</body></html>`;

const htmlPath = output.replace(/\.png$/, '.html');
fs.writeFileSync(htmlPath, html);
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
const page = await browser.newPage({ viewport: { width: VIEW.w, height: VIEW.h }, deviceScaleFactor: 1.5 });
await page.goto(`file://${path.resolve(htmlPath)}`);
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: output });
await browser.close();
console.log(`rendered ${output}`);
