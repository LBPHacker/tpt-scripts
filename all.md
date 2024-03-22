% TPT All script
% LBPHacker
% 2023-12-24

# TPT All script

This script lets you define sets of particles, filter these sets (comparisons,
user filters), execute boolean operations on them (union, difference,
intersection) and finally manipulate the particles in them en masse. It also
lets you access properties of particles through proxy objects.

**DO READ THIS. It's worth it. I mean it. You won't know how to use this if you
don't. It's really useful at times and better than the legacy console commands.**

It does assume a bit of Lua knowledge, but Lua is a language filled to the brim
with easy to discover patterns, so don't be afraid of experimenting. The worst
that can happen is you get an error.

The script sets up a table named `all` in the global `tpt` table, thus it's
accessible as `tpt.all`. All functions defined by the script are in `tpt.all`.

There are two main concepts in this script that you should wrap your head
around: *proxies* and *sets*. Proxies are basically particles, or rather, things
through which you can access properties of particles. Sets are
collections of such proxies.

The properties of particles are the pieces of data you can manipulate with the
PROP tool, e.g. `ctype`, `life` and `dcolour`. When you *index* proxies (that is, use
the `.` or the `[]` operators on them in Lua) they let you access these properties
of the particles they control.

Sets are like boxes with numbered balls in them. You can make your own box with
your own selection of numbered balls, and also combine the contents of boxes
(union), remove all balls from a box that are present in another box
(difference) or only keep balls that are present in another box (intersection).

Proxies for particles are returned by `tpt.all.proxy`. This function expects
a particle ID as a parameter and returns an object that you can index with
property names. For performance reasons, no sanity checking is done when
accessing a property through such a proxy, so if you try to access a property
that doesn't exist, you may get an error. Example:

```lua
local proxy = tpt.all.proxy(1337) -- proxy for particle #1337
proxy.ctype = 0xBADC0DE -- sim.partProperty(1337, "ctype", 0xBADC0DE)
-- the above is also equivalent to !set ctype 1337 0xBADCODE
print(proxy.life) -- print(sim.partProperty(1337, "life"))
```

The property names currently supported are (in version 97.0) `type`, `life`, `ctype`,
`x`, `y`, `vx`, `vy`, `temp`, `flags`, `tmp`, `tmp2`, `tmp3`, `tmp4` and `dcolour`. Proxies also
handle a property called `id`, which is not an actual particle property but,
unsurprisingly enough, the ID of the particle the proxy controls.

Note that a proxy is dumb. If the particle it controls dies, it won't know
about it and if you try to access a dead particle through its proxy, you may
again get an error. I'm saying you *may* because another particle may get the ID
of the particle that died, in which case you won't get an error but you won't
get what you expect either.

Again, no sanity checking is done. For this reason it's best to use the 
functions in this script while the simulation is paused. To be honest, I can't
think of a reason to use them when it's not paused, but I'm sure the community
will find one.

The script makes sure that at any given moment at most one proxy exists for any
particle ID. This means that if you call `tpt.all.proxy` multiple times with the
same ID, you'll get the same object back. This makes sets easy to implement.

Sets are more fun. They are actually sets of proxies but let's just pretend
that they are sets of particles. There are many ways to create such sets:

 - `tpt.all()` returns a set of all particles in the simulation,
 - `tpt.all.at(x, y)` returns a set which holds a single particle
   at coordinates `x, y`,
 - `tpt.all.zero()` returns a set which holds no particles,
 - `tpt.all.one(id)` returns a set which holds a single particle whose ID is `id`,
 - `tpt.all.easy(str)` is a shorthand for `tpt.all():easy(str)`, see `:easy` below,
 - `tpt.all.array(arr)` does the same with the values of `arr` (a Lua array; the
   inverse of this operation is `set_1:array()`, which returns such a table),
 - `tpt.all.buffer(func, ...)` returns a set of particles created by `func` (a
   function which the script calls with the rest of the arguments, the `...`
   thing) by secretly intercepting all `sim.partCreate` calls (see way
   below for examples),
 - `tpt.all.assoc(tbl)` returns a set of particles whose IDs are the keys of `tbl`
   (a Lua table; the inverse of this operation is `set_1:assoc()`, which returns
   such a table).

In fact you shouldn't use `tpt.all.proxy` at all. Sets are way better, believe me.

Now that you have sets, it's time to manipulate the particles in them a bit.
Below are a bunch of examples of such en masse manipulation. Note the use of `:`
instead of `.` when calling `:set`, `:count`, `:kill` and `:each`.

```lua
tpt.all():set("dcolour", 0xFFFF0000) -- paint all particles red
tpt.all():set("ctype", 0xBADC0DE) -- set ctype of all particles to 0xBADC0DE
print(tpt.all:count()) -- count particles
tpt.all():kill() -- KILL ALL HUMA-- ehrm, particles
-- exercise: guess what the two examples below do
tpt.all():set("dcolour", math.random(0, 0xFFFFFFFF))
tpt.all():set("dcolour", function() return math.random(0, 0xFFFFFFFF) end)
tpt.all():each(function(p) p.dcolour = math.random(0, 0xFFFFFFFF) end)
```

The last three examples by no means do the same thing. The first one generates
one random colour and assigns that to the `dcolour` of every particle, while the
last two generate and assign a distinct random colour to each particle.

Here's a full list of property manipulation functions that sets support:

 - `set_1:set(property, value)` sets `property` (a property string or index) of
   all particles in the set to `value` (an adequate value or a function that
   returns such adequate values; the function gets the proxy as its first
   parameter),
 - `set_1:add(property, value)` does the same as set, except it increases or
   decreases the value of the property by the specified value,
 - `set_1:randomise(property, value_array)` is the same as set except it randomly
   chooses one property value from `value_array` for every particle (yes, you can
   even have functions in the array),
 - `set_1:kill()` kills all particles in the set,
 - `set_1:reorder()` orders all particles in the set the way they would be ordered
   when they are freshly loaded from a save file,
 - finally there is `set_1:each(func, ...)` which you can use if no other
   manipulator does what you want: it calls `func` for all particles in the set
   (`func` gets the proxy as its first parameter and the `...` after that).

Note that `:each` is not strictly a property manipulation function; it does
whatever the function you give it does, which may or may not change properties
of particles. It's entirely up to you what `:each` does.

You can of course store sets in variables for later use:

```lua
local stuff = tpt.all() -- remove the 'local' if you do this in the console
stuff:set("tmp", function(p) return p.tmp2 + 1 end)
stuff:each(function(p)
	p.dcolour = (p.x + p.y) % 3 == 0 and 0xFFFFFFFF or 0xFF000000
end)
stuff:randomise("type", { "qrtz", "glas", "tung" })
```

And since most of these functions return the set they're called on (one
exception being `:count`), you can chain them:

```lua
tpt.all():set("tmp", 1):set("ctype", "bray")
```

Sets also support operations that yield new sets holding different particles.
Most of these are boolean operations or filters. Boolean operations take two
sets and create a new set from the particles in the first two sets in various
ways, while filters yield sets that hold the same particles as the original set
except the ones that don't satisfy certain criteria.

Boolean operations are as follows:

 - `set_1 + set_2` (union) yields a set that contains the particles that are in
   either `set_1` or `set_2`,
 - `set_1 * set_2` (intersection) yields a set that contains the particles that
   are in both `set_1` and `set_2`,
 - `set_1 - set_2` (difference) yields a set that contains the particles that are
   in `set_1` but not in `set_2`.

There are many more filters than boolean operations:

 - `set_1:eq(property, value)` (EQual) yields a set with the particles from `set_1`
   whose property named `property` has the value `value`, which may be:
   - a number, e.g. `8` (property values are natively always numbers),
   - an element name, e.g. `"dmnd"` would be converted to `28`, DMND's ID,
   - a string with a number and a trailing C, K or F for Celsius, Kelvin and Fahrenheit,
     e.g. `"777F"` or `"413.89C"` would be converted to `687.04` (TPT uses Kelvin),
 - `set_1:neq(property, value)` (Not EQual) does the opposite,
 - `set_1:lt(property, value)` (Lower Than) is similar, but it only leaves a
   a particle in the new set if its `property` property is lower than `value`,
 - `set_1:lte(property, value)` (Lower Than or Equal) is similar but does `<=`,
 - `set_1:gt(property, value)` (Greater Than) is the same with `>`,
 - `set_1:gte(property, value)` (Greater Than or Equal) is the same with `>=`,

```lua
-- paint everything red that's to the right of the x = 50 line
tpt.all():gt("x", 50):set("dcolour", 0xFFFF0000)
-- make all CLNE particles emit PHOT
-- equivalent to !set ctype clne phot
tpt.all():eq("type", "clne"):set("ctype", "phot")
```

All of the above take an optional boolean argument `eyeball_xy`, which reduces
their precision such that `x`/`y` readings taken from the HUD can be used with them.
For example, a particle may be at `x = 8.7`, but `:gte("x", 9, true)` will match it,
because `8.7` rounds up to `9`.

 - `set_1:bbox(left, top, right, bottom)` (Bounding BOX) yields a set with the
   particles from `set_1` that also happen to fall in the area defined by the
   positions `left`, `top`, `right` and `bottom`. These positions follow the
   notion of Rectangles in programming, which means that while the `left` and
   `top` positions are inclusive, `right` and `bottom` are exclusive. See crappy
   ASCII drawing:

```
+------------------------------------------------------------------------------+
|x                      (this is the simulation)                               |
| (0,0)     #                                                        #         |
|                                     #                                        |
|                       #                                                      |
|                                                        #                     |
|       #           (25,6)                            #                        |
|                #        x-------@--------+                                   |
|            #            |                |                #              #   |
|                         |    @           @                     #   #         |
|                         |        @       |        #                          |
|   #                     @                |                                   |
|                  #      |              @ |#               #                  |
|                         +----@-----------+       #              #      #     |
|       #                         #         x                                  |
|                                            (43,13)                           |
|                   #                                               #          |
|       #                                       #        #                     |
|                              #                                               |
|                 #                                                            |
|                           #                #                         (77,20) |
|        #                                                     #              x|
+------------------------------------------------------------------------------+
```

The `tpt.all():bbox(25, 6, 43, 13)` set will contain all particles marked `@` (and
not `#`). Note how there are particles that are at `x = 43` or `y = 13`, yet they
don't make it into the set because `right` and `bottom` are exclusive.

```lua
-- same as the previous example, but only affects CLNE particles
-- in the [100, 300) * [200, 400) bounding box
tpt.all():eq("type", "clne"):bbox(100, 200, 300, 400):set("ctype", "phot")
```

`:bbox` also takes an optional boolean argument `eyeball_xy`.

 - `set_1:cursor(width, height)` is just `set_1:bbox(M(width, height))`, where
   `M` returns the current mouse vector and the same vector offset by
   `[width, height]`. In other words, this takes a bounding box whose top left
   corner is wherever the cursor is, and whose dimensions are specified by
   width and height.

`:cursor` also takes an optional boolean argument `eyeball_xy`.

 - finally `set_1:filter(func, ...)`, which you can use if no other filter does
   what you want: it calls `func` for all particles in the set (`func` gets the
   proxy as its first parameter and the `...` after that); this function must
   return a truthy value (everything that isn't `nil` or `false` in Lua) if it wants
   to include the particle in the set `:filter` yields.

And then sets support a few miscellaneous operations that I personally rarely
use, but who knows, they might be useful to others:

 - `set_1:count()` returns the number of particles in the set,
 - `set_1:top()` is a filter that yields a set in which all particles are
   *on top*, i.e. in a stack of particles sharing the same position no particle
   is above them,
 - `set_1:clone()` yields a set with the same particles as `set_1`, if for whatever
   reason you need a copy (you likely won't),
 - `set_1:get(property)` tells you the value of the `property` property of each
   particle in the set if all of them have the same value for that property,
   otherwise it says that they don't and returns `false`,
 - `set_1:get_bbox(eyeball_xy)` returns the bounding box of the set as four
   variables: `left, top, right, bottom`, its eyeball_xy again controls whether it
   returning HUD-like integer coordinates,
 - `set_1:average(property)` is the same as get except it returns the average if
   there are multiple particles in the set (so it never returns `false`),
 - `set_1:rotate(angle, xcenter, ycenter)` rotates the set by `angle` degrees in
   the clockwise direction around the point specified with `xcenter` and `ycenter`,
   both of which are optional and default to the center of the bounding box
   (as per `set_1:get_bbox`) along the appropriate dimension,
 - and `set_1:iterate()` can be used as an iterator in a Lua for loop:

```lua
for id, proxy in set_1:iterate() do
	proxy.life = id * 2 -- whatever, do something funny here
end
```

 - `set_1 == set_2` returns `true` if `set_1` and `set_2` are identical in terms of
   particles,
 - `set_1 < set_2` returns `true` if `set_1` is a strict subset of `set_2` (i.e. there
   are particles in `set_2` not present in `set_1` but not the other way around),
 - `set_1 <= set_2` returns `true` if `set_1` is a subset of `set_2` (i.e. one of the
   above two is `true`).

If Lua syntax seems tedious to you, you can just use `:easy`, which takes a string
reminiscent a collection of legacy console commands and wraps the more important
manipulators and filters. Commands in this string consist of an operator, and
optionally a property name on the left and a number of property values on the
right. The operators are as follows:

 - `[]x1,y1,x2,y1` is short for `:bbox(x1, y1, x2, y1)`,
 - `@width,height` is short for `:cursor(width, height)`,
 - `name==value` is short for `:eq(name, value)`,
 - `name!=value` is short for `:neq(name, value)`,
 - `name<value` is short for `:lt(name, value)`,
 - `name<=value` is short for `:lte(name, value)`,
 - `name>value` is short for `:gt(name, value)`,
 - `name>=value` is short for `:gte(name, value)`,
 - `^` is short for `:top()`,
 - `name=value` is short for `:set(name, value)`,
 - `name=val1,val2,...` is short for `:randomise(name, { val1, val2, ... })`,
 - `name+=value` is short for `:add(name, value)`,
 - `name?` is short for `:get(name)`,
 - `name?/` is short for `:average(name)`,
 - `!` is short for `:kill()`,
 - `$` is short for `:count()`.
 - `*` is short for `:reorder()`.

You combine these operators by joining them with spaces. As an example, we're
going to rewrite an earlier example to use `:easy`

```lua
-- these three commands all do the exact same thing
tpt.all():eq("type", "clne"):bbox(100, 200, 300, 400):set("ctype", "phot")
tpt.all():easy("type==clne []100,200,300,400 ctype=phot")
tpt.all("type==clne []100,200,300,400 ctype=phot")
```

Sets also have a few low-level methods that operate with single particle IDs
(generally you should probably have no reason to use these):

 - `set_1:insert(id)` inserts the particle with ID `id` to the set,
 - `set_1:remove(id)` removes the particle with ID `id` from the set,
 - `set_1:has(id)` returns `true` if the particle with ID `id` is in the set, `false`
   otherwise.

Since a total order is defined over particle IDs, it's possible to order the
otherwise unordered sets into ordered sets, which in turn makes it possible
to select certain particles based on their index in these ordered sets. The
following methods facilitate this:

 - `set_1:range(first, last)` selects the range `[first, last]` from the ordered
   set of particle IDs (`first` and `last` follow standard Lua semantics),
 - `set_1[n]` is an aliases for `set_1:range(n, n)`.

The last example I'd like to show will demonstrate the proper usage of
`tpt.all.buffer`. There's another function called `tpt.all.fill(element)` that
fills the entire screen with `element` (defaults to DMND) by calling
`sim.partCreate` a lot. This in itself isn't terribly interesting, but like I
said, `tpt.all.buffer` hijacks `sim.partCreate` and adds every particle to a set
that is created while the function passed to `tpt.all.buffer` is running. In other
words, you can easily fill the whole screen with yellow CRMC like this:

```lua
tpt.all.buffer(tpt.all.fill, "crmc"):set("dcolour", 0xFFFFFF00)
```
