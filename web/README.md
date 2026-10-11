# Hanko — вэбсайт

Next.js + Supabase + Tailwind. Багц удирдах, давтах, статистик, найзууд,
тулаан. Төслийн ерөнхий танилцуулгыг **[үндсэн README](../README.md)**-ээс.

## Ажиллуулах

```bash
npm install
npm run dev      # http://localhost:3000
npm run build
npm run lint
npm test         # node --test src/**/*.test.ts — runner, нэмэлт сангүй
```

`.env.local`-д Supabase URL, publishable key хэрэгтэй (git-д оруулахгүй).
Supabase төсөл, Google нэвтрэлт, deploy — **[SETUP.md](../SETUP.md)**.

## Бүтэц

```text
src/app/decks/          нэвтэрсэн хэрэглэгчийн хэсэг (proxy нь /login руу илгээнэ)
  _components/          багц, үг, нэмэх цонх, гар бичмэл, sidebar, график…
  _lib/                 Supabase client, монгол текст (strings.ts), туслах функцууд
  review/battle/        Мангас агнах
  review/duel/          нүүр тулах тулаан (PvP + бот), ready room, чат
  practice/             энгийн карт давталт
  writing/              ханз бичих хичээл
  stats/ friends/ settings/
src/app/share/          нийтийн багцын линк (нэвтрэлтгүй)
src/app/extension/      extension-ийн нэвтрэх гүүр (/extension/connect)
src/app/api/            lookup (Jisho), translate, экспорт (.apkg/.txt), аудио
src/lib/                srs.ts, jisho.ts, translate.ts, Supabase SSR client
src/ui/                 Hanko-ийн өөрийн дүрсүүд (Icon.tsx), Dialog
```

## Санах зүйлс

- Энэ Next.js-ийн шинэ хувилбар — API, файлын бүтэц таны мэддэгээс
  өөр байж болно ([AGENTS.md](AGENTS.md)).
- Хуваарь серверт (`review_card()`) тооцогддог — client-д SM-2 давтан
  бичихгүй.
- Өнгийг token-оор (`bg-surface`, `seal`…) — хатуу өнгө бичихгүй; гурван
  загвар бүгдэд зөв харагдах ёстой.
- Дүрс нь `@/ui/icons`-оос (lucide-react хэрэглэхгүй).
- Хуудсыг гүйлгэх бол `window` биш `#hk-main`-ийг гүйлгэнэ.

Архитектур, шийдвэрүүдийн шалтгаан — **[CLAUDE.md](../CLAUDE.md)**.
