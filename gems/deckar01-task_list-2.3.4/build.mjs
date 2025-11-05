import { build } from 'esbuild';
import coffeeScriptPlugin from 'esbuild-coffeescript';
import { umdWrapper } from 'esbuild-plugin-umd-wrapper';

await build({
  entryPoints: ['app/assets/javascripts/task_list.coffee'],
  bundle: true,
  minify: true,
  format: 'umd',
  outfile: 'dist/task_list.js',
  plugins: [
    coffeeScriptPlugin(),
    umdWrapper({libraryName: 'TaskList'}),
  ],
  logLevel: 'info',
});

await build({
  entryPoints: ['test/unit/*.coffee'],
  bundle: true,
  outdir: 'bin/test/unit/',
  plugins: [
    coffeeScriptPlugin(),
  ],
  logLevel: 'info',
});
