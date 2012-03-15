# Vadim Ogievetsky

# DVL is a framework for building highly interactive user interfaces and data visualizations dynamically with JavaScript.
# DVL is based the concept that the data in a program should be the programmer’s main focus.


`
function lift(fn) {
  var fn = arguments[0];
  if ('function' !== typeof fn) throw new TypeError();

  return function(/* args: to fn */) {
    var args = Array.prototype.slice.call(arguments),
        n = args.length,
        i;

    for (i = 0; i < n; i++) {
      if ('function' === typeof args[i]) {
        return function(/* args2 to function wrapper */) {
          var args2 = Array.prototype.slice.call(arguments),
              reduced = [],
              i, v;

          for (i = 0; i < n; i++) {
            v = args[i];
            reduced.push('function' === typeof v ? v.apply(this, args2) : v);
          }

          return fn.apply(null, reduced);
        };
      }
    }

    // Fell through so there are no functions in the arguments to fn -> call it!
    return fn.apply(null, args);
  };
}
`

Array::filter ?= (fun, thisp) ->
  throw new TypeError() if typeof fun isnt 'function'

  res = new Array()
  for val in this
    res.push val if fun.call(thisp, val, i, this)

  return res


debug = ->
  return unless console?.log
  console.log.apply(console, arguments)
  return arguments[0]


dvl = { version: '1.0.0' }
this.dvl = dvl
if typeof module isnt 'undefined' and module.exports
  module.exports = dvl
  dvl.dvl = dvl


do ->
  array_ctor = (new Array).constructor
  date_ctor  = (new Date).constructor
  regex_ctor = (new RegExp).constructor
  dvl.typeOf = (v) ->
    if typeof(v) is 'object'
      return 'null'  if v == null
      return 'array' if v.constructor == array_ctor
      return 'date'  if v.constructor == date_ctor
      return 'object'
    else
      return 'regex' if v?.constructor == regex_ctor
      return typeof(v)


dvl.util = {
  strObj: (obj) ->
    type = dvl.typeOf(obj)
    if type in ['object', 'array']
      str = []
      keys = []
      keys.push k for k of obj
      keys.sort()
      str.push k, dvl.util.strObj(obj[k]) for k in keys
      return str.join('|')

    if type is 'function'
      return '&'

    return String(obj)


  uniq: (array) ->
    seen = {}
    uniq = []
    for a in array
      uniq.push a unless seen[a]
      seen[a] = 1

    return uniq


  flip: (array) ->
    map = {};
    i = 0;
    while i < array.length
      map[array[i]] = i
      i++

    return map


  getMinMax: (input, acc) ->
    acc = ((x) -> x) unless acc
    min = +Infinity
    max = -Infinity
    minIdx = -1
    maxIdx = -1

    for d,i in input
      v = acc(d)
      if v < min
        min = v
        minIdx = i
      if max < v
        max = v
        maxIdx = i

    return { min, max, minIdx, maxIdx }


  crossDomainPost: (url, params) ->
    frame = d3.select('body').append('iframe').style('display', 'none')

    clean = (d) -> d.replace(/'/g, "\\'")
    inputs = []
    inputs.push "<input name='#{k}' value='#{clean(v)}'/>" for k,v of params

    post_process = frame.node().contentWindow.document
    post_process.open()
    post_process.write "<form method='POST' action='#{url}'>#{inputs.join('')}</form>"
    post_process.write "<script>window.onload=function(){document.forms[0].submit();}</script>"
    post_process.close()
    setTimeout(frame.remove, 800)
    return;

  isEqual: (a, b, cmp) ->
    # Check object identity.
    return true if a is b
    # Different types?
    atype = dvl.typeOf(a)
    btype = dvl.typeOf(b)
    return false if atype isnt btype
    # One is falsy and the other truthy.
    return false if (not a and b) or (a and not b)
    # Check dates' integer values.
    return a.getTime() is b.getTime() if atype is 'date'
    # Both are NaN?
    return false if a isnt a and b isnt b
    # and Compare regular expressions.
    return a.source is b.source and a.global is b.global and a.ignoreCase is b.ignoreCase and a.multiline is b.multiline if atype is 'regex'
    # If a is not an object by this point, we can't handle it.
    return false unless atype is 'object' or atype is 'array'
    # Check if already compared
    if cmp
      for c in cmp
        return true if (c.a is a and c.b is b) or (c.a is b and c.b is a)
    # Check for different array lengths before comparing contents.
    return false if a.length? and a.length isnt b.length
    # Nothing else worked, deep compare the contents.
    aKeys = []
    aKeys.push k for k of a
    bKeys = []
    bKeys.push k for k of b
    # Different object sizes?
    return false if aKeys.length isnt bKeys.length
    # Recursive comparison of contents.
    cmp = if cmp then cmp.slice() else []
    cmp.push {a,b}
    for k of a
      return false unless b[k]? and dvl.util.isEqual(a[k], b[k], cmp)

    return true

  clone: (obj) ->
    t = dvl.typeOf(obj)
    switch t
      when 'array'
        return obj.slice()
      when 'object'
        ret = {}
        ret[k] = v for k,v of obj
        return ret
      when 'date'
        return new Date(obj.getTime())
      else
        return obj

  escapeHTML: (str) ->
    return str.replace(/&/g,'&amp;').replace(/>/g,'&gt;').replace(/</g,'&lt;').replace(/"/g,'&quot;')
}

(->
  nextObjId = 1
  constants = {}
  variables = {}
  curRecording = null

  class DVLConst
    constructor: (val) ->
      @value = val ? null
      @id = nextObjId
      @changed = false
      constants[@id] = this
      nextObjId += 1
      return this

    toString: ->
      tag = if @n then @n + ':' else ''
      return "[#{@tag}#{@value}]"
    set: -> this
    setLazy: -> this
    update: -> this
    get: -> @value
    getPrev: -> @value
    hasChanged: -> @changed
    resetChanged: -> null
    notify: -> null
    remove: -> null
    gen: ->
      that = this
      if dvl.typeOf(@value) == 'array'
        (i) -> that.value[i]
      else
        () -> that.value
    genPrev: (i) -> @gen(i)
    len: ->
      if dvl.typeOf(@value) == 'array'
        @value.length
      else
        Infinity
    name: ->
      if arguments.length is 0
        return @n ? '<anon_const>'
      else
        @n = arguments[0]
        return this


  dvl.const = (value) -> new DVLConst(value)

  class DVLDef
    constructor: (val) ->
      @value = val ? null
      @id = nextObjId
      @prev = null
      @changed = false
      @vgen = undefined
      @vgenPrev = undefined
      @vlen = -1
      @lazy = null
      @listeners = []
      @changers = []
      variables[@id] = this
      nextObjId++
      if curRecording
        curRecording.vars.push this
      return this

    resolveLazy: ->
      if @lazy
        val = @lazy()
        @prev = val
        @value = val
        @lazy = null
      return

    toString: ->
      tag = if @n then @n + ':' else ''
      return "[#{@tag}#{@value}]"
    hasChanged: -> @changed
    resetChanged: ->
      @changed = false
      return this
    set: (val) ->
      val = val ? null
      @prev = @value unless @changed
      @value = val
      @vgen = undefined
      @changed = true
      @lazy = null
      return this
    setLazy: (fn) ->
      @lazy = fn
      @changed = true
      return this
    setGen: (g, l) ->
      if g is null
        l = 0
      else
        l = Infinity if l is undefined
      @vgenPrev = @vgen unless @changed
      @vgen = g
      @vlen = l
      @changed = true
      return this
    update: (val) ->
      return if dvl.util.isEqual(val, @value)
      this.set(val)
      dvl.notify(this)
    get: ->
      @resolveLazy()
      return @value
    getPrev: ->
      @resolveLazy()
      if @prev and @changed then @prev else @value
    gen: ->
      if @vgen != undefined
        return @vgen
      else
        that = this
        if dvl.typeOf(@value) == 'array'
          return ((i) -> that.value[i])
        else
          return (-> that.value)
    genPrev: ->
      if @vgenPrev and @changed then @vgenPrev else @gen()
    len: ->
      if @vlen >= 0
        return @vlen
      else
        if @value?
          return if dvl.typeOf(@value) == 'array' then @value.length else Infinity
        else
          return 0
    notify: ->
      dvl.notify(this)
    remove: ->
      if @listeners.length > 0
        throw "Cannot remove variable #{@id} because it has listeners."
      if @changers.length > 0
        throw "Cannot remove variable #{@id} because it has changers."
      delete variables[@id]
      return null
    name: ->
      if arguments.length is 0
        return @n ? '<anon>'
      else
        @n = arguments[0]
        return this

  dvl.def = (value) -> new DVLDef(value)

  dvl.knows = (v) ->
    return v and v.id and (variables[v.id] or constants[v.id])

  dvl.wrapConstIfNeeded = (v, name) ->
    v = null if v is undefined
    if dvl.knows(v) then v else dvl.const(v).name(name)

  dvl.wrapVarIfNeeded = (v, name) ->
    v = null if v is undefined
    if dvl.knows(v) then v else dvl.def(v).name(name)

  dvl.valueOf = (v) ->
    if dvl.knows(v)
      return v.get()
    else
      return v ? null

  registerers = {}

  # filter out undefineds and nulls and constants also make unique
  uniqById = (vs, allowConst) ->
    res = []
    if vs
      seen = {}
      for v in vs
        if v? and (allowConst or (v.listeners and v.changers)) and not seen[v.id]
          seen[v.id] = true
          res.push v
    return res


  checkForCycle = (fo) ->
    stack = fo.depends.slice()
    visited = {}

    while stack.length > 0
      v = stack.pop()
      visited[v.id] = true

      for w in v.depends
        throw "circular dependancy detected around #{w.id}" if w is fo
        stack.push w if not visited[w.id]

    return


  bfsUpdate = (stack) ->
    while stack.length > 0
      v = stack.pop()
      nextLevel = v.level+1

      for w in v.depends
        if w.level < nextLevel
          w.level = nextLevel
          stack.push w

    return


  bfsZero = (queue) ->
    while queue.length > 0
      v = queue.shift()
      for w in v.depends
        w.level = 0
        queue.push w

    return


  class DVLFunctionObject
    constructor: (@id, @name, @ctx, @fn, @listen, @change) ->
      @depends = []
      @level = 0
      if curRecording
        curRecording.fns.push this
      return this

    addChange: ->
      uv = uniqById(arguments)

      if uv.length
        for v in uv
          @change.push(v)
          v.changers.push(this)
          for l in v.listeners
            l.depends.push(this)
            @level = Math.max(@level, l.level+1)

        checkForCycle(this)
        bfsUpdate([this])

      return this

    addListen: ->
      uv = uniqById(arguments)

      if uv.length
        for v in uv
          @listen.push(v)
          v.listeners.push(this)
          for c in v.changers
            @depends.push(c)

        checkForCycle(this)
        bfsUpdate([this])

      uv = uniqById(arguments, true)
      start_notify_collect(this)
      changedSave = []
      for v in uv
        changedSave.push(v.changed)
        v.changed = true
      @fn.apply(@ctx)
      for v,i in uv
        v.changed = changedSave[i]
      end_notify_collect()
      return this

    remove: ->
      # Find the register object
      delete registerers[@id]

      bfsZero([this])

      queue = []
      for cv in @change
        for lf in cv.listeners
          queue.push lf
          lf.depends.splice(lf.depends.indexOf(this), 1)

      for v in @change
        v.changers.splice(v.changers.indexOf(this), 1)

      for v in @listen
        v.listeners.splice(v.listeners.indexOf(this), 1)

      # I think this houldbe queue [ToDo]
      bfsUpdate(@depends) # do not care if @update gets trashed
      @change = @listen = @depends = null # cause an error if we hit these
      return


  dvl.register = ({ctx, fn, listen, change, name, force, noRun}) ->
    throw 'cannot call register from within a notify' if curNotifyListener
    throw 'fn must be a function' if typeof(fn) != 'function'

    listen = [listen] unless dvl.typeOf(listen) is 'array'
    change = [change] unless dvl.typeOf(change) is 'array'

    listenConst = []
    if listen
      for v in listen
        listenConst.push v if v?.id and constants[v.id]
    listen = uniqById(listen)
    change = uniqById(change)

    if listen.length isnt 0 or change.length isnt 0 or force
      # Make function/context holder object; set level to 0
      id = ++nextObjId
      fo = new DVLFunctionObject(id, (name or 'fn'), ctx, fn, listen, change)

      # Append listen and change to variables
      for v in listen
        throw "No such DVL variable #{id} in listeners" unless v
        v.listeners.push fo

      for v in change
        throw "No such DVL variable #{id} in changers" unless v
        v.changers.push fo

      # Update dependancy graph
      for cv in change
        for lf in cv.listeners
          lf.depends.push fo
          fo.level = Math.max(fo.level, lf.level+1)

      for lv in listen
        for cf in lv.changers
          fo.depends.push cf

      registerers[id] = fo
      checkForCycle(fo)
      bfsUpdate([fo])

    if not noRun
      # Save changes and run the function with everythign as changed.
      changedSave = []
      for l,i in listen
        changedSave[i] = l.changed
        l.changed = true
      for l in listenConst
        l.changed = true

      start_notify_collect(fo)
      fn.apply ctx
      end_notify_collect()

      for c,i in changedSave
        listen[i].changed = c
      for l in listenConst
        l.changed = false

    return fo


  dvl.clearAll = ->
    # disolve the graph to make the garbage collection job as easy as possibe
    for k, l of registerers
      l.listen = l.change = l.depends = null

    for k, v of variables
      v.listeners = v.changers = null

    # reset everything
    nextObjId = 1
    constants = {}
    variables = {}
    registerers = {}
    return


  levelPriorityQueue = do ->
    queue = []
    sorted = true

    compare = (a, b) ->
      levelDiff = a.level - b.level
      return if levelDiff is 0 then b.id - a.id else levelDiff

    return {
      push: (l) ->
        queue.push l
        sorted = false
        return

      shift: ->
        if not sorted
          queue.sort(compare)
          sorted = true
        return queue.pop()

      length: ->
        return queue.length
    }

  curNotifyListener = null
  curCollectListener = null
  changedInNotify = null
  lastNotifyRun = null
  toNotify = null


  start_notify_collect = (listener) ->
    toNotify = []
    curCollectListener = listener
    dvl.notify = collect_notify
    return


  end_notify_collect = ->
    curCollectListener = null
    dvl.notify = init_notify # ToDo: possible nested notify?

    dvl.notify.apply(null, toNotify)
    toNotify = null
    return


  collect_notify = ->
    throw 'bad stuff happened collect' unless curCollectListener

    for v in arguments
      continue unless variables[v.id]
      throw "changed unregisterd object #{v.id}" if v not in curCollectListener.change
      toNotify.push v

    return


  within_notify = ->
    throw 'bad stuff happened within' unless curNotifyListener

    for v in arguments
      continue unless variables[v.id]
      throw "changed unregisterd object #{v.id}" if v not in curNotifyListener.change
      changedInNotify.push v
      lastNotifyRun.push v.id
      for l in v.listeners
        if not l.visited
          levelPriorityQueue.push l

    return


  init_notify = ->
    throw 'bad stuff happened init' if curNotifyListener

    lastNotifyRun = []
    visitedListener = []
    changedInNotify = []

    for v in arguments
      continue unless variables[v.id]
      changedInNotify.push v
      lastNotifyRun.push v.id
      levelPriorityQueue.push l for l in v.listeners

    dvl.notify = within_notify

    # Handle events in a BFS way
    while levelPriorityQueue.length() > 0
      curNotifyListener = levelPriorityQueue.shift()
      continue if curNotifyListener.visited
      curNotifyListener.visited = true
      visitedListener.push(curNotifyListener)
      lastNotifyRun.push(curNotifyListener.id)
      curNotifyListener.fn.apply(curNotifyListener.ctx)

    curNotifyListener = null
    dvl.notify = init_notify
    v.resetChanged() for v in changedInNotify
    l.visited = false for l in visitedListener # reset visited
    return


  dvl.notify = init_notify

  dvl.startRecording = ->
    throw "already recording" if curRecording
    curRecording = { fns: [], vars: [] }

  dvl.stopRecording = ->
    throw "not recording" unless curRecording
    rec = curRecording
    curRecording = null
    rec.remove = ->
      f.remove() for f in rec.fns
      v.remove() for v in rec.vars
      return

    return rec

  ######################################################
  ##
  ##  Renders the variable graph into dot
  ##
  dvl.graphToDot = (lastTrace, showId) ->
    execOrder = {}
    if lastTrace and lastNotifyRun
      for pos, id of lastNotifyRun
        execOrder[id] = pos

    nameMap = {}

    for k, l of registerers
      fnName = l.id.replace(/\n/g, '')
      #fnName = fnName.replace(/_\d+/, '') unless showId
      fnName = fnName + ' (' + l.level + ')'
      # fnName += ' [[' + execOrder[l.id] + ']]' if execOrder[l.id]
      fnName = '"' + fnName + '"'
      nameMap[l.id] = fnName

    for id,v of variables
      varName = id.replace(/\n/g, '')
      #varName = varName.replace(/_\d+/, '') unless showId
      # varName += ' [[' + execOrder[id] + ']]' if execOrder[id]
      varName = '"' + varName + '"'
      nameMap[id] = varName

    dot = []
    dot.push 'digraph G {'
    dot.push '  rankdir=LR;'

    levels = []
    for id,v of variables
      color = if execOrder[id] then 'red' else 'black'
      dot.push "  #{nameMap[id]} [color=#{color}];"

    for k, l of registerers
      levels[l.level] or= []
      levels[l.level].push nameMap[l.id]
      color = if execOrder[l.id] then 'red' else 'black'

      dot.push "  #{nameMap[l.id]} [shape=box,color=#{color}];"
      for v in l.listen
        color = if execOrder[v.id] and execOrder[l.id] then 'red' else 'black'
        dot.push "  #{nameMap[v.id]} -> #{nameMap[l.id]} [color=#{color}];"
      for w in l.change
        color = if execOrder[l.id] and execOrder[w.id] then 'red' else 'black'
        dot.push "  #{nameMap[l.id]} -> #{nameMap[w.id]} [color=#{color}];"

    for level in levels
      dot.push('{ rank = same; ' + level.join('; ') + '; }')

    dot.push '}'
    return dot.join('\n')

  dvl.postGraph = (file, showId) ->
    file or= 'dvl_graph'
    g = dvl.graphToDot(false, showId)
    dvl.util.crossDomainPost('http://localhost:8124/' + file, { graph: JSON.stringify(g) })
    return

  dvl.postLatest = (file, showId) ->
    file or= 'dvl_graph_latest'
    g = dvl.graphToDot(true, showId)
    dvl.util.crossDomainPost('http://localhost:8124/' + file, { graph: JSON.stringify(g) })
    return

)()

dvl.alwaysLazy = (v, fn) ->
  return ->
    v.setLazy(fn)
    dvl.notify(v)

dvl.zero = dvl.const(0).name('zero')

dvl.null = dvl.const(null).name('null')

dvl.ident = (x) -> x
dvl.identity = dvl.const(dvl.ident).name('identity')


dvl.acc = (column) ->
  column = dvl.wrapConstIfNeeded(column);
  acc = dvl.def().name("acc")

  makeAcc = ->
    col = column.get();
    if col?
      acc.set((d) -> d[col])
    else
      acc.set(null)

    dvl.notify(acc)

  dvl.register({fn:makeAcc, listen:[column], change:[acc], name:'make_acc'})
  return acc


# Workers # -----------------------------------------

######################################################
##
##  A DVL object debugger
##
##  Displays the object value with a message whenever the object changes.
##
dvl.debug = () ->
  genStr = (o) -> if o?.vgen then "[gen:#{o.len()}]" else ''

  if arguments.length == 1
    obj = dvl.wrapConstIfNeeded(arguments[0])
    note = obj.name + ':'
  else
    note = arguments[0]
    obj = dvl.wrapConstIfNeeded(arguments[1])

  dbgPrint = ->
    debug note, obj.get(), genStr(obj)

  dvl.register({fn:dbgPrint, listen:[obj], name:'debug'})
  return obj


######################################################
##
##  Sets up a pipline stage that automaticaly applies the given function.
##
dvl.apply = ->
  switch arguments.length
    when 1
      [{fn, args, out, name, invalid, allowNull, update}] = arguments
    when 2
      [args, fn] = arguments
    when 3
      [args, {out, name, invalid, allowNull, update}, fn] = arguments
    else
      throw "incorect number of arguments"

  fn = dvl.wrapConstIfNeeded(fn or dvl.identity)
  args = [args] unless dvl.typeOf(args) is 'array'
  args = args.map(dvl.wrapConstIfNeeded)
  invalid = dvl.wrapConstIfNeeded(invalid ? null)

  out = dvl.wrapVarIfNeeded(out ? invalid.get(), name or 'apply_out')

  dvl.register {
    name: (name or 'apply')+'_fn'
    listen: args.concat([fn, invalid])
    change: [out]
    fn: ->
      f = fn.get()
      return unless f?
      send = []
      nulls = false
      for a in args
        v = a.get()
        nulls = true unless v?
        send.push v

      if not nulls or allowNull
        r = f.apply(null, send)
        return if r is undefined
      else
        r = invalid.get()

      if update
        out.update(r)
      else
        out.set(r).notify()
  }
  return out


dvl.random = (options) ->
  min = options.min or 0
  max = options.max or min + 10
  int = options.integer
  walk = options.walk

  random = dvl.def((max - min)/2, options.name or 'random')

  gen = ->
    if walk and walk > 0
      # do a random walk
      scale = walk * Math.abs(max - min)
      r = random.get() + scale*(2*Math.random()-1)
      r = min if r < min
      r = max if max < r
    else
      r = Math.random()*(max-min) + min

    r = Math.floor(r) if int
    random.set(r)
    dvl.notify(random)

  setInterval(gen, options.interval) if options.interval
  gen()
  return random


dvl.arrayTick = (data, options) ->
  throw 'dvl.arrayTick: no data' unless data
  data = dvl.wrapConstIfNeeded(data)

  point = options.start or 0
  move = options.move or 1

  out = dvl.def(null, 'array_tick_data')

  gen = ->
    d = data.get()
    len = d.length
    if len > 0
      v = d[point % len]
      point = (point + move) % len
      out.set(v)
      dvl.notify(out)

  setInterval(gen, options.interval) if options.interval
  gen()
  return out


dvl.recorder = (options) ->
  array = dvl.wrapVarIfNeeded(options.array or [], options.name or 'recorder_array')

  data = options.data
  fn = dvl.wrapConstIfNeeded(options.fn or dvl.identity)
  throw 'it does not make sense not to have data' unless dvl.knows(data)

  max = dvl.wrapConstIfNeeded(options.max or +Infinity)
  i = 0

  record = ->
    d = fn.get()(data.get())
    m = max.get()
    if d?
      if options.value
         o = {}
         o[options.value] = d
         d = o
      d[options.index] = i if options.index
      d[options.timestamp] = new Date() if options.timestamp
      _array = array.get()
      _array.push(d)
      _array.shift() while m < _array.length
      array.set(_array).notify()
      i += 1

  dvl.register({fn:record, listen:[data], change:[array], name:'recorder'})
  return array


##-------------------------------------------------------
##
##  Asynchronous ajax fetcher.
##
##  Fetches ajax data form the server at the given url.
##  This function addes the given url to the global json getter,
##  the getter then automaticly groups requests that come from the same event cycle.
##
## ~url:  the url to fetch.
## ~data: data to send
##  type: the type of the request. [json]
##  map:  a map to apply to the recived array.
##  fn:   a function to apply to the recived input.
##
(->
  outstanding = dvl.def(0, 'json_outstanding')
  ajaxManagers = []
  normalRequester = null

  makeManager = ->
    nextQueryId = 0
    initQueue = []
    queries = {}

    maybeDone = (request) ->
      for q in request
        return if q.status isnt 'ready'

      notify = []
      for q in request
        if q.hasOwnProperty('resVal')
          q.res.set(q.resVal ? null)
          notify.push(q.res)
          q.status = ''
          delete q.resVal

      dvl.notify.apply(null, notify)

    getData = (err, resVal) ->
      q = this.q
      if @url is q.url.get() and (@method is 'GET' or (@data is q.data.get() and @dataFn is q.dataFn.get()))
        if err
          q.resVal = null
          q.onError(err) if q.onError
        else
          q.resVal = if @url then resVal else null

      q.status = 'ready'
      q.curAjax = null

      maybeDone(this.request)

    makeRequest = (q, request) ->
      _url = q.url.get()
      _data = q.data.get()
      _dataFn = q.dataFn.get()
      _method = q.method.get()
      _dataType = q.type.get()
      ctx = {
        q
        request
        url:    _url
        data:   _data
        dataFn: _dataFn
        method: _method
      }
      q.curAjax.abort() if q.curAjax
      if _url? and (_method is 'GET' or (_data? and _dataFn?)) and _dataType
        if q.invalidOnLoad.get()
          q.res.update(null)

        q.curAjax = q.requester.request {
          url: _url
          data: _data
          dataFn: _dataFn
          method: _method
          dataType: _dataType
          contentType: q.contentType.get()
          processData: q.processData.get()
          fn: q.fn
          outstanding
          complete: (err, data) -> getData.call(ctx, err, data)
        }

      else
        getData.call(ctx, null, null)

    inputChange = ->
      bundle = []
      for id, q of queries
        continue unless q.url.hasChanged() or q.data.hasChanged() or q.dataFn.hasChanged()

        if q.status is 'virgin'
          if q.url.get()
            initQueue.push q
            q.status = 'requesting'
            makeRequest(q, initQueue)
          else
            q.status = ''
        else
          bundle.push(q)

      if bundle.length > 0
        q.status = 'requesting' for q in bundle
        makeRequest(q, bundle)  for q in bundle

      return

    fo = null
    addHoock = (url, data, dataFn, ret) ->
      if fo
        fo.addListen(url, data, dataFn)
        fo.addChange(ret)
      else
        fo = dvl.register {
          name:   'ajax_man'
          listen: [url, data]
          change: [ret, outstanding]
          fn:     inputChange
          force:  true
        }

      return


    return (url, data, dataFn, method, type, contentType, processData, fn, invalidOnLoad, onError, requester, name) ->
      nextQueryId++
      res = dvl.def(null, name)
      q = {
        id: nextQueryId
        url
        data
        dataFn
        method
        contentType
        processData
        res
        status: 'virgin'
        type
        requester
        onError
        invalidOnLoad
      }
      q.fn = fn if fn
      queries[q.id] = q
      addHoock(url, data, dataFn, res)
      return res


  dvl.ajax = ({url, data, dataFn, method, type, contentType, processData, fn, invalidOnLoad, onError, groupId, requester, name}) ->
    throw 'it does not make sense to not have a url' unless url
    throw 'the fn function must be non DVL variable' if fn and dvl.knows(fn)
    url  = dvl.wrapConstIfNeeded(url)
    data = dvl.wrapConstIfNeeded(data)
    dataFn = dvl.wrapConstIfNeeded(dataFn or dvl.indentity)
    method = dvl.wrapConstIfNeeded(method or 'GET')
    type = dvl.wrapConstIfNeeded(type or 'json')
    contentType = dvl.wrapConstIfNeeded(contentType or 'application/x-www-form-urlencoded')
    processData = dvl.wrapConstIfNeeded(processData ? true)
    invalidOnLoad = dvl.wrapConstIfNeeded(invalidOnLoad or false)
    name or= 'ajax_data'

    groupId = dvl.ajax.getGroupId() unless groupId?
    ajaxManagers[groupId] or= makeManager()

    if not requester
      normalRequester or= dvl.ajax.requester.normal()
      requester = normalRequester

    return ajaxManagers[groupId](url, data, dataFn, method, type, contentType, processData, fn, invalidOnLoad, onError, requester, name)

  dvl.json = dvl.ajax
  dvl.ajax.outstanding = outstanding

  nextGroupId = 0
  dvl.ajax.getGroupId = ->
    id = nextGroupId
    nextGroupId++
    return id

)()

dvl.ajax.requester = {
  normal: () ->
    return {
      request: ({url, data, dataFn, method, dataType, contentType, processData, fn, outstanding, complete}) ->
        dataVal = if method isnt 'GET' then dataFn(data) else null

        getData = (resVal) ->
          if fn
            ctx = { url, data }
            resVal = fn.call(ctx, resVal)

          ajax = null
          complete(null, resVal)

        getError = (xhr, textStatus) ->
          return if textStatus is "abort"
          ajax = null
          complete(textStatus, null)

        ajax = jQuery.ajax {
          url
          data:        dataVal
          type:        method
          dataType
          contentType
          processData
          success:     getData
          error:       getError
          complete:    -> outstanding.set(outstanding.get() - 1).notify()
          context:     { url }
        }

        outstanding.set(outstanding.get() + 1).notify()

        return {
          abort: ->
            if ajax
              ajax.abort()
              ajax = null

            return
        }
    }


  cache: ({max, timeout} = {}) ->
    max = dvl.wrapConstIfNeeded(max or 100)
    timeout = dvl.wrapConstIfNeeded(timeout or 30*60*1000)
    cache = {}
    count = 0

    trim = ->
      tout = timeout.get()
      if tout > 0
        cutoff = Date.now() - tout
        newCache = {}
        for q,d of cache
          newCache[q] = d if cutoff < d.time
        cache = newCache

      m = max.get()
      while m < count
        oldestQuery = null
        oldestTime = Infinity
        for q,d of cache
          if d.time < oldestTime
            oldestTime = d.time
            oldestQuery = q
        delete cache[oldestQuery]
        count--

    dvl.register {fn:trim, listen:[max, timeout], name:'cache_trim'}


    return {
      request: ({url, data, dataFn, method, dataType, contentType, processData, fn, outstanding, complete}) ->
        dataVal = if method isnt 'GET' then dataFn(data) else null
        key = [url, dvl.util.strObj(dataVal), method, dataType, contentType, processData].join('@@')

        c = cache[key]
        added = false
        if not c
          # first time we see this query, create stub
          cache[key] = c = {
            time: Date.now()
            waiting: [complete]
          }
          added = true
          count++
          trim()

          # make the request
          getData = (resVal) ->
            if fn
              ctx = { url, data }
              resVal = fn.call(ctx, resVal)

            c.ajax = null
            c.resVal = resVal
            cb(null, resVal) for cb in c.waiting
            delete c.waiting
            return

          getError = (xhr, textStatus) ->
            return if textStatus is "abort"
            c.ajax = null
            delete cache[key]
            count--
            cb(textStatus, null) for cb in c.waiting
            delete c.waiting
            return

          c.ajax = jQuery.ajax {
            url
            data:        dataVal
            type:        method
            dataType
            contentType
            processData
            success:     getData
            error:       getError
            complete:    -> outstanding.set(outstanding.get() - 1).notify()
          }

          outstanding.set(outstanding.get() + 1).notify()

        if c.resVal
          complete(null, c.resVal)

          return {
            abort: ->
              return
          }
        else
          c.waiting.push(complete) unless added

          return {
            abort: ->
              return unless c.waiting
              c.waiting = c.waiting.filter((l) -> l isnt complete)

              if c.waiting.length is 0 and c.ajax
                c.ajax.abort()
                c.ajax = null
                delete cache[key]
                count--

              return
          }

      clear: ->
        cache = {}
        count = 0
        return
    }
}


dvl.snap = ({data, acc, value, trim, name}) ->
  throw 'No data given' unless data
  acc = dvl.wrapConstIfNeeded(acc or dvl.identity)
  value = dvl.wrapConstIfNeeded(value)
  trim = dvl.wrapConstIfNeeded(trim or false)
  name or= 'snaped_data'

  out = dvl.def(null).name(name)

  updateSnap = ->
    ds = data.get()
    a = acc.get()
    v = value.get()

    if ds and a and v
      if trim.get() and ds.length isnt 0 and (v < a(ds[0]) or a(ds[ds.length-1]) < v)
        minIdx = -1
      else
        minIdx = -1
        minDist = Infinity
        if ds
          for d,i in ds
            dist = Math.abs(a(d) - v)
            if dist < minDist
              minDist = dist
              minIdx = i

      minDatum = if minIdx < 0 then null else ds[minIdx]
      out.set(minDatum) unless out.get() is minDatum
    else
      out.set(null)

    dvl.notify(out)

  dvl.register({fn:updateSnap, listen:[data, acc, value, trim], change:[out], name:name+'_maker'})
  return out


dvl.hasher = (obj) ->
  updateHash = ->
    h = obj.get()
    window.location.hash = h unless window.location.hash == h

  dvl.register({fn:updateHash, listen:[obj], name:'hash_changer'})
  return


# Data # ------------------------------------------------

dvl.data = {}

dvl.data.min = (data, acc) ->
  acc or= dvl.identity
  return dvl.apply {
    args: [data, acc]
    update: true
    fn: (data, acc) -> d3.min(data, acc)
  }

dvl.data.max = (data, acc) ->
  acc or= dvl.identity
  return dvl.apply {
    args: [data, acc]
    update: true
    fn: (data, acc) -> d3.max(data, acc)
  }

# Scales # ------------------------------------------------

dvl.scale = {}

(->
  dvl.scale.linear = (options) ->
    throw 'no options in scale' unless options
    name = options.name or 'linear_scale'

    rangeFrom = options.rangeFrom || 0
    rangeFrom = dvl.wrapConstIfNeeded(rangeFrom)

    rangeTo = options.rangeTo || 0
    rangeTo = dvl.wrapConstIfNeeded(rangeTo)

    padding = options.padding || 0

    numTicks = options.numTicks || 10
    numTicks = dvl.wrapConstIfNeeded(numTicks)

    optDomain = options.domain
    throw 'no domain object' unless optDomain

    switch dvl.typeOf optDomain
      when 'array'
        throw 'empty domain given to scale' unless optDomain.length > 0
      when 'object'
        optDomain = [optDomain]
      else
        throw 'invalid domian type'

    domainFrom = null
    domainTo   = null
    scaleRef  = dvl.def().name(name + '_fn')
    invertRef = dvl.def().name(name + '_invert')
    ticksRef  = dvl.def().name(name + '_ticks')
    formatRef = dvl.def().name(name + '_format')

    makeScale = () ->
      if domainFrom < domainTo
        makeScaleFn()
      else if domainFrom is domainTo
        makeScaleFnSingle()
      else
        makeScaleFnEmpty()

    makeScaleFn = () ->
      isColor = typeof(rangeFrom.get()) == 'string'
      rf = rangeFrom.get()
      rt = rangeTo.get()
      if not isColor
        if rt > rf
          rf += padding
          rt -= padding
        else
          rf -= padding
          rt += padding
      s = pv.Scale.linear().domain(domainFrom, domainTo).range(rf, rt)
      if isColor
        # We are mapping colors so extract the color form the object
        scaleRef.set((x) -> s(x).color)
      else
        scaleRef.set(s)

      invertRef.set(s.invert)
      ticksRef.setLazy(-> s.ticks(numTicks.get()))
      formatRef.set(s.tickFormat)
      dvl.notify(scaleRef, invertRef, ticksRef, formatRef)
      return

    makeScaleFnSingle = ->
      isColor = typeof(rangeFrom.get()) == 'string'
      rf = rangeFrom.get()
      rt = rangeTo.get()
      if not isColor
        if rt > rf
          rf += padding
          rt -= padding
        else
          rf -= padding
          rt += padding
      avg = (rf + rt) / 2
      scaleRef.set(-> avg)
      invertRef.set(-> domainFrom)
      ticksRef.set([domainFrom])
      formatRef.set((x) -> '')
      dvl.notify(scaleRef, invertRef, ticksRef, formatRef)
      return

    makeScaleFnEmpty = () ->
      scaleRef.set(null)
      invertRef.set(null)
      ticksRef.set(null)
      formatRef.set(null)
      dvl.notify(scaleRef, invertRef, ticksRef, formatRef)
      return

    updateData = () ->
      min = +Infinity
      max = -Infinity
      for dom in optDomain
        if dom.data
          data = dom.data.get()

          if data != null
            acc = dom.acc || dvl.identity
            a = acc.get()

            if dvl.typeOf(data) isnt 'array'
              # ToDo: make this nicer
              data = a(data)
              a = (x) -> x

            if data.length > 0
              if dom.sorted
                d0 = a(data[0], 0)
                dn = a(data[data.length - 1], data.length - 1)
                min = d0 if d0 < min
                min = dn if dn < min
                max = d0 if max < d0
                max = dn if max < dn
              else
                mm = dvl.util.getMinMax(data, a)
                min = mm.min if mm.min < min
                max = mm.max if max < mm.max

        else
          f = dom.from.get()
          t = dom.to.get()
          if f? and t?
            min = f if f < min
            max = t if max < t

      if options.anchor
        min = 0 if 0 < min
        max = 0 if max < 0

      if options.scaleMin != undefined
        min *= options.scaleMin

      if options.scaleMax != undefined
        max *= options.scaleMax


      if min <= max
        if domainFrom != min or domainTo != max
          domainFrom = min
          domainTo = max
          makeScale()
      else
        domainFrom = NaN
        domainTo = NaN
        makeScale()

      return

    listenData = []
    for dom in optDomain
      if dom.data
        listenData.push(dom.data, dom.acc)
      else
        listenData.push(dom.from, dom.to)

    change = [scaleRef, invertRef, ticksRef, formatRef]
    dvl.register({fn:makeScale, listen:[rangeFrom, rangeTo, numTicks], change:change, name:name + '_range_change', noRun:true})
    dvl.register({fn:updateData, listen:listenData, change:change, name:name + '_data_change'})

    # return
    scale:  scaleRef
    invert: invertRef
    ticks:  ticksRef
    format: formatRef


  dvl.scale.ordinal = (options) ->
    throw 'no options in scale' unless options
    name = options.name or 'ordinal_scale'

    rangeFrom = options.rangeFrom || 0
    rangeFrom = dvl.wrapConstIfNeeded(rangeFrom)

    rangeTo = options.rangeTo || 0
    rangeTo = dvl.wrapConstIfNeeded(rangeTo)

    padding = options.padding || 0

    optDomain = options.domain
    throw 'no domain object' unless optDomain

    domain = null
    scaleRef  = dvl.def(null, name + '_fn')
    ticksRef  = dvl.def(null, name + '_ticks')
    formatRef = dvl.def(null, name + '_format')
    bandRef   = dvl.def(0,    name + '_band')

    makeScaleFn = () ->
      rf = rangeFrom.get()
      rt = rangeTo.get()
      if rt > rf
        rf += padding
        rt -= padding
      else
        rf -= padding
        rt += padding
      s = pv.Scale.ordinal().domain(domain).split(rf, rt)
      scaleRef.set(s)
      ticksRef.set(domain)
      formatRef.set(s.tickFormat)
      bandRef.set(Math.abs(rt - rf) / domain.length)
      dvl.notify(scaleRef, ticksRef, formatRef, bandRef)
      return

    makeScaleFnEmpty = () ->
      scaleRef.set(null)
      ticksRef.set(null)
      formatRef.set(null)
      bandRef.set(0)
      dvl.notify(scaleRef, ticksRef, formatRef, bandRef)
      return

    updateData = () ->
      domain = optDomain.data.get()

      if not domain
        makeScaleFnEmpty()
        return

      if optDomain.acc
        a = optDomain.acc.get()
        domain = domain.map(a);

      if optDomain.sort
        # Sorting changes the data in place so copy the data if we have not done so already
        domain = domain.slice() unless optDomain.acc or optDomain.uniq
        domain.sort()

      if optDomain.uniq
        domain = dvl.util.uniq(domain);

      if domain.length > 0
        makeScaleFn()
      else
        makeScaleFnEmpty()

      return

    dvl.register({fn:makeScaleFn, listen:[rangeFrom, rangeTo], change:[scaleRef, ticksRef, formatRef, bandRef], name:name + '_range_change', noRun:true})
    dvl.register({fn:updateData, listen:[optDomain.data, optDomain.acc], change:[scaleRef, ticksRef, formatRef, bandRef], name:name + '_data_change'})

    # return
    scale: scaleRef
    ticks: ticksRef
    format: formatRef
    band: bandRef
)()

# dvl.bind # --------------------------------------------------
do ->
  # {parent, self, data, join, attr, style, text, html, on, transition, transitionExit}
  id_class_spliter = /(?=[#.:])/
  def_data_fn = dvl.const((d) -> [d])
  dvl.bind = (args) ->
    throw "'parent' not defiend" unless args.parent
    self = args.self
    throw "'self' not defiend" unless typeof self is 'string'
    parts = self.split(id_class_spliter)
    nodeType = parts.shift()
    staticId = null
    staticClass = []
    for part in parts
      switch part[0]
        when '#'
          staticId = part.substring(1)
        when '.'
          staticClass.push part.substring(1)
        else
          throw "not currently supported in 'self' (#{part})"

    staticClass = staticClass.join(' ')

    parent = dvl.wrapConstIfNeeded(args.parent)
    data = dvl.wrapConstIfNeeded(args.data or def_data_fn)
    join = dvl.wrapConstIfNeeded(args.join)
    text = if args.text then dvl.wrapConstIfNeeded(args.text) else null
    html = if args.html then dvl.wrapConstIfNeeded(args.html) else null
    transition = dvl.wrapConstIfNeeded(args.transition)
    transitionExit = dvl.wrapConstIfNeeded(args.transitionExit)

    listen = [parent, data, join, text, html, transition, transitionExit]

    attrList = {}
    for k, v of args.attr
      v = dvl.wrapConstIfNeeded(v)
      if k is 'class' and staticClass
        v = dvl.op.concat(v, ' ' + staticClass)

      listen.push(v)
      attrList[k] = v

    if staticClass and not attrList['class']
      attrList['class'] = dvl.const(staticClass)

    styleList = {}
    for k, v of args.style
      v = dvl.wrapConstIfNeeded(v)
      listen.push(v)
      styleList[k] = v

    onList = {}
    for k, v of args.on
      v = dvl.wrapConstIfNeeded(v)
      listen.push(v)
      onList[k] = v

    out = dvl.def(null, 'selection')

    dvl.register {
      listen
      change: [out]
      fn: ->
        _parent = parent.get()
        return unless _parent

        force = parent.hasChanged() or data.hasChanged() or join.hasChanged()
        _data = data.get()
        _join = join.get()

        if _data
          _transition = transition.get()
          _transitionExit = transitionExit.get()

          # prep
          enter     = []
          preTrans  = []
          postTrans = []

          add1 = (fn, v) ->
            if v.hasChanged() or force
              preTrans.push  { fn, a1: v.getPrev() }
              postTrans.push { fn, a1: v.get() }
            else
              enter.push  { fn, a1: v.get() }
            return

          add2 = (fn, k, v) ->
            if v.hasChanged() or force
              enter.push     { fn, a1: k, a2: v.getPrev() }
              preTrans.push  { fn, a1: k, a2: v.getPrev() }
              postTrans.push { fn, a1: k, a2: v.get() }
            else
              enter.push     { fn, a1: k, a2: v.get() }
            return

          addO = (fn, k, v) ->
            if v.hasChanged() or force
              preTrans.push { fn, a1: k, a2: v.get() }
            else
              enter.push  { fn, a1: k, a2: v.get() }
            return

          add1('text', text)  if text
          add1('html', html)  if html
          add2('attr', k, v)  for k, v of attrList
          add2('style', k, v) for k, v of styleList
          addO('on', k, v)    for k, v of onList

          # d3 stuff
          s = _parent.selectAll(self).data(_data, _join)
          e = s.enter().append(nodeType)

          e[a.fn](a.a1, a.a2) for a in enter

          s[a.fn](a.a1, a.a2) for a in preTrans

          if _transition and _transition.duration?
            t = s.transition()
            t.duration(_transition.duration or 1000)
            t.delay(_transition.delay) if _transition.delay
            t.ease(_transition.ease)   if _transition.ease
          else
            t = s

          t[a.fn](a.a1, a.a2) for a in postTrans

          ex = s.exit().remove()
          out.set(s).notify() if not e.empty() or not ex.empty() or force
        else
          s = _parent.selectAll(self).remove()
          out.set(s).notify()

        return
    }

    return out


dvl.chain = (f, h) ->
  f = dvl.wrapConstIfNeeded(f)
  h = dvl.wrapConstIfNeeded(h)

  out = dvl.def(null, 'chain')

  dvl.register {
    listen: [f, h]
    change: [out]
    fn: ->
      _f = f.get()
      _h = h.get()
      if _f and _h
        out.set((x) -> _h(_f(x)))
      else
        out.set(null)

      dvl.notify(out)
      return
  }

  return out



dvl_get = (v) -> v.get()
dvl.op = dvl_op = (fn) ->
  liftedFn = lift(fn)
  return (args...) ->
    args = args.map(dvl.wrapConstIfNeeded)
    out = dvl.def(null, 'out')

    dvl.register {
      listen: args
      change: [out]
      fn: ->
        out.set(liftedFn.apply(null, args.map(dvl_get)))
        dvl.notify(out)
        return
    }

    return out

op_to_lift = {
  'or': ->
    for arg in arguments
      return arg if arg
    return false

  'add': ->
    sum = 0
    for arg in arguments
      if arg?
        sum += arg
      else
        return null
    return sum

  'sub': ->
    sum = 0
    mult = 1
    for arg in arguments
      if arg?
        sum += arg * mult
        mult = -1
      else
        return null
    return sum

  'list': (args...) ->
    for arg in args
      return null unless arg?
    return args

  'concat': (args...) ->
    for arg in args
      return null unless arg?
    return args.join('')

  'iff': (cond, truthy, falsy) ->
    return if cond then truthy else falsy

  'iffEq': (lhs, rhs, truthy, falsy) ->
    return if lhs is rhs then truthy else falsy

  'iffLt': (lhs, rhs, truthy, falsy) ->
    return if lhs < rhs then truthy else falsy

  'makeTranslate': (x, y) ->
    return if x? and y? then "translate(#{x},#{y})" else null
}

dvl_op[k] = dvl_op(fn) for k, fn of op_to_lift



clipId = 0
dvl.svg or= {}
dvl.svg.clipPath = ({parent, x, y, width, height}) ->
  x = dvl.wrapConstIfNeeded(x or 0)
  y = dvl.wrapConstIfNeeded(y or 0)

  clipId++
  myId = "cp#{clipId}"
  cp = dvl.valueOf(parent)
    .append('defs')
      .append('clipPath')
      .attr('id', myId)

  dvl.bind {
    parent: cp
    self: 'rect'
    attr: {
      x
      y
      width
      height
    }
  }

  return "url(##{myId})"


# misc # --------------------------------------------------

dvl.misc = {}
dvl.misc.mouse = (element, out) ->
  element = dvl.wrapConstIfNeeded(element)
  width   = dvl.wrapConstIfNeeded(width)
  height  = dvl.wrapConstIfNeeded(height)
  out     = dvl.wrapVarIfNeeded(out, 'mouse')

  recorder = ->
    _element = element.get()
    mouse = if _element and d3.event then d3.svg.mouse(_element.node()) else null
    out.set(mouse).notify()
    return

  element.get()
    .on('mousemove', recorder)
    .on('mouseout', recorder)

  dvl.register {
    name: 'mouse_recorder'
    listen: [parent]
    change: [out]
    fn: recorder
  }

  return out


dvl.misc.delay = (data, time = 1) ->
  data = dvl.wrapConstIfNeeded(data)
  time = dvl.wrapConstIfNeeded(time)
  timer = null
  out = dvl.def()

  timeoutFn = ->
    out.set(data.get()).notify()
    timer = null

  dvl.register {
    listen: [data, time]
    name: name or 'timeout'
    fn: ->
      clearTimeout(timer) if timer
      timer = null
      if time.get()?
        t = Math.max(0, time.get())
        timer = setTimeout(timeoutFn, t)
  }
  return out


# HTML # --------------------------------------------------

dvl.html = {}

##-------------------------------------------------------
##  Capture the size of something in HTML
##
dvl.html.resizer = ({selector, out, dimension, fn}) ->
  out = dvl.wrapVarIfNeeded(out)
  dimension = dvl.wrapConstIfNeeded(dimension or 'width')
  fn = dvl.wrapConstIfNeeded(fn or dvl.identity)

  onResize = ->
    _dimension = dimension.get()
    _fn = fn.get()
    if _dimension in ['width', 'height'] and _fn
      if selector
        e = jQuery(selector)
        val = e[_dimension]()
      else
        val = document.body[if _dimension is 'width' then 'clientWidth' else 'clientHeight']

      out.update(_fn(val))
    else
      out.update(null)

  $(window).resize onResize
  dvl.register {
    name: 'resizer'
    listen: [dimension, fn]
    change: [out]
    fn: onResize
  }
  return out

##-------------------------------------------------------
##  Output to an HTML attribute
##
dvl.html.out = ({selector, data, fn, format, invalid, hideInvalid, attr, style, text}) ->
  throw 'must have data' unless data
  data = dvl.wrapConstIfNeeded(data)
  format = format ? fn

  throw 'must have selector' unless selector
  selector = dvl.wrapConstIfNeeded(selector)

  format = dvl.wrapConstIfNeeded(format or dvl.identity)
  invalid = dvl.wrapConstIfNeeded(invalid or null)
  hideInvalid = dvl.wrapConstIfNeeded(hideInvalid or false)

  if attr
    what = dvl.wrapConstIfNeeded(attr)
    out = (selector, string) -> d3.select(selector).attr(what.get(), string)
  else if style
    what = dvl.wrapConstIfNeeded(style)
    out = (selector, string) -> d3.select(selector).style(what.get(), string)
  else if text
    out = (selector, string) -> d3.select(selector).text(string)
  else
    out = (selector, string) -> d3.select(selector).html(string)

  updateHtml = () ->
    s = selector.get()
    a = format.get()
    d = data.get()
    if s?
      if a? and d?
        sel = out(s, a(d))
        sel.style('display', null) if hideInvalid.get()
      else
        inv = invalid.get()
        out(s, inv)
        d3.select(s).style('display', 'none') if hideInvalid.get()
    return

  dvl.register({fn:updateHtml, listen:[data, selector, format], name:'html_out'})
  return


##-------------------------------------------------------
##
##  Create HTML list
##
dvl.html.list = ({selector, data, label, link, class:listClass, selection, selections, onSelect, onEnter, onLeave, icons, extras, classStr, sortFn}) ->
  throw 'must have selector' unless selector
  throw 'must have data' unless data
  selection  = dvl.wrapVarIfNeeded(selection, 'selection')
  selections = dvl.wrapVarIfNeeded(selections or [], 'selections')
  sortFn = dvl.wrapConstIfNeeded(sortFn)

  data = dvl.wrapConstIfNeeded(data)
  label = dvl.wrapConstIfNeeded(label or dvl.identity)
  link = dvl.wrapConstIfNeeded(link)

  icons or= []
  for i in icons
    i.position or= 'right'

  if listClass?
    listClass = dvl.wrapConstIfNeeded(listClass)
  else
    listClass = dvl.apply(
      [selection, selections]
      (_selection, _selections) ->
        if _selection
          if _selections
            return (value) ->
              (if value is _selection  then 'is_selection'  else 'isnt_selection') + ' ' +
              (if value in _selections then 'is_selections' else 'isnt_selections')
          else
            return (value) ->
              (if value is _selection  then 'is_selection'  else 'isnt_selection')
        else
          if _selections
            return (value) ->
              (if value in _selections then 'is_selections' else 'isnt_selections')
          else
            return null
    )

  ul = d3.select(selector).append('ul').attr('class', classStr)

  onClick = (val, i) ->
    return if onSelect?(val, i) is false
    linkVal = link.get()?(val)
    selection.set(val)

    sl = (selections.get() or []).slice()
    i = sl.indexOf(val)
    if i is -1
      sl.push(val)
      _sortFn = sortFn.get()
      if typeof _sortFn is 'function'
        sl.sort(_sortFn)
      else
        sl.sort()
    else
      sl.splice(i,1)
    selections.set(sl)

    dvl.notify(selection, selections)
    window.location.href = linkVal if linkVal
    return

  dvl.register {
    name: 'update_html_list'
    listen: [data, label, link]
    fn: ->
      _data  = data.get()
      _label = label.get()
      _link  = link.get()
      _class = listClass.get()

      return unless _data

      addIcons = (el, position) ->
        icons.forEach (icon) ->
          return unless icon.position is position

          classStr = 'icon_cont ' + position
          classStr += ' ' + icon.classStr if icon.classStr

          el.append('div')
            .attr('class', classStr)
            .attr('title', icon.title)
            .on('click', (val, i) ->
              d3.event.stopPropagation() if icon.onSelect?(val, i) is false
              return
            ).on('mouseover', (val, i) ->
              d3.event.stopPropagation() if icon.onEnter?(val, i) is false
              return
            ).on('mouseout', (val, i) ->
              d3.event.stopPropagation() if icon.onLeave?(val, i) is false
              return
            ).append('div')
              .attr('class', 'icon')

          return
        return

      sel = ul.selectAll('li').data(_data)
      a = sel.enter().append('li').append('a')

      addIcons a, 'left'
      a.append('span')
      addIcons a, 'right'

      cont = sel
        .attr('class', _class)
        .on('click', onClick)
        .on('mouseover', onEnter)
        .on('mouseout', onLeave)
        .select('a')
          .attr('href', _link)


      cont.select('span').text(_label)

      sel.exit().remove()
      return
  }

  dvl.register {
    name: 'update_class_list'
    listen: [listClass]
    fn: ->
      _class = listClass.get()
      ul.selectAll('li').attr('class', _class)
  }

  return {
    selection
    selections
    node: ul.node()
  }


dvl.html.dropdownList = ({selector, data, label, selectionLabel, link, class:listClass, selection, selections, onSelect, onEnter, onLeave, classStr, menuAnchor, menuOffset, title, icons, sortFn, keepOnClick}) ->
  throw 'must have selector' unless selector
  throw 'must have data' unless data
  selection = dvl.wrapVarIfNeeded(selection, 'selection')
  selections = dvl.wrapVarIfNeeded(selections, 'selections')
  menuAnchor = dvl.wrapConstIfNeeded(menuAnchor or 'left')
  menuOffset = dvl.wrapConstIfNeeded(menuOffset or { x:0, y:0 })

  data = dvl.wrapConstIfNeeded(data)
  label = dvl.wrapConstIfNeeded(label or dvl.identity)
  selectionLabel = dvl.wrapConstIfNeeded(selectionLabel or label)
  link = dvl.wrapConstIfNeeded(link)

  title = dvl.wrapConstIfNeeded(title) if title
  icons or= []

  menuOpen = false
  getClass = ->
    (classStr ? '') + ' ' + (if menuOpen then 'open' else 'closed')

  divCont = d3.select(selector)
    .append('div')
    .attr('class', getClass())
    .style('position', 'relative')

  selectedDiv = divCont.append('div')
    .attr('class', 'selected')

  valueSpan = selectedDiv.append('span')

  open = ->
    sp = $(selectedDiv.node())
    pos = sp.position()
    height = sp.outerHeight(true)
    anchor = menuAnchor.get()
    offset = menuOffset.get()
    menuCont
      .style('display', null)
      .style('top', (pos.top + height + offset.y) + 'px')

    if anchor is 'left'
      menuCont.style('left', (pos.left + offset.x) + 'px')
    else
      menuCont.style('right', (pos.left - offset.x) + 'px')

    menuOpen = true
    divCont.attr('class', getClass())
    return

  close = ->
    menuCont.style('display', 'none')
    menuOpen = false
    divCont.attr('class', getClass())
    return

  myOnSelect = (text, i) ->
    close() unless keepOnClick
    return onSelect?(text, i)

  icons.forEach (icon) ->
    icon_onSelect = icon.onSelect
    icon.onSelect = (val, i) ->
      close() unless keepOnClick
      return icon_onSelect?(val, i)
    return

  menuCont = divCont.append('div')
    .attr('class', 'menu_cont')
    .style('position', 'absolute')
    .style('z-index', 1000)
    .style('display', 'none')

  dvl.html.list {
    selector: menuCont.node()
    data
    label
    link
    class: listClass
    sortFn
    selection
    selections
    onSelect: myOnSelect
    onEnter
    onLeave
    classStr: 'list'
    icons
  }

  $(window).bind('click', (e) ->
    return if $(menuCont.node()).find(e.target).length

    if selectedDiv.node() is e.target or $(selectedDiv.node()).find(e.target).length
      if menuOpen
        close()
      else
        open()
    else
      close()

    return {
      node: divCont.node()
      selection
      selections
    }
  ).bind('blur', close)

  updateSelection = ->
    if title
      valueSpan.text(title.get())
    else
      sel = selection.get()
      selLabel = selectionLabel.get()
      valueSpan.text(selLabel(sel))
    return

  dvl.register {
    fn:updateSelection
    listen:[selection, selectionLabel, title]
    name:'selection_updater'
  }

  return {
    node: divCont.node()
    menuCont: menuCont.node()
    selection
  }


##-------------------------------------------------------
##
##  Select (dropdown box) made with HTML
##
dvl.html.select = ({selector, data, label, selection, onChange, classStr}) ->
  throw 'must have selector' unless selector
  throw 'must have data' unless data
  selection = dvl.wrapVarIfNeeded(selection, 'selection')

  data = dvl.wrapConstIfNeeded(data)
  label = dvl.wrapConstIfNeeded(label or dvl.identity)

  selChange = (val) ->
    return if onChange?(val) is false
    selection.update(val)

  selectEl = d3.select(selector)
    .append('select')
    .attr('class', classStr or null)
    .on('change', selChange)

  dvl.bind {
    parent: selectEl
    self: 'option'
    data
    attr: {
      value: (d,i) -> i
    }
    text: label
  }

  dvl.register {
    listen: [data, selection]
    fn: ->
      _data = data.get()
      _selection = selection.get()
      return unless _data and _selection
      idx = _data.indexOf(_selection)
      if selectEl.node().value isnt idx
        selectEl.node().value = idx
      return
  }


  #updateSelection = () ->
  #  selectEl

  selChange()
  #dvl.register({fn: updateSelection, listen:[], change:[selection]})
  return selection



dvl.compare = (acc, reverse) ->
  acc = dvl.wrapConstIfNeeded(acc || dvl.ident)
  reverse = dvl.wrapConstIfNeeded(reverse || false)
  return dvl.apply {
    args: [acc, reverse]
    fn: (acc, reverse) ->
      if reverse
        return (a,b) ->
          va = acc(a)
          vb = acc(b)
          t = typeof va
          if t is 'string'
            return vb.localeCompare(va)
          else if t is 'number'
            return vb - va
          else
            throw "bad sorting type #{t}"
      else
        return (a,b) ->
          va = acc(a)
          vb = acc(b)
          t = typeof va
          if t is 'string'
            return va.localeCompare(vb)
          else if t is 'number'
            return va - vb
          else
            throw "bad sorting type #{t}"  }


##-------------------------------------------------------
##
##  Table made with HTML
##
##  This module draws an HTML table that can be sorted
##
##  parent:      Where to append the table.
## ~data:        The data displayed.
##  classStr:    The class to add to the table.
## ~rowClassGen: The generator for row classes
## ~visible:     Toggles the visibility of the table. [true]
##  columns:     A list of columns to drive the table.
##    column:
##      id:               The id by which the column will be identified.
##     ~title:            The title of the column header.
##     ~headerTooltip:    The popup tool tip (title element text) of the column header.
##      classStr:         The class given to the 'th' and 'td' elements in this column, if not specified will default to the id.
##      cellClassGen:     The class generator for the cell
##     ~cellClick:        The generator of click handlers
##     ~value:            The value of the cell
##      sortable:         Toggles wheather the column is sortable or not. [true]
##     ~compare:          The generator that will drive the sorting, if not provided then gen will be used instead. [gen]
##     ~compareModes:        ['none', 'up', 'down']
##     ~hoverGen:         The generator for the (hover) title.
##     ~showIndicator:    Toggle the display of the sorting indicator for this column. [true]
##     ~reverseIndicator: Reverses the asc / desc directions of the indicator for this column. [false]
##     ~visible:          Toggles the visibility of the column
##
##  sort:
##   ~on:              The id of the column on which to sort.
##   ~onIndicator:     The id of the column on which the indicator is palced (defaults to sort.on)
##   ~order:           The order of the sort. Must be one of {'asc', 'desc', 'none'}.
##   ~modes:           The order rotation that is allowed. Must be an array of [{'asc', 'desc', 'none'}].
##   ~autoOnClick:     Toggle wheather the table will be sorted (updating sort.on and/or possibly sort.order) automaticaly when clicked. [true]
##   ~indicator:       [true / false]
##
## ~showHeader:        Toggle showing the header [true]
## ~onHeaderClick:     Callback or url when the header of a column is clicked.
## ~headerTooltip:     The default herder tooltip (title element text).
## ~rowLimit:          The maximum number of rows to show; if null all the rows are shown. [null]
##
do ->
  default_compare_modes = ['up', 'down']
  dvl.html.table = ({parent, data, sort, classStr, rowClass, rowLimit, columns}) ->
    table = dvl.valueOf(parent)
      .append('table')
      .attr('class', classStr)

    sort = sort or {}
    sortOn = dvl.wrapVarIfNeeded(sort.on)
    sortDir = dvl.wrapVarIfNeeded(sort.dir)
    sortOnIndicator = dvl.wrapVarIfNeeded(sort.onIndicator ? sortOn)

    headerCol = []
    bodyCol = []
    compareMap = {}
    compareList = [sortOn, sortDir]
    for c in columns
      c.sortable ?= true
      if c.sortable
        if c.compare?
          comp = dvl.wrapConstIfNeeded(c.compare)
        else
          comp = dvl.compare(c.value)
        compareMap[c.id] = comp
        compareList.push comp

        if not c.compareModes?[0]
          c.compareModes = default_compare_modes

      headerCol.push {
        id:       c.id
        title:    c.title
        class:    c.class
        visible:  c.visible
        tooltip:  c.headerTooltip
      }
      bodyCol.push {
        id:       c.id
        class:    c.class
        visible:  c.visible
        value:    c.value
        hover:    c.hover
        render:   c.render
        on:       c.on
      }

    compare = dvl.def(null)
    dvl.register {
      listen: compareList
      change: [compare]
      fn: ->
        _sortOn = sortOn.get()
        _sortDir = sortDir.get()

        if _sortOn?
          cmp = compareMap[_sortOn]?.get()
          if cmp and _sortDir is 'down'
            oldCmp = cmp
            cmp = (a,b) -> oldCmp(b,a)
          compare.set(cmp)
        else
          compare.set(null)
        compare.notify()
        return
    }

    dvl.html.table.header {
      parent: table
      columns: headerCol
      onClick: (id) ->
        column = null
        for c in columns
          if c.id is id
            column = c
            break

        return unless column and column.sortable

        compareModes = column.compareModes
        if id is sortOn.get()
          sortDir.set(compareModes[(compareModes.indexOf(sortDir.get())+1) % compareModes.length])
          dvl.notify(sortDir)
        else
          sortOn.set(id)
          sortDir.set(compareModes[0])
          dvl.notify(sortOn, sortDir)

        return
    }

    dvl.html.table.body {
      parent: table
      data
      rowClass
      rowLimit
      columns: bodyCol
      compare
    }

    return {}


  ##-------------------------------------------------------
  ##
  ##  HTML table header (thead)
  ##
  ##  parent:      Where to append the table.
  ## ~onClick:     The click handler
  ##  columns:
  ##   ~title:       The title of the column.
  ##   ~class:       The class of the column
  ##   ~tooltip:     The tooltip for the column
  ##   ~visible:     Is this visible
  ##   ~indicator:   The column indicator
  ##
  dvl.html.table.header = ({parent, columns, onClick}) ->
    throw 'there needs to be a parent' unless parent
    onClick = dvl.wrapConstIfNeeded(onClick)

    thead = dvl.valueOf(parent).append('thead').append('tr')

    listen = [onClick]
    newColumns = []
    for c in columns
      newColumns.push(nc = {
        id:        c.id
        title:     dvl.wrapConstIfNeeded(c.title)
        class:     dvl.wrapConstIfNeeded(c.class)
        visible:   dvl.wrapConstIfNeeded(c.visible ? true)
        tooltip:   dvl.wrapConstIfNeeded(c.tooltip)
        indicator: dvl.wrapConstIfNeeded(c.indicator) if c.indicator
      })
      listen.push nc.title, nc.class, nc.visible, nc.tooltip, nc.indicator

    columns = newColumns

    # Init step
    sel = thead.selectAll('th').data(columns)
    enterTh = sel.enter().append('th')
    enterTh.append('span')
    enterTh.append('div').attr('class', 'indicator').style('display', 'none')

    sel.exit().remove()

    dvl.register {
      name: 'header_render'
      listen
      fn: ->
        for c,i in columns
          sel = thead.select("th:nth-child(#{i+1})")
          visibleChanged = c.visible.hasChanged()
          if c.visible.get()
            sel.attr('class', c.class.get())       if c.class.hasChanged() or visibleChanged
            sel.attr('title', c.tooltip.get())     if c.tooltip.hasChanged() or visibleChanged
            sel.attr('title', c.tooltip.get())     if c.tooltip.hasChanged() or visibleChanged
            sel.style('display', null)             if visibleChanged
            sel.on('click', (d) -> onClick.get()?(d.id)) if onClick.hasChanged() or visibleChanged
            sel.select('span').text(c.title.get()) if c.title.hasChanged() or visibleChanged

            if c.indicator and (c.indicator.hasChanged() or visibleChanged)
              _indicator = c.indicator.get()
              ind = sel.select('div.indicator')
              if _indicator
                ind.style('display', null).attr('class', 'indicator ' + _indicator)
              else
                ind.style('display', 'none')
          else
            sel.style('display', 'none')           if visibleChanged

        return
    }

    return


  ##-------------------------------------------------------
  ##
  ##  HTML table body (tbody)
  ##
  ##  parent:      Where to append the table.
  ## ~data:        The data displayed.
  ## ~compare:        The function to sort the data on
  ## ~rowClass       The class of the row
  ## ~rowLimit:          The maximum number of rows to show; if null all the rows are shown. [null]
  ##  columns:
  ##   ~value:       The value of the cell
  ##   ~class:       The class of the column
  ##   ~hover:       The hover
  ##   ~visible:     This this column shown?
  ##    on:          Whatever on events you want
  ##
  dvl.html.table.body = ({parent, data, compare, rowClass, rowLimit, columns}) ->
    throw 'there needs to be a parent' unless parent
    throw 'there needs to be data' unless data
    tbody = dvl.valueOf(parent).append('tbody')

    compare = dvl.wrapConstIfNeeded(compare)
    rowClass = dvl.wrapConstIfNeeded(rowClass) if rowClass?
    rowLimit = dvl.wrapConstIfNeeded(rowLimit)
    listen = [data, compare, rowClass, rowLimit]
    change = []
    newColumns = []
    for c in columns
      newColumns.push(nc = {
        id:      c.id
        class:   dvl.wrapConstIfNeeded(c.class)
        visible: dvl.wrapConstIfNeeded(c.visible ? true)
        hover:   dvl.wrapConstIfNeeded(c.hover)
        value:   dvl.wrapConstIfNeeded(c.value)
      })
      # don't listen to value which is handled by the render
      listen.push nc.class, nc.visible, nc.hover

      nc.render = c.render or 'text'

      nc.on = {}
      for k,v of c.on
        v = dvl.wrapConstIfNeeded(v)
        listen.push v
        nc.on[k] = v

      change.push(nc.selection = dvl.def(null).name("#{c.id}_selection"))

    columns = newColumns

    dvl.register {
      name: 'body_render'
      listen
      change
      fn: ->
        dataSorted = data.get() or []

        _compare = compare.get()
        dataSorted = dataSorted.slice().sort(_compare) if _compare

        _rowLimit = rowLimit.get()
        dataSorted = dataSorted.slice(0, _rowLimit) if _rowLimit?

        rowSel = tbody.selectAll('tr').data(dataSorted)
        newRows = not rowSel.enter().append('tr').empty()
        rowSel.exit().remove()
        if rowClass
          _rowClass = rowClass.get()
          rowSel.attr('class', _rowClass)

        colSel = rowSel.selectAll('td').data(columns)
        colSel.enter().append('td')
        colSel.exit().remove()

        for c,i in columns
          sel = tbody.selectAll("td:nth-child(#{i+1})").data(dataSorted)
          visibleChanged = c.visible.hasChanged() or newRows
          if c.visible.get()
            sel.attr('class', c.class.get()) if c.class.hasChanged() or visibleChanged
            sel.attr('title', c.hover.get()) if c.hover.hasChanged() or visibleChanged
            sel.style('display', null)       if visibleChanged

            for k,v of c.on
              sel.on(k, v.get()) if v.hasChanged() or visibleChanged

            c.selection.set(sel).notify()
          else
            sel.style('display', 'none')     if visibleChanged

        return
    }

    for c in columns
      render = if typeof c.render is 'function' then c.render else dvl.html.table.render[c.render]
      render.call(c, c.selection, c.value)

    return


  dvl.html.table.render = {
    text: (selection, value) ->
      dvl.register {
        listen: [selection, value]
        fn: ->
          _selection = selection.get()
          _value = value.get()
          if _selection? and _value
            _selection.text(_value)
          return
      }
      return

    html: (selection, value) ->
      dvl.register {
        listen: [selection, value]
        fn: ->
          _selection = selection.get()
          _value = value.get()
          if _selection? and _value
            _selection.html(_value)
          return
      }
      return


    aLink: ({href}) -> (selection, value) ->
      dvl.bind {
        parent: selection
        self: 'a.link'
        attr: {
          href: href
        }
        text: value
      }
      return

    spanLink: ({click}) ->
      titleGen = dvl.wrapConstIfNeeded(titleGen)
      return (sel, value) ->
        sel = sel.selectAll('span').data((d) -> [d])
        sel.enter().append('span').attr('class', 'span_link')
        sel.html(value).on('click', click)
        return

    img: (selection, value) ->
      dvl.bind {
        parent: selection
        self: 'img'
        attr: {
          src: value
        }
      }
      return

    imgDiv: (selection, value) ->
      dvl.bind {
        parent: selection
        self: 'div'
        attr: {
          class: value
        }
      }
      return

    sparkline: ({width, height, x, y, padding}) ->
      padding ?= 0
      return (selection, value) ->
        lineFn = dvl.apply {
          args: [x, y, padding]
          fn: (x, y, padding) -> (d) ->
            mmx = dvl.util.getMinMax(d, ((d) -> d[x]))
            mmy = dvl.util.getMinMax(d, ((d) -> d[y]))
            sx = d3.scale.linear().domain([mmx.min, mmx.max]).range([padding, width-padding])
            sy = d3.scale.linear().domain([mmy.min, mmy.max]).range([height-padding, padding])
            return d3.svg.line().x((dp) -> sx(dp[x])).y((dp) -> sy(dp[y]))(d)
        }

        dataFn = dvl.apply {
          args: value
          fn: (value) -> (d,i) -> [value(d,i)]
        }

        svg = dvl.bind {
          parent: selection
          self: 'svg.sparkline'
          data: dataFn
          attr: {
            width
            height
          }
        }

        dvl.bind {
          parent: svg
          self: 'path'
          data: (d) -> [d]
          attr: {
            d: lineFn
          }
        }
        return
  }
