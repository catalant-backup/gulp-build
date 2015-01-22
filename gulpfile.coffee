config = require('./config.json')

gulp = require("gulp")
sass = require("gulp-sass")
concat = require("gulp-concat")
sourcemaps = require("gulp-sourcemaps")
watch = require('gulp-watch')
webserver = require("gulp-webserver")
coffee = require("gulp-coffee")
sourcemaps = require("gulp-sourcemaps")
changed = require("gulp-changed")
wiredep = require("wiredep").stream
templateCache = require("gulp-angular-templatecache")
inject = require("gulp-inject")
coffeelint = require('gulp-coffeelint')
del = require('del')
vinylPaths = require('vinyl-paths')
ngClassify = require('gulp-ng-classify')
runSequence = require('run-sequence')
minifyCss = require('gulp-minify-css')
uglify = require('gulp-uglify')
useref = require('gulp-useref')
gulpIf = require('gulp-if')
yuidoc = require("gulp-yuidoc")
ngAnnotate = require('gulp-ng-annotate')
imageop = require('gulp-image-optimization')
karma = require('karma').server
protractor = require("gulp-protractor").protractor

error_handle = (err) ->
    console.error err
    return

TEMP_PATH = "./.tmp"
APP_PATH = "./app"
BOWER_PATH = "./app/bower_components"
DIST_PATH = './dist'
DOCS_PATH = './docs'
PROD_PATH = './prod'


paths =
    css: "./app/+(modules|components)/**/*.scss"
    templates: "./app/+(modules|components)/**/views/*.html"
    coffee: "./app/+(modules|components)/**/*.coffee",
    images: "./app/+(modules|components)/**/images/*.+(png|jpg|gif|jpeg)"
    images_main: "./app/images/*.+(png|jpg|gif|jpeg)"

ngClassifyOptions =
    controller:
        format: 'upperCamelCase'
        suffix: 'Controller'
    constant:
        format: '*' #unchanged
    appName: config.app_name
    provider:
        suffix: ''

gulp.task('watch', ->
    watch(paths.css.substr(2), ->
        runSequence('css', 'inject', 'bower')
    )
    watch(paths.coffee.substr(2), (event) ->
        runSequence('coffee', 'inject', 'bower')
    )
    watch(BOWER_PATH, ->
        runSequence('bower', 'inject', 'bower')
    )
    watch(paths.templates, ->
        runSequence('templates', 'inject', 'bower')
    )
    watch(APP_PATH+'/index.html', -> 
        runSequence('inject', 'bower')
    )
)

gulp.task('watch:package', ->
    watch(paths.css.substr(2), ->
        runSequence('css', 'inject', 'bower', 'package:dist')
    )
    watch(paths.coffee.substr(2), (event) ->
        runSequence('coffee', 'inject', 'bower', 'package:dist')
    )
    watch(BOWER_PATH, ->
        runSequence('bower', 'inject', 'bower', 'package:dist')
    )
    watch(paths.images_main, ->
        runSequence('images:main', 'package:dist')
    )
    watch(paths.images, ->
        runSequence('images:modules', 'package:dist')
    )
    watch(paths.templates, ->
        runSequence('templates', 'inject', 'bower', 'package:dist')
    )
    watch(APP_PATH+'/index.html', -> 
        runSequence('inject', 'bower', 'package:dist')
    )
)


gulp.task "clean:modules", (cb) ->
    return gulp.src(TEMP_PATH)
        .pipe(vinylPaths(del))

gulp.task "clean:dist", (cb) ->
    return gulp.src(DIST_PATH)
        .pipe(vinylPaths(del))

gulp.task "clean:docs", (cb) ->
    return gulp.src(DOCS_PATH)
        .pipe(vinylPaths(del))

gulp.task "inject", ->
    target = gulp.src("./app/index.html")
    sources = gulp.src([
        "./.tmp/+(modules|components)/**/*.css"
        "./.tmp/+(modules|components)/"+config.main_module_name+"/"+config.main_module_name+".module.js"
        "./.tmp/+(modules|components)/"+config.main_module_name+"/*.provider.js"
        "./.tmp/+(modules|components)/"+config.main_module_name+"/*.run.js"
        "./.tmp/+(modules|components)/templates.js"
        "./.tmp/+(modules|components)/"+config.main_module_name+"/*.js"
        "./.tmp/+(modules|components)/**/*.module.js"
        "./.tmp/+(modules|components)/**/*.provider.js"
        "./.tmp/+(modules|components)/**/*.run.js"
        "./.tmp/+(modules|components)/**/*.js"
        "!./.tmp/+(modules|components)/**/tests/*"
        "!./.tmp/+(modules|components)/**/*.backend.js"
    ], read: false)

    return target
        .pipe(inject(sources,
            ignorePath: ['.tmp', BOWER_PATH]
        ))
        .pipe(gulp.dest(TEMP_PATH))
        .on "error", error_handle

gulp.task "webserver", ->
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0" #hackaroo courtesy of https://github.com/request/request/issues/418
    protocol = if ~config.dev_server.backend.indexOf("https:") then "https:" else "http:"
    return gulp.src([
            TEMP_PATH
            APP_PATH
        ])
        .pipe(webserver(
            fallback: 'index.html'
            host: config.dev_server.host
            port: config.dev_server.port
            directoryListing:
                enabled: true
                path: TEMP_PATH
            proxies: [
                {
                    source: "/api/v#{config.api_version}/",
                    target: "#{config.dev_server.backend}/api/v#{config.api_version}/"
                    options: {protocol}
                },
                {
                    source: "/photo/",
                    target: "#{config.dev_server.backend}/photo/"
                    options: {protocol}
                }
            ]
        ))
        .on "error", error_handle

gulp.task "bower", ->
    return gulp.src("./.tmp/index.html")
        .pipe(wiredep({
            directory: BOWER_PATH
            ignorePath: '../app/'
            exclude: config.bower_exclude
        }))
        .pipe(gulp.dest(TEMP_PATH))
        .on "error", error_handle


gulp.task "css", ->
    return gulp.src(paths.css)
        .pipe(sourcemaps.init())
        .pipe(sass({
            includePaths: [BOWER_PATH]
            onError: (err) ->
                console.log err
        }))
        .pipe(sourcemaps.write())
        .pipe(gulp.dest("./.tmp"))
        .on("error", error_handle)

gulp.task "templates", ->
    return gulp.src(paths.templates)
        .pipe(templateCache("templates.js",
            module: config.app_name
            root: config.deploy_path #TODO: we need to support setting this property to things other than "/"
        ))
        .pipe(gulp.dest(TEMP_PATH))
        .on "error", error_handle

gulp.task "coffee", ->
    return gulp.src(paths.coffee)
        .pipe(coffeelint())
        .pipe(coffeelint.reporter())
        .pipe(ngClassify(ngClassifyOptions))
        .on("error", (err) ->
            console.error(err)
            this.emit('end')
        )
        .pipe(sourcemaps.init())
        .pipe(coffee())
        .pipe(sourcemaps.write())
        .pipe(gulp.dest("./.tmp"))
        .on "error", error_handle

gulp.task "images:modules", ->
    return gulp.src(paths.images)
        .pipe(imageop({
            optimizationLevel: 5
            progressive: true
            interlaced: true
        }))
        .pipe(gulp.dest(DIST_PATH))
        .on "error", error_handle

gulp.task "images:main", ->
    return gulp.src(paths.images_main)
        .pipe(imageop({
            optimizationLevel: 5
            progressive: true
            interlaced: true
        }))
        .pipe(gulp.dest(DIST_PATH+"/images"))
        .on "error", error_handle

gulp.task "package:dist", ->
    assets = useref.assets()
    return gulp.src("./.tmp/index.html")
        .pipe(assets)
        .pipe(gulpIf('*.js', ngAnnotate()))
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(gulp.dest(DIST_PATH))
        .on "error", error_handle

gulp.task "package:prod", ->
    assets = useref.assets()
    return gulp.src("./.tmp/index.html")
        .pipe(assets)
        .pipe(gulpIf('*.js', uglify()))
        .pipe(gulpIf('*.js', ngAnnotate()))
        .pipe(gulpIf('*.css', minifyCss()))
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(gulp.dest(PROD_PATH))
        .on "error", error_handle

gulp.task "docs", ['clean:docs'], ->
    return gulp.src(paths.coffee)
        .pipe(yuidoc({
            project:
                name: config.app_name + " Documentation"
                description: "A quick demo"
                version: "0.0.1"
            syntaxtype: 'coffee'
        }))
        .pipe(gulp.dest(DOCS_PATH))
        .on "error", error_handle

gulp.task "karma", ->
    bower_files = require("wiredep")(directory: BOWER_PATH).js
    sources = [].concat bower_files, '.tmp/**/*.!(spec).js', '.tmp/+(modules|components)/**/tests/*.spec.js'
    karma.start({
        files: sources
        frameworks: ['mocha']
        autoWatch: false
        background: true
        #logLevel: config.LOG_WARN
        browsers: [
            'PhantomJS'
        ]
        transports: [
            'flashsocket'
            'xhr-polling'
            'jsonp-polling'
        ]
        singleRun: true
    });


gulp.task('e2e', (cb) ->
    return gulp.src('./app/e2e/**/*.spec.coffee')
        .pipe(protractor({
            configFile: "./protractor.config.coffee"
        })) 
        .on('error', (e) -> throw e )
)

gulp.task "test", (cb) ->
    runSequence('clean:modules'
                ['coffee', 'css']
                'inject'
                'karma'
                cb)

gulp.task "default", (cb) ->
    runSequence('clean:modules'
                'templates'
                ['coffee', 'css']
                'inject',
                'bower'
                'webserver'
                'watch'
                cb)


gulp.task "package", (cb) ->
    runSequence('clean:dist'
                'templates'
                ['coffee', 'css']
                ['images:modules', 'images:main']
                'inject',
                'bower'
                'package:dist')

gulp.task "build", (cb) ->
    runSequence('clean:dist'
                'templates'
                ['coffee', 'css']
                ['images:modules', 'images:main']
                'inject',
                'bower'
                'package:prod')
