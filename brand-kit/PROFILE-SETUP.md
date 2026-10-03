# END OF FEED: Profile Setup Kit

Everything needed to stand up the TikTok and YouTube pages. The assets are in [`out/`](out/).

| Asset | File | Use |
|---|---|---|
| Profile picture (both platforms) | [`out/avatar.png`](out/avatar.png) · 1080×1080 | TikTok profile photo, YouTube channel picture |
| YouTube banner | [`out/banner.png`](out/banner.png) · 2560×1440 | YouTube → Customize channel → Branding → Banner image. Text stays inside the 1546×423 mobile safe area. |
| Teaser / first post | [`out/teaser.mp4`](out/teaser.mp4) · 20s · 1080×1920 | First post on both platforms. 100% code-animated, so no AI disclosure is needed. |

## Name & Handles

- **Display name:** END OF FEED
- **Handle candidates, in order:** `@endoffeed` → `@endoffeed.tv` → `@theendoffeed` → `@skronglecore` → `@endoffeedtv`
  Use the same handle on both platforms if you can. To rebrand, run `node brand-kit/render-stills.mjs "NEW NAME"` and `python3 brand-kit/build-teaser.py "NEW NAME"` to regenerate every asset with the new name.

## Bios

**TikTok bio** (80 char max, this is 65):
```
the world is ending. the feed keeps going. 🥐 new eps mon/wed/fri
```

**YouTube channel description:**
```
The world is ending. The feed keeps going.

END OF FEED is a dark-satire animated series about a society collapsing in real time (toxic air, rising seas, robot layoffs, corporate cover-ups) while everyone, victims and villains alike, keeps scrolling.

Featuring SKRONGLE 🥐, the internet's most dangerous croissant.

New episodes every Monday, Wednesday and Friday.

All characters and companies are fictional. OmniCorp™ is not a real company (yet).
Written by a human. Animated with a lot of help.
```

## Teaser Post Copy

- **TikTok caption:** `this is a public service announcement from OmniCorp™. please continue scrolling. 🥐 #skronglecore #darkhumor #satire #animation #fyp`
- **YouTube Short title:** `OmniCorp™ would like you to keep scrolling 🥐 #shorts`
- **YouTube settings:** Made for kids = **No** · Category = Film & Animation · Altered/synthetic = No (hand-coded animation)

## Setup Steps Only You Can Do (about 10 minutes)

1. **TikTok:** in the TikTok app, sign up. Pick a handle from the list, then add the avatar and bio.
   - Keep it a **Personal** account, not Business. Creator Rewards is only for personal accounts, and Business accounts lose most trending sounds.
2. **YouTube:** on youtube.com, open your profile and choose **Create a channel**. Enter the name and handle, then upload the avatar, banner and description.
3. **Link both to Metricool:** open https://app.metricool.com/brands/connections?blogId=7223965 and connect **TikTok** and **YouTube**. Each one sends you to the platform's own sign-in page, where you click **Allow**.
4. Tell Claude "linked." Claude schedules the teaser to both platforms and builds out the posting calendar.

> 🔐 Never paste a password into a chat. Every connection above uses the platform's own sign-in and "Allow" screen, so passwords are never shared with anyone.
