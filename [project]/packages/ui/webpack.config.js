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
          // Font files referenced from styles/globals.css's @font-face
          // rules (Titillium Web) - emitted alongside the JS/CSS bundle,
          // not inlined, matching the previous Vite build's asset output.
          // Lands in dist/assets/ via output.assetModuleFilename below.
          // publicPath: "../" here is required because css-loader resolves
          // this url() relative to output.publicPath ("./" = dist/), NOT
          // relative to where index.css itself ends up (dist/assets/) -
          // without this override the generated path was
          // ./assets/TitilliumWeb-*.ttf, which from inside dist/assets/
          // resolved to the nonexistent dist/assets/assets/*.ttf (browser
          // reported this as "OTS parsing error: file less than 4 bytes",
          // not a clearer 404). "../" cancels out the extra assets/ level
          // css-loader would otherwise add on top of assetModuleFilename's
          // own "assets/" prefix.
          test: /\.(ttf|woff2?|eot)$/,
          type: "asset/resource",
          generator: {
            publicPath: "../",
          },
        },
      ],
    },

    plugins: [
      new HtmlWebpackPlugin({
        template: path.join(rootDir, "index.html"),
        // MTA serves resource files from a local scheme
        // (http://mta/local/...) with no absolute-path routing, so every
        // built asset reference must be relative to index.html - same
        // constraint the previous Vite config's `base: "./"` addressed.
        publicPath: "./",
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
      publicPath: "./",
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
                    drop_console: true,
                    drop_debugger: true,
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
