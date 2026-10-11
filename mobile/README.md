# Hanko — мобайл апп

Flutter + Riverpod + Drift. Вэбтэй ижил Supabase төсөл, ижил хүснэгт, ижил
RPC — вэбийн сервер рүү хандахгүй, бие даан ажиллана. Төслийн ерөнхий
танилцуулгыг **[үндсэн README](../README.md)**-ээс.

## Ажиллуулах

```bash
cp env.example.json env.json   # Supabase URL, publishable key, Google client ID
flutter pub get
flutter run --dart-define-from-file=env.json
flutter analyze
flutter test
```

`env.json` git-д орохгүй. VS Code-ийн `.vscode/launch.json` түүнийг ашигладаг.

## Бүтэц

```text
lib/core/           Supabase repository, Drift (офлайн), толь/орчуулга,
                    загвар (theme), текст (strings.dart), сануулга
lib/features/
  library/ decks/   багц, үг, нэмэх sheet, гар бичмэл (ML Kit), олон сонголт
  capture/          камераар үг таних (ML Kit OCR)
  review/           давталт, офлайн outbox
  battle/           Мангас агнах, дүрсийн sprite
  duel/ pvp/        нүүр тулах тулаан, ready room, чат
  writing/          ханз бичих хичээл
  audio/            аудио багц (MP3), жишээ өгүүлбэр
  stats/ social/ share/ settings/ home/ shell/
```

## Санах зүйлс

- **Release build-ийг заавал утсан дээр ажиллуулж шалга** — ML Kit-ийн R8
  дүрмүүд (`android/app/proguard-rules.pro`) debug-д илэрдэггүй.
- **`flutter run` эхлэхгүй бол:** release build Бараан/Цэнхэр загвар дээр
  нүүрний дүрсээ солиод `.IconPaper`-ийг унтраасан байна. Аппаа нээж
  **Цайвар** руу шилжүүлээд гарвал засагдана — adb-ээр засах боломжгүй.
- Dart Android-ийн үндсэн thread дээр ажилладаг (Flutter 3.29+) — удаан
  синхрон ажлыг `Isolate.run`-д өгнө, эс бөгөөс ANR.
- Вэбтэй давхардсан дүрмүүд (тулааны тооцоо, асуулт, чатын дүрэм…) хоёр
  талд ижил тестийн тохиолдлоор бэхлэгдсэн — нэг талыг өөрчилбөл нөгөөг нь
  бас өөрчил.

Архитектур, шийдвэрүүдийн шалтгаан — **[CLAUDE.md](../CLAUDE.md)**.
