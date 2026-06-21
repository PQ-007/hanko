import { createClient } from "@/lib/supabase/server";

export default async function DecksLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <div className="flex min-h-screen flex-col bg-gray-50 text-gray-900">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-3 shadow-sm sm:px-6">
        <h1 className="text-lg font-semibold">Vocab Decks</h1>
        <div className="flex items-center gap-4 text-sm text-gray-500">
          <span className="hidden sm:inline">{user?.email}</span>
          <form action="/auth/signout" method="post">
            <button
              type="submit"
              className="rounded border border-gray-300 px-3 py-1 font-medium text-gray-700 transition hover:bg-gray-50"
            >
              Гарах
            </button>
          </form>
        </div>
      </header>
      <main className="flex-1">{children}</main>
    </div>
  );
}
