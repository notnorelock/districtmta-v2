import path from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import webpack from "webpack";
import HtmlWebpackPlugin from "html-webpack-plugin";
import MiniCssExtractPlugin from "mini-css-extract-plugin";
import TerserPlugin from "terser-webpack-plugin";

const srcDir = fileURLToPath(new URL("./src", import.meta.url));
const rootDir = fileURLToPath(new URL(".", import.meta.url));

// Read once at build time - "unknown" outside a git checkout (e.g. a
// packaged release with no .git/) rather than failing the build.
function getBuildCommit() {
  try {
    return execSync("git rev-parse --short HEAD", { cwd: rootDir }).toString().trim();
  } catch {
    return "unknown";
  }
}

/**
 * @param {Record<string, string>} env
 * @param {{ mode?: string }} argv
 */
export default (env, argv) => {
  const isProduction = argv.mode === "production";
  // Independent of --mode on purpose: --mode only ever flips between
  // "production" (real MTA deploy - fixed mta:// publicPath, CSS
  // extraction, hashed CSS-module class names) and "development" (pnpm
  // dev's own localhost server - publicPath: "auto", style-loader instead
  // of extraction). Debugging an in-game build via /browserdebug still
  // needs the production output shape (publicPath must stay mta://, or
  // every asset 404s) but WITHOUT Terser's drop_console/drop_debugger and
  // WITHOUT scripts/build-ui.mjs's js-confuser pass - hence a separate
  // flag, set via `webpack --mode production --env debug` (see
  // build-ui.mjs's --dev flag), instead of overloading --mode for this.
  const keepDebugOutput = env?.debug === true || env?.debug === "true";

  return {
    mode: isProduction ? "production" : "development",
    entry: { index: path.join(srcDir, "index.tsx") },
    devtool: isProduction ? false : "eval-source-map",

    resolve: {
      extensions: [".tsx", ".ts", ".jsx", ".js"],
      alias: {
        "@": srcDir,
      },
    },

    module: {
      rules: [
        {
          test: /\.[jt]sx?$/,
          exclude: /node_modules/,
          use: {
            loader: "babel-loader",
            options: {
              configFile: path.join(rootDir, "babel.config.json"),
            },
          },
        },
        {
          test: /\.css$/,
          use: [
            isProduction ? MiniCssExtractPlugin.loader : "style-loader",
            // css-loader routes any url()/@import starting with "~"
            // through webpack's own module resolver (which respects
            // resolve.alias below) - globals.css's @font-face rules use
            // url("~@/assets/fonts/...") for exactly this reason.
            "css-loader",
            "postcss-loader",
          ],
        },
        {
          // CSS Modules + Sass, scoped to features/hud/ only - class names
          // are hashed at build time (e.g. .icon -> .icon_a3f9x2), unlike
          // the rest of the app which uses plain Tailwind utility classes
          // directly in JSX. postcss-loader still runs here (after
          // sass-loader compiles Sass to plain CSS, loaders apply
          // bottom-up) so @apply can pull in Tailwind utilities inside
          // these modules too - Tailwind v4's plugin resolves @theme
          // tokens project-wide regardless of which file @apply appears
          // in, it doesn't need its own @import "tailwindcss" per file.
          test: /\.module\.scss$/,
          use: [
            isProduction ? MiniCssExtractPlugin.loader : "style-loader",
            {
              loader: "css-loader",
              options: {
                modules: {
                  localIdentName: isProduction ? "[hash:base64:8]" : "[name]__[local]",
                  // css-loader v7 defaults to named exports (import { root }
                  // from "./X.module.scss") - namedExport: false switches
                  // back to a single default export object instead
                  // (import styles from "./X.module.scss"; styles.root),
                  // matching the globals.d.ts ambient module declaration.
                  namedExport: false,
                },
              },
            },
            "postcss-loader",
            "sass-loader",
          ],
        },
        {
          // Font files referenced from styles/globals.css's @font-face
          // rules (Titillium Web) - emitted alongside the JS/CSS bundle,
          // not inlined, matching the previous Vite build's asset output.
          test: /\.(ttf|woff2?|eot)$/,
          type: "asset/resource",
        },
        {
          // Textures referenced via `new URL("...", import.meta.url)` (see
          // features/auth/SmokeBackground.tsx's smoke.png load).
          test: /\.(png|jpe?g|gif|webp)$/,
          type: "asset/resource",
        },
      ],
    },

    plugins: [
      new HtmlWebpackPlugin({
        template: path.join(rootDir, "index.html"),
        scriptLoading: "module",
      }),
      // Exposes the current commit to app code as __BUILD_COMMIT__ (see
      // components/common/Watermark.tsx) - read once per build via
      // getBuildCommit() above, not at runtime (no git available in CEF).
      // process.env.NODE_ENV is defined here too (there's no @types/node
      // dependency, and webpack only auto-injects this for its own
      // internal library code, not app source) - gates BrowserDevTransport's
      // dynamic import in MtaBridge.ts so it's statically eliminated from
      // a production build entirely, not just unused at runtime.
      new webpack.DefinePlugin({
        __BUILD_COMMIT__: JSON.stringify(getBuildCommit()),
        "process.env.NODE_ENV": JSON.stringify(isProduction ? "production" : "development"),
      }),
      ...(isProduction
        ? [
            new MiniCssExtractPlugin({
              filename: "assets/index.css",
            }),
          ]
        : []),
    ],

    output: {
      path: path.join(rootDir, "dist"),
      // A single browser instance loads this bundle once - no content
      // hashing needed, keep filenames stable and simple to reason about.
      // Two chunks are emitted (index, vendor - see optimization.splitChunks
      // below), both named explicitly rather than content-hashed.
      filename: "assets/[name].js",
      chunkFilename: "assets/[name].js",
      assetModuleFilename: "assets/[name][ext]",
      // Absolute in production, not "./" - every asset reference (CSS
      // url(), font-face, new URL(..., import.meta.url) for textures)
      // resolves from this ONE fixed root regardless of which file
      // references it or where that file itself ends up (e.g.
      // assets/index.css referencing assets/smoke.png). A relative "./"
      // instead resolves differently depending on the referencing file's
      // own location - that mismatch is what caused fonts and then the
      // smoke texture to 404 as assets/assets/*, needing a per-asset-type
      // "../" compensation that was easy to get backwards and hard to
      // keep straight. MTA serves this resource's client files under
      // exactly this fixed local-scheme path (see meta.xml's <file>
      // entries under core_ui/client/html/), so it's safe to hardcode -
      // but only for the real MTA build. `pnpm dev` serves this same
      // bundle from localhost:5173 in a plain browser tab (see
      // lib/mta/environment.ts's isMtaEnvironment split), where that
      // absolute mta:// URL would never resolve, so dev keeps "auto"
      // (webpack infers it from the page's own origin).
      publicPath: isProduction ? "http://mta/local/client/html/" : "auto",
      clean: true,
    },

    optimization: {
      // node_modules split into its own "vendor" chunk, separate from
      // app code in "index" - vendor code (solid-js, @kobalte/core, ...)
      // changes far less often than this project's own source, so this
      // keeps rebuilds/diffs smaller and keeps the two concerns visually
      // separable in the emitted output. HtmlWebpackPlugin injects both
      // resulting <script> tags automatically - MTA's local resource file
      // server handles the extra request fine, this isn't a
      // network-latency-sensitive context the way a public website is.
      splitChunks: {
        chunks: "all",
        cacheGroups: {
          vendor: {
            test: /[\\/]node_modules[\\/]/,
            name: "vendor",
            chunks: "all",
          },
        },
      },
      runtimeChunk: false,
      ...(isProduction
        ? {
            minimize: true,
            minimizer: [
              new TerserPlugin({
                terserOptions: {
                  compress: {
                    // Strips every console.* call site entirely (not just
                    // silencing it - the call expression and its arguments
                    // are removed from the output, so nothing the app logs
                    // - including any string that might leak internal
                    // detail - survives into the shipped bundle).
                    // debugger statements are dropped for the same reason.
                    // Both skipped for a --env debug build (see
                    // keepDebugOutput above) so /browserdebug's console
                    // still shows this app's own console.log/error calls.
                    drop_console: !keepDebugOutput,
                    drop_debugger: !keepDebugOutput,
                  },
                  format: {
                    comments: false,
                  },
                },
                extractComments: false,
              }),
              // Webpack requires re-declaring its default CSS minimizer
              // explicitly once `minimizer` is set to anything - otherwise
              // supplying our own array here would silently disable CSS
              // minification (MiniCssExtractPlugin's output would ship
              // unminified). "..." is webpack 5's own placeholder for "use
              // the built-in default minimizer at this position."
              "...",
            ],
          }
        : {}),
    },

    devServer: {
      port: 5173,
      open: false,
      hot: true,
      static: {
        directory: path.join(rootDir, "public"),
      },
    },
  };
};
