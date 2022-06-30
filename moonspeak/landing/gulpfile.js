const gulp = require('gulp');

const git = require("git-rev-sync");
const rename = require("gulp-rename");
const c = require('ansi-colors');

const fs = require('fs');
const data = require('gulp-data');
const merge = require('merge-stream');

const del = require('del');       //< see https://github.com/gulpjs/gulp/blob/master/docs/recipes/delete-files-folder.md


//===========================================
// HTML
const htmlhint = require("gulp-htmlhint");
const htmlmin = require('gulp-htmlmin');
const TOML = require('fast-toml');
const handlebars = require('gulp-compile-handlebars');


function findVariables(lang) {
    return function(file) {
        const fp = './frontend/' + lang + '/' + file.stem + '.toml';
        const language = TOML.parseFileSync(fp)
        return {
            ...language,
            git_hash: git.long(),
            git_date: git.date(),
            "lang": lang,
            gulp_debug_data: {
                template: file.basename,
                toml: lang + '/' + file.stem + '.toml',
            }
        }
    }
}

const htmlhintconfig = {
    // doctype and head
    "doctype-first": true,
    "doctype-html5": true,
    "html-lang-require": true,
    "head-script-disabled": true,
    "style-disabled": true,
    "script-disabled": false,
    "title-require": true,
    // attributes
    "attr-lowercase": true,
    "attr-no-duplication": true,
    "attr-no-unnecessary-whitespace": true,
    "attr-unsafe-chars": true,
    "attr-value-double-quotes": true,
    "attr-value-single-quotes": false,
    "attr-value-not-empty": true,
    "attr-sorted": true,
    "attr-whitespace": true,
    "alt-require": true,
    "input-requires-label": true,
    // tags
    "tags-check": true,
    "tag-pair": true,
    "tag-self-close": false,
    "tagname-lowercase": true,
    "tagname-specialchars": true,
    "empty-tag-not-self-closed": false,
    "src-not-empty": true,
    "href-abs-or-rel": false,
    // id
    "id-class-ad-disabled": true,
    "id-class-value": "underscore",
    "id-unique": true,
    // inline
    "inline-script-disabled": true,
    "inline-style-disabled": true,
    // formatting
    "space-tab-mixed-disabled": "space",
    "spec-char-escape": true,
}

function htmlTemplateLintTask() {
    return gulp.src(["./frontend/templates/*.template"])
                    .pipe(htmlhint(htmlhintconfig))
                    .pipe(htmlhint.reporter())
                    .pipe(htmlhint.failOnError({suppress: true}));
}

function annotateError(err) {
    if (err.message.includes("not defined in [object Object]")) {
        // this is an error about the templates compilation, it is critical
        let data = err.domainEmitter._transformState.writechunk.data.gulp_debug_data;
        let msg = "Error mashing " + data.toml + " with " + data.template + ". Template received null for this variable: " + err.message;
        console.error(c.bold.red(msg));
    } 
    else if (err.plugin === 'gulp-htmlhint') {
        let msg = c.bold.red("HTMLHint reporting uses wrong filenames:\n")
                + "For errors in " + c.bold.red("templates/ru/doc.html") + " find the actual error in " + c.bold.red("frontend/ru/doc.toml")
        console.error(msg);
    }
}

// Minify html and fix links to CSS and JS
function htmlTask() {
    // use a nodejs domain to get more exact info for handling template errors
    const d = require('domain').create();
    d.on('error', (err) => {annotateError(err); throw err;});
    d.enter();

    const result = merge();
    for (const lang of ["test", "ru", "en", "kz"]) {
        const r = gulp.src(["./frontend/templates/*.template"])
                .pipe(data(findVariables(lang)))
                .pipe(handlebars({}, {compile: {strict:true}}))
                // becasue we sourced *.template we need to fix names here
                .pipe(rename(path => {
                    path.dirname += "/" + lang;
                    path.extname = ".html";
                }))
                .pipe(htmlhint(htmlhintconfig))
                .pipe(htmlhint.reporter())
                .pipe(htmlhint.failOnError({ suppress: true }))
                // minify html
                .pipe(htmlmin({collapseWhitespace:true, removeComments: true}))
                .pipe(gulp.dest('./dist/'));

        result.add(r, {end: false});
    }

    // close the domain of error handling
    d.exit();

    return result.end();
}


//===========================================
// Font minify
const fontmin = require('gulp-fontmin');

// takes the source files and fonts
// writes the font files only for thouse characters
// that we use in the source files
function fontminFountainTask(force_gulp_serial_callback) {
    let buffers = [];

    gulp.src([
        './frontend/common/fountain.js',
    ])
    .on('data', file => {
        buffers.push(file.contents);
    })
    .on('end', function() {
        // fontmin needs a ttf font source from which it generates all other fonts
        let text = Buffer.concat(buffers).toString('utf-8');
        gulp.src([
            './frontend/common/MochiyPopOne-Regular.ttf',
        ])
        .pipe(fontmin({
            text: text,
            hinting: false,
        }))
        .pipe(gulp.dest('./dist/common/'))
        // now we can finally call the callback to say that this task is done
        .on('end', force_gulp_serial_callback);
    });
}

function preCleanTask() {
    return del([
        './dist/**/*',
    ]);
}

function copyTask() {
    return gulp.src([
            './frontend/*/*', 
            
            // exclude these
            '!./frontend/*/*.html',
            '!./frontend/*/*.template',
            '!./frontend/*/*.toml',
        ])
        .pipe(gulp.dest('./dist/'));
}

function postCleanTask(cb) {
    // remove files that are only used in development
    return del([
        './dist/*/*.toml',
        './dist/templates',
        './dist/README.md',
    ]);
}


// start by copying all files,
// then gradually improve by overriding some of them with optimised versions
exports.default = gulp.series(
    preCleanTask,

    copyTask,

    // html
    htmlTemplateLintTask,
    htmlTask,

    fontminFountainTask,
);

exports.lint = gulp.series(
    htmlTemplateLintTask,
);
