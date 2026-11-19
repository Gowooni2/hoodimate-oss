# Hoodimate Lite 🐣 — a tiny virtual pet for your Mac desktop

**Mongsil lives on your desktop.** Feed it, play with it, put it to bed, and chat with it using your own AI key. Its eyes follow your cursor.

[한국어 소개는 아래에 있어요 ↓](#한국어)

This is the open-source **basic edition** of Hoodimate. It contains the core pet and one character (Mongsil).

## What it does

- **Pet care**: hunger, happiness, health and energy change over time, even while the app is closed. Feed · Play · Medicine · Sleep · Scold.
- **Moods and reactions**: 13 moods, looping animations, live eyes that follow your cursor. Rub its head to pet it, wiggle over its belly to tickle it.
- **Emoticons**: 24 animated KakaoTalk-style stickers with lettering in Korean, English and Chinese.
- **Chat with your own AI**: Gemini, Claude, OpenAI, GLM, Kimi, MiniMax, or a local model (LM Studio, Ollama, any OpenAI-compatible server). The app asks before the first message goes to a cloud AI. API keys stay on your Mac.
- **Alarms and notes**: "remind me in 10 minutes". When it rings, the pet grabs a clock and runs until you catch it. Notes are saved as Markdown files in a folder you pick.
- **Make the chat yours**: resize the menu by dragging its corner. Right-click it for 7 color themes, a cute or system font, and text size.
- Korean, English and Chinese.

## Build

Needs macOS on Apple silicon, [Flutter](https://flutter.dev) 3.x and Xcode.

```bash
flutter pub get
flutter build macos --dart-define=EDITION=lite
open build/macos/Build/Products/Release/Hoodimate.app
```

The build defaults to the lite edition (`lib/edition.dart`). For a signed build, set your own team ID in `macos/Runner/Configs/AppInfo.xcconfig` (`DEVELOPMENT_TEAM`, see `Signing.example.xcconfig`) and in the entitlements' app-group string.

```bash
flutter test
```

## Licenses

- Code: MIT ([LICENSE](LICENSE))
- Mongsil artwork: CC BY-NC 4.0 ([LICENSE-ASSETS.md](LICENSE-ASSETS.md))
- Fonts and third-party code: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

The names "Hoodimate", "Hoodimong", "Hoodies" and "Mongsil" are not licensed for forks or commercial use — please give your fork its own name and art.

---

## 한국어

**몽실이가 맥 바탕화면에 살아요.** 밥을 주고, 놀아 주고, 재우고, 내 AI 키로 대화할 수 있어요. 눈이 마우스를 따라와요.

후디메이트의 오픈소스 **기본판**이에요. 기본 펫 기능과 캐릭터 하나(몽실)가 들어 있어요.

- **돌보기**: 배부름·행복·건강·기운이 시간이 지나면 줄어요. 앱을 꺼 둔 동안에도 줄어요. 밥·놀기·약·재우기·혼내기.
- **기분과 반응**: 기분 13가지와 반복 애니메이션이 있어요. 머리를 문지르면 쓰다듬기, 배 위에서 흔들면 간지럼이에요.
- **이모티콘**: 카카오톡 스타일로 움직이는 이모티콘 24종에 한·영·중 효과 문구가 붙어요.
- **내 AI와 대화**: 클라우드 AI로 처음 보낼 때 동의를 받아요. API 키는 맥에만 저장돼요.
- **알람·노트**: "10분 뒤에 알려줘"라고 하면 시간이 됐을 때 펫이 시계를 들고 도망쳐요. 잡아야 꺼져요.
- **대화창 꾸미기**: 모서리를 끌어 크기를 바꿔요. 우클릭하면 색 테마 7가지, 글꼴, 글자 크기를 고를 수 있어요.

라이선스: 코드는 MIT, 몽실 그림은 CC BY-NC 4.0(비상업·출처 표시)이에요. "후디메이트·후디몽·후디즈·몽실" 이름은 포크에 쓰지 말아 주세요.
