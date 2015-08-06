config = require('./config.json')
fs = require('fs')
async = require('async')
https = require('https')
path = require('path')
httpProxy = require('http-proxy')
gulp = require("gulp")
colors = require("colors")
glob = require("glob")
sass = require("gulp-sass")
replace = require("gulp-replace")
sourcemaps = require("gulp-sourcemaps")
concat = require("gulp-concat")
changed = require("gulp-changed")
wiredep = require("wiredep").stream
inject = require("gulp-inject")
del = require('del')
vinylPaths = require('vinyl-paths')
runSequence = require('run-sequence')
minifyCss = require('gulp-minify-css')
uglify = require('gulp-uglify')
useref = require('gulp-useref')
rename = require('gulp-rename')
gulpIf = require('gulp-if')
imageop = require('gulp-image-optimization')
#karma = require('karma').server
#protractor = require("gulp-protractor").protractor
rev = require('gulp-rev')
revReplace = require('gulp-rev-replace')
header = require('gulp-header')
plumber = require('gulp-plumber')
gutil = require('gulp-util')
lazypipe = require('lazypipe')
express = require('express')
compression = require('compression')
yargs = require('yargs')
bless = require('gulp-bless')
cache = require('gulp-cache')
ignore = require('gulp-ignore')
partialify = require('partialify/custom')

rework = require('rework')
reworkUrl = require('rework-plugin-url')

transform = require('vinyl-transform')
browserify = require("browserify")

coffeeify = require("caching-coffeeify")
$ = require('gulp-load-plugins')()
sass = require('gulp-sass')
concat = require('gulp-concat')
watchify = require('watchify')
source = require('vinyl-source-stream')
buffer = require('vinyl-buffer')
_ = require('lodash')
ngClassify = require('ng-classify')
through = require('through')
parcelify = require('parcelify')
uglify = require('gulp-uglify')
cssmin = require('gulp-cssmin')
aliasify = require('aliasify')
browserify_ngannotate = require('browserify-ngannotate')

bowerResolve = require('bower-resolve')

sassCssStream = require('sass-css-stream')
browserifyInc = require('browserify-incremental')
filesize = (f) ->
    return " "+require('filesize')(fs.statSync(path.join(__dirname, f)).size)

SegfaultHandler = require('segfault-handler')
SegfaultHandler.registerHandler()
# Troubleshooting:

# segfault:
# if segfault happens and its related to sass, print out 'file' from here: node_modules/scssify/lib/index.js@67

# too many open files:
# launchctl limit maxfiles 16384 16384 && ulimit -n 16384


LOG_PROXY_HEADERS = false
UGLIFY_DEV = false
SERVE_MINFIED = false #serve dist, toggle to true, gulp build, then gulp webserver to see prod like stuffs
buildEnv = 'dev'
cacheEnabled = false #to enable, in app console: apicache.enable() and .disable() .clear() .status()
ravenDsn = ''

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
        fs.writeFileSync(cfg, JSON.stringify(json, null, "    "))
        return json

config.dev_server.backend = local_config().backend or "local"

if '--staging' in process.argv
    config.dev_server.backend = 'staging'

if '--local' in process.argv
    config.dev_server.backend = 'local'

if '--test' in process.argv
    config.dev_server.backend = 'test'

console.log("Using Backend: "+config.dev_server.backend.toUpperCase().red.underline)
console.log("API cache ENABLED".green.underline) if cacheEnabled

# Deprecated, use --buildenv argument instead, left here for legacy
if '--prod' in process.argv
    buildEnv = 'prod'

if yargs.argv.buildenv
    buildEnv = yargs.argv.buildenv

if '--ugly' in process.argv
    UGLIFY_DEV = true
    console.log("making your code really ugly!!! wait.. that doesnt need a special flag! zing!")

if '--verbose' in process.argv
    LOG_PROXY_HEADERS = true
    console.log("====== verbose proxy header logging enabled ======".red.underline)

if yargs.argv.raven_dsn
    ravenDsn = yargs.argv.raven_dsn
else
    if config.raven_dsn_env_map? and buildEnv of config.raven_dsn_env_map
        ravenDsn = config.raven_dsn_env_map[buildEnv]

gitHash = 'didnt find it yet'
require('child_process').exec('git log -1 --pretty=format:Hash:%H%nDate:%ai', (err, stdout) ->
    gitHash = stdout.replace('\n', '<br/>')
)

gitBranch = 'didnt find it yet'
require('child_process').exec('git rev-parse --abbrev-ref HEAD', (err, stdout) ->
    gitBranch = stdout.replace('\n', '')
)


COMPILE_PATH = "./.compiled"            # Compiled JS and CSS, Images, served by webserver
TEMP_PATH = "./.tmp"                    # hourlynerd dependencies copied over, uncompiled
APP_PATH = "./app"                      # this module's precompiled CS and SASS
BOWER_PATH = "./app/bower_components"   # this module's bower dependencies
DOCS_PATH = './docs'
DIST_PATH = './dist'

# Used by gulp-cache to get a unique cache dir by branch/app_name
gulpCache = ->
    return new cache.Cache({ cacheDirName: 'gulp-cache/' + gitBranch + '/' + config.app_name })

dedupeGlobs = (globs, root="/modules") ->
    #expand globs arrays, dedupe paths after 'root' in order of arrival. return a new glob array ignoring dupes
    deduper = {}
    ignorePaths = []
    re = RegExp("^.*?"+root)
    _.each(globs, (glb) ->
        if glb.charAt(0) != '!'
            glob.sync(glb).forEach((p) ->
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
        "./app/bower_components/hn-core/app/**/*.#{ext}"
        "./app/**/*.#{ext}"
    ]
paths =
    sass: pathsForExt('scss')
    #coffee: pathsForExt('coffee')
    images: pathsForExt('+(png|jpg|gif|jpeg|svg)')
    bower_images: './app/bower_components/**/*.+(png|jpg|gif|jpeg)'
    fonts: BOWER_PATH + '/**/*.+(woff|woff2|svg|ttf|eot|otf)'
    runtimes: BOWER_PATH + '/**/*.+(xap|swf)'
    assets: [
        path.join(BOWER_PATH, '/hn-*/app/*/**/*.*')
        "!"+path.join(BOWER_PATH, '/hn-*/app/bower_components/**/*.*')
    ]



gulp.task "clean:compiled",  ->
    return gulp.src(COMPILE_PATH)
        .pipe(vinylPaths(del))

gulp.task "clean:tmp",  ->
    return gulp.src(TEMP_PATH)
        .pipe(vinylPaths(del))


gulp.task "clean:dist",  ->
    return gulp.src(DIST_PATH)
        .pipe(vinylPaths(del))


injectBundle = (task_cb, theme) ->
    target = gulp.src("./app/index.html")

    if theme
        filename = theme.index
        themeName = theme.filename
        themeType = theme.type
    else
        filename = "index.html"
        themeName = "app.css"
        themeType = "public-enterprise"

    sources = gulp.src([
        "./.compiled/bundle/*.map"
        "./.compiled/bundle/common.js"
        "./.compiled/bundle/app.js"
    ], read: false)


    tr = (filepath) ->
        filepath = path.normalize(path.join(config.dev_server.staticRoot, filepath))
        filepath = filepath.replace('/.compiled', '') #TODO
        return inject.transform.apply(inject.transform, [filepath])

    return target
        .pipe(rename(filename))
        .pipe(replace('APP_TYPE_CLASS', themeType))
        .pipe(inject(sources,
            transform:  tr
        ))
        .pipe(gulpIf(ravenDsn != '', inject(gulp.src(["./.compiled/index.html"], read:false),
            starttag: '<!-- raven -->',
            endtag: '<!-- end_raven -->'
            transform: (filepath, file) ->
                return """
                <script src="//cdnjs.cloudflare.com/ajax/libs/raven.js/1.1.16/raven.min.js"></script>
                <script>
                Raven.config('#{ravenDsn}', {
                  logger: 'javascript',
                  ignoreErrors: [
                    // Random plugins/extensions
                    'top.GLOBALS',
                    // See: http://blog.errorception.com/2012/03/tale-of-unfindable-js-error. html
                    'originalCreateNotification',
                    'canvas.contentDocument',
                    'MyApp_RemoveAllHighlights',
                    'http://tt.epicplay.com',
                    "Can't find variable: ZiteReader",
                    'jigsaw is not defined',
                    'ComboSearch is not defined',
                    'http://loading.retry.widdit.com/',
                    'atomicFindClose',
                    // Facebook borked
                    'fb_xd_fragment',
                    // ISP "optimizing" proxy - `Cache-Control: no-transform` seems to reduce this. (thanks @acdha)
                    // See http://stackoverflow.com/questions/4113268/how-to-stop-javascript-injection-from-vodafone-proxy
                    'bmi_SafeAddOnload',
                    'EBCallBackMessageReceived',
                    // See http://toolbar.conduit.com/Developer/HtmlAndGadget/Methods/JSInjection.aspx
                    'conduitPage'
                  ],
                  ignoreUrls: [
                    // Facebook flakiness
                    /graph\\.facebook\\.com/i,
                    // Facebook blocked
                    /connect\\.facebook\\.net\\/en_US\\/all\\.js/i,
                    // Woopra flakiness
                    /eatdifferent\\.com\\.woopra-ns\\.com/i,
                    /static\\.woopra\\.com\\/js\\/woopra\\.js/i,
                    // Chrome extensions
                    /extensions\\//i,
                    /^chrome:\\/\\//i,
                    // Other plugins
                    /127\\.0\\.0\\.1:4001\\/isrunning/i,  // Cacaoweb
                    /webappstoolbarba\\.texthelp\\.com\\//i,
                    /metrics\\.itunes\\.apple\\.com\\.edgesuite\\.net\\//i
                  ]
                }).install();
                </script>"""
        )))
        .pipe(inject(gulp.src(["./.compiled/bundle/#{themeName}"], read:false),
            starttag: '<!-- theme_css -->',
            endtag: '<!-- end_theme_css -->'
            transform:  tr
        ))

        .pipe(gulp.dest(COMPILE_PATH))
        .on("end", ->
            task_cb and task_cb()
        )

gulp.task('inject:build_meta', ->
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(inject(gulp.src('./bower.json'),
            starttag: '<!-- build_info -->',
            endtag: '<!-- end_build_info -->'
            transform: (filepath, file) ->
                contents = file.contents.toString('utf8')
                data = JSON.parse(contents)
                return "<script>HN={env:'#{buildEnv}'};</script>"
        ))
        .pipe(gulp.dest(COMPILE_PATH))
)

gulp.task "webserver", (cb) ->
    cb() #no need to wait for this to be done, this cb creates an illusion of speeeeeeeeed

    fallback = (req, res, next) ->
        if SERVE_MINFIED
            folderPath = path.join(__dirname, DIST_PATH)
        else
            folderPath = path.join(__dirname, COMPILE_PATH)

        themeFile = path.join(folderPath, req.hostname + ".index.html")
        if fs.existsSync(themeFile)
            res.sendFile(themeFile)
        else
            f = path.join(folderPath, "index.html")
            if fs.existsSync(f)
                res.sendFile(f)
            else
                res.send("<html><meta http-equiv='refresh' content='1'><br><br><br><center><h1>Still Gulping...")

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


    apicache = {}



    apicacheCfg = local_config().apicache
    if not apicacheCfg
        apicacheCfg =
            allow:
                GET: true
                POST: true
                PATCH: true
                DELETE: true
        local_config(apicache: apicacheCfg)

    app.use((req, res, next) ->
        _write = res.write
        _end = res.end
        url = req.url.toString()

        if not cacheEnabled
            return next()
        if not url.match(/^\/api\//)
            return next()

        cacheKey = url+" [#{req.method}]"

        if not apicacheCfg.allow[req.method]
            console.log("cache IGNORE: #{req.method} not allowed - [#{url}]")
            return next()

        if apicache[cacheKey]
            console.log("cache HIT: [#{cacheKey}]")
            res.setHeader("hn-local-api-cache", "HIT")
            return res.send(apicache[cacheKey])
        else
            res.setHeader("hn-local-api-cache", "MISS")

        buffer = ""
        req.on("close", () ->
            buffer = ""
        )
        res.write = (data) ->
            if res._headers['content-type'] == 'application/json'
                buffer += data.toString()
            _write.call(res, data)

        res.end = () ->
            if not apicache[cacheKey]
               console.log("cache MISS: [#{cacheKey}]")
               apicache[cacheKey] = buffer
            _end.call(res)

        next()
    )

    app.post("/__devapi__/cache/:command?", (req, res) ->
        cmd = (req.params.command or 'status').toLowerCase()
        if cmd == 'enable'
            cacheEnabled = true
        if cmd == 'disable'
            cacheEnabled = false
        if cmd == 'clear'
            apicache = {}
        if cmd == 'delete'
            key = req.body.key
            success = !!apicache[key]
            delete apicache[key]
            return res.json({success: success, key: key})

        console.log("api cache command: [#{cmd}] - key count:", _.keys(apicache).length)
        return res.json({cacheEnabled: cacheEnabled, index: _.mapObject(apicache, (val, key) -> val.length)})
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
    app.use(compression())
    if SERVE_MINFIED
        app.use(staticRoot, express.static(path.join(__dirname, DIST_PATH)))
    else
        app.use(staticRoot, express.static(path.join(__dirname, COMPILE_PATH)))
        app.use(staticRoot, express.static(path.join(__dirname, TEMP_PATH)))
        app.use(staticRoot, express.static(path.join(__dirname, APP_PATH)))
    app.use(fallback)

    app.listen(config.dev_server.port, config.dev_server.host)
    console.log("listening on ", config.dev_server.port)

linkToCore = (dirname) ->
    coreDir = path.join(__dirname, './app/bower_components/hn-core')
    coreDirReal =  fs.realpathSync(coreDir)
    coreSymlinked = coreDirReal != coreDir
    coreSubDir = path.join(coreDirReal, dirname)
    try
        if fs.existsSync(fs.readlinkSync(coreSubDir))
            fs.unlinkSync(coreSubDir)
    catch e

    if coreSymlinked
        fs.symlinkSync(path.join(__dirname, dirname), coreSubDir, "dir")

# this is pretty hacky, oh well :P - also does it actually work? should test!
#linkToCore("./node_modules")
#linkToCore("./app/bower_components")

getChildOverrides = (bowerPath) ->
    configs = glob.sync(bowerPath+"/**/bower.json")
    overrides = {}
    configs.forEach((cpath)->
        _.extend(overrides, require(cpath).overrides or {})
    )
    _.extend(overrides, require(path.join(__dirname, "bower.json")).overrides or {})
    return overrides

getThemes = () ->
    try
        themes = JSON.parse(fs.readFileSync(path.join(__dirname, 'themes.json')))
    catch e
        themes = []
    _.each(themes, (theme) ->
        theme.filename = "theme_"+_.snakeCase(theme.name)+".css"
        theme.index = theme.domain+".index.html"
    )
    return themes

sassStream = (file, theme, vendorCss) ->

    fileName = path.basename(file)
    if fileName.match(/^(_|\.)/)
        return through((() ->), () ->
            this.queue('.node-sass-bug-fixer { content:"its a bug";}')
            this.queue(null)
        )

    Color = require('node-sass').types.Color
    Null = require('node-sass').types.Null()

    hexToColor = (hex) ->
        hex = parseInt(hex.substring(1), 16)
        r = hex >> 16
        g = hex >> 8 & 0xFF
        b = hex & 0xFF
        return new Color(r, g, b)

    return sassCssStream( file, {
        includePaths: [
            './app/',
            './app/bower_components/hn-core/app/',
            './app/bower_components/'
            './node_modules/',
        ]
        precision: 8
        sourceMap: buildEnv == 'dev' #"./compiled/bundle/styles.css.map"
        sourceMapContents: false
        sourceMapEmbed: true
        sourceMapRoot: "."
        functions:
            "theme-color($color, $d:null)": (name, d) ->
                name = name.getValue()

                c = theme[name + "_color"]
                if _.isString(c)
                    return hexToColor(c)
                else if _.isArray(c)
                    return new Color(c[0], c[1], c[2], c[3]) #support alpha
                else if d
                    return d
                else
                    console.log("SASS Error:".red.underline + " cannot find theme color " + name + " from theme #{theme.name}")
                    return Null

        importer: (url, fromFile) ->
            if url.match(/\.css$/i)
                if not vendorCss #themes dont pass this in
                    return {contents: "", file: file}

                file = path.join(__dirname, "./app/bower_components", url)
                if not fs.existsSync(file)
                    file = path.join(__dirname, "./node_modules", url) # look there too!

                if vendorCss[url] or fs.existsSync(file)
                    if not vendorCss[url]
                        contents = fs.readFileSync(file, 'utf8').toString()
                        contents = rework(contents, source: url).use(reworkUrl((url) ->
                            if not url.match(/^\/modules/) and url.match(/\.(png|jpeg|jpg|gif)$/i)
                                return "/bower_images/#{_.last(url.split("/"))}"
                            return url
                        )).toString(sourcemap: false)
                        vendorCss[url] = contents
                    r =
                        contents: "/* note: [#{url}] was moved into vendor.css by build */"
                        file: file
                    return r
                else
                    console.log("SASS CSS Import Error:".red.underline
                        " cannot @import url: "
                        "[#{url}] from: [#{fromFile}] file not found: #{file}")
            return
    })

buildStyles = (bundler, watch,  output, onDone) ->
    vendorCss = {}
    themes = getThemes()
    bundleDir = path.join(COMPILE_PATH,  "bundle")
    if not fs.existsSync(bundleDir)
        fs.mkdirSync(bundleDir)

    _.each(themes, (theme) ->
        dest = path.join(bundleDir, theme.filename)
        theme.stream = fs.createWriteStream(dest)
        theme.stream.setMaxListeners(500) # more might be needed?
    )
    options = {
        watch: watch
    #    logLevel: "verbose"
        bundles: {
            style: output
        }
        appTransforms: [
            # need an wrapper function to pass options to the stream transformer
            (file) ->
                pass = through()
                _.each(themes, (theme) -> # build themes, if any
                    pass.pipe(sassStream(file, theme)).pipe(theme.stream, end:false)
                )
                return pass
            (file) ->
                return sassStream(file, {}, vendorCss) # build the 'default' theme
        ],
        appTransformDirs: [
            './app/', './app/bower_components/', './node_modules/',
            fs.realpathSync(path.join(__dirname, './app/bower_components/hn-core/app/'))
        ]
    }

    p = parcelify(bundler, options)
    p.on('done', ->
        console.log(">> theme [default]:".green + filesize('./.compiled/bundle/app.css'))
        _.each(themes, (theme) ->
            injectBundle((->), theme)
            console.log(">> theme [#{theme.name}]:".green + filesize(path.join(bundleDir, theme.filename)))
        )
        onDone and onDone(null, _.values(vendorCss).join("\n\n"))
    )
    p.on('error', (err) ->
        onDone and onDone(err, null)
        onDone = null
    )

    return p


bundle = (watch, task_cb) ->
    if not watch
        watchify = browserifyInc = (b) ->
            return b

    FULL_PATHS = true # required for incremental builds to work. prod doesnt use these so its ok

    aliases =
        'underscore': 'lodash'

    externals = ['hn-config']
    getBowerDeps = ->
        ret = {}
        _.each(require('wiredep')().packages, (dep, name) ->
            return if name == 'hn-core'
            js = _.filter(dep.main, (file) -> path.extname(file) == '.js')
#            css = _.filter(dep.main, (file) -> path.extname(file) == '.css')
            if js.length == 1 and fs.existsSync(js[0])
                relative = "./"+path.relative(__dirname, js[0])

                ret[name] = {
                    path: js[0]
                    used: false
                    markUsed: ->
                        ret[name].used = true
                        _.each(_.keys(dep.dependencies), (dname) ->
                            ret[dname]?.used = true
                        )
                    require: (b) ->
                        console.log("common bunddle", name, relative)
                        b.require(relative, expose: name)
                }
            else if js.length > 1
                console.log("dunno how to require because it has multiple js files:", name)
        )
        # TOOD: make this work, it will become more important as we have more npm stuff!!
#        _.each(require("./package.json").dependencies, (v, name) ->
#            ret[name] = {
#                used: false
#                markUsed: ->
#                    ret[name].used = true
#                require: (b) ->
#                    b.require(name)
#            }
#        )
        return ret

    deps = getBowerDeps()

    buildCommonBundle = () ->
        if buildEnv == 'dev'
            commonHash = local_config().common_bundle_hash or 0
            mod = (+fs.statSync("./package.json").mtime) / 1000 + (+fs.statSync("./bower.json").mtime) / 1000
            local_config(common_bundle_hash: mod)
            if mod == commonHash
                console.log("common bundle rebuild not required".green.underline)
                return

        opts =
            fullPaths: FULL_PATHS
            noParse: []
            cache: {}
            packageCache: {}
            paths: ['./app/bower_components', './node_modules']

        requires = []
        _.each(deps, (dep, name) ->
            return if not dep.used
            opts.noParse.push(dep.path)
            requires.push(dep.require)
        )


        b = browserify(opts) #need to call this AFTER expose is called  so that it mutates opts!!

        if buildEnv == 'dev'
            b = browserifyInc(b, cacheFile: './.compiled/browserify_common_cache.json')

        _.each(requires, (r) -> r(b))

        b.require(path.join(__dirname, '.compiled', 'config.js'), expose: 'hn-config')

        b.bundle()
            .pipe(source('./app/common.js'))
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(buffer())
            .pipe($.flatten())
            .pipe(gulp.dest('.compiled/bundle/', {base: '.compiled'}))
            .on('end', ->
                console.log("common bundle finished:".green.underline + filesize('./.compiled/bundle/common.js'))
            )

    bundler = watchify(
        browserify(
            entries: ['./app/app.coffee']
            extensions: ['.coffee']
            paths: ['./app/', './app/bower_components/']
            debug: buildEnv == 'dev'
            cache: {}
            packageCache: {}
            fullPaths: FULL_PATHS
            bundleExternal: true
            filter: (id) ->
                vendorDep = deps[id]
                if vendorDep
                    vendorDep.markUsed()
                    return false #same as adding to 'externals'
                return true
        )
        .transform(partialify.onlyAllow('html'))
        .transform((file) ->
            return through() if not (/\.(scss|css)$/i).test(file)
            # ignore some files for now
            # console.log("remove scss, and css for some reason", file)
            return through((->), ->
                this.queue('')
                this.queue(null)
            )
        )
        .transform((file) ->
            return through() if not (/\.coffee$/i).test(file)
            data = ""
            #TODO: make into a plugin!
            return through((buf) ->
                data += buf
            , ->
                try
                    data = ngClassify(data, ngClassifyOptions)
                    this.queue(data)
                    this.queue(null)
                catch err
                    error = new gutil.PluginError('coffeescript', err)
                    loc = error.location
                    issue = error.code.split("\n")[loc.first_line]
                    before = issue[loc.first_line - 1] or ""
                    after = issue[loc.first_line + 1] or ""
                    before = before + "\n" if before
                    after = "\n" + after if after
                    first = issue.substring(0, loc.first_column)
                    middle = issue.substring(loc.first_column, loc.last_column)
                    last = issue.substring( loc.last_column)
                    console.log("coffeescript! #{error.name}:".red.bold.underline
                        "'#{error.message}' in #{file}"+"@".bold+"#{loc.first_line}:#{loc.first_column}\n"
                        before+first+middle.red.underline+last+after
                    )
            )
        )
        .transform(coffeeify)
        .transform(aliasify,
            aliases: aliases
            verbose: buildEnv == 'dev'
        )
        .transform((file) ->
            return through() if not (/\.coffee|app\/modules|app\/components/i).test(file)
            return browserify_ngannotate(file, {ext: ['.coffee']})
        )
    )
    if buildEnv != 'dev'
        bundler.plugin(require('bundle-collapser/plugin'))


    buildStyles(bundler, watch, './.compiled/bundle/app.css', (err, vendorCss) ->
        fs.writeFileSync("./.compiled/bundle/vendor.css", vendorCss)
        injectBundle(->
            console.log("css bundle finished:".green.underline + filesize('./.compiled/bundle/vendor.css'))
            task_cb()
        )
    )
    _.each(externals, (name) ->
        bundler.external(name)
    )
    rebundle = (firstRun = false) ->
        console.log("gulpfile@812:", firstRun)
        stream = bundler.bundle()
        stream
            .pipe(source('./app/app.js'))
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(buffer())
            .pipe($.flatten())
            .pipe(gulp.dest('.compiled/bundle', {base: '.compiled'}))
            .on('end', ->
                if firstRun
                    buildCommonBundle()
                    injectBundle( ()->
                        console.log("app bundle finished:".green.underline + filesize('./.compiled/bundle/app.js'))
                    )
            )
            .on('error', (err) ->
                console.log(new gutil.PluginError("Browserify", err, showStack: yes).toString())
            )

    rebundle(true)
    bundler.on('update', rebundle)
    return

gulp.task 'bundle', (task_cb) ->
    bundle(true, task_cb)

gulp.task 'bundle:dist', (task_cb) ->
    bundle(false, task_cb)

bower_images = () ->
    return gulp.src(paths.bower_images)
    .pipe(rename( (file) ->
        if file.extname != ''
            file.dirname = "bower_images"
            return file
        else
            return no
    ))

gulp.task "bower_images:dev", ->
    bower_images()
    .pipe(gulp.dest(COMPILE_PATH))

gulp.task "bower_images:dist", ->
    bower_images()
    .pipe(gulp.dest(DIST_PATH))


handler = (err) ->
    console.error(err.message+"  "+err.filename+" line:"+err.location?.first_line)


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
    return gulp.src(paths.images)
#        .pipe(imageop({
#            optimizationLevel: 5
#            progressive: true
#            interlaced: true
#        }))
        .pipe(gulp.dest(DIST_PATH))

createThemedIndex = (from, theme) ->
    data = fs.readFileSync(path.join(from, "index.html"), 'utf8')
    result = data.replace(/(([ \t]*)<!--\s*theme:*(\S*)\s*-->)(\n|\r|.)*?(<!--\s*endtheme\s*-->)/gi, (str, a, b) ->
        return """
<!-- build:css /css/#{theme.filename} -->
<link rel="stylesheet" href="/bundle/#{theme.filename}">
<!-- endbuild -->
"""
    )
    dest = path.join(COMPILE_PATH, theme.index)
    fs.writeFileSync(dest, result)
    return dest


gulp.task "package:themes", ["package:dist"], (cb) ->
    themes = getThemes()

    async.eachSeries(themes, (theme, cb) ->
        src = createThemedIndex(DIST_PATH, theme)
        assets = useref.assets()
        gulp.src(src)
            .pipe(assets)
            .pipe(gulpIf("*.css", minifyCss({
                cache: true
                compatibility: 'colors.opacity' # ie doesnt like rgba values :P
            })))
            .pipe(rev())
            .pipe(assets.restore())
            .pipe(useref())
            .pipe(gulpIf('*.css', rename({ extname: '.min.css' })))
            .pipe(revReplace())
            .pipe(gulpIf('*.css', bless())) # fix ie9 4096 max selector per file evil
            .pipe(gulp.dest(DIST_PATH))
            .on('end', ->
                cb()
            )
    , cb)

gulp.task "package:dist", () ->
    assets = useref.assets()
    return gulp.src(path.join(COMPILE_PATH, "index.html"))
        .pipe(assets)
        .pipe(gulpIf('*.js', sourcemaps.init()))
        .pipe(gulpIf('*.css', minifyCss({
            cache: true
            compatibility: 'colors.opacity' # ie doesnt like rgba values :P
        })))
        .pipe(rev())
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(gulp.dest(DIST_PATH))
        .pipe(gulpIf('*.js', uglify()))
        .pipe(gulpIf('*.js', rename({ extname: '.min.js' })))
        .pipe(gulpIf('*.css', rename({ extname: '.min.css' })))
        .pipe(revReplace())
        .pipe(gulpIf('*.css', bless())) # fix ie9 4096 max selector per file evil
        # We do this to make it easier to snag the actual un-minified source via a browser
        .pipe(gulpIf('*.js', sourcemaps.write('.', {includeContent: false, sourceRoot: '/'})))
        # Cheap trick to fix source map URL
        .pipe(gulpIf('*.js', replace('//# sourceMappingURL=..', '//# sourceMappingURL=')))
        .pipe(gulp.dest(DIST_PATH))

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

    settings = baseConfig(buildEnv, {
        app_version: bwr.version
        bower_versions: versions
        build_date: new Date()
        hash: gitHash
        app_host: config.app_host
        build_env: buildEnv
        raven_dsn: ravenDsn
    })

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
            path: '/HourlyNerd/gulp-build/themes/' + filename,
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
        tasks = []
        remoteCode.replace(/[^\.]require\(["']([\w\d_-]+)["']\)/g, (str, match) ->
            try
                require(match)
            catch e
                tasks.push({cmd: "npm install #{match} --save-dev", match: match})
        )
        exec = require('child_process').exec
        async.eachSeries(tasks, (task, cb) ->
            console.log("npm module '#{task.match}' is missing, installing..")
            exec(task.cmd, (err, stdout) ->
                console.log("couldnt npm install '#{task.match}' because:", err) if err
                cb()
            )
        )
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


    parseUrlParams = (url='', abstract) ->
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

bower_install = (gulpCb) ->
    exec = require('child_process').exec
    path = require('path')
    async = require('async')
    fs = require('fs')
    _ = require('underscore')

    parser = require('optimist')
        .usage('Update or link HN modules from bower')
        .describe('clean', 'install fresh dependencies')
        .describe('link', 'comma separated list of repos to link')
        .describe('fav', "link favorite repos for project. found in config.local.json as 'link_favorites:[]'")
        .describe('h', 'print usage')
        .alias('h', 'help')
        .default('link', '')


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

    repos = args.link.trim().split(',')

    if args.fav
        repos = local_config()?.link_favorites or []

    console.log("Installing bower components...")
    if args.clean
        console.log('Cleaning!')
    if repos.join(', ')
        console.log('Linking: ', repos.join(', '))
    console.log("---------------------------------------------")


    tasks = []
    if args.clean
        tasks.push(task("rm -rf #{path.join(__dirname, 'app', 'bower_components')}", __dirname))
        tasks.push(task("bower cache clean", __dirname))

    tasks.push(task("bower install",  __dirname))

    for r in repos
        continue if r == ''
        dir = path.join(__dirname, '..', r)
        destLink = path.join(__dirname, BOWER_PATH, r)
        if not fs.existsSync(destLink) or destLink == fs.realpathSync(destLink)
            if fs.existsSync(dir)
                tasks.push(task("bower link", dir))
                tasks.push(task("bower link #{r}", __dirname))
            else
                console.log("#{r} does not exist! Did you git clone it? Looked here:", dir)
        else
            console.log("#{dir}> (already linked)")

    async.series(tasks, (err) ->
        console.log("Finished!")
        gulpCb()
    )

gulp.task('bower_install', bower_install)
gulp.task('b', bower_install)

gulp.task "default", (cb) ->
    runSequence(
        #'clean:compiled'
        'bower_images:dev'
        'make_config'
        'copy_extras'
        'webserver'
        'bundle'
        cb)

gulp.task "build", (cb) ->
    runSequence(
        'clean:compiled'
        'clean:dist'
        'images'
        'bower_images:dist'
        'make_config'
        'copy_extras'
        'bundle:dist'
        'package:themes'
        cb)


if fs.existsSync('./custom_gulp_tasks.coffee')
    require('./custom_gulp_tasks.coffee')(gulp)
