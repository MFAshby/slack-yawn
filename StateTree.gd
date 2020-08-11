extends Tree

# Useful for debugging, just a visual of the whole, current, state tree
func _ready():
	Slack.connect("state_changed", self, "_state_changed")
	
	
func _state_changed(old_state, new_state):
	# https://github.com/godotengine/godot/issues/16174
	self.call_deferred("_rebuild_tree", old_state, new_state)
	
func _rebuild_tree(old_state, new_state):
	var oldRoot = self.get_root()
	if oldRoot != null:
		oldRoot.call_recursive("free")
	
	var root = self.create_item()
	root.set_text(0, "state")
	_build_state_tree(new_state, root)
	
func _build_state_tree(state, root):
	for key in state:
		var v = state[key]
		var nd = self.create_item(root)
		nd.set_text(0, str(key))
		if typeof(v) == TYPE_DICTIONARY:
			self._build_state_tree(v, nd)
		else:
			nd.set_text(1, str(v))

