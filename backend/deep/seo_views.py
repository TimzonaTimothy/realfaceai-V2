"""robots.txt, sitemap.xml and llms.txt for search engines and AI crawlers."""
from django.http import HttpResponse
from django.views.decorators.cache import cache_page

SITE = "https://realfaceai.app"
PAGES = [  # (path, changefreq, priority)
    ("/", "weekly", "1.0"),
    ("/download/", "weekly", "0.9"),
    ("/consent/", "yearly", "0.4"),
    ("/privacy/", "yearly", "0.3"),
    ("/terms/", "yearly", "0.3"),
]
LASTMOD = "2026-10-23"  # bump when page content changes


@cache_page(60 * 60 * 24)
def robots_txt(request):
    lines = [
        "User-agent: *",
        "Allow: /",
        "Disallow: /admin/",
        "Disallow: /api/",
        "Disallow: /download/file/",
        "",
        # AI search / answer engines: explicitly welcome
        *[f"User-agent: {b}\nAllow: /\nDisallow: /admin/\nDisallow: /api/\n" for b in (
            "GPTBot", "OAI-SearchBot", "ChatGPT-User", "ClaudeBot", "Claude-SearchBot", "Claude-User",
            "PerplexityBot", "Perplexity-User", "Google-Extended", "Applebot-Extended", "Bingbot")],
        f"Sitemap: {SITE}/sitemap.xml",
    ]
    return HttpResponse("\n".join(lines) + "\n", content_type="text/plain")


@cache_page(60 * 60 * 24)
def sitemap_xml(request):
    urls = "".join(
        f"<url><loc>{SITE}{p}</loc><lastmod>{LASTMOD}</lastmod><changefreq>{f}</changefreq><priority>{pr}</priority></url>"
        for p, f, pr in PAGES)
    xml = f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>'
    return HttpResponse(xml, content_type="application/xml")


LLMS = """# RealFaceAI

> RealFaceAI is a desktop app (macOS and Windows) for real-time AI face swap on live video calls and streams. It swaps your face onto a consented character in real time and runs locally on your computer, so video frames are not uploaded to the cloud.

## Key facts
- Works with any app that can pick a camera: Zoom, Google Meet, Microsoft Teams, Discord, Slack Huddles, OBS Studio and browsers.
- Platforms: macOS 13 Ventura or later (Apple Silicon and Intel), Windows 10/11 64-bit with a DirectX 12 GPU. 8 GB RAM minimum.
- Pricing: pay-as-you-go credits, not a subscription. One credit is about one second of live streaming. Credits never expire. Free to try, no credit card.
- Payments in the app with USDT / USDC on BSC and Solana.
- Consent: you may only use your own face, a fictional character, or a real adult who gave explicit consent. Minors are never allowed.
- Support: support@realfaceai.app

## Pages
- [Home](https://realfaceai.app/): product overview, features, pricing, FAQ
- [Download & install guide](https://realfaceai.app/download/): macOS .dmg and Windows .exe, macOS Gatekeeper fix, OBS Browser Source setup
- [Consent Policy](https://realfaceai.app/consent/)
- [Privacy Policy](https://realfaceai.app/privacy/)
- [Terms of Use](https://realfaceai.app/terms/)

## Common questions
- macOS blocks the app on first launch: right-click the app in Applications > Open > Open, or on macOS 15+ use System Settings > Privacy & Security > Open Anyway, or run `xattr -dr com.apple.quarantine /Applications/RealFaceAI.app` in Terminal.
- OBS: add a Browser Source pointing at the local popout URL shown in the app (e.g. http://127.0.0.1:8700/popout; port may differ), sized to your stream resolution, e.g. 1920x1080.
"""


@cache_page(60 * 60 * 24)
def llms_txt(request):
    return HttpResponse(LLMS, content_type="text/plain; charset=utf-8")
