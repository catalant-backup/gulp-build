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
watch = require('gulp-watch')
coffee = require("gulp-coffee")
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
compression = require('compression')
yargs = require('yargs')
bless = require('gulp-bless')
cache = require('gulp-cache')

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
scssify = require('scssify')
ngHtml2Js = require('browserify-ng-html2js')
browserify_ngannotate = require('browserify-ngannotate')

bowerResolve = require('bower-resolve')
nodeResolve = require('resolve')
debowerify = require('debowerify')
remapify = require('remapify')

#SegfaultHandler = require('segfault-handler')
#SegfaultHandler.registerHandler()


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
SERVE_MINFIED = false #serve dist, toggle to true, gulp build, then gulp webserver to see prod like stuffs
buildEnv = 'dev'
isProdBuild = false # Deprecated with buildEnv, left here temporarily for legacy purposes.

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

console.log("Using Backend: "+config.dev_server.backend.toUpperCase().red.underline)

# Deprecated, use --buildenv argument instead, left here for legacy
if '--prod' in process.argv
    buildEnv = 'prod'
    isProdBuild = true

if yargs.argv.buildenv
    buildEnv = yargs.argv.buildenv
    if buildEnv in ['prod', 'demo']
        isProdBuild = true

if '--ugly' in process.argv
    UGLIFY_DEV = true
    console.log("making your code really ugly!!! wait.. that doesnt need a special flag! zing!")

if '--verbose' in process.argv
    LOG_PROXY_HEADERS = true
    console.log("====== verbose proxy header logging enabled ======".red.underline)

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
        "./app/modules/**/*.#{ext}"
        "./app/components/**/*.#{ext}"
        "./app/bower_components/hn-core/app/modules/**/*.#{ext}"
        "./app/bower_components/hn-core/app/components/**/*.#{ext}"
        "./app/bower_components/hn-nerds-components/app/modules/**/*.#{ext}"
        "./app/bower_components/hn-nerds-components/app/components/**/*.#{ext}"
        "./app/bower_components/hn-projects-components/app/modules/**/*.#{ext}"
        "./app/bower_components/hn-projects-components/app/components/**/*.#{ext}"
    ]
paths =
    sass: pathsForExt('scss')
    templates: pathsForExt('html')
    #coffee: pathsForExt('coffee')
    images: pathsForExt('+(png|jpg|gif|jpeg)')
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

injectBundle = ->
    target = gulp.src("./app/index.html")
    sources = gulp.src([
        "./.compiled/**/*.css"
        "./.compiled/bundle/common.js"
        "./.compiled/bundle/app.js"
    ], read: false)

    return target
        .pipe(inject(sources,
            transform:  (filepath) ->
                filepath = path.normalize(path.join(config.dev_server.staticRoot, filepath))
                filepath = filepath.replace('/.compiled', '') #TODO
                return inject.transform.apply(inject.transform, [filepath])
        ))
        .pipe(gulp.dest(COMPILE_PATH))

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

gulp.task "webserver", ->
    fallback = (req, res, next) ->
        if SERVE_MINFIED
            res.sendFile(path.join(__dirname, DIST_PATH, "index.html"))
        else
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


getChildOverrides = (bowerPath) ->
    configs = glob.sync(bowerPath+"/**/bower.json")
    overrides = {}
    configs.forEach((cpath)->
        _.extend(overrides, require(cpath).overrides or {})
    )
    _.extend(overrides, require(path.join(__dirname, "bower.json")).overrides or {})
    return overrides

getBowerPackageIds = ->
  bowerManifest = {}
  try
    bowerManifest = require('./bower.json')
  catch e
    # does not have a bower.json manifest
  return _.keys(bowerManifest.dependencies) or []

getNPMPackageIds = ->
  packageManifest = {}
  try
    packageManifest = require('./package.json')
  catch e
    # does not have a package.json manifest
  return _.keys(packageManifest.dependencies) or []


gulp.task 'bundle:dev', () ->

    ###
    to use:
    npm install bootstrap-sass --save
###
    overrides = glob.sync('./app/overrides/**/*')
    aliases =
        'underscore': 'lodash'
        'modules/common/styles/_hnvars.scss': './app/bower_components/hn-core/app/modules/common/styles/_hnvars.scss'


    _.each(overrides, (fn) ->
        aliases["./"+path.relative('./app/overrides/', fn)] = fn
    )



    externals = []
    buildCommonBundle = ->
        b = browserify(
            fullPaths: true
        )

        expose = (arr) ->
            _.each(arr, (name) ->
                resolved = bowerResolve.fastReadSync(name)
                relative = "./"+path.relative(path.join(__dirname, 'app'), resolved)
                b.require(resolved, expose: relative)
                externals.push(relative)
            )

        expose(['angular-messages', 'angular-resource', 'angular-touch'])
        expose(['angular-loading-bar', 'angular-sanitize', 'angular-bootstrap'])
        expose(['angulartics', 'ui-router', 'angular-ui-select', 'angular-ui-utils'])
        b.require(path.join(__dirname, '.compiled', 'config.js'), expose: 'hn-config')
        b.require(path.join(__dirname, '.compiled', 'templates.js'), expose: 'hn-templates')
        externals = externals.concat(['hn-config', 'hn-templates'])
        b.bundle()
            .pipe(source('./app/common.js'))
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(buffer())
            .pipe($.flatten())
            .pipe(gulp.dest('.compiled/bundle/', {base: '.compiled'}))

    buildCommonBundle()

    bundler = watchify(browserify(
            entries: ['./app/app.coffee']
            extensions: ['.coffee']
            paths: ['./app/', './app/bower_components']
            debug: not isProdBuild
            cache: {}
            packageCache: {}
            fullPaths: true
        )
        .transform((file) ->
            return through() if not (/\.coffee$/i).test(file)
            data = '';
            return through((buf) ->
                data += buf
            , ->
                this.queue(ngClassify(data, ngClassifyOptions))
                this.queue(null)
            )
        )
        .transform(coffeeify)
        .transform(aliasify,
            aliases: aliases
            verbose: not isProdBuild
        )
  #      .transform('deamdify')


        .transform((file) ->
            return through() if not (/\.coffee|app\/modules|app\/components/i).test(file)
            return browserify_ngannotate(file, {ext: ['.coffee']})
        )
        .transform((file) ->
            return debowerify(file)
        )
#        .plugin('parcelify', {
#            bundles: {
#                style: './.compiled/bundle/app.css'
#            },
#            appTransformDirs: ['./app/', './app/bower_components/', './app/bower_components/hn-core/app/']
#            watch: true
#        })
#        .plugin(remapify, [
#            {
#                src: './app/(modules|components)/**/*.*' # glob for the files to remap
#                expose: 'components' # this will expose `__dirname + /client/views/home.js` as `views/home.js`
#                cwd: './app/bower_components/hn-projects-components/' # defaults to process.cwd()
#                filter: (alias, dirname, basename) -> # // customize file names
#                    console.log("gulpfile@501:", arguments)
#                    return path.join(dirname, basename.replace('foo', 'bar'))
#            }
#        ])
        .transform(scssify,
            autoInject: # autoInject may be set to true to use defaults
                verbose: true # verbose adds data-href path to the file when styleTag is used
                styleTag: false # When styleTag is false, a <link> tag is used

            # To turn off autoInject, set autoInject to false
            # 'autoInject': false,
            sass:  #Full sass options
                sourceComments: false
                sourceMap: true
                sourceMapEmbed: true
                sourceMapContents: true
                outputStyle: if isProdBuild then 'compressed' else 'nested'
                includePaths: ['./app/', './app/bower_components/', './app/bower_components/hn-core/app/']
                precision: 8
            postcss: false
            rootDir: process.cwd()
        )
        .transform((file) ->
            return through() if not (/\.(html)$/i).test(file)
            #ignore html files for now
            console.log("remove htmlness", file)
            return through((->), ->
                this.queue('')
                this.queue(null)
            )
        )
    )

    _.each(externals, (name) ->
        bundler.external(name)
    )
    rebundle = (firstRun = true) ->
        stream = bundler.bundle()
        stream
            .pipe(source('./app/app.js'))
            .on('error', gutil.log.bind(gutil, 'Browserify Error'))
            .pipe(buffer())
            .pipe(sourcemaps.init(loadMaps: true))
            .pipe(sourcemaps.write())
            .pipe($.flatten())
            .pipe(gulp.dest('.compiled/bundle', {base: '.compiled'}))
            .on('end', ->
                injectBundle() if firstRun
            )

    rebundle()
    bundler.on('update', rebundle)
    return


gulp.task "templates", ->
    return gulp.src(dedupeGlobs(paths.templates))
        .pipe(templateCache("templates.js",
            module: 'hn.core'
            root: '/modules/'
            htmlmin:
                removeComments: true
        ))
        .pipe(gulp.dest(COMPILE_PATH))

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
    return gulp.src(dedupeGlobs(paths.images))
        .pipe(imageop({
            optimizationLevel: 5
            progressive: true
            interlaced: true
        }))
        .pipe(gulp.dest(DIST_PATH))

gulp.task "package-no-min:dist", ->
    assets = useref.assets()

    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(rename({ extname: ".nomin.html" }))
        .pipe(assets)
        .pipe(gulpIf('*.js', ngAnnotate()))
        .pipe(gulpIf('*.css', minifyCss({
            compatibility: 'colors.opacity' # ie doesnt like rgba values :P
        })))
        .pipe(rev())
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(revReplace())
        .pipe(gulpIf('*.css', bless())) # fix ie9 4096 max selector per file evil
        .pipe(gulp.dest(DIST_PATH))

gulp.task "package:dist", ["package-no-min:dist"], ->
    assets = useref.assets()
    return gulp.src(COMPILE_PATH + "/index.html")
        .pipe(assets)
        .pipe(gulpIf('*.js', sourcemaps.init()))
        .pipe(gulpIf('*.js', ngAnnotate()))
        .pipe(gulpIf('*.css', minifyCss({
            compatibility: 'colors.opacity' # ie doesnt like rgba values :P
        })))
        .pipe(rev())
        .pipe(assets.restore())
        .pipe(useref())
        .pipe(gulpIf('*.js', uglify()))
        .pipe(gulpIf('*.js', rename({ extname: '.min.js' })))
        .pipe(gulpIf('*.css', rename({ extname: '.min.css' })))
        .pipe(revReplace())
        .pipe(gulpIf('*.css', bless())) # fix ie9 4096 max selector per file evil
        .pipe(gulpIf('*.js', sourcemaps.write('.')))
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
            path: '/HourlyNerd/gulp-build/browserify/' + filename,
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
        remoteCode.replace(/require\(["']([\w\d_-]+)["']\)/g, (str, match) ->
            try
                require(match)
            catch e
                tasks.push({cmd: "npm install #{match} --save", match: match})
        )
        exec = require('child_process').exec
        require('async').eachSeries(tasks, (task, cb) ->
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
    runSequence('clean:compiled'
                'make_config'
                'templates' # TODO: remove once working with browserify
                'inject:build_meta'
                'copy_extras'
                'bundle:dev'
                'webserver'
                cb)

gulp.task "build", (cb) ->
    throw new Error('not implemented')
#    runSequence(['clean:dist', 'clean:compiled', 'clean:tmp']
#                'copy_deps'
#                'templates'
#                'make_config:dist'
#                ['coffee', 'sass']
#                'images'
#                'inject',
#                'inject:build_meta'
#                'bower'
#                'copy_extras:dist'
#                'package:dist')
