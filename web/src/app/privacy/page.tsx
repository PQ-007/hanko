import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Hanko",
  description:
    "What data Hanko collects, why, where it is stored, and how to delete it.",
};

// Static, unauthenticated, and deliberately not behind the Supabase client:
// the Chrome Web Store and addons.mozilla.org both fetch this URL anonymously
// during review, so it must render without a session.
export const dynamic = "force-static";

const LAST_UPDATED = "30 August 2026";
const CONTACT = "bilguuntushig.a@gmail.com";

export default function PrivacyPage() {
  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-16">
      <header className="mb-12">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/hanko.svg" alt="" className="mb-4 h-12 w-12" />
        <h1 className="text-3xl font-semibold tracking-tight">Privacy Policy</h1>
        <p className="mt-2 text-sm text-ink-mute">
          Hanko — browser extension and web app. Last updated {LAST_UPDATED}.
        </p>
      </header>

      <Callout>
        Hanko stores the vocabulary you choose to save, so it can sync between
        your devices and schedule your reviews. It does not track your browsing,
        does not sell data, and does not use your data for advertising.
      </Callout>

      <Section title="Who this covers">
        <P>
          This policy applies to the Hanko browser extension (Chrome and
          Firefox) and the Hanko web app at{" "}
          <Code>hanko-amber.vercel.app</Code>. They share a single account and a
          single database.
        </P>
      </Section>

      <Section title="What is collected">
        <P>
          Only two kinds of data: what is needed to sign you in, and what you
          deliberately save.
        </P>
        <Table
          rows={[
            [
              "Account information",
              "Your email address, display name, and profile picture URL, received from Google when you sign in. Used to identify your account and nothing else.",
            ],
            [
              "Vocabulary you save",
              "The word you selected, its reading, its English meaning, its Mongolian translation, and the deck and folder names you create. A word is only ever saved when you explicitly trigger a save.",
            ],
            [
              "Review history",
              "For each card you review: the rating you gave, how long you took to answer, and when. This is what produces your scheduling, streaks, and statistics — the app cannot function without it.",
            ],
            [
              "Audio files",
              "If you generate pronunciation audio for a word, the resulting file is stored in your own private folder and is readable only by your account.",
            ],
            [
              "Local extension storage",
              "The extension keeps a copy of your decks and words on your own device so it works offline, along with your sign-in token so you stay logged in. This never leaves your browser except to sync with your own account.",
            ],
          ]}
        />
      </Section>

      <Section title="What is not collected">
        <List
          items={[
            "Your browsing history, or the addresses of pages you visit.",
            "Page content, beyond the text you yourself select and choose to save.",
            "Your location, IP-derived or otherwise, beyond the transient logs kept by our hosting providers.",
            "Passwords or credentials. Sign-in is handled entirely by Google; Hanko never sees your password.",
            "Payment information. Hanko is free and takes no payments.",
          ]}
        />
        <P>
          The extension&rsquo;s content script runs on every site because Japanese
          text can appear on any site. It reads only your current text selection,
          and only at the moment you trigger a save with the right-click menu or
          the keyboard shortcut. It is idle otherwise.
        </P>
      </Section>

      <Section title="Why each permission is requested">
        <Table
          rows={[
            ["Context menus", "Adds the single right-click entry that saves a selected word."],
            ["Storage", "Keeps your decks on your device so the extension opens instantly and works offline."],
            ["Active tab", "Reads your selection when you press the save shortcut, for that tab only, at that moment only."],
            ["Alarms", "Runs a background sync every five minutes so your words reach your other devices."],
            ["Notifications", "Confirms that a word was saved, since saving usually happens with no window open."],
            ["Site access", "Lets you capture a word on whichever page you are reading."],
          ]}
        />
      </Section>

      <Section title="Third parties">
        <P>
          Hanko sends data to four services, each for one purpose. None of them
          receive your data for their own advertising or profiling.
        </P>
        <Table
          rows={[
            [
              "Supabase",
              "Hosts the database, authentication, and audio storage. This is where your account and your words live.",
            ],
            [
              "Vercel",
              "Hosts the web app and its API endpoints.",
            ],
            [
              "Google",
              "Provides sign-in. Separately, the word being defined is sent to Google Translate to produce the Mongolian meaning. Only the word itself is sent — never your identity.",
            ],
            [
              "Jisho.org",
              "Looked up to find a word's reading and English meaning. Only the word you selected is sent, with no account information attached.",
            ],
          ]}
        />
      </Section>

      <Section title="How your data is protected">
        <P>
          Every table is protected by PostgreSQL row-level security, scoped to
          your user ID. This is enforced by the database itself, not by the app:
          a request carrying your token can read your rows and no one else&rsquo;s,
          even if a client is modified. Audio files are held in a private bucket
          under a path keyed to your user ID. All traffic is over HTTPS.
        </P>
        <P>
          No engineer routinely browses user data, and no data is shared with,
          sold to, or licensed to any third party for any purpose.
        </P>
      </Section>

      <Section title="Keeping and deleting your data">
        <P>
          Your data is kept for as long as your account exists, because a
          spaced-repetition system is only useful with its history intact.
        </P>
        <P>
          You can delete individual words and whole decks at any time from the
          web app or the extension. To delete your account and everything in it,
          email <Mail>{CONTACT}</Mail> from the address you signed up with.
          Deletion removes your profile, decks, words, review history, and audio
          files, and it cannot be undone. Clearing the extension&rsquo;s local data is
          done by removing the extension from your browser.
        </P>
      </Section>

      <Section title="Children">
        <P>
          Hanko is not directed at children under 13 and does not knowingly
          collect their data.
        </P>
      </Section>

      <Section title="Changes">
        <P>
          If this policy changes materially, the date at the top of this page
          will change and the new version will be published here before it takes
          effect.
        </P>
      </Section>

      <Section title="Contact">
        <P>
          Questions about this policy, or requests concerning your data:{" "}
          <Mail>{CONTACT}</Mail>.
        </P>
      </Section>

      <footer className="mt-16 border-t border-line pt-6 text-sm text-ink-mute">
        <Link href="/" className="underline hover:text-ink">
          Back to Hanko
        </Link>
      </footer>
    </main>
  );
}

/* ---------------------------------------------------------------- primitives */

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-10">
      <h2 className="mb-3 text-lg font-semibold tracking-tight">{title}</h2>
      <div className="space-y-3">{children}</div>
    </section>
  );
}

function P({ children }: { children: React.ReactNode }) {
  return <p className="text-[0.9375rem] leading-relaxed text-ink-soft">{children}</p>;
}

function Callout({ children }: { children: React.ReactNode }) {
  return (
    <p className="mb-12 rounded-card border border-line bg-paper-dim px-5 py-4 text-[0.9375rem] leading-relaxed text-ink">
      {children}
    </p>
  );
}

function List({ items }: { items: string[] }) {
  return (
    <ul className="space-y-2">
      {items.map((item) => (
        <li
          key={item}
          className="flex gap-3 text-[0.9375rem] leading-relaxed text-ink-soft"
        >
          <span aria-hidden className="mt-2 h-1 w-1 shrink-0 rounded-full bg-seal" />
          <span>{item}</span>
        </li>
      ))}
    </ul>
  );
}

function Table({ rows }: { rows: [string, string][] }) {
  return (
    <dl className="overflow-hidden rounded-card border border-line">
      {rows.map(([term, description], i) => (
        <div
          key={term}
          className={`grid gap-1 px-5 py-4 sm:grid-cols-[11rem_1fr] sm:gap-5 ${
            i % 2 ? "bg-paper-dim/50" : "bg-white/40"
          }`}
        >
          <dt className="text-[0.9375rem] font-medium text-ink">{term}</dt>
          <dd className="text-[0.9375rem] leading-relaxed text-ink-soft">
            {description}
          </dd>
        </div>
      ))}
    </dl>
  );
}

function Code({ children }: { children: React.ReactNode }) {
  return (
    <code className="rounded bg-paper-deep px-1.5 py-0.5 font-mono text-[0.85em] text-ink">
      {children}
    </code>
  );
}

function Mail({ children }: { children: string }) {
  return (
    <a href={`mailto:${children}`} className="text-seal underline hover:text-seal-dark">
      {children}
    </a>
  );
}
