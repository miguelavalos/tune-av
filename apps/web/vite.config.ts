import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

export default defineConfig({
  build: {
    rollupOptions: {
      output: {
        manualChunks(id: string) {
          if (!id.includes("node_modules")) {
            return undefined;
          }
          if (id.includes("/react/") || id.includes("/react-dom/") || id.includes("/scheduler/")) {
            return "vendor-react";
          }
          if (id.includes("/@clerk/localizations/")) {
            return "vendor-clerk-localizations";
          }
          if (id.includes("/@clerk/")) {
            return "vendor-clerk";
          }
          return undefined;
        }
      }
    }
  },
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url))
    },
  },
  server: {
    port: 5194
  },
  plugins: [tanstackStart({ serverFns: { disableCsrfMiddlewareWarning: true } }), viteReact(), tailwindcss()]
});
