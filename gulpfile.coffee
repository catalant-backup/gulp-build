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

error_handle = (err) ->
    console.error err
    return

COMPILE_PATH = "./.compiled"            # Compiled JS and CSS, Images, served by webserver
TEMP_PATH = "./.tmp"                    # hourlynerd dependencies copied over, uncompiled
APP_PATH = "./app"                      # this module's precompiled CS and SASS
BOWER_PATH = "./app/bower_components"   # this module's bower dependencies
DOCS_PATH = './docs'
DIST_PATH = './dist'


paths =
    sass: [
        "./app/modules/**/*.scss"
        "./.tmp/modules/**/*.scss"
    ]
    templates: [
        "./app/modules/**/views/*.html"
        "./.tmp/modules/**/views/*.html"
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
    hn_assets: BOWER_PATH + '/hn-*/app/modules/**/*.*'
    #images_main: "./app/images/*.+(png|jpg|gif|jpeg)"

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
    watch(paths.sass, ->
        runSequence('sass', 'inject', 'bower')
    )
    watch(paths.coffee, (event) ->
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
    watch(paths.hn_assets, ->
        runSequence('clean:tmp', 'clean:compiled', 'inject', 'inject:version', 'copy_deps', ['coffee', 'sass'])
    )
)

gulp.task "clean:compiled", (cb) ->
    return gulp.src(COMPILE_PATH)
        .pipe(vinylPaths(del))

gulp.task "clean:tmp", (cb) ->
    return gulp.src(TEMP_PATH)
        .pipe(vinylPaths(del))


gulp.task "clean:docs", (cb) ->
    return gulp.src(DOCS_PATH)
        .pipe(vinylPaths(del))


gulp.task "clean:dist", (cb) ->
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
            ignorePath: ['.compiled', BOWER_PATH]
            transform:  (filepath) ->
                filepath = path.normalize(path.join(config.deploy_path, filepath))
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
    protocol = if ~config.dev_server.backend.indexOf("https:") then "https:" else "http:"
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
            ],
            middleware: [
                (req, res, next) ->
                    if req.url.indexOf(config.web_root) == 0
                        req.url = req.url.substring(config.web_root.length)
                    if req.url.indexOf(config.deploy_path) == 0
                        req.url = req.url.substring(config.deploy_path.length)
                    next()
            ]
        ))
        .on "error", error_handle

gulp.task "bower", ->
    prefix = path.join(config.deploy_path, "/")
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(wiredep({
            directory: BOWER_PATH
            ignorePath: '../app/'
            exclude: config.bower_exclude
            fileTypes: {
                html: {
                    block: /(([ \t]*)<!--\s*bower:*(\S*)\s*-->)(\n|\r|.)*?(<!--\s*endbower\s*-->)/gi,
                    detect: {
                        js: /<script.*src=['"]([^'"]+)/gi,
                        css: /<link.*href=['"]([^'"]+)/gi
                    },
                    replace: {
                        js: '<script src="'+prefix+'{{filePath}}"></script>',
                        css: '<link rel="stylesheet" href="'+prefix+'{{filePath}}" />'
                    }
                }
            }
        }))
        .pipe(gulp.dest(COMPILE_PATH))
        .on "error", error_handle


gulp.task "sass", ->
    return gulp.src(paths.sass)
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
    return gulp.src(paths.templates)
        .pipe(templateCache("templates.js",
            module: config.app_name
            root: path.join(config.deploy_path, 'modules')
        ))
        .pipe(gulp.dest(COMPILE_PATH))
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
        .pipe(ngAnnotate())
        .pipe(gulp.dest(COMPILE_PATH + "/modules"))
        .on "error", error_handle

gulp.task "copy_deps", ->
    return gulp.src(paths.hn_assets, {
            dot: true
            base: "./app/bower_components"
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

gulp.task "copy_fonts", ->
    return gulp.src(paths.fonts, {
            dot: true
            base: "./app/bower_components"
        }).pipe(rename( (file) ->
            if file.extname != ''
                file.dirname = 'ng/fonts'
                return file
            else
                return no
        ))
        .pipe(gulp.dest(COMPILE_PATH))
        .pipe(gulp.dest(DIST_PATH))

gulp.task "images", ->
    return gulp.src(paths.images)
        .pipe(imageop({
            optimizationLevel: 5
            progressive: true
            interlaced: true
        }))
        .pipe(gulp.dest(DIST_PATH, cwd: DIST_PATH))
        .on "error", error_handle


gulp.task "move_folders", ->
    return gulp.src([
            DIST_PATH + "/dist/**"
        ])
        .pipe(gulp.dest(DIST_PATH + "/ng/modules"))

gulp.task "delete_things", (cb) ->
    del([
        DIST_PATH + "/dist/**"
    ], cb)

gulp.task "package:dist", ->
    assets = useref.assets()
    jsRe = RegExp("""<script.*src=["]#{config.deploy_path}/([^"]+)""", 'gi')
    cssRe = RegExp("""<link.*href=["]#{config.deploy_path}/([^"]+)""", 'gi')
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(replace(jsRe, '<script src="$1'))
        .pipe(replace(cssRe, '<link rel="stylesheet" href="$1'))
        .pipe(assets)
        .pipe(gulpIf('*.js', ngAnnotate()))
        .pipe(gulpIf('*.js', uglify()))
        .pipe(gulpIf('*.css', minifyCss()))
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(gulp.dest(DIST_PATH))
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

# generate sprite file
# See: https://github.com/aslansky/css-sprite
# Compiles images in all modules into base64 encoded sass mixins
# Must @import "sprite" in file then @include sprite($sprite_name)
# See .tmp/sprite.scss after compilation step to see variable names.
# Variable name = $[module_name]-images-[filename_underscore_separated]
gulp.task('sprite', ->
    return gulp.src(paths.images)
    .pipe(sprite({
        name: "sprite"
        style: "sprite.scss"
        cssPath: ""
        base64: true
        processor: "scss"
    }))
    .pipe(gulp.dest(TEMP_PATH))
)

gulp.task('make_config', (cb) ->
    configs = glob.sync(BOWER_PATH+"/**/bower.json")
    versions = {}
    configs.forEach((cpath)->
      c = require(cpath)
      versions[c.name] = c.version
    )
    config.bower_versions = versions
    config.build_date = new Date()
    constant = JSON.stringify(config)
    template = """
        angular.module('appConfig', [])
            .constant('APP_CONFIG', #{constant});
    """
    fs.writeFile(COMPILE_PATH + "/config.js", template, cb)
)

gulp.task "update_self", (cb) ->
    called = false
    callback = ->
        if not called
            called = true
            cb()
            
    getRemoteCode = (cb) ->
        remoteCode = ""
        req = https.request({
          host: 'raw.githubusercontent.com',
          port: 443,
          path: '/HourlyNerd/gulp-build/master/gulpfile.coffee',
          method: 'GET'
        }, (res) ->
            res.on('data', (d) ->
                remoteCode += d
            )
            res.on('end', ->
                cb(null, remoteCode)
            )
            res.on('error', (err) ->
                cb(err)
            )
        )
        req.end()
        req.on('error', (err) ->
            cb(err)
        )

    getRemoteCode((err, remoteCode) ->
        if err
            console.log("Could not self update! remote returned an error: ", err)
            return callback()
            
        localCode = fs.readFileSync('./gulpfile.coffee', 'utf8')

        if localCode.length != remoteCode.length
            newName = "./gulpfile.bak#{~~(Math.random() * 100)}.coffee"
            fs.writeFileSync(newName, localCode)
            fs.writeFileSync("./gulpfile.coffee", remoteCode)
            args = process.argv

            spawn = require('child_process').spawn
            console.log("!!!!!!!!!!!!!!!!!!!!!!! SELF UPDATE !!!!!!!!!!!!!!!!!!!!!", localCode.length, remoteCode.length)
            console.log("The contents of your gulpfile dont match github!\nBacking up your gulpfile to #{newName} and updating self.")
            if args.length == 2 #ran gulp without any args
                console.log("Looks like you are in dev mode, attempting to restart process.")
                spawn('gulp', [], {stdio: 'inherit'})
            else
                console.log("Looks like you are doing a prod build, Im going to kill this and you will have to re-build. sorry!")
                process.exit(0)
        else
            callback()
    )
gulp.task "default", (cb) ->
    runSequence(['update_self', 'clean:compiled', 'clean:tmp']
                'copy_deps'
                'templates'
                'make_config'
                'sprite'
                ['coffee', 'sass']
                'inject',
                'inject:version'
                'bower'
                'copy_fonts'
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
    runSequence(['update_self', 'clean:dist', 'clean:compiled', 'clean:tmp']
                'copy_deps'
                'templates'
                'make_config'
                'sprite'
                ['coffee', 'sass']
                'images'
                'inject',
                'inject:version'
                'bower'
                'copy_fonts'
                'package:dist'
                'move_folders'
                'delete_things')
