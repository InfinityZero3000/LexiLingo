"""Drive the Flutter web build through its semantics tree; shots + metrics per screen."""
import asyncio, json, re, sys
from playwright.async_api import async_playwright

SIZES = {"390": (390, 844), "768": (768, 1024), "1440": (1440, 900)}
JS_NODES = """() => [...document.querySelectorAll('flt-semantics')].map(e => {
  const b = e.getBoundingClientRect();
  const own = [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('');
  return {role: e.getAttribute('role'), label: (e.getAttribute('aria-label') || own || '').trim(),
          tappable: e.hasAttribute('flt-tappable'), x: Math.round(b.x), y: Math.round(b.y),
          w: Math.round(b.width), h: Math.round(b.height),
          scroll: getComputedStyle(e).overflowX === 'scroll' || getComputedStyle(e).overflowX === 'auto' ? e.scrollWidth - e.clientWidth : 0};
}).filter(n => n.w > 0 && n.h > 0)"""

class App:
    def __init__(self, page, size, out):
        self.page, self.size, self.out = page, size, out
        self.w, self.h = SIZES[size]
    async def nodes(self):
        if self.w >= 840:
            await self.page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
        elif not await self.page.evaluate("document.querySelectorAll('flt-semantics').length"):
            # On a phone the placeholder covers the screen and only a touch at its centre enables semantics.
            for _ in range(3):
                await self.page.touchscreen.tap(self.w / 2, self.h / 2); await self.page.wait_for_timeout(700)
                if await self.page.evaluate("document.querySelectorAll('flt-semantics').length"): break
        await self.page.wait_for_timeout(350)
        return await self.page.evaluate(JS_NODES)
    async def find(self, label, role=None, nth=0):
        hits = [n for n in await self.nodes() if re.search(label, n["label"], re.I) and (role is None or n["role"] == role)
                and 0 <= n["y"] < self.h and n["x"] < self.w]
        hits.sort(key=lambda n: n["w"] * n["h"])
        return hits[nth] if len(hits) > nth else None
    async def click(self, label, role=None, nth=0, wait=1500, must=True):
        n = await self.find(label, role, nth)
        if not n:
            if must: raise RuntimeError(f"[{self.size}] no node for {label!r}")
            return False
        if self.w < 840 and n["y"] + n["h"] / 2 > self.h - 80:  # under the bottom bar
            await self.scroll(320); n = await self.find(label, role, nth) or n
        await self.page.mouse.click(n["x"] + n["w"] / 2, n["y"] + n["h"] / 2)
        await self.page.wait_for_timeout(wait)
        return True
    async def type(self, label, text):
        await self.click(label, wait=300)
        await self.page.keyboard.type(text, delay=15)
    async def back(self, wait=1200):
        await self.page.go_back(); await self.page.wait_for_timeout(wait)
    async def scroll(self, dy=700):
        await self.page.mouse.move(self.w / 2, self.h / 2); await self.page.mouse.wheel(0, dy)
        await self.page.wait_for_timeout(700)
    async def shot(self, name, wait=600):
        await self.page.wait_for_timeout(wait)
        await self.page.screenshot(path=f"{self.out}/{name}-{self.size}.png")
        ns = await self.nodes()
        vis = [n for n in ns if n["y"] < self.h and n["y"] + n["h"] > 0]
        small = [n for n in vis if (n["tappable"] or n["role"] in ("button", "link", "tab", "checkbox", "switch", "radio", "textbox"))
                 and (n["w"] < 44 or n["h"] < 44) and n["x"] >= 0 and n["x"] < self.w]
        over = [n for n in vis if n["x"] + n["w"] > self.w + 1 and n["w"] <= self.w * 3 and n["x"] < self.w]
        hscroll = [n for n in vis if n["scroll"] > 4]
        doc = await self.page.evaluate("[document.documentElement.scrollWidth, document.documentElement.clientWidth]")
        rec = {"screen": name, "size": self.size, "page_hscroll": doc[0] > doc[1],
               "small": [(n["label"][:40] or n["role"], n["w"], n["h"], n["x"], n["y"]) for n in small],
               "overflow_right": [(n["label"][:40] or n["role"], n["x"], n["w"]) for n in over],
               "hscroll_areas": [(n["label"][:40] or n["role"], n["w"], n["scroll"]) for n in hscroll]}
        with open(f"{self.out}/metrics.jsonl", "a") as f: f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        return rec
    async def dump(self, limit=80):
        for n in (await self.nodes()):
            if n["label"] or n["role"] in ("button", "textbox", "tab"):
                if 0 <= n["y"] < self.h: print(f'  {n["role"] or "-":8} {n["w"]:>4}x{n["h"]:<4} @{n["x"]},{n["y"]}  {n["label"][:70]!r}{" T" if n["tappable"] else ""}')

async def open_app(p, size, out, storage=None):
    b = await p.chromium.launch(channel="chrome")
    w, h = SIZES[size]
    touch = {} if w >= 840 else {"has_touch": True, "is_mobile": True, "user_agent":
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"}
    ctx = await b.new_context(viewport={"width": w, "height": h}, storage_state=storage, locale="vi-VN", **touch)
    if touch:  # Flutter picks its platform from navigator.platform, which a UA override leaves alone
        await ctx.add_init_script("Object.defineProperty(navigator, 'platform', {get: () => 'iPhone'})")
    page = await ctx.new_page()
    page.on("console", lambda m: print("  console.error:", m.text[:160]) if m.type == "error" and "overflow" in m.text.lower() else None)
    await page.goto("http://localhost:8080/"); await page.wait_for_timeout(8000)
    return b, ctx, App(page, size, out)


async def ensure_login(a):
    """Log in when the app opens on the welcome or login page. AUDIT_EMAIL / AUDIT_PASSWORD."""
    import os
    if await a.find("^Khám phá"): return
    await a.click("Đã có tài khoản", must=False)
    forgot = await a.find("Quên mật khẩu")
    eye = min((n for n in await a.nodes() if n["role"] == "button" and not n["label"] and abs(n["y"] - forgot["y"]) < 120 and n["y"] > forgot["y"]),
              key=lambda n: n["y"])
    y = eye["y"] + eye["h"] / 2
    await a.page.mouse.click(a.w / 2 - 20, y - 94); await a.page.keyboard.type(os.environ["AUDIT_EMAIL"], delay=10)
    await a.page.mouse.click(a.w / 2 - 20, y); await a.page.keyboard.type(os.environ["AUDIT_PASSWORD"], delay=10)
    await a.page.keyboard.press("Enter"); await a.page.wait_for_timeout(1500)
    if not await a.find("^Khám phá"):
        await a.click("^Đăng nhập$", wait=8000, must=False)
    if not await a.find("^Khám phá"): raise SystemExit("login failed: Home never appeared")
