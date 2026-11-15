import asyncio, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from audit import *
async def main():
    out = sys.argv[1]
    async with async_playwright() as p:
        for size in sys.argv[2:] or list(SIZES):
            for name, path in [("91-login", []), ("92-register", ["Đăng ký miễn phí"]), ("93-forgot", ["Quên mật khẩu"]), ("94-onboarding", None)]:
                b, ctx, a = await open_app(p, size, out)   # fresh context: the app remembers the welcome page was seen
                try:
                    if path is None:
                        await a.shot("90-welcome"); await a.click("Bắt đầu ngay", wait=2500)
                        r = await a.shot(name); await a.click("Tiếp tục", wait=2500, must=False); await a.shot(name + "-2")
                    else:
                        await a.click("Đã có tài khoản", wait=2500)
                        for s in path:
                            if not await a.find(s): await a.scroll(400)
                            await a.click(s, wait=2500)
                        r = await a.shot(name); await a.scroll(500); await a.shot(name + "-s1")
                    print(size, name, "ok", len(r["small"]), flush=True)
                except Exception as e: print(size, name, "MISS", str(e)[:80], flush=True)
                await b.close()
asyncio.run(main())
