import asyncio, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from audit import *
SCREENS=[("90-welcome",[]),("91-login",["Đã có tài khoản"]),("92-register",["Đã có tài khoản","Đăng ký miễn phí"]),("93-forgot",["Đã có tài khoản","Quên mật khẩu"]),("94-onboarding",["Bắt đầu ngay"])]
async def main():
    out=sys.argv[1]
    async with async_playwright() as p:
        for size in SIZES:
            b, ctx, a = await open_app(p, size, out)
            for name, path in SCREENS:
                try:
                    await a.page.goto("http://localhost:8080/"); await a.page.wait_for_timeout(6000)
                    for s in path: await a.click(s, wait=2200)
                    r=await a.shot(name); print(size,name,"ok",len(r["small"]),flush=True)
                except Exception as e: print(size,name,"MISS",str(e)[:80],flush=True)
            await b.close()
asyncio.run(main())
