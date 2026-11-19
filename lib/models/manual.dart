import 'profile.dart';
import '../edition.dart';

/// The user manual shown in the 📖 Manual chat room (Settings > Manual).
/// The same text is given to the AI as context there, so questions asked
/// in that room are answered from it.
class Manual {
  static const roomId = 'manual';

  static String get title => Lang.t('📖 설명서', '📖 Manual', '📖 说明书');

  static String get text => Lang.t(_ko, _en, _zh);

  /// What this edition can't do, said up front (manual + Settings), so
  /// everything is explained inside the app. Empty when nothing is missing.
  static String get notice {
    final lines = <String>[
      if (!Ed.noncommercialApis) ...[
        Lang.t('• 날씨 정보를 가져오지 않아요. 그래서 더위·추위·비에 반응하지 않아요.',
            "• It doesn't fetch weather, so it doesn't react to heat, cold or rain.",
            '• 不获取天气信息，所以不会对冷热和下雨做出反应。'),
        Lang.t('• 웹 검색은 설정에 Brave Search 키를 넣어야 돼요.',
            '• Web search needs a Brave Search key in Settings.',
            '• 网页搜索需要在设置里填入 Brave Search 密钥。'),
      ],
      if (!Ed.market)
        Lang.t('• 주가·뉴스 자동 알림은 없어요.', '• No automatic stock or news alerts.', '• 没有股价和新闻的自动提醒。'),
      Lang.t('• 체험판(키 없이) AI는 가벼운 대화와 알람 정도만 돼요. 더 똑똑하게 쓰려면 AI 키를 넣어 주세요.',
          '• The keyless Trial AI only handles light chat and alarms. Add an AI key for a smarter pet.',
          '• 免密钥体验版 AI 只能简单聊天和设闹钟。想要更聪明，请填写 AI 密钥。'),
    ];
    return lines.join('\n');
  }

  static String get welcome => Lang.t(
      '궁금한 건 여기서 물어보세요. 예: "알람은 어떻게 맞춰?", "로컬 AI 연결하는 법". 다 봤으면 위쪽 대화방 버튼의 ✕로 닫으면 돼요.',
      'Ask anything about Hoodimate right here, e.g. "How do I set an alarm?" or "How do I use a local AI?". Close this room with the ✕ on its tab when you\'re done.',
      '有问题可以在这里问，例如“怎么设闹钟？”。看完后点标签上的 ✕ 关闭。');

  static String get _ko => '''📖 후디메이트 사용 설명서

━━ 1. 기본 ━━
• 후디메이트를 클릭하면 메뉴(${Ed.isSold ? '돌봄·말하기·설정' : '대화·돌봄·설정'})가 열리고, 한 번 더 클릭하면 닫혀요.
• 후디메이트를 끌면 화면 어디로든 옮길 수 있어요.
• 눈이 마우스를 따라와요. 머리를 문지르면 쓰다듬기, 배 위에서 흔들면 간지럼이에요.
• 캐릭터: 설정 > 캐릭터에서 후디즈 다섯 친구(몽실·새봄·달잠·모랑·소복) 중 고를 수 있어요.
• 크기: 설정 > 캐릭터 크기.
• 메뉴 창 크기: 메뉴 오른쪽 아래 모서리(빗금)를 끌면 늘이고 줄일 수 있어요. 두 번 누르면 원래 크기로 돌아가요.
• 메뉴 색·대화 글꼴·글자 크기: 메뉴 창을 우클릭(또는 Control+클릭)하거나 설정 > 대화창 모양에서 바꿔요.
• 투명한 부분은 클릭이 뒤의 앱으로 통과해요.

━━ 2. 돌봄 (가상 펫 키우기) ━━
• 배부름·행복·건강·기운이 시간이 지나면 줄어요. 앱을 꺼 둔 동안에도 줄어요(최대 12시간).
• 🍪 밥 · 🧸 놀기 · 💊 약 · 🌙 재우기: 버튼마다 소리와 트랙패드 진동이 달라요.
• 너무 배부르거나 지쳤으면 버튼이 잠기고 이유가 아래에 나와요.
• 밤 10시가 지나고 15분 동안 아무것도 안 하면 스스로 자요. 아침 7시에 일어나요. 낮에 재우기를 누르면 잠깐 쉬기만 해요.
• 혼자 오래 두면 만화책을 보고, 하품하고, 커피·물을 마시다가 "놀아줘~" 하고 찡찡대요.
• 💢 혼내기: 두 번 이상 찡찡댔을 때만 눌려요. 혼나면 시무룩해지고 30분 동안 조용해요. 놀아 주거나 쓰다듬으면 찡찡이 풀려요.

━━ 3. ${Ed.isSold ? '말하기 (AI 대화는 선택 기능)' : '대화 (AI 비서)'} ━━
• ${Ed.isSold ? '말하기' : '대화'} 탭을 열면 후디메이트가 동그란 얼굴로 바뀌어 마주 보고 대화해요.
• 🎤 버튼으로 말로 물어볼 수 있어요. 처음에 마이크·음성 인식 권한을 허용해 주세요.
• 듣는 동안은 귀 기울이고, 생각하는 동안은 고민하는 동작을 해요.
• AI 연결: 설정 > 대화 AI
  - 클라우드: Gemini, Claude, OpenAI, GLM, Kimi, MiniMax 중 고르고 각 회사의 API 키를 넣어요. 채팅 앱 구독과는 별개예요.
  - 로컬(무료): Bionic · LM Studio(주소 http://127.0.0.1:1234/v1) 또는 Ollama(http://127.0.0.1:11434/v1). 키 없이 돼요.
  - 체험판(키 없이): 이 맥의 Apple Intelligence를 써요. 가벼운 대화와 알람 정도만 돼요.${Ed.isSold ? ' 키가 없고 이 맥이 지원하면 처음부터 이걸로 시작해요.' : ''}
  - "불러오기"로 모델 목록을 가져와 고르고, "연결 테스트"로 확인해요.
• 클라우드 AI로 처음 대화를 보내기 전에 동의를 물어봐요.
• 키와 대화 기록은 이 Mac에만 저장돼요.
• AI 도구(설정 > 대화 AI > AI 도구 쓰기): 후디메이트가 직접 웹 검색, 웹페이지 읽기, ${Ed.noncommercialApis ? '날씨(아무 도시), ' : ''}알람 맞추기·확인·취소, 노트 저장, 맥 캘린더 일정 보기·추가를 해요. 예: "도쿄 날씨 어때?", "애플 신제품 소식 찾아줘", "이번 주 일정 알려줘", "금요일 3시에 치과 넣어줘". ${Ed.noncommercialApis ? '검색은 기본 DuckDuckGo이고, Brave Search 키를 넣으면 그걸 써요.' : '웹 검색은 설정에 Brave Search 키를 넣으면 돼요.'} 일정은 처음에 캘린더 권한을 허용해야 해요. 도구를 지원하지 않는 로컬 모델은 도구 없이 대답해요.
• 대답 읽어 주기(설정 > 대답 읽어 주기): 끄기 / Mac 목소리(무료) / ElevenLabs(본인 키·Voice ID). 읽는 동안 입이 말에 맞춰 움직여요. "들어보기"로 미리 들을 수 있어요.

━━ 4. 대화방 ━━
• ${Ed.isSold ? '말하기' : '대화'} 탭 위쪽 버튼이 대화방이에요. 주제(프로젝트)별로 기억을 따로 해요.
• ＋로 새 대화방을 만들고, ✕로 닫아요. 닫은 방은 지워지지 않고 설정 > 보관된 대화방에서 다시 열 수 있어요.
• AI가 주제를 알아서 맞는 방으로 옮겨 주기도 해요.

━━ 5. 알람·알림 ━━
• 말로 맞춰요: "10분 뒤 알람 해줘", "내일 오후 3시 회의 알려줘", "매일 9시 물 마시라고 알려줘"
• 명령어: /알림 18:30 약 먹기 · /알림 (목록) · /알림 취소 2
• 알람이 울리면 후디메이트가 시계를 들고 화면을 도망다녀요. 클릭해서 잡으면 꺼져요(1분 뒤 자동으로 꺼짐).

━━ 6. 노트 (옵시디언) ━━
• 설정 > 노트 폴더 고르기에서 옵시디언 볼트 안의 폴더를 골라요.
• "/노트 우유 사기"라고 쓰거나, 후디메이트의 답 뒤에 "이거 노트에 저장해줘"라고 하면 저장해요.
• 대화방마다 ${Ed.dataFolder}/<대화방 이름>.md 파일로 쌓여요.

━━ 7. ${Ed.market ? '날씨·투자·뉴스' : (Ed.noncommercialApis ? '날씨' : '사는 곳')} ━━
${Ed.noncommercialApis ? '• 설정 > 내 프로필에서 도시를 찾아 저장하면 그곳 날씨(°F)에 반응해요. 더우면 부채질, 추우면 덜덜, 천둥이면 무서워해요.' : '• 설정 > 내 프로필에 사는 도시와 우편번호를 넣으면, 동네·뉴스 질문을 그 위치 기준으로 찾아요.'}${Ed.market ? '\n• 관심 종목(예: AAPL)과 이름을 넣으면 주가에 반응하고 큰 뉴스를 알려 줘요(하루 최대 3개).\n• 매일 10시·17시에 브리핑해요. 감정 표현만 하고 투자 조언은 하지 않아요.' : ''}

━━ 8. 언어 ━━
• 대화창에 "영어로 대화하자", "let's talk in Korean", "说中文"처럼 말하면 메뉴·대사·목소리까지 바뀌어요.
• 설정 > 내 프로필 > 언어에서도 바꿀 수 있어요. (중국어 화면은 일부만 번역돼 있어요.)

━━ 9. 소리·진동 ━━
• 설정 > 상황 음성: 밥·비·아픔 등 상황 목소리를 켜고 꺼요. 말할 때 입도 같이 움직여요.
• 설정 > 버튼 효과음(음량)과 트랙패드 진동(포스터치 트랙패드에서만 느껴져요).

━━ 10. 맥끼리 동기화 ━━
• 집 맥과 회사 맥을 같이 쓰면 설정 > 맥끼리 동기화에서 두 맥 모두 같은 폴더(iCloud Drive, Dropbox, Google Drive 등)를 골라요.
• 대화·기억, 펫 상태, 프로필, 알람, 코인이 3분마다 맞춰져요. "지금 동기화"로 바로 맞출 수도 있어요.
• 두 맥에서 대화하면 대화는 합쳐져요. 펫 상태는 마지막으로 돌본 쪽을 따라가요.
• AI 키, 캐릭터 크기, 효과음 음량은 맥마다 따로예요.
• 새 맥은 처음 동기화할 때 공유 폴더의 내용을 먼저 받아요.

${notice.isEmpty ? '' : '━━ ⚠️ 주의사항 ━━\n$notice\n\n'}━━ 11. 기타 ━━
• 생일: 설정 > 내 프로필에 월-일(예: 03-14)을 넣으면 그날 축하해 줘요.
• 할로윈, 평일 저녁 6시 퇴근 시간에도 반응해요.
• 개인 정보(키·위치·코인·대화)는 모두 이 Mac에만 있어요.
• 끄기: 설정 맨 아래 "펫 종료하기".${Ed.isSold ? _soldKo : ''}''';

  static String get _en => '''📖 Hoodimate user manual

━━ 1. Basics ━━
• Click Hoodimate to open the menu (${Ed.isSold ? 'Care · Talk · Settings' : 'Chat · Care · Settings'}); click again to close it.
• Drag Hoodimate to move it anywhere on screen.
• Its eyes follow your cursor. Rub its head to pet it; wiggle over its belly to tickle.
• Character: pick one of the five Hoodies (Mongsil, Saebom, Daljam, Morang, Sobok) in Settings > Character.
• Size: Settings > Pet size.
• Menu size: drag the striped bottom-right corner of the menu to make it bigger or smaller. Double-click it to reset.
• Menu color, chat font and text size: right-click (or Control-click) the menu, or Settings > Chat look.
• Clicks on the transparent area pass through to the app behind.

━━ 2. Care (virtual pet) ━━
• Hunger, happiness, health and energy drop over time, even while the app is closed (up to 12 hours).
• 🍪 Feed · 🧸 Play · 💊 Medicine · 🌙 Sleep: each button has its own sound and trackpad haptic.
• A button locks when it isn't needed (too full, too tired); the reason shows under it.
• After 10 PM, with 15 quiet minutes, Hoodimate goes to sleep on its own and wakes at 7 AM. Sleep during the day is just a short rest.
• Left alone, it reads comics, yawns, drinks coffee or water — then whines "play with me~".
• 💢 Scold works only after it has whined twice or more. It sulks and stays quiet for 30 minutes. Playing or petting also stops the whining.

━━ 3. ${Ed.isSold ? 'Talk (AI chat is optional)' : 'Chat (AI assistant)'} ━━
• Open the ${Ed.isSold ? 'Talk' : 'Chat'} tab and Hoodimate turns into a round, face-to-face view.
• 🎤 lets you ask by voice. Allow Microphone and Speech Recognition the first time.
• It cups its ear while listening and ponders while thinking.
• Connect an AI in Settings > Chat AI:
  - Cloud: pick Gemini, Claude, OpenAI, GLM, Kimi or MiniMax and paste that company's API key (separate from chat-app subscriptions).
  - Local (free): Bionic · LM Studio (http://127.0.0.1:1234/v1) or Ollama (http://127.0.0.1:11434/v1). No key needed.
  - Trial (no key): uses Apple Intelligence on this Mac. Light chat and alarms only.${Ed.isSold ? ' With no key and a supported Mac, it starts with this one.' : ''}
  - "Load" fetches the model list; "Test connection" checks it.
• Before the first chat goes to a cloud AI, it asks for your OK.
• Keys and chats are stored only on this Mac.
• AI tools (Settings > Chat AI > Let the AI use tools): Hoodimate can search the web, read a page, ${Ed.noncommercialApis ? 'check the weather anywhere, ' : ''}set/list/cancel alarms, save notes and read or add Mac calendar events. Try "Weather in Tokyo?", "Find news about Apple", "What's on my calendar this week?", "Add dentist Friday 3 PM". ${Ed.noncommercialApis ? 'Search uses DuckDuckGo, or Brave Search if you add a key.' : 'Web search needs a Brave Search key in Settings.'} Allow Calendar access the first time. Local models without tool support simply answer without tools.
• Read replies aloud (Settings > Read replies aloud): Off / Mac voice (free) / ElevenLabs (your key and voice ID). The mouth moves with the speech; "Try it" plays a sample.

━━ 4. Chat rooms ━━
• The buttons above the chat are rooms; each topic (project) keeps its own memory.
• ＋ makes a room, ✕ closes it. Closed rooms are kept: reopen them in Settings > Archived chats.
• The AI may move a conversation into the matching room by itself.

━━ 5. Alarms & reminders ━━
• Just ask: "remind me in 10 minutes", "remind me tomorrow at 3 PM about the meeting", "remind me every day at 9 to drink water".
• Commands: /remind 18:30 take medicine · /remind (list) · /remind cancel 2
• When an alarm rings, Hoodimate grabs a clock and runs around the screen. Click it to catch it (it stops by itself after 1 minute).

━━ 6. Notes (Obsidian) ━━
• Settings > Pick notes folder: pick a folder inside your Obsidian vault.
• Type "/note buy milk", or after a reply say "save this to my notes".
• Each room gets its own file: ${Ed.dataFolder}/<room name>.md.

━━ 7. ${Ed.market ? 'Weather, stocks, news' : (Ed.noncommercialApis ? 'Weather' : 'Your place')} ━━
${Ed.noncommercialApis ? '• Settings > My profile: search your city and save; Hoodimate reacts to its weather (°F) — fanning when hot, shivering when cold, hiding at thunder.' : '• Settings > My profile: add your city and ZIP code; local questions and news searches follow that place.'}${Ed.market ? '\n• Add a stock symbol (e.g. AAPL) and name: it reacts to the price and tells you big news (up to 3 a day).\n• Briefings at 10 AM and 5 PM. Feelings only, never investment advice.' : ''}

━━ 8. Language ━━
• Say "let's talk in English", "한국어로 대화하자" or "说中文" in chat: menus, lines and voice all switch.
• Or use Settings > My profile > Language.

━━ 9. Sound & haptics ━━
• Settings > Reaction sounds: turns the voice lines on/off. The mouth moves while it talks.
• Settings > Button sounds (volume) and Trackpad haptics (felt on Force Touch trackpads).

━━ 10. Sync between Macs ━━
• Using Hoodimate on two Macs (home and work)? In Settings > Sync between Macs, pick the same shared folder (iCloud Drive, Dropbox, Google Drive ...) on both.
• Chats and memory, pet stats, profile, alarms and coins sync every 3 minutes, or press "Sync now".
• Chats from both Macs are combined; the pet's stats follow the Mac where you last cared for it.
• AI keys, pet size and sound volume stay per Mac.
• A new Mac first takes what's in the shared folder.

${notice.isEmpty ? '' : '━━ ⚠️ Good to know ━━\n$notice\n\n'}━━ 11. More ━━
• Birthday: put MM-DD (e.g. 03-14) in My profile and Hoodimate celebrates that day.
• It also notices Halloween and weekday 6 PM (time to clock out).
• Your data (keys, location, coins, chats) stays on this Mac.
• Quit: "Quit the pet" at the bottom of Settings.${Ed.isSold ? _soldEn : ''}''';

  static String get _zh => '''📖 Hoodimate 使用说明书

━━ 1. 基本 ━━
• 点击 Hoodimate 打开菜单（${Ed.isSold ? '照顾 · 聊天 · 设置' : '聊天 · 照顾 · 设置'}），再点一次关闭。
• 拖动 Hoodimate 可以把它放到屏幕任何地方。
• 眼睛会跟着鼠标。摸摸头是抚摸，在肚子上晃动是挠痒痒。
• 角色：在 设置 > 角色 里从五位 Hoodies（蒙实、新春、月眠、暮朗、素福）中选一个。
• 大小：设置 > 宠物大小。
• 菜单大小：拖动菜单右下角的斜纹即可放大或缩小，双击恢复原来的大小。
• 菜单颜色、聊天字体和字号：右键（或按住 Control 点击）菜单，或在 设置 > 聊天外观 里更改。
• 透明的地方点击会穿透到后面的应用。

━━ 2. 照顾（虚拟宠物）━━
• 饱腹、快乐、健康、体力会随时间下降，关掉应用时也会下降（最多 12 小时）。
• 🍪 喂食 · 🧸 玩耍 · 💊 吃药 · 🌙 睡觉：每个按钮都有自己的声音和触控板震动。
• 不需要时按钮会锁住（太饱、太累），原因会显示在按钮下面。
• 晚上 10 点后安静 15 分钟，Hoodimate 会自己去睡觉，早上 7 点醒来。白天睡觉只是小憩。
• 放着不管时，它会看漫画、打哈欠、喝咖啡或喝水，然后撒娇说“陪我玩嘛~”。
• 💢 训斥只有在它撒娇两次以上后才能用。它会委屈地安静 30 分钟。陪它玩或摸摸它也能让它不再撒娇。

━━ 3. ${Ed.isSold ? '聊天（AI 对话是可选功能）' : '聊天（AI 助手）'} ━━
• 打开聊天页，Hoodimate 会变成圆圆的脸，面对面和你聊天。
• 🎤 可以用语音提问。第一次需要允许麦克风和语音识别。
• 听的时候它会把手放在耳边，想的时候会托腮思考。
• 在 设置 > 聊天 AI 里连接 AI：
  - 云端：选择 Gemini、Claude、OpenAI、GLM、Kimi 或 MiniMax，填入该公司的 API 密钥（和聊天应用的订阅不是一回事）。
  - 本地（免费）：Bionic · LM Studio（http://127.0.0.1:1234/v1）或 Ollama（http://127.0.0.1:11434/v1），不需要密钥。
  - 体验版（免密钥）：在这台 Mac 上用 Apple Intelligence，只能简单聊天和设闹钟。${Ed.isSold ? '没有密钥且这台 Mac 支持时，一开始就用它。' : ''}
  - “加载”会取得模型列表，“测试连接”会检查是否能用。
• 第一次把聊天发给云端 AI 之前，会先问你是否同意。
• 密钥和聊天记录只保存在这台 Mac 上。
• AI 工具（设置 > 聊天 AI > 允许 AI 使用工具）：Hoodimate 可以自己搜索网页、阅读网页、${Ed.noncommercialApis ? '查任意城市的天气、' : ''}设置/查看/取消闹钟、保存笔记，以及查看或添加 Mac 日历。比如“这周我有什么日程？”、“周五下午 3 点加一个看牙医的日程”。${Ed.noncommercialApis ? '搜索默认用 DuckDuckGo，填入 Brave Search 密钥后改用它。' : '网页搜索需要在设置里填入 Brave Search 密钥。'}第一次使用日历需要允许访问。不支持工具的本地模型会直接回答。
• 朗读回答（设置 > 朗读回答）：关 / Mac 语音（免费）/ ElevenLabs（你的密钥和语音 ID）。说话时嘴巴会跟着动，“试听”可以听样本。

━━ 4. 聊天室 ━━
• 聊天上方的按钮是聊天室，每个话题（项目）有自己的记忆。
• ＋ 新建聊天室，✕ 关闭。关闭的聊天室会保留，可以在 设置 > 已归档的聊天 里重新打开。
• AI 有时会自己把对话移到相应的聊天室。

━━ 5. 闹钟和提醒 ━━
• 直接说：“10分钟后提醒我”、“明天下午3点提醒我开会”、“每天9点提醒我喝水”。
• 命令：/remind 18:30 吃药 · /remind（查看列表）· /remind cancel 2
• 闹钟响时，Hoodimate 会抱着闹钟在屏幕上到处跑。点它就能抓住（1 分钟后会自己停下）。

━━ 6. 笔记（Obsidian）━━
• 设置 > 选择笔记文件夹：选 Obsidian 库里的一个文件夹。
• 输入“/note 买牛奶”，或在回答后说“把这个存到笔记里”。
• 每个聊天室一个文件：${Ed.dataFolder}/<聊天室名>.md。

━━ 7. ${Ed.market ? '天气、股票、新闻' : (Ed.noncommercialApis ? '天气' : '所在地')} ━━
${Ed.noncommercialApis ? '• 设置 > 我的资料：搜索你的城市并保存，Hoodimate 会对那里的天气（°F）做出反应：热了扇扇子，冷了发抖，打雷会害怕。' : '• 设置 > 我的资料：填写所在城市和邮编，本地问题和新闻会按这个位置搜索。'}${Ed.market ? '\n• 填写关注的股票代码（例如 AAPL）和名称，它会对股价做出反应，并告诉你重要新闻（每天最多 3 条）。\n• 每天上午 10 点和下午 5 点播报。只表达心情，不提供投资建议。' : ''}

━━ 8. 语言 ━━
• 在聊天里说“说中文”、“let's talk in English”或“한국어로 대화하자”，菜单、台词和语音都会切换。
• 也可以在 设置 > 我的资料 > 语言 里更改。

━━ 9. 声音和触感 ━━
• 设置 > 反应声音：打开或关闭台词语音。说话时嘴巴会动。
• 设置 > 按钮声音（音量）和 触控板震动（在 Force Touch 触控板上能感觉到）。

━━ 10. 多台 Mac 同步 ━━
• 在家里和公司两台 Mac 上都用 Hoodimate？在两台 Mac 的 设置 > 多台 Mac 同步 里选同一个共享文件夹（iCloud Drive、Dropbox、Google Drive 等）。
• 聊天和记忆、宠物状态、资料、闹钟和币每 3 分钟同步一次，也可以按“立即同步”。
• 两台 Mac 的聊天会合在一起；宠物状态以你最后照顾它的那台 Mac 为准。
• AI 密钥、宠物大小和音量每台 Mac 各自独立。
• 新的 Mac 会先取用共享文件夹里的内容。

${notice.isEmpty ? '' : '━━ ⚠️ 注意事项 ━━\n$notice\n\n'}━━ 11. 其他 ━━
• 生日：在我的资料里填 MM-DD（例如 03-14），Hoodimate 会在那天为你庆祝。
• 它也知道万圣节和工作日下午 6 点（下班时间）。
• 你的数据（密钥、位置、币、聊天）只保存在这台 Mac 上。
• 退出：设置最下面的“退出宠物”。${Ed.isSold ? _soldZh : ''}''';

  // Extra sections of the sold editions (Hoodibot; more are added below).

  static String get _soldKo => '''

━━ 12. 후디봇 만나기 ━━
• 같은 맥에서 후디봇(바탕화면을 정리해 주는 우리 로봇 펫)이 돌아가고 있으면 둘이 알아서 만나요.
• 서로 인사하고, 후디봇 쪽으로 놀러 가고, 후디봇이 청소할 땐 응원해 줘요. 한쪽 알람이 울리면 다른 쪽도 같이 놀라요.
• 따로 설정할 건 없어요. 둘 다 켜져 있기만 하면 돼요.

━━ 13. 맥 기능 ━━
• 메뉴 막대: 위쪽 메뉴 막대에 후디메이트 얼굴이 떠요. 눌러 보면 배부름·기운이 보이고, 밥 주기·재우기·새 알람·후디메이트 보이기를 바로 할 수 있어요. 설정 > 맥 기능에서 끌 수 있어요.
• 알림 센터: 설정 > 맥 기능에서 켜면 배고플 때, 알람이 울릴 때, 잠잘 시간에 알림 센터로 알려 줘요. 켤 때 한 번 허용을 물어보고, 기본은 꺼져 있어요.
• 단축어·Siri: "밥 줘", "알람 맞춰", "기분 어때"를 단축어 앱이나 Siri로 부를 수 있어요. 동의하기 전에는 Siri로 한 말이 클라우드 AI로 가지 않아요.''';

  static String get _soldEn => '''

━━ 12. Meeting Hoodibot ━━
• If Hoodibot (our desktop robot pet that tidies your desktop) is running on the same Mac, the two of them find each other.
• They say hi, Hoodimate drops by Hoodibot's place, cheers it on while it cleans, and reacts when the other one's alarm rings.
• There is nothing to set up. Just have both running.

━━ 13. Mac features ━━
• Menu bar: Hoodimate's mood face sits in the menu bar. Open it to see fullness and energy, and to feed, put to sleep, set a new alarm or show Hoodimate. Turn it off in Settings > Mac features.
• Notification Center: turn it on in Settings > Mac features to get a notice when it is hungry, when an alarm rings and at bedtime. macOS asks for permission once when you switch it on; it is off by default.
• Shortcuts and Siri: "Feed Hoodimate", "Set an alarm with Hoodimate" and "How is Hoodimate feeling" work from the Shortcuts app or Siri. Nothing said to Siri goes to a cloud AI until you have agreed in the app.''';

  static String get _soldZh => '''

━━ 12. 和 Hoodibot 见面 ━━
• 如果同一台 Mac 上也在运行 Hoodibot（帮你整理桌面的机器人宠物），它们会自己找到对方。
• 它们会互相打招呼，Hoodimate 会去 Hoodibot 家串门，在它打扫时加油，一方的闹钟响了另一方也会被吓一跳。
• 不需要任何设置，两个都开着就行。

━━ 13. Mac 功能 ━━
• 菜单栏：Hoodimate 的心情表情会出现在菜单栏。点开可以看到饱腹和体力，并直接喂食、哄睡、设新闹钟、显示 Hoodimate。可在 设置 > Mac 功能 里关闭。
• 通知中心：在 设置 > Mac 功能 里打开后，饿了、闹钟响了、该睡觉时会通过通知中心提醒。打开时 macOS 会询问一次权限，默认是关闭的。
• 快捷指令和 Siri：“Feed Hoodimate”“Set an alarm with Hoodimate”“How is Hoodimate feeling”可以在快捷指令 App 或 Siri 中使用。在应用里同意之前，对 Siri 说的话不会发送给云端 AI。''';
}
