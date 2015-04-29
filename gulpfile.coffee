config = require('./config.json')
fs = require('fs')
https = require('https')
path = require('path')
httpProxy = require('http-proxy')
gulp = require("gulp")
colors = require("colors")
glob = require("glob")
sass = require("gulp-sass")
replace = require("gulp-replace")
concat = require("gulp-concat")
sourcemaps = require("gulp-sourcemaps")
watch = require('gulp-watch')
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
header = require('gulp-header')
plumber = require('gulp-plumber')
gutil = require('gulp-util')
lazypipe = require('lazypipe')
express = require('express')
sassGraph = require('gulp-sass-graph')

gulp_src = gulp.src

gulp.src = ->
  gulp_src.apply(gulp, arguments).pipe(plumber((error) ->
    # Output an error message
    gutil.log gutil.colors.red('Error (' + error.plugin + '): ' + error.message)
    # emit the end event, to properly end the task
    @emit 'end'
    return
  ))

LOG_PROXY_HEADERS = false
UGLIFY_DEV = false
isProdBuild = false

# read or update local config - no args = read, or update with an object
local_config = (update) ->
    LOCAL_CONFIG_FILE = 'config.local.json'
    cfg = path.join(__dirname, LOCAL_CONFIG_FILE)
    read = ->
        if not fs.existsSync(cfg)
            fs.writeFileSync(cfg, "{}")
            gi = path.join(__dirname, '.gitignore')
            giContents = fs.readFileSync(gi)
            if LOCAL_CONFIG_FILE not in giContents
                fs.writeFileSync(gi, giContents+"\r\n"+LOCAL_CONFIG_FILE)
            return {}
        else
            try
                return JSON.parse(fs.readFileSync(cfg))
            catch e
                console.error('could not json parse local config file:', cfg, e)
                return {}

    if arguments.length == 0
        return read()
    else
        json = _.extend(read(), update)
        fs.writeFileSync(cfg, JSON.stringify(json))
        return json

if '--staging' in process.argv
    config.dev_server.backend = 'staging'


if '--prod' in process.argv
    isProdBuild = true

if '--ugly' in process.argv
    UGLIFY_DEV = true
    console.log("making your code really ugly!!! wait.. that doesnt need a special flag! zing!")

if '--verbose' in process.argv
    LOG_PROXY_HEADERS = true
    console.log("====== verbose proxy header logging enabled ======")

gitHash = 'didnt find it yet'
require('child_process').exec('git log -1 --pretty=format:Hash:%H%nDate:%ai', (err, stdout) ->
    gitHash = stdout.replace('\n', '<br/>')
)

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
    _.each(globs, (glb) ->
        if glb.charAt(0) != '!'
            glob.sync(glb).forEach((p) ->
                if p.indexOf('bower_components') <= -1
                    d = p.replace(re, "")
                    if not deduper[d]
                        deduper[d] = p
                    else
                        ignorePaths.push("!"+p)
            )
    )
    return globs.concat(ignorePaths)


ngClassifyOptions =
    controller:
        format: 'upperCamelCase'
        suffix: 'Controller'
    constant:
        format: '*' #unchanged
    appName: config.app_name
    provider:
        suffix: ''
pathsForExt = (ext) ->
    return [
        "./app/*/**/*."+ext
        "./.tmp/*/**/*."+ext
        "!./app/bower_components/**/*."+ext
    ]
paths =
    sass: pathsForExt('scss')
    templates: pathsForExt('html')
    coffee: pathsForExt('coffee')
    images: pathsForExt('+(png|jpg|gif|jpeg)')
    fonts: BOWER_PATH + '/**/*.+(woff|woff2|svg|ttf|eot|otf)'
    runtimes: BOWER_PATH + '/**/*.+(xap|swf)'
    assets: [
        path.join(BOWER_PATH, '/hn-*/app/*/**/*.*')
        "!"+path.join(BOWER_PATH, '/hn-*/app/bower_components/**/*.*')
    ]


pipes = {
    coffeeLint:
        lazypipe()
            .pipe(coffeelint)
            .pipe(coffeelint.reporter)
            .pipe(gulp.dest, COMPILE_PATH)
    sass:
        lazypipe()
            .pipe(sourcemaps.init)
            .pipe(sass, {
                includePaths: ['.tmp/', 'app/bower_components', 'app']
                precision: 8
                onError: (err) ->
                    file_path = err.file.replace(__dirname, "")
                    console.log("SASS Error:".red.underline
                        err.message.bold
                        'in file'
                        file_path.bold
                        'on line'
                        (err.line+'').bold
                        'column'
                        (err.column+'').bold)
            })
            .pipe(sourcemaps.write)
            .pipe(gulp.dest, COMPILE_PATH)
}


gulp.task 'watch', (cb) ->
    watch(APP_PATH+'/index.html', ->
        runSequence('inject', 'bower')
    )
    types = '/**/*.+(js|css|coffee|html|scss)'
    assets = [APP_PATH+"/modules"+types, APP_PATH+"/components"+types]

    _.each(glob.sync(path.join(BOWER_PATH, 'hn-*')), (p) ->
        resolved = fs.realpathSync(p)
        if resolved != p
            assets.push(path.join(resolved, 'app/modules'+types))
            assets.push(path.join(resolved, 'app/components'+types))
    )

    watch(assets , followSymlinks: false, (v) ->
        tasks = []
        pre = (cb) ->
            cb()
        ext = path.extname(v.path).toLowerCase()
        if ext == '.scss'
            tasks = ['sass', 'inject', 'bower']
        if ext == '.coffee'
            tasks = ['coffee', 'inject', 'bower']
        if ext == '.html'
            tasks = ['templates']
        assetPath = v.path
        if v.path.indexOf(__dirname) != 0 # this path comes from within the bower components dir
            pre = (cb) ->
                assetPath = v.path.replace(/^.*?\/app\//, TEMP_PATH+"/") # gets put here next
                copyDeps(gulp.src(v.path, {
                    dot: true
                    base: BOWER_PATH
                }), cb)

        if tasks.length
            console.log('change:', v.path)
            pre( ->
                runSequence.apply(runSequence, tasks)
            )
        return
    )
    cb()

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
        "./.compiled/components/**/*.css"
        "./.compiled/modules/"+config.main_module_name+"/"+config.main_module_name+".module.js"
        "./.compiled/modules/**/*.module.js"
        "./.compiled/modules/**/*.provider.js"
        "./.compiled/templates.js"
        "./.compiled/config.js"
        "./.compiled/modules/**/*.run.js"
        "./.compiled/modules/**/*.js"
        "./.compiled/components/**/*.js"
        "!./.compiled/modules/**/tests/*"
        "!./.compiled/modules/**/*.backend.js"
        "./.compiled/modules/"+config.main_module_name+"/*.provider.js"
        "./.compiled/modules/"+config.main_module_name+"/*.config.js"
        "./.compiled/modules/"+config.main_module_name+"/*.run.js"
        "./.compiled/modules/"+config.main_module_name+"/*.js"
    ], read: false)

    return target
        .pipe(inject(sources,
            ignorePath: [".compiled", BOWER_PATH]
            transform:  (filepath) ->
                filepath = path.normalize(path.join(config.dev_server.staticRoot, filepath))
                return inject.transform.apply(inject.transform, [filepath])
        ))
        .pipe(gulp.dest(COMPILE_PATH))

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
)

gulp.task "webserver", ->
    fallback = (req, res, next) ->
        res.sendFile(path.join(__dirname, COMPILE_PATH, "index.html"))

    backend = config.backends[config.dev_server.backend]
    app = express()
    proxy = httpProxy.createProxyServer()

    proxy.on('proxyReq', (proxyReq, req, res, options) ->
        if config.app_host
            proxyReq.setHeader('X-App-Host', config.app_host)
        else
            proxyReq.setHeader('X-App-Host', req.hostname)
        proxyReq.setHeader('X-App-Token', backend.app_token)
        LOG_PROXY_HEADERS and console.log('proxy request: headers:', proxyReq._headers)
        LOG_PROXY_HEADERS and console.log('proxy request: method:', proxyReq.method)
        LOG_PROXY_HEADERS and console.log('proxy request: path:', proxyReq.path)
    )
    proxy.on('proxyRes', (proxyRes, req, res) ->
        LOG_PROXY_HEADERS and console.log('proxy response: headers:', proxyRes.headers)
    )
    proxy.on('error', (err, req, res, options) ->
        LOG_PROXY_HEADERS and console.log('proxy error:', err)
    )
    app.use((req, res, next) ->
        if req.method.toLowerCase() == 'delete' # fix 411 http errors on delete thing
            req.headers['Content-Length'] = '0'
        next()
    )
    app.all("/api/*", (req, res) ->
        req.url = req.url.replace('/api', '')
        LOG_PROXY_HEADERS and console.log('proxying ', req.url, 'to', backend.host)
        proxy.web(req, res, {target: backend.host, secure: false, changeOrigin: true, rejectUnauthorized: false})
    )
    app.use((req, res, next) ->
        if req.path.match(/\/[^\.]*$/) # path ends with /foo or /bar/ - not a static file
            fallback(req, res, next)
        else
            next()
    )
    staticRoot = config.dev_server.staticRoot or "/"
    app.use(staticRoot, express.static(path.join(__dirname, COMPILE_PATH)))
    app.use(staticRoot, express.static(path.join(__dirname, TEMP_PATH)))
    app.use(staticRoot, express.static(path.join(__dirname, APP_PATH)))
    app.use(fallback)
    app.listen(config.dev_server.port, config.dev_server.host)
    console.log("listening on ", config.dev_server.port)

gulp.task "bower", ->
    prefix = config.dev_server.staticRoot
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

gulp.task "sass", ->
    return gulp.src(dedupeGlobs(paths.sass))
        .pipe(changed(COMPILE_PATH))
        .pipe(pipes.sass())
        .on('error', (e) ->
            console.error("Error in file "+e.fileName+" line "+e.lineNumber+":\n"+e.message)
        )

gulp.task "templates", ->
    return gulp.src(dedupeGlobs(paths.templates))
        .pipe(templateCache("templates.js",
            module: config.app_name
            root: '/'
            htmlmin:
                removeComments: true
        ))
        .pipe(gulp.dest(COMPILE_PATH))

handler = (err) ->
    console.error(err.message+"  "+err.filename+" line:"+err.location.first_line)

gulp.task "coffee", ->
    pipe = gulp.src(dedupeGlobs(paths.coffee))
        .pipe(sourcemaps.init())
        .pipe(ngClassify(ngClassifyOptions)).on('error', handler)
        .pipe(coffee()).on('error', handler)
        .pipe(ngAnnotate())
    if UGLIFY_DEV
        pipe = pipe.pipe(uglify())
    pipe = pipe
        .pipe(sourcemaps.write())
        .pipe(gulp.dest(COMPILE_PATH))


gulp.task "coffee_lint", ->
    return gulp.src(dedupeGlobs(paths.coffee))
        .pipe(pipes.coffeeLint())


copyDeps = (src, cb=->) ->
    src.pipe(rename( (file) ->
        if file.extname != ''
            file.dirname = file.dirname.replace(/^.*?\/app\//, '')
            return file
        else
            return no
    ))
    .pipe(gulp.dest(TEMP_PATH))
    .on('end', cb)

gulp.task "copy_deps", ->
    copyDeps(gulp.src(paths.assets, {
        dot: true
        base: BOWER_PATH
    }))

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
        .pipe(gulp.dest(DIST_PATH))

#gulp.task "add_banner", ->
#    banner = """// <%= file.path %>"""
#    gulp.src(DIST_PATH+"/**/*.js")
#    .pipe(header(banner, file: {path: 'foo'}))
#    .pipe(gulp.dest(DIST_PATH))


gulp.task "package:dist", ->
    assets = useref.assets()
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(assets)
        .pipe(gulpIf('*.js', ngAnnotate()))
        .pipe(gulpIf('*.js', uglify()))
        .pipe(gulpIf('*.css', minifyCss({
            compatibility: 'colors.opacity' # ie doesnt like rgba values :P
        })))
        .pipe(rev())
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(revReplace())
        .pipe(gulp.dest(DIST_PATH))

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

    baseConfig = require(path.join(__dirname, "./config/config_base"))
    if not baseConfig
        console.error(path.join(__dirname, "./config/config_base.coffee")+" needs to exist!")

    settings = baseConfig(isProdBuild, {
        app_version: bwr.version
        bower_versions: versions
        build_date: new Date()
        hash: gitHash
        app_host: config.app_host
    })
    settings.keys = 'its a secret' #secret stuff in here!

    template = """
        angular.module('appConfig', [])
            .constant('APP_CONFIG', #{JSON.stringify(settings)});
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
    getRemoteCode = (filename, cb) ->
        console.log("Grabbing latest gulpfile from github...")
        remoteCode = ""
        req = https.request({
            host: 'raw.githubusercontent.com',
            port: 443,
            path: '/HourlyNerd/gulp-build/standalone/' + filename,
            method: 'GET'
            agent: false
        }, (res) ->
            res.on('data', (d) ->
                remoteCode += d
            )
            res.on('end', ->
                cb(filename, remoteCode)
            )
        )
        req.end()

    getRemoteCode('gulpfile.coffee', (filename, remoteCode) ->
        localCode = fs.readFileSync("./#{filename}", 'utf8')
        if localCode.length != remoteCode.length
            fs.writeFileSync("./#{filename}", remoteCode)
            console.log("The contents of your #{filename} do not match latest. Updating...")
        else
            console.log("Your #{filename} matches latest. No update required.")
    )

# builds a json file containing all of this application's state urls
gulp.task('build_routes', (cb) ->
    OUTPUT = './app_routes.json'
    INPUT = './.compiled/**/*.routes.js'

    glob = require('glob')
    path = require('path')
    vm = require("vm")
    fs = require("fs")

    stateMap = {}

    snakeSnakeIts_A_SNAAAAKE = (str) ->
        # badger badger badger badger MUSHROOM MUSHROOM
        return str.replace(/([A-Z])/g, "_$1").toLowerCase()


    parseUrlParams = (url, abstract) ->
        url = url.replace(/{([^:]+)(:\w+)?}/g, (orig, match) -> "<string:" + snakeSnakeIts_A_SNAAAAKE(match) + ">")
        url = url.replace(/\/:(\w+)/g, (orig, match) -> "/<string:" + snakeSnakeIts_A_SNAAAAKE(match) + ">")
        surl = url.split("?")
        if surl.length == 2
            [path, qs] = surl
            qps = []
            for qp in qs.split("&")
                qps.push(qp + "=<string:" + snakeSnakeIts_A_SNAAAAKE(qp) + ">")
            url = path + "?" + qps.join("&")
        return {url, abstract}

    inject =
        $urlRouterProvider:
            when: (urlFrom, urlTo) ->
                return inject.$stateProvider
        $stateProvider:
            state: (name, map) ->
                stateMap[name] = parseUrlParams(map.url, !!map.abstract)
                return inject.$stateProvider
        componentProvider:
            state: (map) ->
                stateMap[map.name] = parseUrlParams(map.url, !!map.abstract)
                return inject.componentProvider
        coreSettingsProvider:
            $get: ->
                return {path: ->}
        e:
            UserType: {}

    moduleMock =
        config: (arr) ->
            [things..., fn] = arr
            args = []
            for name in things
                args.push(inject[name])
            fn.apply(null, args)
            return moduleMock
        run: ->
            return moduleMock

    angular =
        module: ->
            return moduleMock


    ctx =
        angular: angular


    for m in glob.sync(INPUT)
        vm.runInNewContext(fs.readFileSync(m), ctx)

    urlMap = {}
    map = {}
    Object.keys(stateMap).sort((a, b) ->
        return a.split(".").length - b.split(".").length
    ).forEach((s) ->
        obj = stateMap[s]
        st = s.split(".")
        if st.length > 1
            parentState = st.slice(0, st.length-1).join('.')
            if urlMap[parentState] is undefined
                console.log('parent state not found:', parentState, s)
            url = urlMap[s] = urlMap[parentState] + obj.url
        else
            urlMap[s] = obj.url
        if not obj.abstract
            map[s] = url
    )
    fs.writeFileSync(OUTPUT, JSON.stringify(map, null, "    "))
    console.log("wrote #{Object.keys(map).length} routes to #{OUTPUT}")
)

gulp.task('bower_install', (gulpCb) ->
    exec = require('child_process').exec
    path = require('path')
    async = require('async')
    fs = require('fs')
    _ = require('underscore')

    parser = require('optimist')
        .usage('Update or link HN modules from bower')
        .describe('clean', 'install fresh dependencies')
        .describe('link', 'comma separated list of repos to link')
        .describe('last', 'link the repos that you linked last time')
        .describe('h', 'print usage')
        .alias('h', 'help')
        .default('link', '')
        .default('last', '')


    task = (command, cwd) ->
        return (cb) ->
            console.log("#{cwd}> "+command)
            exec(command, cwd: cwd, (err, out) ->
                if err
                    console.log("ERR: ", err)
                cb()
            )
            return

    args = parser.argv
    if args.help
        console.log(parser.help())
        return

    repos = args.link.split(',')

    command = 'link'
    if args.link
        local_config({bower_link: repos})

    if args.last
        repos = local_config()?.bower_link or []
        command = 'last'

    console.log("Installing bower components:\n--#{command}: #{repos.join(',')}")
    console.log("--clean: #{(if args.clean then 'Yes' else 'No')}")
    console.log("Starting...")
    console.log("---------------------------------------------")




    tasks = []
    if args.clean
        tasks.push(task("rm -rf #{path.join(__dirname, 'app', 'bower_components')}", __dirname))

    tasks.push(task("bower install",  __dirname))

    for r in repos
        dir = path.join(__dirname, '..', r)
        if fs.existsSync(dir)
            tasks.push(task("bower link", dir))
            tasks.push(task("bower link #{r}", __dirname))
        else
            console.log("#{r} does not exist! Did you git clone it? Looked here:", dir)


    async.series(tasks, (err) ->
        console.log("Finished!")
        gulpCb()
    )
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
