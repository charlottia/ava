2025-01-04: designer is pretty nyonk

Last steps:

* [x] checkbox
* [x] ability to reorder elements
* [x] radio button ordering -- we can infer, but are there ever multiple groups?
  * I see no evidence of this.
* [x] DesignSelect
* [x] file/dir selection
* [x] "files not saved" dialog has oddly-sized buttons
* [x] Zig export
* [x] new/open/save in designer itself
  * [x] XXX Current crash: start program no args, move dialog 1px, File > New
        Program, Yes.
* [ ] fix re-save in other directory
* [ ] some edge cases, some crashing (usually element resize where r2<r1 etc.)
  * [ ] don't crash on bad open
* [x] Select doesn't show selection until you actually force/make one, and doing
      so un-'selects' all other Selects on the dialog; pressing up or down just
      focuses the horizontal control, but left or right focuses and moves. u/d/l/r
      just focus the vertical control. note difference in behaviour between these
      and the Display Options colour pickers, which always show their selected
      item.
* [ ] showing the current filename somewhere would be nice
* [ ] horizontal select focus needs to focus on click

---

2024-12-16: refactor done, now what

* [x] fix 'blur'
* [x] investigate vtable instead of comptime wonk
* [x] centralise editing between Editor/DialogInput/DialogTextarea
  * last one doesn't exist yet, but think of the &Help dialog
* [x] materialise Editor in the focus stack
* [x] what ids _should_ we use for dialog stuff? buncha XXX there
* [x] do the dialog designer. HACE LA COSA VERDADERA.
  * [x] move generationGet/Set into Control itself?
    * Not Control, but a "base class".
  * [x] how about refactoring `create` somehow too?
* [ ] consider interaction tests -- can test against TextMode w/o backing, no
      graphics required.

Re: centralise editing between Editor/etc.: we'll probably just want to use
Source in DialogInput (i.e. align with Editor), and then add a layer between the
controls and the source which holds the 'editor-like' state and handles relevant
events!

* [x] use Source in DialogInput
* [x] extract editor UI interface

Putting off for now, it'll be more fun once we've had some time away from Imtui
internals:

* [ ] scour remaining XXX/TODO and just do a bunch (h.a.d)
* [x] consider if we care to look into ctm stuff per below
  * I think I ended up fixing this to a good enough state.
* [x] text selection in EditorLike could use a real fixer upper.

---

Two major refactors need to be done:

* [x] Imtui's existing model has been stretched and kinda frankenstein'd
      with the Dialog and all the forwarding to very similar interfaces.
      Ideally everything is managed by the top-level system, with parent-child
      relationships known to the system.
  * The Menubar reconciliation task already wants this. -- turns out it didn't!
  * [x] Remember we have this "offset" stuff right now with Dialogs which is
        super busted.
    * [ ] Dialog also is really confused about how to handle click/drag/
          clickmatic.
          We still are fairly confused about clickmatic across the board, but
          now there at least aren't as many layers of it.  THERE ARE, however,
          still layers of it, where dialog control events need to decide when to
          delegate to the "common" dialog handler; we haven't actually settled
          on a heuristic for that yet, and each control does something slightly
          different and some of the are probably wrong in an observable way.

Thinking about WinForms and DOM when searching for API inspiration (particularly
on recently adding "blur()" as an 'event', the general state of confusion of
event handlers vs setters vs attributes vs ...).

One big thing is that we could take this opportunity to decouple the "user
interface" from the backend interface entirely; the object instantiated by the
backend (which events currently 'propagate' through and to etc.) doesn't have to
be the same type of thing the user manipulates. Right now they are and it's
_annoying_, because we have completely separate APIs in the one namespace!

This'll help a bunch, yikes. Thanks for letting me run with this!

~

OK, that's done. Now. Howwwwwww are we gonna awawa this?

Imtui handles all events. It takes care of instrumenting TextMode, handing only
translated positions through to controls, and handles click- + type-matic. It
maintains a sense of what is focussed and chooses where to dispatch events.

At present it privileges Editor/Menu(bar)/Dialog as the only possible focuses
(which is true inasmuch as those things handle their own "subfocus" currently),
and deals with how focus gets transferred to the Menu(bar) when Alt is pressed.
It also entirely handles Menu(bar) controls. That's ugly!

~

DX-wise, we really want a way to instantiate a control as a child of another one
in a generic fashion. Manual offset tracking sucks, and so does having controls
split across e.g. Imtui and Dialog. A control probably could have a generic
"children" thing; whether *all* controls get this (how?) or only the ones that
want it is a reasonable question. (Probably reasonable to let comptime answer
this last question.)

Keep in mind, our current event model depends on the current granularity of
event targets! We pass drag/up events to the current "mouse_event_target", which
is a ?Imtui.Control. We will need to rework the event model here (and in other
places).


Existing Controls:
- Button
- Menubar
- Menu
- MenuItem
- Editor
- Dialog
- DialogRadio
- DialogSelect
- DialogCheckbox
- DialogInput
- DialogButton
- Shortcut (invisible)

Button and DialogButton are similar yet different. Better off calling Button
"HelpLineButton" or something. They do have much in common, though ... One big
differentiator is that a DialogButton anticipates having keyboard focus, an
accelerator, and a different look.  Indeed -- the Dialog* Controls really do
belong in their own group.

Different Control types have different restrictions on the kinds of Controls
that can be their children (with many allowing none).

var radio = dialog.child(imtui.radio());
var radio = imtui.radio().parent(dialog);
var radio = imtui.radio(dialog); <-- we'll probably have to do this because
                                     its parent is a part of its identity.

Establishing this relationship immediately is important because the position of
the children will depend on the parent!

We'll need some kind of focus tree? Dialog -> DialogButton. ??Menubar->Menu??.
Technically a Dialog is never focussed -- only its elements are.

How shall we handle e.g. using the editor and then pressing and holding alt.
The menubar should immediately receive focus. Releasing & depressing again then
restores focus to the editor. It's more like a focus stack.

Key is that, at least in ADC, there's *always* an Editor at the bottom of that
stack, and we never get to the Menubar except by Alt or a direct click. In other
words, those key bindings *could* belong to the Editor, prompting a push to the
focus stack. And on un-focus, the Menubar just pops itself off again. Menubar
items render themselves when selected, or when a Menu(Item?) is focused which
belongs to it.

I can pretty much just start rewonking this by this stage, I think.


* [ ] Editor's general text-editing needs to be afforded to DialogInput.
      Selections, dragging, heaps of shortcut keys we don't yet support.
      (Help dialog will need its own read-only Editor-like thing.)

---

Some last low-hanging fruit to forage for.

* [x] dot-point menu toggles
* [x] "easy" menus
  * [x] save settings
* [-] display customisation 
  * [x] colours: Normal Text (17), Current Statement (1F), Breakpoint Lines (47)
    * [x] bad hover using 0x2f as normal text
  * [x] scroll bars on/off
  * [x] variable tab stop (not retroactive; not sure how QB handles actual \t)
  * [-] "Display" dialogue box (and accompanying Imtui infrastructure!)
* [ ] Menubar reconciliation redo (use ids)
* [x] rethink some of the many heap-allocated objects that probably don't need
      to be (like Font)
* [x] fix teardown on Windows (we try to destroy textures whose renderer has
      already been torn down; D3D doesn't tolerate this)
* [x] hidpi windows (piretike: 150% scaling, per default) doesn't give us a
      hidpi window. mods?

---

2024-11-24: end of basic editor

* [x] click to set cursor
* [x] selection (shift)
* [x] selection (drag)
  * [x] dragging to edge to select wider
    * dragging in an editor, if the cursor is outside the editable area
      horizontally (c==0/79), it scrolls once per tick in that direction, if
      possible.
    * if it's *not* outside horizontally, but is outside vertically, it scrolls
      once per tick in that direction, if possible. (hscroll is considered
      "outside".)
    * [x] moving the cursor within that same section also causes a scroll-by-1
          (on top of clickmatic).
* [x] scroll bars (clicking on arrows adjusts scroll by exactly 1; clicking in a
      space moves one entire page in that direction, capping at the end)
  * [x] clicking *on* the thumb seems to just reset cursor_x to scroll_x
    * [x] it also sets scroll_x to the earliest position for that thumb.
  * [x] the cursor's position should otherwise remain constant
  * [x] all the above for vertical too --- it's weird.
* [x] mouse wheel scrolling
  * I think it should be sufficient to translate wheel to cursor up/down keypresses.
* [x] fullscreen
* [x] F6 cycles windows; when one is fullscreen, cycles them through in turn.
* [x] split either splits main in 2, or unsplits. (always un-fullscreens.)
* [x] click and drag to resize middle/imm editor.
* [x] menus
* [x] typematic but for click&hold on scrollbar
* [x] no actual 255 character limit; QB reallocates on save
  * mitigated this Enough for now.
* [x] consider redoing this with 'controls' instead of manually drawing and
      checking click coordinates etc.
  * Actually: make an immediate mode-type thing? Could be nicer and more fun.
    * [x] :) :) :) :)
* [-] split view of same document: updates other on changing line
  * right now it updates immediately; we probably want to buffer the Source in
    the Editor and sync back on certain events.
* [x] don't process document events with zero-sized editor focussed
  * confirmed this is indeed the precise behaviour from QB. wonder if we
    actually knew that, somewhere deep down; feels like it!
* [x] click in Immediate editor somewhere not at col 1, press enter, crash
* [x] focussing a different Editor drops the Editor's selection
  * doesn't happen when just using menus, otherwise how do you Edit->Copy?
  * blur event just for Editor-Editor switches?
* [x] QB doesn't allow click in virtual line UNLESS it's the only line in the
      doc
  * [x] as soon as there is a line, click&drag (e.g. midscreen) will drag the
        sole line; if no content there's no drag effect
* [x] cap mouse cursor to display (e.g. in drag operations)
* [x] split screen, resize a non-immediate editor to display one line of text,
      click/drag in/around it, crash

---

Vertical scroll bar first can appear when an editor is 5 high: titlebar, 3 lines
of editing (with vscroll on right), 1 line hscroll (which we remember disappears
when the window isn't active). hscroll appears when the window is active & r2-r1
is >= 3. (at r2-r1=1, it's only a draggable titlebar, and =2 it's 1 editable
line.)

^ and v move scroll_row by exactly 1, without affecting cursor_row unless it's
required to keep the cursor in bounds. Remember that "bounds" here includes
the hscroll (which will always be there: if we get small enough for hscroll to
vanish, we're too small for a visible vscroll).

the highest we go is scroll_row=0. the lowest means the last displayed line
(above hscroll) is the virtual line after EOF. (again, hscroll is always
there to be blocked by if we're vscrolling to begin with. there'll be an empty
(non-existent) line behind hscroll when we make a different editor active;
that's fine.


What's the sensible way to determine whether or not we need to adjust
cursor_row?

Scroll up: the starting {scroll,cursor}_row is situated on the last visible line
above the hscroll.

Scroll down: starting {scroll,cursor}_row are identical.
What's the limit?
The last line that is visible above the hscroll is the virtual line.

---

Clicking the vscroll thumb seems to set both scroll_row and cursor_row to the
line indicated by that scroll position.

Having deduced that exactly lets us ensure we actually are doing the vst
calculation correctly ...

we are! Yay. Sure enuogh, the exact formula is there in reverse lol. Fml.

We have:

cr = sr = n*vst/(r2-r1-5)

They have:

vst = cr*(r2-r1-5)/n

n*vst = cr*(r2-r1-5)
n*vst/(r2-r1-5) = cr

If only I had listened to my elders. Can't believe I already had it.

---

Now I have to work out how pgup/pgdn work. This is one of the annoying behaviour
repro bits!! Keep at it babe!

---

\o/ Onto selections.

Pressing down shift seems to record current row/col.
If cursor then moved to same row, different col, select within the line text covered.
Note that c2 shift c3 selects what's at c2, but c2 shift c1 selects c1.
If the cursor is moved to a diff row, then line select all rows inclusive of start and end.
Moving back to the same row resumes inline selection.

TODO: interaction between selections and various controls and actions. (scroll/pgdn/etc.)
