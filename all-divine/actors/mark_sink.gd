class_name MarkSink
extends Node
## The rig's `Marks` node: where a clip's Marks method track points.
##
## A mark is a key on that track whose method is the mark's kind and whose only argument is a
## Dictionary. The AnimationTree calls these as it plays through the keys, which happens in the
## editor's clip preview and in game. They do nothing: the move runner reads the marks from the clip
## itself and acts on them on the gameplay clock. This node only gives the calls somewhere to land.
## Keep one method per mark kind.


func hitbox_on(_args: Dictionary) -> void: pass
func hitbox_off(_args: Dictionary) -> void: pass
func iframes_on(_args: Dictionary) -> void: pass
func iframes_off(_args: Dictionary) -> void: pass
func hyperarmour_on(_args: Dictionary) -> void: pass
func hyperarmour_off(_args: Dictionary) -> void: pass
func cancel_open(_args: Dictionary) -> void: pass
func cancel_close(_args: Dictionary) -> void: pass
func recovery(_args: Dictionary) -> void: pass
func fx(_args: Dictionary) -> void: pass
func sfx(_args: Dictionary) -> void: pass
func shake(_args: Dictionary) -> void: pass
func hitstop(_args: Dictionary) -> void: pass
