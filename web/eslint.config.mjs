import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // UI v2: icons come from src/ui/Icon.tsx (Hanko's own set). Generic icon
  // packs were removed on purpose — see CLAUDE.md "Web UI v2".
  {
    rules: {
      "no-restricted-imports": [
        "error",
        {
          paths: [{ name: "lucide-react", message: "Use <Icon name=…> from @/ui/Icon (Hanko's own icon set)." }],
          patterns: [{ group: ["lucide-react/*", "react-icons", "react-icons/*", "@heroicons/*"], message: "Use <Icon name=…> from @/ui/Icon." }],
        },
      ],
    },
  },
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
]);

export default eslintConfig;
