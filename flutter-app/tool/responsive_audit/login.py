"""Log in once at 390px and save the session for crawl.py. AUDIT_EMAIL / AUDIT_PASSWORD from the environment."""
import asyncio, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from audit import *

async def main():
    out = sys.argv[1]
    async with async_playwright() as p:
        b, ctx, a = await open_app(p, "390", out)
        await a.click("Đã có tài khoản")
        # The text fields carry no semantics label; these are their centres at 390x844.
        await a.page.mouse.click(195, 462); await a.page.keyboard.type(os.environ["AUDIT_EMAIL"], delay=10)
        await a.page.mouse.click(190, 556); await a.page.keyboard.type(os.environ["AUDIT_PASSWORD"], delay=10)
        await a.page.mouse.click(195, 668); await a.page.wait_for_timeout(8000)
        if not await a.find("^Khám phá"): raise SystemExit("login failed: Home never appeared")
        await ctx.storage_state(path=f"{out}/../state.json")
        await b.close()
asyncio.run(main())
