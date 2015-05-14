/* globals require */
var sourcemaps = require('gulp-sourcemaps');
var del = require('del');
var transform = require('vinyl-transform');
var gutil = require('gulp-util');
var browserify = require("browserify");
var ejs = require("gulp-ejs");
var coffeeify = require("coffeeify");
var $ = require('gulp-load-plugins')();
var webserver = require('gulp-webserver');
var sass = require('gulp-sass');
var concat = require('gulp-concat');
var watchify = require('watchify');
var source = require('vinyl-source-stream');
var buffer = require('vinyl-buffer');
var _ = require('lodash');
var requireStylify = require('require-stylify');
var ngClassify = require('ng-classify');
var through = require('through');
var parcelify = require('parcelify');
var uglify = require('gulp-uglify');
var cssmin = require('gulp-cssmin');
var rename = require('gulp-rename');


module.exports = function (gulp, options) {
    var runSequence = require('run-sequence').use(gulp);
    var src = {
        assets: [
            'app/assets/**'
        ],
        static: 'app/index.ejs'
    };

    var static_vars = {
        common: {
            config: options.config
        },
        dev: {
            env: 'DEV'
        },
        prod: {
            env: 'PROD'
        }
    }

    var sassOptions = {
        includePaths: ['app', 'bower_components', 'node_modules'],
        precision: 8,
        errLogToConsole: true,
        onError: function (err) {
            file_path = err.file.replace(__dirname, "")
            console.log("SASS Error:".red.underline,
                err.message.bold,
                'in file',
                file_path.bold,
                'on line',
                (err.line+'').bold,
                'column',
                (err.column+'').bold);
        }
    };

    var ngClassifyTransform = function (file) {
        var data = '';
        return through(write, end);

        function write (buf) {
            data += buf
        }
        function end () {
            this.queue(ngClassify(data));
            this.queue(null);
        }
    };

    // browserify tasks
    var customOpts = {
        entries: ['./app/app.coffee'],
        extensions: ['.coffee'],
        paths: ['./app'],
        debug: true
    };
    var opts = _.assign({}, watchify.args, customOpts);
    var b = watchify(browserify(opts))
        .transform(ngClassifyTransform)
        .transform(coffeeify)
        .plugin('parcelify', {
            bundles: {
                style: './.tmp/assets/bundle.css'
            },
            watch: true
        });

    var packageJson = require('./package.json');
    var dependencies = Object.keys(packageJson && packageJson.dependencies || {});

    gulp.task('bundle:dev', function() {
        return b
            .external(dependencies)
            .bundle()
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(source('app/app.js'))
            .pipe(buffer())
            .pipe(sourcemaps.init({loadMaps: true}))
            .pipe(sourcemaps.write())
            .pipe($.flatten())
            .pipe(gulp.dest('.tmp/assets', {base: '.tmp'}));
    });

    gulp.task('vendor:dev', function() {
        return browserify()
            .transform('browserify-css', { autoInject: true })
            .require(dependencies)
            .bundle()
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(source('vendor.js'))
            .pipe(gulp.dest('.tmp/assets', {base: '.tmp'}));
    });

    gulp.task('bundle:prod', function() {
        return browserify(opts)
            .transform(ngClassifyTransform)
            .transform(coffeeify)
            .plugin('parcelify', {
                bundles: {
                    style: './.tmp/assets/bundle.min.css'
                }
            })
            .external(dependencies)
            .bundle()
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(source('app/app.min.js'))
            .pipe(buffer())
            .pipe(sourcemaps.init({loadMaps: true}))
            .pipe(sourcemaps.write())
            .pipe($.flatten())
            .pipe(uglify())
            .pipe($.stripDebug())
            .pipe(gulp.dest('.tmp/assets', {base: '.tmp'}));
    });

    gulp.task('vendor:prod', function() {
        return browserify()
            .transform('browserify-css', { autoInject: true })
            .require(dependencies)
            .bundle()
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(source('vendor.min.js'))
            .pipe(buffer())
            .pipe(uglify())
            .pipe(gulp.dest('.tmp/assets', {base: '.tmp'}));
    });

    // move SASS that has been imported in coffeescript
    // from the app folder to the .tmp folder
    gulp.task('move_generated_css', function (){
        gulp.src('app/**/*.css')
            .pipe(concat('generated.css'))
            .pipe(gulp.dest('.tmp/assets'))
    });
    gulp.task('generated_css', ['move_generated_css'], function (cb){
        del('app/**/*.css', cb);
    });

    // dev
    gulp.task('coffee', ['clean'], function (){
        runSequence('bundle:dev');
    });
    b.on('update', function (){
        runSequence('bundle:dev');
    });
    b.on('log', gutil.log);

    gulp.task('clean', del.bind(
        null, ['.tmp'], {dot: true}
    ));

    gulp.task('static:dev', function() {
        var vars = _.extend(static_vars.common, static_vars.dev);
        return gulp.src(src.static)
            .pipe(ejs(vars))
            .pipe(gulp.dest(".tmp"));
    });

    gulp.task('static:prod', function() {
        var vars = _.extend(static_vars.common, static_vars.prod);
        return gulp.src(src.static)
            .pipe(ejs(vars))
            .pipe(gulp.dest(".tmp"));
    });

    gulp.task('assets', function() {
        return gulp.src(src.assets)
            .pipe($.changed('.tmp'))
            .pipe(gulp.dest('.tmp'))
            .pipe($.size({title: 'assets'}));
    });

    gulp.task('sass:dev', function() {
        return gulp.src("app/**/*.scss")
            .pipe(sourcemaps.init())
            .pipe(sass(sassOptions))
            .pipe(concat('app.css'))
            .pipe(sourcemaps.write({debug: true}))
            .pipe(gulp.dest(".tmp/assets/"));
    });

    gulp.task('sass:prod', function() {
        return gulp.src("app/**/*.scss")
            .pipe(sass(sassOptions))
            .pipe(concat('app.min.css'))
            .pipe($.autoprefixer('ie 9'))
            .pipe(cssmin())
            .pipe(gulp.dest(".tmp/assets/"));
    });


    gulp.task('watch', ['coffee'], function() {
        gulp.watch("./app/*.scss", ['sass:dev']);
        gulp.watch(src.assets, ['assets']);
        gulp.watch(src.static, ['static:dev']);
        gulp.watch('package.json', ['vendor:dev']);
    });

    gulp.task('webserver', function() {
        gulp.src('./.tmp/')
            .pipe(webserver({
                livereload: true,
                fallback: 'index.html'
            }));
    });

    gulp.task('default', function (){
        runSequence(
            'clean',
            'watch',
            ['sass:dev', 'assets', 'static:dev', 'vendor:dev'],
            'webserver'
        );
    });

    gulp.task('build', function (cb){
        runSequence(
            'clean',
            ['sass:prod', 'assets', 'static:prod', 'bundle:prod', 'vendor:prod']
        );
    });
}
