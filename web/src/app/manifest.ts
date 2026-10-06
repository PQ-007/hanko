import type { MetadataRoute } from "next";

// "Add to Home Screen" opens Hanko full-screen, without the browser's bars —
// the web app then behaves like an installed app on phones and tablets.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Hanko",
    short_name: "Hanko",
    description: "Japanese vocabulary with spaced repetition",
    start_url: "/decks/stats",
    scope: "/",
    display: "standalone",
    orientation: "any",
    background_color: "#faf7f0",
    theme_color: "#faf7f0",
    icons: [
      { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
      { src: "/apple-icon.png", sizes: "180x180", type: "image/png" },
    ],
  };
}
