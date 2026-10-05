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

  // ---- Mobile only -------------------------------------------------------
  static const navHome = 'Нүүр';
  static const navStats = 'Статистик';
  static const navPvp = 'Тулаан';
  static const navLibrary = 'Сан';
  static const navActions = 'Үйлдэл';

  static const actionStartReview = 'Давталт эхлүүлэх';
  static const actionAddWord = 'Үг нэмэх';
  static const actionScan = 'Камераар унших';
  static const actionAudioDeck = 'Аудио багц үүсгэх';
  static const nextStage = 'Удахгүй нэмэгдэнэ';

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

  static const speedRoundTitle = 'Хурдан давталт';
  static const speedRoundDesc =
      'Эзэмшсэн үгсээ хурдан шалгана. Хуваарь өөрчлөгдөхгүй.';
  static const leechTitle = 'Leech аврах';
  static const leechDesc = 'Дахин дахин алддаг үгсээ тусад нь давтана.';

  static const settings = 'Тохиргоо';
  static const appearance = 'Харагдах байдал';
  static const themeSystem = 'Утасны дагуу';
  static const themeLight = 'Цайвар';
  static const themeDark = 'Бараан';
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
