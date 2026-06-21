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
};

export default nextConfig;
