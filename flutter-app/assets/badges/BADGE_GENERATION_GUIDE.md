# Badge Generation Guide for LexiLingo

## Tổng quan

LexiLingo cần 26 badge icons cho hệ thống achievements. Có nhiều cách để tạo:

## Cách 1: Sử dụng AI Image Generation (Recommended)

### Prompt templates cho từng category:

#### Streak Badges (Fire/Flame theme)
```
A beautiful gaming achievement badge, shield shape, fire and flame theme, 
[RARITY] border glow, number "[DAYS]" in center, gradient orange to red,
game UI style, 3D render, transparent background, 256x256px
```

- 3 days: common (gray border)
- 7 days: rare (blue border)
- 30 days: epic (purple border)
- 365 days: legendary (gold border, extra glow)

#### Lesson Badges (Book/Education theme)
```
A beautiful gaming achievement badge, circular shape, book and education theme,
[RARITY] glow effect, scholarly design, gradient green,
game achievement icon style, 3D render, transparent background, 256x256px
```

#### Vocabulary Badges (Dictionary/Words theme)
```
A beautiful gaming achievement badge, hexagon shape, dictionary and letters theme,
[RARITY] border, "ABC" symbols, gradient cyan to blue,
game UI achievement style, 3D render, transparent background, 256x256px
```

#### XP Badges (Star/Energy theme)
```
A beautiful gaming achievement badge, star shape, golden star and sparkle theme,
[RARITY] glow, energy particles, gradient gold to orange,
game achievement icon style, 3D render, transparent background, 256x256px
```

#### Voice Badges (Microphone theme)
```
A beautiful gaming achievement badge, shield shape, microphone and sound waves theme,
[RARITY] border glow, audio visualization, gradient purple to pink,
game UI style, 3D render, transparent background, 256x256px
```

### Tools để generate:
- Midjourney: /imagine [prompt] --ar 1:1 --style raw
- DALL-E 3: Use the prompts above
- Stable Diffusion: với model game-icon-institute

## Cách 2: Sử dụng Free Badge Makers Online

### Websites:
1. **Canva** (canva.com/create/badges)
   - Free templates cho badges
   - Export as PNG với transparent background

2. **Placeit** (placeit.net)
   - Gaming badge templates
   - Customizable colors và text

3. **Fotor** (fotor.com/design/badge)
   - Badge generator với nhiều styles

4. **Adobe Express** (express.adobe.com)
   - Free badge templates

## Cách 3: Icon Packs (Nhanh nhất)

### Recommended packs:
1. **Flaticon** - Search "achievement badge", "game badge"
   - https://www.flaticon.com/search?word=achievement%20badge
   
2. **Icons8** - Gaming icons
   - https://icons8.com/icons/set/achievement

3. **Game-icons.net** (Free, CC BY 3.0)
   - https://game-icons.net/
   - SVG format, có thể colorize

## Cách 4: SVG Badge Library (Cho developers)

Tạo file SVG và dùng `flutter_svg` package:

```yaml
dependencies:
  flutter_svg: ^2.0.9
```

### Folder structure:
```
assets/
  badges/
    svg/
      streak_common.svg
      streak_rare.svg
      lesson_common.svg
      ...
    png/
      streak_3days.png
      streak_7days.png
      ...
```

## Cách 5: Sử dụng Badge Generator đã tạo

File `lib/core/widgets/badge_generator.dart` tự động tạo badges đẹp với:
- 8 shapes: Circle, Shield, Star, Hexagon, Medal, Diamond, Ribbon, Banner
- 4 rarity levels: Common, Rare, Epic, Legendary
- Glow effects cho Epic/Legendary
- Shine animation

Không cần image files, hoàn toàn code-generated!

## Badge Specs

| Achievement | Category | Shape | Rarity | Primary Color |
|------------|----------|-------|--------|---------------|
| First Steps | lessons | circle | common | #4CAF50 |
| Dedicated Learner | lessons | circle | common | #8BC34A |
| Knowledge Seeker | lessons | circle | rare | #009688 |
| Scholar | lessons | circle | epic | #673AB7 |
| Professor | lessons | circle | legendary | #FFD700 |
| Getting Started | streak | shield | common | #FF9800 |
| Week Warrior | streak | shield | rare | #FF5722 |
| Two Weeks Strong | streak | shield | rare | #E91E63 |
| Month Master | streak | shield | epic | #9C27B0 |
| Quarterly Champion | streak | shield | legendary | #3F51B5 |
| Year Legend | streak | shield | legendary | #FFD700 |
| Word Collector | vocabulary | hexagon | common | #00BCD4 |
| Vocab Builder | vocabulary | hexagon | rare | #03A9F4 |
| Vocab Master | vocabulary | hexagon | epic | #2196F3 |
| Walking Dictionary | vocabulary | hexagon | legendary | #1976D2 |
| XP Hunter | xp | star | common | #FFC107 |
| XP Warrior | xp | star | rare | #FF9800 |
| XP Champion | xp | star | epic | #FF5722 |
| XP Legend | xp | star | legendary | #9C27B0 |
| Perfectionist | quiz | medal | common | #4CAF50 |
| Perfect 10 | quiz | medal | rare | #8BC34A |
| Flawless | quiz | medal | epic | #CDDC39 |
| Graduate | course | banner | rare | #3F51B5 |
| Multi-Course Master | course | banner | epic | #673AB7 |
| Voice Starter | voice | hexagon | common | #E91E63 |
| Voice Pro | voice | hexagon | epic | #9C27B0 |

## Recommended Workflow

1. **MVP**: Dùng Badge Generator (code-generated) - đã có sẵn ✅
2. **Beta**: Dùng icon pack từ Flaticon/Game-icons
3. **Production**: Thuê designer hoặc generate với AI

## Export Settings

- Format: PNG với transparency
- Size: 256x256 px (sẽ được scale trong app)
- DPI: 72-96 cho mobile
- Color mode: sRGB
