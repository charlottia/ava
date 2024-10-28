* [x] can pretty much ignore key events while mouse is down on menu.
* [x] mouse down: opens menu.
* [x] can drag to other menus
* [ ] releasing outside item/menu `[ File ]` closes again
* [x] until mouse up, no item is selected
* [x] when mouse down, hover items selected
* [x] mouse down on menu: deselect
* [x] mouse up on open menu: close
  * what the hell is the actual heuristic here? Something like:
    * mouse down on an already open menu's menubar item, AND
    * mouse not dragged anywhere that would cause a switch of focus, AND
    * mouse up on that same menubar item
