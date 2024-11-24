Some last low-hanging fruit to forage for.

* [ ] dot-point menu toggles
* [ ] "easy" menus
* [ ] display customisation
  * [ ] colours: Normal Text (17), Current Statement (1F), Breakpoint Lines (47)
  * [ ] scroll bars on/off
  * [ ] variable tab stop (not retroactive; not sure how QB handles actual \t)
* [-] rethink some of the many heap-allocated objects that probably don't need
      to be (like Font)
* [-] fix teardown on Windows (we try to destroy textures whose renderer has
      already been torn down; D3D doesn't tolerate this)

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
