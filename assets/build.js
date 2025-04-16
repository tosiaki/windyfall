const esbuild = require('esbuild');
const babel = require('@babel/core')
const fs = require('fs')
const path = require('path');
// Import other plugins/deps (like babel-jsx plugin from previous steps)

const babelJsxPlugin = {
  name: 'babel-jsx',
  setup(build) {
    build.onLoad({ filter: /\.(js|jsx|ts|tsx)$/ }, async (args) => {
      if (!args.path.match(/node_modules/) && (args.path.endsWith('.jsx') || args.path.endsWith('.tsx'))) {
         const source = await fs.promises.readFile(args.path, 'utf8');
         try {
           const { code } = await babel.transformAsync(source, {
              presets: ['@babel/preset-react'],
              filename: args.path, // Important for Babel presets/plugins
              sourceMaps: true, // Optional: if you want source maps
            });
           return { contents: code, loader: 'js' }; // Output as JS
         } catch (e) {
            console.error(`Babel transform failed for ${args.path}:`, e);
            return { errors: [{ text: e.message }] };
         }
      }
      // Let esbuild handle regular JS/TS or node_modules
      return undefined;
    });
  },
};

// --- Get Watch Flag ---
const watch = process.argv.includes('--watch');

// --- Define Tailwind Input/Output ---
const tailwindInput = path.resolve(__dirname, 'css/app.css');
const tailwindOutput = path.resolve(__dirname, '../priv/static/assets/app.css');
const tailwindConfig = path.resolve(__dirname, 'tailwind.config.js');

// --- Common esbuild Options (WITHOUT 'watch') ---
const commonEsbuildOptions = {
  entryPoints: [path.resolve(__dirname, 'js/app.js')],
  bundle: true,
  outfile: path.resolve(__dirname, '../priv/static/assets/app.js'),
  logLevel: 'info',
  target: 'es2017',
  plugins: [babelJsxPlugin /* other plugins */],
  loader: { '.js': 'jsx', '.jsx': 'jsx', '.ts': 'tsx', '.tsx': 'tsx' },
  nodePaths: [path.resolve(__dirname, 'node_modules')]
  // sourcemap is configured below based on mode
};

// --- Build Function for Tailwind ---
function buildTailwind(isWatching = false) {
    console.log('Building Tailwind CSS...');
    try {
        const minifyFlag = isWatching ? '' : '--minify'; // No minify in watch
        const cmd = `npx @tailwindcss/cli -c "${tailwindConfig}" -i "${tailwindInput}" -o "${tailwindOutput}" ${minifyFlag}`;
        console.log(`Executing: ${cmd}`);
        execSync(cmd, { stdio: 'inherit' });
        console.log('Tailwind CSS build complete.');
    } catch (error) {
        console.error('Tailwind CSS build failed:');
        process.exit(1);
    }
}

// --- Main Async Function ---
async function main() {
  if (watch) {
    // --- WATCH MODE ---
    console.log("Initializing esbuild context for watch mode...");

    try {
      // Create the build context
      const context = await esbuild.context({
        ...commonEsbuildOptions,
        sourcemap: 'inline', // Enable sourcemaps for dev watch
      });

      // Start esbuild's watch mode
      await context.watch();
      console.log("esbuild watcher started successfully.");

      // Note: Tailwind watching is handled separately by the Phoenix watcher in dev.exs
      // No need to call buildTailwind() here repeatedly.

      // Keep the process alive, esbuild watch does this implicitly
      // Add signal handling to dispose of the context gracefully on exit
       const disposeContext = async () => {
            console.log('\nDisposing esbuild context...');
            await context.dispose();
            console.log('esbuild context disposed.');
            process.exit(0);
        };
        process.on('SIGINT', disposeContext); // Ctrl+C
        process.on('SIGTERM', disposeContext); // Termination signal

    } catch (error) {
      console.error("Failed to initialize or start esbuild watcher:", error);
      process.exit(1);
    }

  } else {
    // --- ONE-OFF BUILD MODE (for mix assets.build/deploy) ---
    console.log("Performing one-off production build...");
    try {
      // Build Tailwind CSS (minified)
      // buildTailwind(false); // isWatching = false

      // Build JS (minified, no sourcemap)
      await esbuild.build({
        ...commonEsbuildOptions,
        minify: true,
        sourcemap: false,
      });
      console.log("Production build complete.");

    } catch (error) {
      console.error("Production build failed:", error);
      process.exit(1);
    }
  }
}

// --- Run the main function ---
main().catch(e => {
    console.error(e);
    process.exit(1);
});
