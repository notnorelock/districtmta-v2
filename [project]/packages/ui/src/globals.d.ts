/** Injected by webpack.config.js's DefinePlugin at build time (git rev-parse --short HEAD). */
declare const __BUILD_COMMIT__: string;

/**
 * Only process.env.NODE_ENV is defined (via DefinePlugin) - not a real
 * Node process object, and no @types/node dependency backs this. Don't
 * reach for any other process.env.* member; it won't exist at runtime.
 */
declare const process: {
  env: {
    NODE_ENV: "development" | "production";
  };
};
