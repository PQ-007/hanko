// Mongolian UI strings. Copy is taken word for word from the web app's
// web/src/app/decks/_lib/strings.ts wherever the same thing is said, so the
// two clients never describe one feature in two different ways. Strings only
// mobile needs (navigation, settings, sheets) are at the bottom.
// ignore_for_file: constant_identifier_names

class T {
  const T._();

  // Decks / folders (strings.ts)
  static const folders = 'Хавтаснууд';
  static const allDecks = 'Бүх багц';
  static const noFolder = 'Хавтасгүй';
  static const newFolder = 'Шинэ хавтасны нэр';
  static const newFolderTitle = 'Шинэ хавтас нэмэх';
  static const emptyFolder = 'хоосон';
  static const decks = 'Багцууд';
  static const newDeck = 'Шинэ багцын нэр';
  static const add = 'Нэмэх';
  static const noDecks = 'Багц алга';
  static const loading = 'Ачааллаж байна…';
  static const createDeckToStart = 'Эхлэхийн тулд багц үүсгэнэ үү.';
  static const search = 'Үг хайх…';
  static const searchResults = 'Хайлтын үр дүн';
  static const noResults = 'Илэрц олдсонгүй';
  static const noWords =
      'Энэ багцад үг алга. Дээр нэмэх эсвэл өргөтгөлөөс хадгална уу.';
  static const exportApkg = '.apkg татах';
  static const exportTxt = '.txt татах';
  static const building = 'Бэлдэж байна…';
  static const exportFailed = 'Экспорт амжилтгүй';
  static const delete = 'Устгах';
  static const ok = 'За';
  static const deleteDeckTitle = 'Багц устгах уу?';
  static const deleteFolderTitle = 'Хавтас устгах уу?';
  static const deleteWordTitle = 'Үг устгах уу?';
  static String deleteWordBody(String t) => '“$t” энэ багцаас устгагдана.';
  static const removeFriendTitle = 'Найзаас хасах уу?';
  static String removeFriendBody(String h) =>
      '@$h таны найзын жагсаалтаас хасагдана. Дахин найзлахын тулд хүсэлт илгээх хэрэгтэй.';
  static const term = 'Үг (ж: 勉強)';
  static const reading = 'Дуудлага';
  static const lookingUp = 'Хайж байна…';
  static const meaningEn = 'Утга (Англи)';
  static const mongolian = 'Монгол';
  static const addWord = 'Үг нэмэх';
  static const playAudio = 'Дуудлага сонсох';
  static const removeWord = 'Үг устгах';
  static const edit = 'Засах';
  static const editWord = 'Үг засах';
  static const refresh = 'Шинэчлэх';
  static const research = 'Jisho-оос дахин хайх';
  static const translate = 'Орчуулах';
  static const save = 'Хадгалах';
  static const cancel = 'Болих';
  static const gridView = 'Картаар харах';
  static const listView = 'Жагсаалтаар харах';
  static const noFolderOption = '— Хавтасгүй —';
  static const audioFailed = 'Дуу үүсгэж чадсангүй';
  static String deleteDeckConfirm(String n) =>
      '“$n” багц болон доторх бүх үгийг устгах уу? Буцаах боломжгүй.';
  static String deleteFolderConfirm(String n) =>
      '“$n” хавтсыг устгах уу? Доторх багцууд устахгүй, хавтасгүй болно.';
  static const duplicateWord = 'Давхардсан үг';
  static String duplicateWordConfirm(String t) =>
      '“$t” энэ багцад аль хэдийн бүртгэгдсэн байна. Дахин нэмэх үү?';
  static const addAnyway = 'Дахин нэмэх';
  static const practice = 'Давтах';
  static const practiceAll = 'Давтах';
  static const noWordsDue = 'Одоогоор давтах үг алга. Дараа дахин ирнэ үү!';
  static const showAnswer = 'Хариулт харах';
  static const again = 'Дахин';
  static const hard = 'Хэцүү';
  static const good = 'Сайн';
  static const easy = 'Амархан';
  static const undo = 'Буцаах';
  static const undoTitle = 'Сүүлийн хариултыг буцаах';
  static String remainingN(int n) => '$n үг үлдсэн';
  static const sessionComplete = 'Давтаж дууслаа!';
  static String sessionCompleteDesc(int n) => 'Та $n үг дахин үзлээ.';
  static const gradeTitle = 'Түвшин';
  static const gradeNew = 'Шинэ';
  static const gradeClearFilter = 'Шүүлтүүр арилгах';
  static const gradeFilterEmpty = 'Энэ түвшинд үг алга.';

  // Mode chooser (strings.ts)
  static const chooseModeTitle = 'Ямар байдлаар давтах вэ?';
  static const classicModeTitle = 'Энгийн давталт';
  static const classicModeDesc = 'Дөрвөн товчоор өөрөө үнэлж давтана.';
  static const battleModeTitle = 'Мангас агнах';
  static const battleModeDesc =
      'Зөв хариултаар дайсныг цохино, буруу хариулбал өөрөө цохиулна.';
  static const freeModeTitle = 'Чөлөөт дасгал';
  static const freeModeDesc =
      'Хуваариас үл хамааран дурын үгээр тулаанд орно. Хуваарь өөрчлөгдөхгүй.';
  static const practiceKicker = 'Өнөөдрийн давталт';
  static String practiceDueHeadline(int n) => '$n үг хүлээж байна';
  static const practiceNothingDue = 'Өнөөдөр давтах үг алга';
  static String practiceDueBreakdown(int review, int fresh) =>
      '$review давталт · $fresh шинэ';
  static const practiceScopeAll = 'Бүх багц';
  static const heroPickerTitle = 'Баатраа сонго';
  static const heroPickerHint = 'Мангастай энэ дүрээр тулна.';
  static const multiplayerTitle = 'Найзтайгаа тулах';
  static const multiplayerDesc =
      'Хоёр тоглогч тус тусын багцаасаа асуулт хүлээн авч, шууд тулна.';
  static const comingSoon = 'Тун удахгүй';
  static String battleLocked(int n) => 'Тулаанд хамгийн багадаа $n үг хэрэгтэй';

  // Stats (strings.ts)
  static const statTotalWords = 'Нийт үг';
  static const statTotalDecks = 'Багц';
  static const statDueToday = 'Өнөөдөр давтах';
  static String dueHeldBack(int n) => 'Өдрийн хязгаараас $n үг хойшлов';
  static const statMastered = 'Эзэмшсэн (A+B)';
  static const overallGradeTitle = 'Нийт түвшин';
  static const weekdayTitle = 'Гараг тус бүрийн давталт';
  static String weekdaySummary(int n) => 'Сүүлийн хагас жилд нийт $n давталт';
  static String perWeekAvg(num n) => '7 хоногт дунджаар $n';
  static const deckBreakdownTitle = 'Багц тус бүрээр';
  static const colDeck = 'Багц';
  static const colWords = 'Үг';
  static const colDue = 'Давтах';
  static const colMastered = 'Эзэмшсэн';
  static const noStatsData = 'Одоогоор өгөгдөл алга. Багц үүсгээд үг нэмнэ үү.';
  static const loadingStats = 'Тооцоолж байна…';
  static const streakLabel = 'Дараалсан өдөр';
  static String bestStreak(int n) => 'Хамгийн урт: $n өдөр';
  static String streakFreezes(int n) => '$n хамгаалалттай';
  static const masteredRingLabel = 'Эзэмшсэн хувь';
  static const goalRingLabel = 'Шинэ үгийн зорилго';
  static const goalRingEdit = 'Зорилго өөрчлөх';
  static const addedRingLabel = 'Өнөөдөр нэмэгдсэн';
  static String addedTodayCta(int n) => 'Өнөөдөр $n үг нэмлээ';
  static const addedTodayNone = 'Өнөөдөр шинэ үг нэмээгүй байна';
  static const heatmapTitle = 'Давталтын хуанли';
  static const addedHeatmapTitle = 'Үг нэмсэн хуанли';
  static String heatmapSummary(String totalLabel, int days) =>
      'Сүүлийн хагас жилд $totalLabel · $days өдөр';
  static String reviewsN(int n) => '$n давталт';
  static String wordsN(int n) => '$n үг';
  static const less = 'Бага';
  static const more = 'Их';
  static String growthTitle(int d) => 'Сүүлийн $d хоногийн өсөлт';
  static const wordsUnit = 'үг';
  static const reviewsThisWeek = 'Энэ 7 хоногийн давталт';
  static const saveFailed = 'Хариултыг хадгалж чадсангүй. Дахин оролдоно уу.';

  // Quick add + goal (strings.ts)
  static const quickAdd = 'Үг нэмэх';
  static const quickAddTitle = 'Шинэ үг нэмэх';
  static const quickAddDeckLabel = 'Аль багц руу';
  static const quickAddNoDecks = 'Үг нэмэхийн тулд эхлээд багц үүсгэнэ үү.';
  static const quickAddSaveFailed = 'Үгийг хадгалж чадсангүй.';
  static String quickAddedCount(int n) => '$n үг нэмлээ';
  static const quickAddDone = 'Дуусгах';
  static const goalModalTitle = 'Өдрийн шинэ үгийн зорилго';
  static const goalModalDesc = 'Өдөрт хэдэн шинэ үг сурахыг зорих вэ?';
  static const goalModalLabel = 'Шинэ үг / өдөр';
  static const goalSaveFailed = 'Зорилгыг хадгалж чадсангүй. Дахин оролдоно уу.';

  // Word spotlight (strings.ts)
  static const spotlightTitle = 'Таны үгсээс';
  static const spotlightAnother = 'Өөр үг';
  static const spotlightOpenDeck = 'Багц руу очих';
  static const spotlightNoMeaning = 'Утга оруулаагүй байна';

  // Monster Hunt (strings.ts)
  static const loadingWords = 'Үгсийг ачааллаж байна…';
  static const loadingQuiz = 'Асуулт бэлдэж байна…';
  static const noWordsDueBattle = 'Одоогоор тулаанд дайх үг алга байна.';
  static const noWordsDueBattleHint =
      'Бүх үгээ давтсан байна. Сурч буй үгс хэдэн минутын дараа эргэж ирнэ.';
  static const queueLoadFailed = 'Давтах үгсийг ачаалж чадсангүй.';
  static const freePracticeCta = 'Ямар ч үгээр чөлөөтэй тулаанд орох';
  static const freePracticeBanner =
      'Чөлөөт дасгал — хариултууд давтлагын хуваарь болон цувралд нөлөөлөхгүй.';
  static const notEnoughWordsBattle =
      'Мангас агнахад хамгийн багадаа 4 үг хэрэгтэй. Эхлээд өргөтгөл эсвэл гараар цөөн үг нэмнэ үү.';
  static String monstersDefeated(int n) => '$n дайсан устгалаа';
  static const stopBattle = 'Тулаан зогсоох';
  static const retryBattle = 'Дахин оролдох';
  static const victoryTitle = 'Ялалт!';
  static const defeatTitle = 'Ялагдал';
  static const clearedTitle = 'Өнөөдрийн ажил дууслаа';
  static const clearedDesc = 'Бүх үгээ давтлаа';
  static const critLabel = 'КРИТИКАЛ ЦОХИЛТ!';
  static const evadedLabel = 'ЗАЙЛСХИЙВ!';
  static const armorBlockedLabel = 'ХАМГААЛАЛТ ХААЛАА!';
  static const timeUpLabel = 'ЦАГ ДУУСЛАА!';
  static const armorGainedLabel = 'Хамгаалалт олдлоо';
  static const exitBattle = 'Буцах';
  static const pauseBattle = 'Түр зогсоох';
  static const resumeBattle = 'Үргэлжлүүлэх';
  static const pausedTitle = 'Түр зогсов';
  static const pausedDesc = 'Цаг зогслоо. Үргэлжлүүлэхэд яг эндээсээ цааш явна.';
  static String killCount(int n) => '$n устгав';
  static const victoryFlag = 'ДАЙСАН УНАЛАА!';
  static const resultKicker = 'Тулааны дүн';
  static const resultWords = 'Давтсан үг';
  static const resultCorrect = 'Зөв хариулт';
  static const resultBestStreak = 'Дээд цуврал';
  static const resultCrits = 'Критикал цохилт';
  static const noMonsterDefeated = 'Энэ дайсныг дийлсэнгүй';
  static const victoryDesc = 'Унагасан дайснуудаа доор харна уу.';
  static const defeatDesc =
      'Амь дуусав. Хариулсан үгс аль хэдийн хадгалагдсан — дахин орвол үлдсэн үгнээс үргэлжилнэ.';
  static const offlineQueued = 'Офлайн — хариултууд хадгалагдаж, дараа илгээгдэнэ';

  // Duel (strings.ts)
  static const duelKicker = 'Тулаан';
  static const duelLobbyTitle = 'Хэнтэй тулах вэ?';
  static const duelBotSection = 'Боттой тулах';
  static const duelBotDesc = 'Хүлээх шаардлагагүй. Гурван түвшин.';
  static const duelBotRookie = 'Дасгалжигч';
  static const duelBotRookieDesc = 'Удаан бөгөөд олон алддаг.';
  static const duelBotRival = 'Өрсөлдөгч';
  static const duelBotRivalDesc = 'Тэнцүү хиртэй тулаан.';
  static const duelBotMaster = 'Мастер';
  static const duelBotMasterDesc = 'Хурдан, бараг алддаггүй.';
  static const duelFriendSection = 'Найзтайгаа тулах';
  static const duelCreate = 'Тулаан үүсгэх';
  static const duelJoin = 'Кодоор нэгдэх';
  static const duelCodeLabel = 'Тулааны код';
  static const duelCodePlaceholder = 'ЖИШЭЭ: 7K2Q';
  static const duelCodeShare = 'Энэ кодыг найздаа явуулаарай.';
  static const duelWaitingGuest = 'Найзаа хүлээж байна…';
  static const duelJoinFailed = 'Ийм кодтой тулаан олдсонгүй, эсвэл аль хэдийн эхэлсэн байна.';
  static const duelCreateFailed = 'Тулаан үүсгэж чадсангүй.';
  static const duelCancel = 'Тулааныг цуцлах';
  static const duelYou = 'Та';
  static String duelRoundOf(int n, int total) => '$n / $total тойрог';
  static const duelOpponentAnswered = 'Өрсөлдөгч хариуллаа';
  static const duelOpponentThinking = 'Өрсөлдөгч бодож байна…';
  static String duelStreakLabel(int n) => '$n дараалан';
  static const duelWon = 'Ялалт!';
  static const duelLost = 'Ялагдал';
  static const duelDraw = 'Тэнцлээ';
  static const duelWonDesc = 'Өрсөлдөгчөө дийллээ.';
  static const duelLostDesc = 'Энэ удаад бүтсэнгүй. Дахин оролдоорой.';
  static const duelDrawDesc = 'Хоёулаа тэнцүү үлдлээ.';
  static const duelRematch = 'Дахин тулах';
  static const duelResultRounds = 'Тойрог';
  static const duelResultCorrect = 'Зөв хариулт';
  static const duelResultBestStreak = 'Дээд цуврал';
  static const duelResultDamage = 'Хийсэн хохирол';
  static const duelTimedOut = 'Хоцорлоо';
  static const duelNotScheduled = 'Тулааны хариултууд давтлагын хуваарьт нөлөөлөхгүй — зөвхөн тэмдэглэгдэнэ.';
  static const duelLoading = 'Тулаан бэлдэж байна…';
  static const duelLoadFailed = 'Тулааны үгсийг ачаалж чадсангүй.';
  static const duelOpponentLeft = 'Өрсөлдөгч гарлаа.';
  // Mobile only
  static const duelLeaveTitle = 'Тулаанаас гарах уу?';
  static const duelLeaveDesc = 'Гарвал энэ тулаанд ялагдсанд тооцогдоно.';
  static const duelLeave = 'Гарах';
  static const duelStay = 'Үргэлжлүүлэх';
  static const duelOnlineUnavailable = 'Онлайн тулаан одоогоор боломжгүй (сервер бэлэн биш эсвэл интернэт алга).';

  // ---- Mobile only -------------------------------------------------------
  static const navHome = 'Нүүр';
  static const navStats = 'Статистик';
  static const navPvp = 'Тулаан';
  static const navLibrary = 'Сан';

  // Friends, leaderboard, XP/ELO (0026)
  static const socialTitle = 'Найзууд';
  static const socialTabFriends = 'Найзууд';
  static const socialTabBoard = 'Тэргүүлэгчид';
  static const socialTabDuel = 'Тулаан';
  static const socialPickHandle = 'Хэрэглэгчийн нэрээ сонгоно уу';
  static const socialPickHandleDesc = 'Найзууд тань энэ нэрээр л таныг хайж олно. И-мэйл хэзээ ч харагдахгүй.';
  static const socialHandleLabel = 'Хэрэглэгчийн нэр';
  static const socialSave = 'Хадгалах';
  static const socialHandleFormat = '3–20 тэмдэгт: a–z, 0–9, _';
  static const socialHandleTaken = 'Энэ нэрийг өөр хүн авсан байна.';
  static const socialHandleFailed = 'Хадгалж чадсангүй.';
  static String socialShareInvite(String h) => 'Hanko дээр намайг @$h гэж нэмээрэй!';
  static const socialAddFriend = 'Найз нэмэх';
  static const socialAddHint = '@хэрэглэгчийн нэр';
  static const socialAdd = 'Нэмэх';
  static const socialSent = 'Хүсэлт илгээлээ.';
  static const socialAccepted = 'Найз боллоо!';
  static const socialAlready = 'Аль хэдийн найз эсвэл хүсэлт илгээсэн байна.';
  static const socialNotFound = 'Ийм хэрэглэгч олдсонгүй.';
  static const socialSelf = 'Өөрийгөө нэмэх боломжгүй.';
  static const socialRequests = 'Найзын хүсэлт';
  static const socialOutgoing = 'Хариу хүлээж байна';
  static const socialAccept = 'Зөвшөөрөх';
  static const socialDecline = 'Татгалзах';
  static const socialCancelRequest = 'Цуцлах';
  static const socialRemove = 'Найзаас хасах';
  static const socialNoFriends = 'Одоохондоо найз алга. Хэрэглэгчийн нэрээр нь нэмээрэй.';
  static const socialHidden = 'Идэвхээ нуусан';
  static const socialYou = 'Та';
  static String socialLevel(int lv) => 'Түвшин $lv';
  static String socialXp(int xp) => '$xp XP';
  static String socialAddedToday(int n) => '+$n үг нэмсэн';
  static String socialReviewedToday(int n) => '$n давталт';
  static String socialWordsLearned(int n) => '$n үг сурсан';
  static String socialKanjiLearned(int n) => '$n ханз';
  static String socialElo(int e) => 'ELO $e';
  static const socialToday = 'Өнөөдөр';
  static const socialBoardWeek = '7 хоног';
  static const socialBoardTotal = 'Нийт XP';
  static const socialBoardElo = 'ELO';
  static const socialScopeFriends = 'Найзууд';
  static const socialScopeAll = 'Бүгд';
  static const socialGlobalNote = 'Бүх хэрэглэгч — зөвхөн хэрэглэгчийн нэр, оноо харагдана. Тохиргооноос идэвхээ нуувал энд гарахгүй.';
  static const socialGlobalNeedHandle = 'Энд гарахын тулд Найзууд хэсэгт хэрэглэгчийн нэрээ сонгоорой.';
  static const socialFriendTag = 'найз';
  static const socialBoardEmpty = 'Найзуудаа нэмээд хамт өрсөлдөөрэй.';
  static const socialBoardEloNote = 'ELO зөвхөн найзтайгаа хийсэн онлайн тулаанаар өөрчлөгдөнө.';
  static const socialXpNote = 'XP: давталт, Монстр агнах, ханз бичих, шинэ үг, тулаан.';
  static const socialUnavailable = 'Найзын функц одоогоор боломжгүй (серверт 0026 шилжилт хийгдээгүй эсвэл интернэт алга).';
  static const socialShareSetting = 'Идэвхээ найзуудад харуулах';
  static const socialShareSettingDesc = 'Унтраавал найзууд тань зөвхөн нэрийг тань харна.';
  static const navActions = 'Үйлдэл';

  static const actionStartReview = 'Давталт эхлүүлэх';
  static const actionAddWord = 'Үг нэмэх';
  static const actionScan = 'Камераар унших';
  static const actionAudioDeck = 'Аудио багц';

  // Camera capture
  static const captureTitle = 'Камераар унших';
  static const captureIntro =
      'Япон текстийн зураг аваад эсвэл сонгоод, хадгалах үгсээ сонгоно уу.';
  static const captureTakePhoto = 'Зураг авах';
  static const captureFromGallery = 'Зургийн сангаас';
  static const captureAnotherPhoto = 'Өөр зураг нэмэх';
  static const captureReading = 'Текст уншиж байна…';
  static const captureNothingFound =
      'Энэ зургаас япон текст олдсонгүй. Илүү ойроос, тод гэрэлтэй дахин оролдоно уу.';
  static const captureFailed = 'Зургийг уншиж чадсангүй';
  static const captureSuggestions = 'Санал болгох үгс';
  static const captureSuggestionsHint = 'Бүгд сонгогдсон — хэрэггүйгээ товшиж болиулна уу.';
  static const captureText = 'Танигдсан текст';
  static const captureTextHint = 'Санал болгоогүй үг байвал текстээс тэмдэглээд «Үг болгох»-ыг дарна уу.';
  static const captureAddSelection = 'Үг болгох';
  static const captureRemovePhoto = 'Зургийг хасах';
  static const captureEditPhoto = 'Тайрах, сонгох';
  static const capturePhotoTitle = 'Тайрах, сонгох';
  static const captureModeCrop = 'Тайрах';
  static const captureModeSelect = 'Сонгох';
  static const captureCropHint = 'Булан эсвэл хүрээг чирж хэрэгтэй хэсгээ үлдээнэ үү.';
  static const captureSelectHint = 'Үгсийн дээгүүр хуруугаараа зурж сонгоно. Сонгосон үг дээгүүр зурвал болино.';
  static const captureClear = 'Цэвэрлэх';
  static const captureNewDeck = 'Шинэ багц';
  static const captureNewDeckTitle = 'Шинэ багц үүсгэх';
  static const captureFolderLabel = 'Хавтас';
  static const captureNewFolderOption = '+ Шинэ хавтас';
  static String captureDeckName(DateTime d) => 'Скан ${d.month}/${d.day}';
  static const captureAutoHint = 'Тайрсан хэсгийн санал болгох үгс автоматаар сонгогдоно.';
  static const captureAll = 'Бүгдийг сонгох';
  static const captureNone = 'Бүгдийг болих';
  static const captureDone = 'Болсон';
  static String captureDoneN(int n) => 'Болсон ($n үг)';
  static String capturePhotoN(int n) => '$n-р зураг';
  static String captureNext(int n) => 'Үргэлжлүүлэх ($n)';
  static const captureReviewTitle = 'Үгсээ шалгах';
  static const captureLookingUp = 'Толь бичгээс хайж байна…';
  static const captureAlreadyInDeck = 'Багцад байгаа';
  static const captureNoLookup = 'Толь бичигт олдсонгүй — гараар засна уу';
  static String captureSave(int n) => '$n үг хадгалах';
  static String captureSaved(int n) => '$n үг хадгалагдлаа';
  static String captureQueued(int n) =>
      'Офлайн — $n үг утсанд хадгалагдлаа, холболт сэргэхэд илгээгдэнэ';

  static const leechTitle = 'Leech аврах';
  static String leechLink(int n) => '$n хэцүү үг давтах →';
  static const leechDesc = 'Дахин дахин алддаг үгсээ тусад нь давтана.';

  // Kanji writing practice
  static const writingTitle = 'Ханз бичих';
  static const writingDesc = 'Ханз бүрийг дагаж, хагас харж, санаж бичих хичээл. Хуваарь өөрчлөгдөхгүй.';
  static const writingModelDownloading = 'Гар бичмэл танигчийг татаж байна… (зөвхөн анх удаа)';
  static const writingModelFailed =
      'Гар бичмэл танигчийг татаж чадсангүй. Интернэтээ шалгаад дахин оролдоно уу.';
  static const writingNoKanji = 'Ханзтай үг алга байна.';
  static const writingPrompt = 'Энэ үгийг ханзаар бичнэ үү';
  static const writingCheck = 'Шалгах';
  static const writingUndo = 'Буцаах';
  static const writingClear = 'Арилгах';
  static const writingReveal = 'Хариуг харах';
  static const writingCorrect = 'Зөв!';
  static const writingWrong = 'Буруу';
  static const writingRevealed = 'Хариу';
  static const writingYouWrote = 'Танигдсан:';
  static const writingNothingRead = 'Юу ч танигдсангүй — илүү том бичээд үзээрэй';
  static const writingRetry = 'Дахин бичих';
  static const writingNext = 'Дараах';
  static const writingAgain = 'Дахин эхлэх';
  static const writingPreparing = 'Хичээл бэлдэж байна…';
  static const writingStepTrace = 'Шинэ ханз — дарааллыг ажиглаад дагаж бичээрэй';
  static const writingStepPartial = 'Зарим зурлага харагдана — бүтнээр нь бичээрэй';
  static const writingStepBlank = 'Одоо санаж бичээрэй';
  static const writingStepWord = 'Үгийг бүтнээр нь бичээрэй';
  static const writingReplay = 'Дахин үзүүлэх';
  static const writingContinue = 'Үргэлжлүүлэх';
  static const writingSkip = 'Алгасах';
  static const writingLessonDone = 'Хичээл дууслаа!';
  static const writingStatWords = 'Үг';
  static const writingStatNewKanji = 'Шинэ ханз';
  static const writingStatAccuracy = 'Анхны оролдлогоор';
  static const writingNextLesson = 'Дараагийн хичээл';
  static const writingFinish = 'Дуусгах';
  static String writingStrokeCount(int drawn, int expected) => 'Зурлагын тоо буруу: $drawn / $expected';
  static String writingStrokeOrder(int i, int j) => '$i-р зурлагын дараалал буруу — энэ $j-р зурлага';
  static String writingStrokeDirection(int i) => '$i-р зурлагыг эсрэг чиглэлд татсан';
  static String writingStrokeShape(int i) => '$i-р зурлагын хэлбэр эсвэл байрлал буруу';
  static String writingShapeNotRead(String guesses) => 'Зурлагууд зөв ч ханз танигдсангүй: $guesses';
  static const writingSetupDeck = 'Багц';
  static const writingAllDecks = 'Бүх багц';
  static const writingByWord = 'Үгээр';
  static const writingByKanji = 'Ханзаар';
  static const writingPickNew = 'Шинэ ханзтай';
  static const writingPickAll = 'Бүгд';
  static const writingPickNone = 'Цэвэрлэх';
  static const writingLearnedLegend = '✓ — сурсан ханз';
  static String writingStartLesson(int n) => 'Хичээл эхлэх ($n үг)';
  static String writingKanjiSelected(int k, int w) => '$k ханз → $w үг';
  static String writingSplitHint(int n, int per) =>
      '$n шинэ ханз сонгосон — нэг хичээлд $per хүртэл, үлдсэнийг дараагийн хичээлд.';
  static const writingBackToPick = 'Өөр үг сонгох';
  static const huntDescMobile =
      'Утгыг нь сонгох, ханзаар нь бичих асуултаар дайсантай тулалдана. Бичвэл илүү хүчтэй цохино.';
  // Audio decks
  // Offline decks.
  // Public deck link (0028), same as the web's.
  static const shareDeck = 'Хуваалцах';
  // Story images (ports of the web's storyCard strings).
  static const shareStoryImage = 'Story зураг';
  static const shareTodayTitle = 'Өнөөдрийн үгс';
  static const shareTodayEmpty = 'Өнөөдөр зөв хариулсан үг алга байна — эхлээд давтаад ирээрэй.';
  static const shareImageShare = 'Хуваалцах';
  static String shareImageHint(int w, int h) =>
      'Утасны дэлгэцийн хэмжээтэй ($w×$h) — Instagram, Facebook story-д бүтэн дүүрнэ.';
  static const storyTodayHeading = 'Өнөөдөр сурсан үгс';
  static String storyMore(int n) => '+$n үг';
  static const storyNumRecalled = 'үг санасан';
  static const storyNumAdded = 'шинэ үг';
  static const storyNumStreak = 'өдөр дараалан';
  static const storyNumWords = 'үг · бүртгэлгүй тоглоно';
  static const storyStyleLabel = 'Загвар';
  static const storyStyleSeal = 'Цэнхэр';
  static const storyStyleDark = 'Бараан';
  static const storyStylePaper = 'Цайвар';
  static const storyLangLabel = 'Утга';
  static const storyLangMn = 'Монгол';
  static const storyLangEn = 'English';
  static const storyLangBoth = 'Хоёул';
  static const storyLayoutLabel = 'Хэлбэр';
  static const storyLayoutGrid = 'Тор';
  static const storyLayoutList = 'Жагсаалт';
  static const storyLayoutSpotlight = 'Нэг үг';
  static const storyLayoutQuiz = 'Асуулт';
  static const storyNextWord = 'Өөр үг';
  static const storyQuizPrompt = 'Энэ үг ямар утгатай вэ?';
  static const storyQuizAnswer = 'Хариулт';
  static const storyQuizNeedsWords = 'Асуулт хийхэд утгатай 4+ үг хэрэгтэй';
  static const sharedBy = 'Хуваалцсан багц';
  static const shareDeckTitle = 'Багцыг хуваалцах';
  static const shareDeckDesc = 'Холбоосыг авсан хэн ч бүртгэлгүйгээр үгсийг харж, хөтөч дээр давтаж тоглож чадна. Таны нэр, давтлагын түүх харагдахгүй. Холбоос 24 цаг хүчинтэй.';
  static const shareLinkOn = 'Холбоос идэвхтэй';
  static const shareLinkEnable = 'Холбоос үүсгэх';
  static const shareLinkDisable = 'Холбоосыг хаах';
  static const shareLinkDisableHint = '24 цагийн дараа өөрөө хаагдана. Хаавал шууд ажиллахаа болино; дахин нээвэл шинэ холбоос үүснэ.';
  static const shareCopy = 'Хуулах';
  static const shareCopied = 'Холбоосыг хууллаа';
  static const shareSend = 'Илгээх';
  static const shareFailed = 'Хуваалцах тохиргоо хадгалагдсангүй.';
  static String shareTimeLeft(Duration d) =>
      d.inMinutes >= 60 ? '${d.inHours} ц ${d.inMinutes % 60} мин үлдсэн' : '${d.inMinutes.clamp(1, 59)} мин үлдсэн';
  static const avatarChange = 'Зураг солих';
  static const avatarRemove = 'Арилгах';
  static const avatarFailed = 'Зургийг хадгалж чадсангүй.';
  static const offlineDownload = 'Офлайнд татах';
  static const offlineRefresh = 'Офлайн хуулбар шинэчлэх';
  static const offlineRemove = 'Офлайн хуулбар устгах';
  static const offlineDownloading = 'Багцыг татаж байна…';
  static String offlineReady(int n) => '$n карт офлайнд бэлэн. Интернэтгүй үед ч давтаж болно.';
  static const offlineDownloadFailed = 'Татаж чадсангүй — интернэт холболтоо шалгана уу.';
  static const offlineRemoved = 'Офлайн хуулбарыг устгалаа.';
  static const offlineBadge = 'офлайн';
  static const audioTitle = 'Аудио багц';
  static const audioManage = 'Бүгд';
  static const audioIntro = 'Багцаа MP3 болгоод алхаж, явж байхдаа сонсоорой. Япон үг, дараа нь англи утга нь уншигдана.';
  static const audioMnNote = 'Монгол утгыг дуугаар уншуулах боломжгүй тул тоглуулагч дээр бичгээр харагдана.';
  static const audioCreate = 'Үүсгэх';
  static const audioOpenInMusic = 'Хөгжмийн аппаар сонсох (дэлгэц түгжигдсэн үед)';
  static const audioRegenerate = 'Дахин үүсгэх';
  static const audioPlay = 'Тоглуулах';
  static const audioShare = 'MP3 хуваалцах';
  static const audioDelete = 'Аудиог устгах';
  static String audioBuilding(int done, int total) => 'Дуу бэлдэж байна… $done / $total';
  static const audioDeckFailed = 'Дуу татаж чадсангүй. Интернэтээ шалгаад дахин оролдоно уу.';
  static String audioSkipped(int n) => '$n үгийн дуу татагдсангүй, алгаслаа';
  static const audioOptionsTitle = 'Аудио тохиргоо';
  static const audioEnglish = 'Англи утгыг уншуулах';
  static const audioRepeat = 'Үг бүрийг давтах';
  static const audioPause = 'Завсарлага';
  static const audioShuffle = 'Санамсаргүй дараалал';
  static const audioNoWords = 'Энэ багцад үг алга байна.';
  static String audioSummary(int words, String length) => '$words үг · $length';
  static String audioRepeatN(int n) => '$n удаа';
  static String audioPauseS(double s) => '${s.toStringAsFixed(s == s.roundToDouble() ? 0 : 1)} сек';
  static const kanjiVgCredit = 'Зурлагын дараалал: KanjiVG (CC BY-SA 3.0)';
  static String writingProgress(int i, int n) => '$i / $n';
  static String writingDone(int correct, int total) => '$total үгээс $correct-г зөв бичлээ';

  static const settings = 'Тохиргоо';
  static const appearance = 'Харагдах байдал';
  static const themeSystem = 'Утасны дагуу';
  static const themeLight = 'Цагаан';
  static const themeDark = 'Бараан';
  static const themeBlue = 'Цэнхэр';
  static const themePaper = 'Цайвар';
  static const signOut = 'Гарах';
  static const privacy = 'Нууцлалын бодлого';
  static const reminder = 'Өдөр тутмын сануулга';

  static const newFolderInside = 'Дотор нь хавтас нэмэх';
  static const rename = 'Нэр солих';
  static const moveTo = 'Зөөх';
  static const moveToRoot = 'Үндсэн түвшин';
  static const name = 'Нэр';
  static const create = 'Үүсгэх';
  static String wordCount(int n) => '$n үг';

  static const heroResting = 'Таны баатар амарч байна';
  static const pvpPlaceholder =
      'Найзтайгаа тулах горим удахгүй. Одоохондоо мангас агнаарай!';

  static const retentionTitle = 'Санах чадвар';
  static const retentionLabel = 'Хадгалалт';
  static const retentionHint = 'Давталтын картуудаас «Дахин» биш хариулсан хувь';
  static const accuracyLabel = 'Нарийвчлал';
  static const accuracyHint = 'Бүх хариултаас зөвийн хувь';
  static String lastNDays(int n) => 'Сүүлийн $n хоног';

  static const noJapaneseVoice =
      'Утсанд япон хэлний дуу хоолой суугаагүй байна. Тохиргоо → Текст-яриа хэсгээс татаж авна уу.';
  static const back = 'Буцах';
  static const offline = 'Офлайн';
  static const loadFailed = 'Уншиж чадсангүй';
  static const retry = 'Дахин оролдох';
}

/// Weekday labels, Sunday first, matching web/src/app/decks/_lib/dates.ts.
const weekdayMn = ['Ня', 'Да', 'Мя', 'Лх', 'Пү', 'Ба', 'Бя'];

/// Month labels, matching `MONTH_MN` in dates.ts.
const monthMn = [
  '1-р', '2-р', '3-р', '4-р', '5-р', '6-р',
  '7-р', '8-р', '9-р', '10-р', '11-р', '12-р',
];
