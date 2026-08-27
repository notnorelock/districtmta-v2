/** Injected by vite.config.ts's define block at build time (git rev-parse --short HEAD). */
declare const __BUILD_COMMIT__: string;

/**
 * Only process.env.NODE_ENV is defined (via vite.config.ts's define block,
 * string-replaced at build time) - not a real Node process object, and no
 * @types/node dependency backs this. Don't reach for any other
 * process.env.* member; it won't exist at runtime.
 */
declare const process: {
  env: {
    NODE_ENV: "development" | "production";
  };
};

/** CSS Modules (Vite's built-in *.module.scss handling) - scoped to features/hud/ only, see its module comment. */
declare module "*.module.scss" {
  const classes: { readonly [className: string]: string };
  export default classes;
}

/** Image assets (Vite's built-in asset handling) - `import url from "*.png"` resolves to the built asset's URL string. */
declare module "*.png" {
  const url: string;
  export default url;
}
