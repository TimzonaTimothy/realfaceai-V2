// Builds ../../assets/js/rt.js: @xmaxai/web-sdk and all its RTC / storage
// dependencies in one self-contained ES module, served by the stream screen's
// local server as /static/rt.js.
//
//   cd tool/xmax_web_bundle && npm install && npm run build
//
// Patch: the stream page is served from http://127.0.0.1, and cos-js-sdk
// copies the page's protocol, so face uploads went to http://…myqcloud.com.
// macOS WKWebView (App Transport Security) blocks that and the upload fails
// with "CORS blocked or network error". The SDK creates the COS client itself,
// so force https at build time.

import { build } from 'esbuild';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const out = fileURLToPath(new URL('../../assets/js/rt.js', import.meta.url));

const forceCosHttps = {
  name: 'force-cos-https',
  setup(b) {
    b.onLoad({ filter: /@xmaxai[\\/]web-sdk[\\/]dist[\\/].*\.js$/ }, async (args) => {
      const src = await readFile(args.path, 'utf8');
      const pattern = /SecurityToken: configuration\.credentials\.sessionToken(\s*)\}\)/g;
      const matches = src.match(pattern) ?? [];
      if (!src.includes('cos-js-sdk-v5')) return { contents: src, loader: 'js' };
      if (matches.length !== 1) {
        throw new Error(`force-cos-https: expected 1 COS client in ${args.path}, found ${matches.length}; ` +
          'the SDK changed — update the patch');
      }
      return {
        contents: src.replace(pattern, 'SecurityToken: configuration.credentials.sessionToken,$1Protocol: "https:"$1})'),
        loader: 'js',
      };
    });
  },
};

await build({
  stdin: { contents: "export * from '@xmaxai/web-sdk';", resolveDir: process.cwd(), loader: 'js' },
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2020',
  minify: true,
  legalComments: 'none',
  define: { 'process.env.NODE_ENV': '"production"' },
  plugins: [forceCosHttps],
  outfile: out,
  logLevel: 'info',
});
