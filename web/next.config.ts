import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The .apkg route reads sql.js's wasm file at runtime via require.resolve.
  // Ensure it's traced into the serverless bundle on Vercel.
  outputFileTracingIncludes: {
    "/api/decks/[id]/apkg": ["./node_modules/sql.js/dist/sql-wasm.wasm"],
  },
  // sql.js is a CommonJS module that references "fs"/"path"; keep it external so
  // it isn't bundled/transformed on the server.
  serverExternalPackages: ["sql.js"],
  // The user guide is a static page in public/doc (images in public/doc/img).
  // /doc serves it with the address bar left at /doc; it is outside /decks,
  // so it opens without signing in.
  async rewrites() {
    return [{ source: "/doc", destination: "/doc/index.html" }];
  },
};

export default nextConfig;
