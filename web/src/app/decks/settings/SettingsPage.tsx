"use client";

import { useEffect, useRef, useState } from "react";
import { Check, LogOut } from "@/ui/icons";
import { supabase } from "../_lib/db";
import { T } from "../_lib/strings";
import { normalizeHandle } from "../_lib/social";
import { readTheme, saveTheme, type ThemeChoice } from "../_lib/theme";
import LoadingScene from "../review/battle/_components/LoadingScene";

// Тохиргоо: your profile (picture, name, username), how the app looks, how
// much it asks of you each day, and who sees your activity. Everything here
// is your own profiles row (RLS: update own) except the theme, which is per
// device, and the picture, which goes to the `avatars` bucket (0029).

interface Profile {
  id: string;
  email: string | null;
  name: string | null;
  image: string | null;
  handle: string | null;
  share_activity: boolean;
  new_per_day: number;
  reviews_per_day: number;
  day_cutoff_hour: number;
  timezone: string | null;
}

const AVATAR_PX = 256;

/** Centre-crop to a square and re-encode as WebP — small, and strips EXIF (GPS). */
async function toAvatar(file: File): Promise<Blob> {
  const bmp = await createImageBitmap(file);
  const side = Math.min(bmp.width, bmp.height);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = AVATAR_PX;
  const ctx = canvas.getContext("2d")!;
  ctx.drawImage(bmp, (bmp.width - side) / 2, (bmp.height - side) / 2, side, side, 0, 0, AVATAR_PX, AVATAR_PX);
  bmp.close();
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("encode failed"))), "image/webp", 0.86)
  );
}

export default function SettingsPage() {
  const [p, setP] = useState<Profile | null>(null);
  const [failed, setFailed] = useState(false);

  async function load() {
    const { data: auth } = await supabase.auth.getUser();
    const { data, error } = await supabase
      .from("profiles")
      .select("id, email, name, image, handle, share_activity, new_per_day, reviews_per_day, day_cutoff_hour, timezone")
      .eq("id", auth.user?.id ?? "")
      .maybeSingle();
    if (error || !data) return setFailed(true);
    setP({ ...(data as Profile), email: (data as Profile).email ?? auth.user?.email ?? null });
  }

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- one fetch on mount
    void load();
  }, []);

  if (failed) return <p className="mx-auto max-w-2xl p-8 text-sm text-ink-mute">{T.settingsLoadFailed}</p>;
  if (!p) return <LoadingScene label={T.loading} />;

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-4 px-4 py-6 sm:py-10">
      <h1 className="text-2xl font-bold tracking-tight text-ink">{T.settingsTitle}</h1>
      <ProfileCard profile={p} onChanged={load} />
      <ThemeCard />
      <LearningCard profile={p} onChanged={load} />
      <PrivacyCard profile={p} onChanged={load} />
      <form action="/auth/signout" method="post" className="hk-card flex items-center justify-between gap-3 p-5">
        <div className="min-w-0">
          <p className="text-sm font-semibold text-ink">{T.settingsSignedInAs}</p>
          <p className="truncate text-sm text-ink-mute">{p.email}</p>
        </div>
        <button type="submit" className="hk-btn hk-btn-quiet shrink-0 px-4 py-2 text-sm text-red-700">
          <LogOut size={15} /> {T.signOut}
        </button>
      </form>
    </div>
  );
}

function Section({ title, desc, children }: { title: string; desc?: string; children: React.ReactNode }) {
  return (
    <section className="hk-card p-5">
      <h2 className="text-base font-bold text-ink">{title}</h2>
      {desc && <p className="mt-0.5 text-xs text-ink-mute">{desc}</p>}
      <div className="mt-4">{children}</div>
    </section>
  );
}

function Saved({ show }: { show: boolean }) {
  return (
    <span className={`flex items-center gap-1 text-xs font-semibold text-emerald-700 transition-opacity ${show ? "opacity-100" : "opacity-0"}`}>
      <Check size={13} /> {T.settingsSaved}
    </span>
  );
}

function useFlash(): [boolean, () => void] {
  const [on, setOn] = useState(false);
  const t = useRef<ReturnType<typeof setTimeout> | null>(null);
  return [
    on,
    () => {
      setOn(true);
      if (t.current) clearTimeout(t.current);
      t.current = setTimeout(() => setOn(false), 2000);
    },
  ];
}

const inputCls =
  "w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink outline-none focus:border-seal focus:ring-2 focus:ring-seal-tint";

// ---- Profile -----------------------------------------------------------------

function ProfileCard({ profile, onChanged }: { profile: Profile; onChanged: () => Promise<void> }) {
  const [name, setName] = useState(profile.name ?? "");
  const [handle, setHandle] = useState(profile.handle ?? "");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, flash] = useFlash();
  const [uploading, setUploading] = useState(false);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const dirty = name.trim() !== (profile.name ?? "") || handle.trim().replace(/^@/, "").toLowerCase() !== (profile.handle ?? "");

  async function save() {
    const h = handle.trim() === "" ? null : normalizeHandle(handle);
    if (handle.trim() !== "" && !h) return setError(T.socialHandleFormat);
    setBusy(true);
    const { error: err } = await supabase
      .from("profiles")
      .update({ name: name.trim() || null, handle: h })
      .eq("id", profile.id);
    setBusy(false);
    if (err) {
      // 23505 unique violation, 23514 check violation (the server's own rule).
      return setError(err.code === "23505" ? T.socialHandleTaken : err.code === "23514" ? T.socialHandleFormat : T.socialHandleFailed);
    }
    setError(null);
    flash();
    await onChanged();
  }

  async function pickPhoto(file: File | undefined) {
    if (!file) return;
    setPhotoError(null);
    if (!file.type.startsWith("image/")) return setPhotoError(T.settingsPhotoType);
    setUploading(true);
    try {
      const blob = await toAvatar(file);
      const path = `${profile.id}/${Date.now()}.webp`;
      const bucket = supabase.storage.from("avatars");
      const { error: upErr } = await bucket.upload(path, blob, { contentType: "image/webp", upsert: false });
      if (upErr) throw upErr;
      const url = bucket.getPublicUrl(path).data.publicUrl;
      const { error: dbErr } = await supabase.from("profiles").update({ image: url }).eq("id", profile.id);
      if (dbErr) throw dbErr;
      // Old pictures are only clutter now; best effort.
      const { data: old } = await bucket.list(profile.id);
      const stale = (old ?? []).map((o) => `${profile.id}/${o.name}`).filter((n) => n !== path);
      if (stale.length) await bucket.remove(stale);
      await onChanged();
    } catch {
      setPhotoError(T.settingsPhotoFailed);
    } finally {
      setUploading(false);
      if (fileInput.current) fileInput.current.value = "";
    }
  }

  async function removePhoto() {
    await supabase.from("profiles").update({ image: null }).eq("id", profile.id);
    const bucket = supabase.storage.from("avatars");
    const { data: old } = await bucket.list(profile.id);
    if (old?.length) await bucket.remove(old.map((o) => `${profile.id}/${o.name}`));
    await onChanged();
  }

  const shownName = name.trim() || profile.handle || profile.email || "?";

  return (
    <Section title={T.settingsProfile}>
      <div className="flex items-center gap-4">
        {profile.image?.startsWith("https://") ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={profile.image} alt="" width={72} height={72} className="h-[72px] w-[72px] shrink-0 rounded-full object-cover" referrerPolicy="no-referrer" />
        ) : (
          <span className="flex h-[72px] w-[72px] shrink-0 items-center justify-center rounded-full bg-seal-tint text-2xl font-bold text-seal">
            {shownName.charAt(0).toUpperCase()}
          </span>
        )}
        <div className="flex flex-col items-start gap-1.5">
          <div className="flex flex-wrap gap-2">
            <button onClick={() => fileInput.current?.click()} disabled={uploading} className="hk-btn hk-btn-quiet px-3 py-1.5 text-sm">
              {uploading ? T.settingsUploading : T.settingsChangePhoto}
            </button>
            {profile.image && (
              <button onClick={removePhoto} disabled={uploading} className="rounded-control px-3 py-1.5 text-sm font-medium text-ink-soft hover:bg-paper-dim">
                {T.settingsRemovePhoto}
              </button>
            )}
          </div>
          <p className={`text-xs ${photoError ? "text-red-600" : "text-ink-mute"}`}>{photoError ?? T.settingsPhotoHint}</p>
          <input ref={fileInput} type="file" accept="image/*" hidden onChange={(e) => pickPhoto(e.target.files?.[0])} />
        </div>
      </div>

      <div className="mt-5 grid gap-4 sm:grid-cols-2">
        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-medium text-ink-soft">{T.settingsDisplayName}</span>
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={40} className={inputCls} />
        </label>
        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-medium text-ink-soft">{T.socialHandleLabel}</span>
          <span className="flex items-center rounded-control border border-line bg-surface pl-3 focus-within:border-seal focus-within:ring-2 focus-within:ring-seal-tint">
            <span className="text-sm text-ink-mute">@</span>
            <input
              value={handle}
              onChange={(e) => {
                setHandle(e.target.value);
                setError(null);
              }}
              maxLength={21}
              className="min-w-0 flex-1 bg-transparent px-1 py-2 text-sm text-ink outline-none"
            />
          </span>
          <span className={`text-xs ${error ? "text-red-600" : "text-ink-mute"}`}>{error ?? T.socialHandleFormat}</span>
        </label>
      </div>
      <label className="mt-4 flex flex-col gap-1.5">
        <span className="text-xs font-medium text-ink-soft">{T.settingsEmail}</span>
        <input value={profile.email ?? ""} readOnly disabled className={`${inputCls} cursor-not-allowed bg-paper-dim text-ink-mute`} />
        <span className="text-xs text-ink-mute">{T.settingsEmailHint}</span>
      </label>

      <div className="mt-4 flex items-center justify-end gap-3">
        <Saved show={saved} />
        <button onClick={save} disabled={!dirty || busy} className="hk-btn hk-btn-primary px-4 py-2 text-sm disabled:opacity-50">
          {T.save}
        </button>
      </div>
    </Section>
  );
}

// ---- Appearance --------------------------------------------------------------

function ThemeCard() {
  const [theme, setTheme] = useState<ThemeChoice>("system");
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the stored choice is browser-only
    setTheme(readTheme());
  }, []);

  // "System" must keep following the OS while the page is open.
  useEffect(() => {
    if (theme !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const on = () => saveTheme("system");
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, [theme]);

  const options: { value: ThemeChoice; label: string; swatch: string }[] = [
    { value: "light", label: T.themeLight, swatch: "bg-[#faf7f0] border-[#d8d0be]" },
    { value: "dark", label: T.themeDark, swatch: "bg-[#14171c] border-[#363d48]" },
    { value: "system", label: T.themeSystem, swatch: "bg-[linear-gradient(135deg,#faf7f0_50%,#14171c_50%)] border-line" },
  ];

  return (
    <Section title={T.settingsAppearance} desc={T.settingsAppearanceDesc}>
      <div role="radiogroup" aria-label={T.settingsAppearance} className="grid grid-cols-3 gap-2">
        {options.map((o) => (
          <button
            key={o.value}
            role="radio"
            aria-checked={theme === o.value}
            onClick={() => {
              setTheme(o.value);
              saveTheme(o.value);
            }}
            className={`flex flex-col items-center gap-2 rounded-control border-2 px-2 py-3 text-sm font-medium transition ${
              theme === o.value ? "border-seal text-ink" : "border-line-soft text-ink-soft hover:border-line"
            }`}
          >
            <span className={`h-9 w-14 rounded-md border ${o.swatch}`} />
            {o.label}
          </button>
        ))}
      </div>
    </Section>
  );
}

// ---- Learning ----------------------------------------------------------------

function LearningCard({ profile, onChanged }: { profile: Profile; onChanged: () => Promise<void> }) {
  const [newPerDay, setNewPerDay] = useState(String(profile.new_per_day));
  const [reviewsPerDay, setReviewsPerDay] = useState(String(profile.reviews_per_day));
  const [cutoff, setCutoff] = useState(profile.day_cutoff_hour);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, flash] = useFlash();

  const n = Math.round(Number(newPerDay));
  const r = Math.round(Number(reviewsPerDay));
  // Bounds match the profiles check constraints (0023, 0007).
  const valid = newPerDay.trim() !== "" && n >= 0 && n <= 999 && reviewsPerDay.trim() !== "" && r >= 0 && r <= 9999;
  const dirty = n !== profile.new_per_day || r !== profile.reviews_per_day || cutoff !== profile.day_cutoff_hour;

  async function save() {
    if (!valid) return setError(T.settingsLimitsInvalid);
    setBusy(true);
    const { error: err } = await supabase
      .from("profiles")
      .update({ new_per_day: n, reviews_per_day: r, day_cutoff_hour: cutoff })
      .eq("id", profile.id);
    setBusy(false);
    if (err) return setError(T.settingsSaveFailed);
    setError(null);
    flash();
    await onChanged();
  }

  return (
    <Section title={T.settingsLearning} desc={T.settingsLearningDesc}>
      <div className="grid gap-4 sm:grid-cols-3">
        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-medium text-ink-soft">{T.settingsNewPerDay}</span>
          <input type="number" inputMode="numeric" min={0} max={999} value={newPerDay} onChange={(e) => setNewPerDay(e.target.value)} className={inputCls} />
        </label>
        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-medium text-ink-soft">{T.settingsReviewsPerDay}</span>
          <input type="number" inputMode="numeric" min={0} max={9999} value={reviewsPerDay} onChange={(e) => setReviewsPerDay(e.target.value)} className={inputCls} />
        </label>
        <label className="flex flex-col gap-1.5">
          <span className="text-xs font-medium text-ink-soft">{T.settingsDayCutoff}</span>
          <select value={cutoff} onChange={(e) => setCutoff(Number(e.target.value))} className={inputCls}>
            {Array.from({ length: 24 }, (_, h) => (
              <option key={h} value={h}>
                {String(h).padStart(2, "0")}:00
              </option>
            ))}
          </select>
        </label>
      </div>
      <p className="mt-2 text-xs text-ink-mute">{T.settingsTimezone(profile.timezone ?? "UTC")}</p>
      {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
      <div className="mt-4 flex items-center justify-end gap-3">
        <Saved show={saved} />
        <button onClick={save} disabled={!dirty || busy} className="hk-btn hk-btn-primary px-4 py-2 text-sm disabled:opacity-50">
          {T.save}
        </button>
      </div>
    </Section>
  );
}

// ---- Privacy -----------------------------------------------------------------

function PrivacyCard({ profile, onChanged }: { profile: Profile; onChanged: () => Promise<void> }) {
  const [on, setOn] = useState(profile.share_activity);
  async function toggle() {
    const next = !on;
    setOn(next);
    const { error } = await supabase.from("profiles").update({ share_activity: next }).eq("id", profile.id);
    if (error) setOn(!next);
    else await onChanged();
  }
  return (
    <Section title={T.settingsPrivacy}>
      <button role="switch" aria-checked={on} onClick={toggle} className="flex w-full items-center justify-between gap-4 text-left">
        <span>
          <span className="block text-sm font-medium text-ink">{T.socialShareSetting}</span>
          <span className="block text-xs text-ink-mute">{T.socialShareSettingDesc}</span>
        </span>
        <span className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${on ? "bg-seal" : "bg-paper-deep"}`}>
          <span className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all ${on ? "left-[22px]" : "left-0.5"}`} />
        </span>
      </button>
    </Section>
  );
}
