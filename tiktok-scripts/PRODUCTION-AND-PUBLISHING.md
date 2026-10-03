# Production & Publishing Playbook

How to turn these scripts into finished videos and get them onto TikTok and YouTube Shorts, plus how the account actually makes money. Researched October 2026.

---

## 1. The Production Stack

| Job | Recommended tool | Why | Approx. cost |
|---|---|---|---|
| **Character reference sheets** (Skrongle, Steve, Derek, Brenda, Kevin, CEO-Bot, CDO) | Any image model (Midjourney, Gemini image, etc.) | Lock each character's look *before* animating, then feed the sheet into image-to-video for consistency. | Subscription you already have |
| **Video clips (primary)** | **Google Veo 3.1** via the Flow app or the Gemini API | Best prompt adherence, native synced audio (SFX and ambience), vertical output. | API: Fast about $0.10–0.12/sec, Lite about $0.05–0.08/sec, Standard $0.40/sec. Flow has a free daily credit tier. |
| **Video clips (budget / alt)** | **Kling 3.0** | Strong cinematic motion, native audio, cheap starter plan. | Plans from about $6.99/mo. API about $0.084–0.112/sec. |
| **Video clips (max control)** | Runway Gen-4.5 | Fine camera and motion control. No native audio, so add SFX in the edit. | Subscription |
| **Narrator VO** | **Your own voice** (recommended) or a consistent AI voice | YouTube treats a real human voiceover as "authentic value" for monetization (see §4). | Free with a phone mic and a quiet closet |
| **Skrongle's scream** | **Record it yourself** | An original sound you own. Every time someone reuses it on TikTok, it points back to your account. | Free |
| **Edit & captions** | CapCut (TikTok-native) or DaVinci Resolve | Burned-in overlays, beat-synced cuts, 1080×1920 export. | Free tiers |

> ⚠️ **Don't build on Sora.** OpenAI shut down the Sora app in April 2026 and the Sora API on September 24, 2026. Write prompts for Veo or Kling instead. The prompts in these scripts work for both.

### Per-episode workflow
1. **Reference sheets:** generate each character from the script's *Cast & Set Reference Sheet* plus the Global Style Lock in [README](README.md).
2. **Shots:** for every table row, run image-to-video with the row's **PROMPT** plus the character sheet. Veo clips run up to 8 seconds, which matches one row.
3. **Takes:** budget about 3 takes per shot and keep the best one.
4. **VO:** record the whole narration column in one pass, deadpan, with a beat of silence before each punchline.
5. **Assemble:** clips, then VO, then the SFX column, then text overlays. Match the last frame's audio to the first for the loop.
6. **Export:** 1080×1920, 30fps, H.264, -14 LUFS.

### Cost per 45-second episode (API pricing)
- 9 shots × 8s = 72s per full pass. With about 3 takes per shot, that's about 216 generated seconds.
- **Veo 3.1 Fast (1080p):** about $26 per episode · **Veo 3.1 Lite:** about $17 · **Kling 3.0 API (1080p):** about $24
- The Flow and Kling subscription plans can come out cheaper if you generate by hand.

---

## 2. Getting It Onto Your Accounts

### Option A: Upload manually (works today, free)
Post from the TikTok and YouTube apps. Use these settings every time:

**TikTok**
- Turn on the **"AI-generated content" label**. TikTok already detects AI media on its own through C2PA credentials and watermarks, and posts it catches unlabeled can be removed or pushed down.
- Caption: the episode's **CAPTION CTA** plus its hashtags.
- Save Skrongle's scream as an **original sound** so other creators can reuse it.

**YouTube Shorts**
- Audience: **"No, it's not made for kids."** This is critical. Animated videos with child characters and dark themes must never be flagged as kids' content.
- "Altered or synthetic content": YouTube says clearly unrealistic or animated AI content doesn't need this disclosure, but turning it on doesn't limit reach or monetization.
- Title formula: `<punchline> 🥐 #shorts #skronglecore`

### Option B: I schedule posts for you through Metricool (recommended next step)
**Metricool** is available as a Claude connector. It posts to TikTok and YouTube through its own approved API access, so posts go out **public**, which a fresh developer app can't do (see Option C).
1. Connect **Metricool Social Media Management** at claude.ai → Settings → Connectors.
2. Inside Metricool, link your TikTok and YouTube accounts.
3. Give me the finished videos. I'll schedule each one with its caption, hashtags and time slot, and I'll confirm every post with you before it's scheduled.

### Option C: A fully automated pipeline built in this repo
This splits into two parts:

| Part | Status | What's needed |
|---|---|---|
| **Generate clips with Veo and assemble them with ffmpeg** | ✅ Doable in this cloud session. The Gemini API host is reachable and ffmpeg is installed. | Add a Gemini API key as the environment variable `GEMINI_API_KEY` in the environment settings. A new session picks it up. |
| **Upload via your own TikTok or YouTube API app** | ⚠️ Not worth it at first | Both platforms restrict uploads from **unaudited** apps to **private-only** until they pass a compliance audit. YouTube also caps `videos.insert` at a default of 100 calls/day. Use Option B for posting instead. |

Best combination: **Option C for making the videos, Option B for posting them.**

---

## 3. Release Plan

| Week | Mon | Wed | Fri |
|---|---|---|---|
| 1 | Ep 01 "The AC Filter" | Ep 02 "The Distracted Park" | Ep 03 "High Tide" |
| 2 | Ep 04 "Restructuring" | Ep 05 "Release the Croissant" (finale) | **Compilation:** "Skrongle Cinematic Universe" (60s+) |

- Post each episode to **both** TikTok and YouTube Shorts the same day.
- Reply to comments in character as the narrator (deadpan). That keeps the lore going and gets more people commenting.
- The CTAs are written to pull different actions: **comments** (Ep 03 elevation), **tags** (Ep 04), **shares** (Ep 01, Ep 05), **follows** (Ep 02).

---

## 4. How the Money Works

### TikTok Creator Rewards
- Needs **10,000 followers**, **100,000 views in the last 30 days**, age 18+, and original content.
- 🚨 **Only videos 60 seconds or longer earn Rewards.** The 30–45s episodes are for growth and earn $0 from Rewards directly.
- **Fix:** post **60s+ cuts** too, such as double features (Ep 04 + Ep 05 is a natural 90-second "corporate arc") or a "Skrongle Cinematic Universe" supercut.

### YouTube Shorts (Partner Program)
- **Tier 1 (fan funding):** 500 subs, 3 uploads in 90 days, and 3M Shorts views in 90 days.
- **Tier 2 (ad revenue, 45% of Shorts ad revenue):** 1,000 subs and 10M Shorts views in 90 days.
- Reported change on **Feb 1, 2027:** the Tier 2 threshold rises to 20M Shorts views, so it's worth building views before then.

### ⚠️ YouTube's "Inauthentic Content" rule (updated July 2026)
YouTube demonetizes AI content that is **generic, templated and mass-produced with no real creator input**. It also added an **"off-putting or distressing"** category. To stay safe:
- Every episode needs a genuinely different story, jokes and visuals. The 3-act formula is a story structure, not a copy-paste template. Never upload near-duplicate variants.
- **Use your own voice for the narrator.** It's the strongest "human value" signal you can give.
- Keep it **obviously satire**: stylized 3D, cartoon villains, no photoreal children, no gore. Ep 02 is the riskiest episode on this point.

### The bigger money: Skrongle as IP
- **Merch:** print-on-demand Skrongle plush, stickers, "SKRONGLE 💚" protest-sign tees.
- **The sound:** every reuse of the original Skrongle audio advertises the account.
- **Long-form:** stitch the season into a YouTube compilation to earn watch hours toward the 4,000-hour YPP path.
- **Brand deals:** once the account has an audience, Skrongle can "react" to sponsored products in character.

---

## Sources
- [Best AI video generators 2026: Sora 2 vs Veo 3.1 vs Kling 3.0 vs Runway](https://www.getaiperks.com/en/blogs/44-best-ai-video-generators-2026)
- [How to Choose the Best AI Video Generator in 2026 (Kling)](https://kling.ai/blog/best-ai-video-generator-2026-kling-ai)
- [What to know about the Sora discontinuation (OpenAI Help)](https://help.openai.com/en/articles/20001152-what-to-know-about-the-sora-discontinuation)
- [Sora API Shuts Down September 24, 2026](https://twinailabs.com/en/blog/sora-api-shutdown-september-2026)
- [Gemini Developer API pricing](https://ai.google.dev/gemini-api/docs/pricing) · [Veo 3.1 pricing breakdown](https://magichour.ai/blog/veo-3-pricing)
- [Kling AI pricing in 2026](https://www.cloudzero.com/blog/kling-ai-pricing/)
- [TikTok Content Posting API: private-only until audited](https://vorplabs.com/agent-tools/tiktok-content-posting-api) · [TikTok Content Posting API: Direct Post, Audit, Limits](https://www.outstand.so/blog/tiktok-content-posting-api)
- [YouTube Data API: videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert) · [YouTube API quota changes (2026)](https://www.outstand.so/blog/youtube-api-pricing-quota)
- [TikTok AI content rules 2026](https://www.hypelive.io/en/blog/tiktok-ai-content-rules-2026) · [TikTok's AI labeling rules explained](https://storrito.com/resources/tiktoks-2026-ai-labeling-rules-and-what-they-signal-for-platform-governance/)
- [TikTok Creator Rewards Program requirements 2026](https://timetopost.co/blog/tiktok-creator-rewards-requirements-2026/)
- [YouTube Shorts monetization 2026 (vidIQ)](https://vidiq.com/blog/post/youtube-shorts-monetization/) · [YouTube stricter ad eligibility (Tubefilter)](https://www.tubefilter.com/2026/08/10/youtube-partner-program-ad-eligibility-requirements-shorts/)
- [YouTube clarifies policies around AI slop and upsetting videos (TechCrunch)](https://techcrunch.com/2026/07/20/youtube-clarifies-policies-around-ai-slop-and-upsetting-videos/) · [YouTube inauthentic content policy, July 16 2026](https://creatorblade.com/blog/youtube-inauthentic-content-policy-2026-stay-monetized)
- [Metricool: schedule and publish on YouTube](https://help.metricool.com/en/article/schedule-and-publish-on-youtube-btmd1m/) · [Metricool: schedule and post on TikTok](https://help.metricool.com/en/article/schedule-and-post-on-tiktok-pl1qpr/)
