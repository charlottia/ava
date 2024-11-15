* [x] click to set cursor
* [ ] selection (shift)
* [ ] selection (drag)
* [-] scroll bars (clicking on arrows adjusts scroll by exactly 1; clicking in a
      space moves one entire page in that direction, capping at the end)
  * [x] clicking *on* the thumb seems to just reset cursor_x to scroll_x
    * [x] it also sets scroll_x to the earliest position for that thumb.
  * [x] the cursor's position should otherwise remain constant
  * [-] all the above for vertical too --- it's weird. 🐈
* [ ] mouse wheel scrolling
* [x] fullscreen
* [x] F6 cycles windows; when one is fullscreen, cycles them through in turn.
* [x] split either splits main in 2, or unsplits. (always un-fullscreens.)
* [x] click and drag to resize middle/imm editor.
* [x] menus
* [ ] typematic but for click&hold on scrollbar
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
* [x] click in Immediate editor somewhere not at col 1, press enter, crash 🐈‍⬛
