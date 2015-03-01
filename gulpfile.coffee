config = require('./config.json')
fs = require('fs')
https = require('https')
path = require('path')
gulp = require("gulp")
glob = require("glob")
sass = require("gulp-sass")
replace = require("gulp-replace")
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
rename = require('gulp-rename')
gulpIf = require('gulp-if')
yuidoc = require("gulp-yuidoc")
ngAnnotate = require('gulp-ng-annotate')
imageop = require('gulp-image-optimization')
karma = require('karma').server
protractor = require("gulp-protractor").protractor
sprite = require('css-sprite').stream
rev = require('gulp-rev')
revReplace = require('gulp-rev-replace')
_ = require("underscore")

if '--staging' in process.argv
    config.dev_server.backend = 'staging'
    
error_handle = (err) ->
    console.log(err)

COMPILE_PATH = "./.compiled"            # Compiled JS and CSS, Images, served by webserver
TEMP_PATH = "./.tmp"                    # hourlynerd dependencies copied over, uncompiled
APP_PATH = "./app"                      # this module's precompiled CS and SASS
BOWER_PATH = "./app/bower_components"   # this module's bower dependencies
DOCS_PATH = './docs'
DIST_PATH = './dist'

dedupeGlobs = (globs, root="/modules") ->
    #expand globs arrays, dedupe paths after 'root' in order of arrival. return a new glob array ignoring dupes
    deduper = {}
    ignorePaths = []
    re = RegExp("^.*?"+root)
    globs.forEach((glb) ->
        glob.sync(glb).forEach((p) ->
            d = p.replace(re, "")
            if not deduper[d]
                deduper[d] = true
            else
                ignorePaths.push("!"+p)
        )
    )
    return globs.concat(ignorePaths)

paths =
    sass: [
        "./app/modules/**/*.scss"
        "./.tmp/modules/**/*.scss"
    ]
    templates: [
        "./app/modules/**/*.html"
        "./.tmp/modules/**/*.html"
    ]
    coffee: [
        "./app/modules/**/*.coffee"
        "./.tmp/modules/**/*.coffee"
    ]
    images: [
        "./app/modules/**/images/*.+(png|jpg|gif|jpeg)"
        "./.tmp/modules/**/images/*.+(png|jpg|gif|jpeg)"
    ]
    fonts: BOWER_PATH + '/**/*.+(woff|woff2|svg|ttf|eot)'
    runtimes: BOWER_PATH + '/**/*.+(xap|swf)'
    assets: BOWER_PATH + '/hn-*/app/modules/**/*.*'


ngClassifyOptions =
    controller:
        format: 'upperCamelCase'
        suffix: 'Controller'
    constant:
        format: '*' #unchanged
    appName: config.app_name
    provider:
        suffix: ''

gulp.task 'watch', ->
    watch(paths.sass, ->
        runSequence('sass', 'inject', 'bower')
    )
    watch(paths.coffee, (event) ->
        runSequence('coffee', 'inject', 'bower')
    )
    watch(BOWER_PATH, ->
        runSequence('inject', 'bower')
    )
    watch(paths.templates, ->
        runSequence('templates', 'inject', 'bower')
    )
    watch(APP_PATH+'/index.html', ->
        runSequence('inject', 'bower')
    )
    watch(paths.assets, ->
        runSequence(#'clean:tmp',
#                    'clean:compiled',
                    'copy_deps'
#                    'templates'
#                    'make_config'
#                    'sprite'
                    ['coffee', 'sass']
                    'inject',
#                    'inject:version'
                    'bower'
#                    'copy_extras'
        )
    )

gulp.task "clean:compiled",  ->
    return gulp.src(COMPILE_PATH)
        .pipe(vinylPaths(del))

gulp.task "clean:tmp",  ->
    return gulp.src(TEMP_PATH)
        .pipe(vinylPaths(del))


gulp.task "clean:docs",  ->
    return gulp.src(DOCS_PATH)
        .pipe(vinylPaths(del))


gulp.task "clean:dist",  ->
    return gulp.src(DIST_PATH)
        .pipe(vinylPaths(del))


gulp.task "inject", ->
    target = gulp.src("./app/index.html")
    sources = gulp.src([
        "./.compiled/modules/**/*.css"
        "./.compiled/modules/"+config.main_module_name+"/"+config.main_module_name+".module.js"
        "./.compiled/modules/"+config.main_module_name+"/*.provider.js"
        "./.compiled/modules/"+config.main_module_name+"/*.run.js"
        "./.compiled/modules/"+config.main_module_name+"/*.js"
        "./.compiled/modules/**/*.module.js"
        "./.compiled/modules/**/*.provider.js"
        "./.compiled/templates.js"
        "./.compiled/config.js"
        "./.compiled/modules/**/*.run.js"
        "./.compiled/modules/**/*.js"
        "!./.compiled/modules/**/tests/*"
        "!./.compiled/modules/**/*.backend.js"
    ], read: false)

    return target
        .pipe(inject(sources,
            ignorePath: [".compiled", BOWER_PATH]
            transform:  (filepath) ->
                return inject.transform.apply(inject.transform, [filepath])
        ))
        .pipe(gulp.dest(COMPILE_PATH))
        .on "error", error_handle

gulp.task('inject:version', ->
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(inject(gulp.src('./bower.json'),
            starttag: '<!-- build_info -->',
            endtag: '<!-- end_build_info -->'
            transform: (filepath, file) ->
                contents = file.contents.toString('utf8')
                data = JSON.parse(contents)
                return "<!-- version: #{data.version} -->"
        ))
        .pipe(gulp.dest(COMPILE_PATH))
        .on "error", error_handle
)

gulp.task "webserver", ->
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0" #hackaroo courtesy of https://github.com/request/request/issues/418
    backend = config.backends[config.dev_server.backend]
    apiVersion = backend.api_version

    makeProxy = (url) ->
        return {
            source: url,
            target: "#{backend.host}#{url}"
            options: {
                protocol: "https:"
                headers: {'X-App-Token': backend.app_token}
            }
        }
    return gulp.src([
            COMPILE_PATH
            TEMP_PATH
            APP_PATH
        ])
        .pipe(webserver(
            fallback: 'index.html'
            host: config.dev_server.host
            port: config.dev_server.port
            directoryListing:
                enabled: true
                path: COMPILE_PATH
            proxies: [
                makeProxy("/api/v#{apiVersion}/")
                makeProxy("/photo/")
            ],
            middleware: [
                (req, res, next) ->
                    req.url = '/' if req.url  == ''
                    next()
            ]
        ))
        .on "error", error_handle

gulp.task "bower", ->
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(wiredep({
            directory: BOWER_PATH
            ignorePath: '../app'
            exclude: config.bower_exclude
        }))
        .pipe(gulp.dest(COMPILE_PATH))
        .on "error", error_handle


gulp.task "sass", ->
    return gulp.src(dedupeGlobs(paths.sass))
        .pipe(sourcemaps.init())
        .pipe(sass({
            includePaths: [ '.tmp/', 'app/bower_components', 'app' ]
            precision: 8
            onError: (err) ->
                console.log err
        }))
        .pipe(sourcemaps.write())
        .pipe(gulp.dest(COMPILE_PATH + "/modules"))
        .on("error", error_handle)

gulp.task "templates", ->
    return gulp.src(dedupeGlobs(paths.templates))
        .pipe(templateCache("templates.js",
            module: config.app_name
            root: '/modules'
            htmlmin:
                removeComments: true
                maxLineLength: 100
        ))
        .pipe(gulp.dest(COMPILE_PATH))
        .on "error", error_handle

gulp.task "coffee", ->
    return gulp.src(dedupeGlobs(paths.coffee))
        .pipe(coffeelint())
        .pipe(coffeelint.reporter())
        .pipe(ngClassify(ngClassifyOptions))
        .on("error", (err) ->
            console.error(err)
        )
        .pipe(sourcemaps.init())
        .pipe(coffee())
        .pipe(sourcemaps.write())
        .pipe(ngAnnotate())
#        .pipe(gulpIf('*.js', uglify())) # makes it easy to test minification issues
        .pipe(gulp.dest(COMPILE_PATH + "/modules"))
        .on "error", error_handle

gulp.task "copy_deps", ->
    return gulp.src(paths.assets, {
            dot: true
            base: BOWER_PATH
        })
        .pipe(rename( (file) ->
            if file.extname != ''

                parts = file.dirname.split('/')
                file.dirname = file.dirname.replace(parts[0] + '/app/', '')
                return file
            else
                return no
        ))
        .pipe(gulp.dest(TEMP_PATH));

copyExtras = (types..., dest) ->
    types.forEach((type) ->
        gulp.src(paths[type], {
            dot: true
            base: BOWER_PATH
        }).pipe(rename((file) ->
            if file.extname != ''
                file.dirname = type
                return file
            else
                return no
        )).pipe(gulp.dest(dest))
    )
gulp.task "copy_extras", ->
    copyExtras('fonts', 'runtimes', COMPILE_PATH)

gulp.task "copy_extras:dist", ->
    copyExtras('fonts', 'runtimes', DIST_PATH)

gulp.task "images", ->
    return gulp.src(dedupeGlobs(paths.images))
        .pipe(imageop({
            optimizationLevel: 5
            progressive: true
            interlaced: true
        }))
        .pipe(gulp.dest(DIST_PATH, cwd: DIST_PATH))
        .on "error", error_handle

gulp.task "package:dist", ->
    assets = useref.assets()
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(assets)
        .pipe(gulpIf('*.js', ngAnnotate()))
        .pipe(gulpIf('*.js', uglify()))
        .pipe(gulpIf('*.css', minifyCss()))
        .pipe(rev())
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(revReplace())
        .pipe(gulp.dest(DIST_PATH))
        .on "error", error_handle

gulp.task "docs", ['clean:docs'], ->
    return gulp.src(dedupeGlobs(paths.coffee))
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

# generate sprite file
# See: https://github.com/aslansky/css-sprite
# Compiles images in all modules into base64 encoded sass mixins
# Must @import "sprite" in file then @include sprite($sprite_name)
# See .tmp/sprite.scss after compilation step to see variable names.
# Variable name = $[module_name]-images-[filename_underscore_separated]
gulp.task('sprite', ->
    return gulp.src(dedupeGlobs(paths.images))
    .pipe(sprite({
        name: "sprite"
        style: "sprite.scss"
        cssPath: ""
        base64: true
        processor: "scss"
    }))
    .pipe(gulp.dest(TEMP_PATH))
)

makeConfig = (isDebug, cb) ->
    configs = glob.sync(BOWER_PATH+"/**/bower.json")
    versions = {}
    configs.forEach((cpath)->
      c = require(cpath)
      versions[c.name] = c.version
    )
    bwr = require(path.join(__dirname, './bower.json'))
    cfg = _.extend({}, require(path.join(__dirname, './config.json')))
    backend = cfg.backends[config.dev_server.backend]

    cfg.api_version = backend.api_version
    cfg.app_version = bwr.version
    cfg.app_id = backend.app_id
    cfg.app_debug = isDebug
    cfg.bower_versions = versions
    cfg.build_date = new Date()
    delete cfg.backends # shhhh super secret! don't tell anyone!
    template = """
        angular.module('appConfig', [])
            .constant('APP_CONFIG', #{JSON.stringify(cfg)});
    """
    if not fs.existsSync(COMPILE_PATH)
        fs.mkdirSync(COMPILE_PATH)
    fs.writeFile(COMPILE_PATH + "/config.js", template, cb)

gulp.task('make_config', (cb) ->
    makeConfig(true, cb)
)

gulp.task('make_config:dist', (cb) ->
    makeConfig(false, cb)
)

gulp.task "update",  ->
    getRemoteCode = (cb) ->
        console.log("Grabbing latest gulpfile from github...")
        remoteCode = ""
        req = https.request({
            host: 'raw.githubusercontent.com',
            port: 443,
            path: '/HourlyNerd/gulp-build/standalone/gulpfile.coffee',
            method: 'GET'
            agent: false
        }, (res) ->
            res.on('data', (d) ->
                remoteCode += d
            )
            res.on('end', ->
                cb(remoteCode)
            )
        )
        req.end()

    getRemoteCode((remoteCode) ->
        localCode = fs.readFileSync('./gulpfile.coffee', 'utf8')
        if localCode.length != remoteCode.length
            fs.writeFileSync("./gulpfile.coffee", remoteCode)
            console.log("The contents of your gulpfile do not match latest. Updating...")
        else
            console.log("Your gulpfile matches latest. No update required.")
    )

gulp.task "default", (cb) ->
    runSequence(['clean:compiled', 'clean:tmp']
                'copy_deps'
                'templates'
                'make_config'
                'sprite'
                ['coffee', 'sass']
                'inject',
                'inject:version'
                'bower'
                'copy_extras'
                'webserver'
                'watch'
                cb)

gulp.task "test", (cb) ->
    runSequence(['clean:compiled', 'clean:tmp']
                ['coffee', 'sass']
                'inject'
                'karma'
                cb)

gulp.task "build", (cb) ->
    runSequence(['clean:dist', 'clean:compiled', 'clean:tmp']
                'copy_deps'
                'templates'
                'make_config:dist'
                'sprite'
                ['coffee', 'sass']
                'images'
                'inject',
                'inject:version'
                'bower'
                'copy_extras:dist'
                'package:dist')

if fs.existsSync('./custom_gulp_tasks.coffee')
    require('./custom_gulp_tasks.coffee')(gulp)
